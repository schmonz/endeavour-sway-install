#!/usr/bin/env bash
# setup-power.sh
#
# Unified power-button / lid-close / sleep configuration for EndeavourOS/Sway.
# Run as your normal user (sudo used internally where needed).
# Safe to re-run; all writes are idempotent.
#
# Supported machines:
#   Chromebook 100e (Google/MrChromebox firmware)
#     - Suspend disabled (resume is broken)
#     - Lid-close via ACPI sysfs poller (EC never generates input events)
#     - Power button: logind ignores it; Sway handles XF86PowerOff
#   MacBookPro5,2 / MacBookAir7,1
#     - Suspend left alone
#     - Power button: HandlePowerKey=ignore + XF86PowerOff binding in Sway
#       (no udev rule needed; libinput sees the event without it)
#   ThinkPad X270 / T60
#     - Suspend left alone
#     - Power button: udev strips power-switch tag so logind releases the
#       exclusive grab; HandlePowerKey=ignore as belt-and-suspenders;
#       XF86PowerOff binding in Sway

set -euo pipefail

# ── Helpers ───────────────────────────────────────────────────────────────────

die()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo "==> $*"; }
warn() { echo "WARN: $*" >&2; }

require_not_sway() {
    [[ -z "${SWAYSOCK:-}" ]] \
        || die "Running inside a Sway session. Some steps require being outside Sway (udev trigger, logind restart). Log out to a VT, run from there."
}

require_sudo() {
    sudo -v || die "sudo credentials required."
}

# ── Machine detection ─────────────────────────────────────────────────────────

MACHINE=""   # chromebook | macbook | thinkpad

detect_machine() {
    local vendor product bios

    vendor=$(sudo dmidecode -s system-manufacturer 2>/dev/null || true)
    product=$(sudo dmidecode -s system-product-name 2>/dev/null || true)
    bios=$(sudo dmidecode -s bios-version 2>/dev/null || true)

    if [[ "$vendor" == "Google" && "$bios" == MrChromebox* ]]; then
        MACHINE=chromebook
    elif [[ "$vendor" == "Apple Inc." ]]; then
        case "$product" in
            MacBookPro5,2|MacBookAir7,1) MACHINE=macbook ;;
            *) die "Unrecognised Apple product '${product}'. Add it to detect_machine() if needed." ;;
        esac
    elif [[ "$vendor" == "LENOVO" ]] && echo "$product" | grep -qi "ThinkPad\|2623P3U\|20HMS6VR00"; then
        MACHINE=thinkpad
    else
        die "Unrecognised machine (vendor='${vendor}' product='${product}'). Add it to detect_machine()."
    fi

    info "Detected machine class: ${MACHINE} (${product})"
}

# ── Shared: logind drop-in ────────────────────────────────────────────────────
#
# All machines: HandlePowerKey=ignore so Sway can handle XF86PowerOff.
# Chromebook additionally: IdleAction=ignore, HandleLidSwitch=lock,
#   sleep targets masked, sleep.conf drop-in.

write_logind_dropin() {
    local file="$1"; shift   # full path
    local content="$1"; shift

    info "Writing ${file} ..."
    sudo mkdir -p "$(dirname "$file")"
    echo "$content" | sudo tee "$file" > /dev/null
}

configure_logind_common() {
    # Power key: logind ignores it on all machines; Sway handles it.
    write_logind_dropin "/etc/systemd/logind.conf.d/power-key.conf" \
"[Login]
HandlePowerKey=ignore"
}

configure_logind_chromebook() {
    # Replaces (or creates) the main chromebook drop-in.
    # Name: disable-sleep.conf (the name that actually exists on the machine).
    write_logind_dropin "/etc/systemd/logind.conf.d/disable-sleep.conf" \
"[Login]
IdleAction=ignore
HandleLidSwitch=lock
HandleLidSwitchExternalPower=lock
HandlePowerKey=ignore
HandlePowerKeyLongPress=ignore"

    info "Masking sleep/suspend/hibernate targets ..."
    sudo systemctl mask \
        hibernate.target \
        hybrid-sleep.target \
        sleep.target \
        suspend-then-hibernate.target \
        suspend.target

    info "Writing /etc/systemd/sleep.conf.d/disable-sleep.conf ..."
    sudo mkdir -p /etc/systemd/sleep.conf.d
    sudo tee /etc/systemd/sleep.conf.d/disable-sleep.conf > /dev/null << 'EOF'
[Sleep]
AllowHibernation=no
AllowHybridSleep=no
AllowSuspendThenHibernate=no
AllowSuspend=no
EOF
}

restart_logind() {
    info "Restarting systemd-logind ..."
    sudo systemctl restart systemd-logind
    # greetd depends on logind; restart it so the login prompt comes back up.
    if sudo systemctl is-active --quiet greetd 2>/dev/null \
       || sudo systemctl is-failed --quiet greetd 2>/dev/null; then
        info "Restarting greetd ..."
        sudo systemctl restart greetd
    fi
}

# ── ThinkPad: udev rule to release power button from logind ───────────────────

configure_thinkpad_udev() {
    local event_dev="" event_node="" id_path=""

    info "Searching for ACPI power button input device ..."
    local input_dir name phys
    for input_dir in /sys/class/input/input*/; do
        name=$(cat "${input_dir}name" 2>/dev/null || true)
        if [[ "$name" == "Power Button" ]]; then
            phys=$(cat "${input_dir}phys" 2>/dev/null || true)
            if [[ "$phys" == *LNXPWRBN* ]]; then
                for evdir in "${input_dir}"event*/; do
                    event_node=$(basename "$evdir")
                    break
                done
                break
            fi
        fi
    done

    [[ -n "$event_node" ]] \
        || die "Could not find ACPI power button (LNXPWRBN). Check /proc/bus/input/devices."

    event_dev="/dev/input/${event_node}"
    [[ -c "$event_dev" ]] || die "${event_dev} is not a character device."
    info "Found power button at ${event_dev}."

    id_path=$(udevadm info "$event_dev" | awk -F= '/^E: ID_PATH=/{print $2}')
    [[ -n "$id_path" ]] \
        || die "udevadm reported no ID_PATH for ${event_dev}."
    info "ID_PATH=${id_path}"

    local udev_rule="/etc/udev/rules.d/99-power-button-sway.rules"
    info "Writing ${udev_rule} ..."
    sudo tee "$udev_rule" > /dev/null << EOF
# Strips power-switch tag so logind releases its exclusive grab.
# Allows libinput/Sway to handle XF86PowerOff via bindsym.
SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_PATH}=="${id_path}", \\
    TAG-="power-switch", TAG+="seat", TAG+="uaccess"
EOF

    info "Reloading udev rules ..."
    sudo udevadm control --reload-rules
    sudo udevadm trigger --action=add "$event_dev"
    sleep 1

    if udevadm info "$event_dev" | grep -E "^E: CURRENT_TAGS=" | grep -q "power-switch"; then
        warn "power-switch tag still present after reload. You may need to reboot for the grab to be released."
    else
        info "power-switch tag removed successfully."
    fi
}

# ── Shared: Sway XF86PowerOff binding ────────────────────────────────────────

add_sway_poweroff_binding() {
    local sway_user="${SUDO_USER:-${USER}}"
    local sway_user_home
    sway_user_home=$(getent passwd "$sway_user" | cut -d: -f6)

    local sway_conf_dir="${sway_user_home}/.config/sway"
    [[ -d "$sway_conf_dir" ]] || sway_conf_dir="${sway_user_home}/.sway"
    [[ -d "$sway_conf_dir" ]] \
        || die "No Sway config dir found for ${sway_user}."

    # Find the file that defines $powermenu; fall back to config.d/default.
    local target
    target=$(grep -rlE '^\s*set\s+\$powermenu\b' "$sway_conf_dir" 2>/dev/null | head -1 || true)
    if [[ -z "$target" ]]; then
        target="${sway_conf_dir}/config.d/default"
        warn "No \$powermenu definition found; appending to ${target}. Edit the exec command if needed."
    fi
    [[ -f "$target" ]] || die "${target} does not exist."

    # Check all config files, not just $target, for an existing binding.
    if grep -rlE '^\s*bindsym\s+XF86PowerOff\b' "$sway_conf_dir" 2>/dev/null | grep -q .; then
        info "XF86PowerOff binding already present in Sway config — skipping."
        return
    fi

    info "Adding XF86PowerOff binding to ${target} ..."
    printf '\n# Power button → power menu (added by setup-power.sh)\nbindsym XF86PowerOff exec $powermenu\n' \
        >> "$target"

    if [[ -n "${SUDO_USER:-}" ]]; then
        chown "${SUDO_USER}:" "$target"
    fi
}

# ── Chromebook: swayidle ──────────────────────────────────────────────────────

configure_chromebook_swayidle() {
    local autostart="$HOME/.config/sway/config.d/autostart_applications"
    [[ -f "$autostart" ]] || die "${autostart} not found."

    local backup="${autostart}.bak.$(date +%Y%m%d%H%M%S)"
    info "Backing up ${autostart} to ${backup} ..."
    cp "$autostart" "$backup"

    info "Patching swayidle in ${autostart} ..."

    # Remove old sleep-triggering forms.
    sed -i \
        '/^exec swayidle idlehint/d;
         /^exec_always swayidle -w before-sleep/d' \
        "$autostart"

    # Replace any bare timeout-only swayidle line with the full lock+dpms form,
    # but only if the full form isn't already there.
    local full_idle='exec swayidle -w \
    idlehint 1 \
    timeout 300  '"'"'gtklock -d --lock-command "swaymsg output \* dpms off"'"'"' resume '"'"'swaymsg "output * dpms on"'"'"' \
    lock         '"'"'gtklock -d --lock-command "swaymsg output \* dpms off"'"'"' \
    unlock       '"'"'swaymsg "output * dpms on"'"'"''

    if grep -q 'swayidle' "$autostart"; then
        # Already has some swayidle line; leave it alone and warn.
        warn "swayidle line already present in ${autostart} — review manually."
        warn "Expected form:"
        echo "$full_idle" | sed 's/^/    /'
    else
        printf '\n%s\n' "$full_idle" >> "$autostart"
        info "Added swayidle line."
    fi
}

# ── Chromebook: lid handler service ──────────────────────────────────────────

install_lid_handler() {
    local handler="$HOME/.local/bin/sway-lid-handler"
    local service="$HOME/.config/systemd/user/sway-lid-handler.service"
    local autostart="$HOME/.config/sway/config.d/autostart_applications"

    info "Installing ${handler} ..."
    mkdir -p "$(dirname "$handler")"
    cat > "$handler" << 'SCRIPT'
#!/bin/bash
# sway-lid-handler
#
# Polls /proc/acpi/button/lid/LID0/state and acts on lid open/close.
#
# On this Chromebook hardware the EC handles the lid switch without generating
# kernel input events (EV_SW SW_LID never fires on /dev/input/event0), so
# logind and sway/libinput never see lid events. Polling the ACPI sysfs file
# is the only reliable detection mechanism.
#
# Lid close: loginctl lock-session → swayidle lock handler → gtklock + dpms off
# Lid open:  swaymsg output dpms on

LID_STATE=/proc/acpi/button/lid/LID0/state

read -r _ prev < "$LID_STATE"

while true; do
    read -r _ cur < "$LID_STATE"
    if [[ "$cur" != "$prev" ]]; then
        if [[ "$cur" == "closed" ]]; then
            loginctl lock-session
        else
            swaymsg "output * dpms on"
        fi
        prev="$cur"
    fi
    sleep 1
done
SCRIPT
    chmod +x "$handler"

    info "Installing ${service} ..."
    mkdir -p "$(dirname "$service")"
    cat > "$service" << 'SERVICE'
[Unit]
Description=Sway lid close handler (ACPI sysfs poller)
Documentation=file://%h/.local/bin/sway-lid-handler
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=%h/.local/bin/sway-lid-handler
Restart=always
RestartSec=1

[Install]
WantedBy=graphical-session.target
SERVICE

    systemctl --user daemon-reload
    systemctl --user enable sway-lid-handler.service
    # Only start now if we're in a graphical session; otherwise it starts at login.
    if [[ -n "${SWAYSOCK:-}" ]]; then
        systemctl --user restart sway-lid-handler.service
        info "Service enabled and started."
    else
        info "Service enabled (will start at next Sway login)."
    fi

    local exec_line="exec systemctl --user start sway-lid-handler.service"
    if grep -qF "$exec_line" "$autostart" 2>/dev/null; then
        info "Autostart entry already present — skipping."
    else
        info "Adding autostart entry to ${autostart} ..."
        cat >> "$autostart" << EOF

# Lid-close handling via ACPI sysfs poller (see ~/.local/bin/sway-lid-handler).
${exec_line}
EOF
    fi
}

# ── etckeeper ─────────────────────────────────────────────────────────────────

etckeeper_commit() {
    local msg="$1"
    if command -v etckeeper &>/dev/null; then
        info "etckeeper commit: ${msg}"
        sudo etckeeper commit -m "$msg" 2>/dev/null || warn "etckeeper commit failed (non-fatal)."
    fi
}

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
    require_sudo
    detect_machine

    case "$MACHINE" in

      chromebook)
        require_not_sway
        configure_logind_chromebook
        restart_logind
        configure_chromebook_swayidle
        install_lid_handler
        add_sway_poweroff_binding
        etckeeper_commit "setup-power.sh: chromebook power/lid/sleep config"
        ;;

      macbook)
        require_not_sway
        configure_logind_common
        restart_logind
        add_sway_poweroff_binding
        etckeeper_commit "setup-power.sh: macbook power-key config"
        ;;

      thinkpad)
        require_not_sway
        configure_logind_common
        configure_thinkpad_udev
        restart_logind
        add_sway_poweroff_binding
        etckeeper_commit "setup-power.sh: thinkpad power-key config"
        ;;

    esac

    echo ""
    info "Done. Reload Sway to apply config changes: swaymsg reload"
    if [[ "$MACHINE" == "thinkpad" ]]; then
        info "Note: the udev grab release requires a re-login or reboot to take full effect."
    fi
}

main "$@"
