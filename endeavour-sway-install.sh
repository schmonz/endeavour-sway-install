#!/usr/bin/env bash
# endeavour-sway-install.sh
#
# Multi-phase setup for EndeavourOS Sway edition.
#
# Usage:
#   Phase 1 — installer chroot (root, no systemd, no graphical session):
#     bash endeavour-sway-install.sh --phase 1
#   Phase 2 — first-boot systemd service (root, systemd running):
#     Invoked automatically by endeavour-sway-firstboot.service.
#   Phase 3 — first Sway session (normal user):
#     endeavour-sway-install.sh --phase 3
#
# Phase 1 is run by the Calamares post-install hook after the Sway CE script.
# Safe to re-run individual phases.
#
# Boot repair / emergency references (not run by this script):
#   chroot via live USB: https://gist.github.com/EdmundGoodman/c057ce0c826fd0edde7917d15b709f4f
#   mount btrfs root subvolume: https://wiki.archlinux.org/title/Btrfs#Mounting_subvolumes
#   EndeavourOS system rescue: https://discovery.endeavouros.com/system-rescue/arch-chroot/
#   Restore: ~/.config/sway/config.d/*, /etc/sudo*, clight configs
#   XXX system (and foot, text editor, etc.) font size for small screens
#   XXX maybe punt on geolocation?
#   XXX I'll need to create AUR packages for the TI calc backup programs
#   XXX pre-populate known WiFi configs in NetworkManager?
#   XXX captive portal auto-browsing
#   Pinebook Pro: https://endeavouros.com/endeavouros-arm-install/
#
# Install steps (done before running this script, via live installer):
#   Pull in Sway Community Edition:
#     https://github.com/EndeavourOS-Community-Editions/sway
#   Options: whole disk, encrypted, one big btrfs
#   XXX swap enough for hibernate? (different for Chromebook?)
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

WARNINGS_FILE="/root/endeavour-setup-warnings.txt"
INSTALL_SCRIPT_DEST="/usr/local/bin/endeavour-sway-install.sh"
FIRSTBOOT_SERVICE="/etc/systemd/system/endeavour-sway-firstboot.service"
SELF_URL="https://raw.githubusercontent.com/schmonz/endeavour-sway-install/main/endeavour-sway-install.sh"
SWAY_CE_URL="https://raw.githubusercontent.com/EndeavourOS-Community-Editions/sway/main/setup_sway_isomode.bash"

# ── Helpers ───────────────────────────────────────────────────────────────────

die()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo "==> $*"; }
warn() { echo "WARN: $*" >&2; }

# Accumulate warnings during unattended phases; user sees them on first login.
accumulate_warning() {
    warn "$*"
    [[ $EUID -eq 0 ]] && echo "$*" >> "$WARNINGS_FILE" || true
}

# Runs as root in phases 1 and 2; uses sudo in phase 3 (normal user).
_sudo() {
    if [[ $EUID -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

require_sudo() {
    sudo -v || die "sudo credentials required."
}

swaymsg_reload() {
    if [[ -n "${SWAYSOCK:-}" ]]; then
        info "Reloading Sway config ..."
        swaymsg reload
    else
        warn "Not in a Sway session — reload manually: swaymsg reload"
    fi
}

# Append LINE to FILE only if not already present.
append_once() {
    local file="$1" line="$2"
    grep -qF "$line" "$file" 2>/dev/null || printf '%s\n' "$line" >> "$file"
}

# ── Machine detection ─────────────────────────────────────────────────────────

MACHINE=""   # chromebook | macbook | thinkpad | unknown

detect_machine() {
    local vendor product bios

    vendor=$(_sudo dmidecode -s system-manufacturer 2>/dev/null || true)
    product=$(_sudo dmidecode -s system-product-name 2>/dev/null || true)
    bios=$(_sudo dmidecode -s bios-version 2>/dev/null || true)

    if [[ "$vendor" == "Google" && "$bios" == MrChromebox* ]]; then
        MACHINE=chromebook
    elif [[ "$vendor" == "Apple Inc." ]]; then
        case "$product" in
            MacBookPro5,2|MacBookAir7,1) MACHINE=macbook ;;
            *)
                accumulate_warning "Unrecognised Apple product '${product}'. Add it to detect_machine() if needed."
                MACHINE=unknown
                ;;
        esac
    elif [[ "$vendor" == "LENOVO" ]] && echo "$product" | grep -qi "ThinkPad\|2623P3U\|20HMS6VR00"; then
        MACHINE=thinkpad
    else
        accumulate_warning "Unrecognised machine (vendor='${vendor}' product='${product}'). Add it to detect_machine()."
        MACHINE=unknown
    fi

    info "Detected machine class: ${MACHINE} (${product:-unknown})"
}

# First real user account (uid 1000–65533); used by phases 1 and 2.
detect_target_user() {
    getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 { print $1; exit }'
}

# ── etckeeper ─────────────────────────────────────────────────────────────────

etckeeper_commit() {
    local msg="$1"
    if command -v etckeeper &>/dev/null; then
        info "etckeeper commit: ${msg}"
        _sudo etckeeper commit -m "$msg" 2>/dev/null \
            || warn "etckeeper commit failed (non-fatal)."
    fi
}

# ── Logind drop-ins ───────────────────────────────────────────────────────────
#
# All machines: HandlePowerKey=ignore so Sway can handle XF86PowerOff.
# Chromebook additionally: IdleAction=ignore, HandleLidSwitch=lock,
#   sleep targets masked, sleep.conf drop-in.

write_logind_dropin() {
    local file="$1" content="$2"
    info "Writing ${file} ..."
    _sudo mkdir -p "$(dirname "$file")"
    echo "$content" | _sudo tee "$file" > /dev/null
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
    # systemctl mask creates /dev/null symlinks — works in chroot and live system.
    _sudo systemctl mask \
        hibernate.target \
        hybrid-sleep.target \
        sleep.target \
        suspend-then-hibernate.target \
        suspend.target

    info "Writing /etc/systemd/sleep.conf.d/disable-sleep.conf ..."
    _sudo mkdir -p /etc/systemd/sleep.conf.d
    _sudo tee /etc/systemd/sleep.conf.d/disable-sleep.conf > /dev/null << 'EOF'
[Sleep]
AllowHibernation=no
AllowHybridSleep=no
AllowSuspendThenHibernate=no
AllowSuspend=no
EOF
}

restart_logind() {
    info "Restarting systemd-logind ..."
    _sudo systemctl restart systemd-logind
    # greetd depends on logind; restart it so the login prompt comes back up.
    if _sudo systemctl is-active --quiet greetd 2>/dev/null \
       || _sudo systemctl is-failed --quiet greetd 2>/dev/null; then
        info "Restarting greetd ..."
        _sudo systemctl restart greetd
    fi
}

# ── ThinkPad: udev rule ───────────────────────────────────────────────────────

write_thinkpad_udev_rule() {
    local udev_rule="/etc/udev/rules.d/99-power-button-sway.rules"
    info "Writing ${udev_rule} ..."
    _sudo tee "$udev_rule" > /dev/null << 'EOF'
# Strips power-switch tag so logind releases its exclusive grab.
# Allows libinput/Sway to handle XF86PowerOff via bindsym.
# Uses ATTRS matching so the rule can be written before first boot (no ID_PATH needed).
SUBSYSTEM=="input", KERNEL=="event*", ATTRS{name}=="Power Button", ATTRS{phys}=="*LNXPWRBN*", \
    TAG-="power-switch", TAG+="seat", TAG+="uaccess"
EOF
}

reload_thinkpad_udev() {
    info "Reloading udev rules and triggering power button ..."
    _sudo udevadm control --reload-rules
    _sudo udevadm trigger --action=add --subsystem-match=input
    sleep 1

    local event_dev=""
    local input_dir name phys
    for input_dir in /sys/class/input/input*/; do
        name=$(cat "${input_dir}name" 2>/dev/null || true)
        if [[ "$name" == "Power Button" ]]; then
            phys=$(cat "${input_dir}phys" 2>/dev/null || true)
            if [[ "$phys" == *LNXPWRBN* ]]; then
                for evdir in "${input_dir}"event*/; do
                    event_dev="/dev/input/$(basename "$evdir")"
                    break
                done
                break
            fi
        fi
    done

    if [[ -n "$event_dev" ]] \
       && _sudo udevadm info "$event_dev" 2>/dev/null \
          | grep -E "^E: CURRENT_TAGS=" | grep -q "power-switch"; then
        warn "power-switch tag still present on ${event_dev}. May need a reboot."
    else
        info "power-switch tag removed (or device not yet visible — check after login)."
    fi
}

# ── Sway XF86PowerOff binding ─────────────────────────────────────────────────

add_sway_poweroff_binding() {
    local sway_user="${1}"
    local sway_user_home
    sway_user_home=$(getent passwd "$sway_user" | cut -d: -f6)

    local sway_conf_dir="${sway_user_home}/.config/sway"
    [[ -d "$sway_conf_dir" ]] || sway_conf_dir="${sway_user_home}/.sway"
    if [[ ! -d "$sway_conf_dir" ]]; then
        accumulate_warning "No Sway config dir found for ${sway_user} — XF86PowerOff binding skipped."
        return
    fi

    # Find the file that defines $powermenu; fall back to config.d/default.
    local target
    target=$(grep -rlE '^\s*set\s+\$powermenu\b' "$sway_conf_dir" 2>/dev/null | head -1 || true)
    if [[ -z "$target" ]]; then
        target="${sway_conf_dir}/config.d/default"
        warn "No \$powermenu definition found; appending to ${target}. Edit exec command if needed."
    fi
    if [[ ! -f "$target" ]]; then
        accumulate_warning "${target} does not exist — XF86PowerOff binding skipped."
        return
    fi

    # Check all config files, not just $target, for an existing binding.
    if grep -rlE '^\s*bindsym\s+XF86PowerOff\b' "$sway_conf_dir" 2>/dev/null | grep -q .; then
        info "XF86PowerOff binding already present — skipping."
        return
    fi

    info "Adding XF86PowerOff binding to ${target} ..."
    printf '\nbindsym XF86PowerOff exec $powermenu\n' >> "$target"
    chown "${sway_user}:" "$target"
}

# ── Chromebook: swayidle ──────────────────────────────────────────────────────

configure_chromebook_swayidle() {
    local autostart="$HOME/.config/sway/config.d/autostart_applications"
    if [[ ! -f "$autostart" ]]; then
        warn "${autostart} not found — skipping swayidle config."
        return
    fi

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

# ── Machine-specific stubs (phase 3) ─────────────────────────────────────────

setup_chromebook_audio() {
    info "Setting up Chromebook audio ..."
    if [[ ! -d ~/trees/chromebook-linux-audio ]]; then
        git clone https://github.com/WeirdTreeThing/chromebook-linux-audio ~/trees/chromebook-linux-audio
    fi
    cd ~/trees/chromebook-linux-audio
    echo "WHATEVER IT WANTS ME TO SAY" | ./setup-audio --force-avs-install  # XXX placeholder response
    cd -
}

setup_chromebook_fkeys() {
    info "Setting up Chromebook F-keys ..."
    if [[ ! -d ~/trees/cros-keyboard-map ]]; then
        git clone https://github.com/WeirdTreeThing/cros-keyboard-map ~/trees/cros-keyboard-map
    fi
    cd ~/trees/cros-keyboard-map
    ./install.sh
    cd -
}

setup_mac_fan() {
    info "Installing mbpfan ..."
    sudo cp /usr/lib/systemd/system/mbpfan.service /etc/systemd/system/
    sudo systemctl enable --now mbpfan.service
    etckeeper_commit "Enable mbpfan Mac fan control."
}

setup_mac_light_sensors() {
    : # lightum: https://github.com/poliva/lightum
      # macbook-lighter: https://github.com/harttle/macbook-lighter
      # pommed: https://packages.debian.org/trixie/pommed
      # pommed-light: https://github.com/bytbox/pommed-light
      # Debian Mactel Team: https://qa.debian.org/developer.php?login=team%2Bpkg-mactel-devel%40tracker.debian.org
}

setup_webcam() {
    info "Setting up webcam ..."
    # FaceTime webcam (e.g. MacBookAir7,1)
    # facetimehd-dkms installed via yay above
    sudo modprobe  # XXX missing module name
    # iSight webcam — not sure who needs this:
    # yay -S --noconfirm isight-firmware
    sudo pacman -S --noconfirm guvcview
}

# Idempotently add PARAMS to grub variable VAR, guarded by CHECK already present.
# Handles empty and non-empty values, single- or double-quoted.
add_grub_param() {
    local var="$1" check="$2" params="$3"
    sudo sed -i -E "
/^${var}=/{
    /${check}/! {
        s/=([\"'])\1\$/=\1${params}\1/
        t
        s/=([\"'])(.*)\1\$/=\1\2 ${params}\1/
    }
}" /etc/default/grub
}

setup_nvidia_display() {
    # For MacBookPro5,2 so the display manager comes up on the real screen.
    info "Disabling phantom second internal display (LVDS-2) ..."
    # Targets GRUB_CMDLINE_LINUX (not _DEFAULT) so recovery boots also get the fix.
    add_grub_param GRUB_CMDLINE_LINUX video=LVDS-2:d video=LVDS-2:d
    sudo grub-mkconfig -o /boot/grub/grub.cfg
    etckeeper_commit "Disable second internal display (MacBookPro5,2 LVDS-2)."
}

setup_zswap() {
    info "Enabling zswap ..."
    # Targets GRUB_CMDLINE_LINUX_DEFAULT — performance optimization, not needed in recovery.
    add_grub_param GRUB_CMDLINE_LINUX_DEFAULT zswap.enabled=1 \
        "zswap.enabled=1 zswap.compressor=zstd zswap.zpool=z3fold zswap.max_pool_percent=20"
    sudo grub-mkconfig -o /boot/grub/grub.cfg
    etckeeper_commit "Enable zswap."
}

setup_pacman_cache() {
    # XXX CLI equivalent for "Package Cleanup Configuration" from the Welcome screen
    # (that GUI creates paccache.service + paccache.timer)
    etckeeper_commit "Periodically clean pacman cache."
}

setup_power_saving() {
    : # TLP: https://wiki.archlinux.org/title/TLP
}

setup_infrared_receiver() {
    : # LIRC: https://wiki.archlinux.org/title/LIRC
}

setup_thinkpad_goodies() {
    : # XXX smart card?
      # XXX T60 volume and power buttons, ThinkVantage button, fingerprint reader
}

# ── First-boot service (written by phase 1, runs as phase 2) ─────────────────

install_firstboot_service() {
    info "Installing ${FIRSTBOOT_SERVICE} ..."
    if [[ -f "$0" ]]; then
        cp "$0" "$INSTALL_SCRIPT_DEST"
    else
        # Piped via curl | bash — $0 is not a real file; fetch the script directly.
        curl -fsSL "$SELF_URL" -o "$INSTALL_SCRIPT_DEST"
    fi
    chmod +x "$INSTALL_SCRIPT_DEST"

    cat > "$FIRSTBOOT_SERVICE" << EOF
[Unit]
Description=EndeavourOS Sway first-boot setup (phase 2)
Documentation=file://${INSTALL_SCRIPT_DEST}
After=network-online.target systemd-user-sessions.service
Wants=network-online.target
ConditionPathExists=${INSTALL_SCRIPT_DEST}

[Service]
Type=oneshot
ExecStart=${INSTALL_SCRIPT_DEST} --phase 2
ExecStartPost=/bin/rm -f ${FIRSTBOOT_SERVICE}
RemainAfterExit=no
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    systemctl enable endeavour-sway-firstboot.service
    info "First-boot service installed and enabled."
    info "Script saved to ${INSTALL_SCRIPT_DEST} — call with --phase 3 after first login."
}

# ── Warnings display (set up in phase 2, fires on first Sway login) ───────────

install_warnings_displayer() {
    local target_home="$1"
    local warnings_file="${target_home}/.config/endeavour-warnings"
    [[ -f "$warnings_file" ]] || return 0

    local displayer="${target_home}/.local/bin/endeavour-show-warnings"
    mkdir -p "$(dirname "$displayer")"

    cat > "$displayer" << 'SCRIPT'
#!/bin/bash
file="${HOME}/.config/endeavour-warnings"
[[ -f "$file" ]] || exit 0
foot -e sh -c "cat '$file'; echo; read -r -p 'Press Enter to dismiss.' _"
rm -f "$file"
sed -i '/exec endeavour-show-warnings/d' \
    "${HOME}/.config/sway/config.d/autostart_applications" 2>/dev/null || true
SCRIPT
    chmod +x "$displayer"

    local autostart="${target_home}/.config/sway/config.d/autostart_applications"
    if [[ -f "$autostart" ]]; then
        append_once "$autostart" "exec endeavour-show-warnings"
    else
        warn "${autostart} not found — warnings displayer autostart skipped."
        warn "Run ${displayer} manually on first login."
    fi
}

# ── Phase 1: installer chroot ─────────────────────────────────────────────────

phase1() {
    [[ $EUID -eq 0 ]] || die "Phase 1 must run as root."

    local target_user
    target_user=$(detect_target_user)
    [[ -n "$target_user" ]] \
        || die "No user found with uid >= 1000. Has Calamares created the user yet?"

    detect_machine

    info "=== Phase 1: pacman installs ==="
    pacman -Syuu --noconfirm
    pacman -S --noconfirm \
        etckeeper git git-delta \
        blueman \
        gvfs-dnssd tailscale \
        seahorse \
        fwupd \
        discord signal-desktop \
        libreoffice-fresh abiword cups cups-browsed system-config-printer \  # XXX other cups goodies the installer was offering?
        xdg-desktop-portal xdg-desktop-portal-wlr \
        steam prismlauncher \
        eos-update-notifier \
        btop fastfetch tmux the_silver_searcher xorg-xhost \
        apostrophe glow tig github-cli socat

    # Replaced by Helium in phase 3.
    pacman -Rs --noconfirm firefox || true

    info "=== Phase 1: etckeeper init ==="
    if ! etckeeper vcs log --oneline -1 &>/dev/null; then
        etckeeper init
    fi

    info "=== Phase 1: autologin ==="
    # https://github.com/EndeavourOS-Community-Editions/sway/issues/105
    if ! grep -q 'initial_session' /etc/greetd/greetd.conf; then
        tee -a /etc/greetd/greetd.conf > /dev/null << EOF

[initial_session]
command = "sway"
user = "${target_user}"
EOF
    else
        info "Autologin already configured."
    fi

    info "=== Phase 1: macOS keyboard layout ==="
    # localectl requires systemd-localed; write the config file directly instead.
    mkdir -p /etc/X11/xorg.conf.d
    tee /etc/X11/xorg.conf.d/00-keyboard.conf > /dev/null << 'EOF'
Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "us"
    Option "XkbVariant" "mac"
EndSection
EOF

    info "=== Phase 1: pbcopy / pbpaste ==="
    printf '#!/bin/sh\nexec wl-copy "$@"\n' > /usr/local/bin/pbcopy
    printf '#!/bin/sh\nexec wl-paste --no-newline "$@"\n' > /usr/local/bin/pbpaste
    chmod +x /usr/local/bin/pbcopy /usr/local/bin/pbpaste

    info "=== Phase 1: 1Password browser integration ==="
    mkdir -p /etc/1password
    grep -qF 'helium' /etc/1password/custom_allowed_browsers 2>/dev/null \
        || echo 'helium' >> /etc/1password/custom_allowed_browsers

    info "=== Phase 1: eos-update-notifier ==="
    sed -i 's|ShowHowAboutUpdates=notify\b|ShowHowAboutUpdates=notify+tray|' \
        /etc/eos-update-notifier.conf 2>/dev/null || true

    info "=== Phase 1: firewall (permanent rules, no daemon needed) ==="
    firewall-cmd --set-default-zone=home --permanent \
        || warn "firewall-cmd --set-default-zone failed (will retry in phase 2)."
    firewall-cmd --add-port=53317/tcp --permanent || true
    firewall-cmd --add-port=53317/udp --permanent || true

    info "=== Phase 1: systemd-resolved ==="
    ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

    info "=== Phase 1: logind / sleep config ==="
    case "$MACHINE" in
      chromebook) configure_logind_chromebook ;;
      *)          configure_logind_common ;;
    esac

    if [[ "$MACHINE" == "thinkpad" ]]; then
        write_thinkpad_udev_rule
    fi

    info "=== Phase 1: first-boot service ==="
    install_firstboot_service

    info ""
    info "Phase 1 complete. Reboot — phase 2 will run automatically on first boot."
    if [[ -f "$WARNINGS_FILE" ]]; then
        warn "Warnings accumulated during phase 1 (will appear on first Sway login):"
        cat "$WARNINGS_FILE" >&2
    fi
}

# ── Phase 2: first-boot systemd service ──────────────────────────────────────

phase2() {
    [[ $EUID -eq 0 ]] || die "Phase 2 must run as root (via systemd service)."

    local target_user target_home
    target_user=$(detect_target_user)
    [[ -n "$target_user" ]] || die "No user found with uid >= 1000."
    target_home=$(getent passwd "$target_user" | cut -d: -f6)

    detect_machine

    info "=== Phase 2: etckeeper commit ==="
    etckeeper commit -m 'Track /etc after phase-1 install.' 2>/dev/null || true

    local current_branch
    current_branch=$(git -C /etc symbolic-ref --short HEAD 2>/dev/null || true)
    if [[ -n "$current_branch" && "$current_branch" != "$(hostname)" ]]; then
        git -C /etc branch -m "$(hostname)"
        git -C /etc gc --prune
    fi

    info "=== Phase 2: dotfiles ==="
    if [[ ! -d "${target_home}/trees/dotfiles" ]]; then
        su - "$target_user" -c \
            "mkdir -p ~/trees && git clone https://github.com/schmonz/dotfiles.git ~/trees/dotfiles"
    fi
    su - "$target_user" -c \
        "ln -sf ~/trees/dotfiles/gitconfig ~/.gitconfig && ln -sf ~/trees/dotfiles/tmux.conf ~/.tmux.conf"
    ln -sf "${target_home}/trees/dotfiles/gitconfig" /root/.gitconfig || true

    info "=== Phase 2: systemctl enables ==="
    systemctl enable --now bluetooth
    # XXX what's --needed (skips already-installed packages)
    # bluetoothctl pairing: https://wiki.archlinux.org/title/Bluetooth#Pairing
    systemctl enable --now tailscaled
    systemctl enable --now systemd-resolved

    info "=== Phase 2: firewall (daemon now running) ==="
    firewall-cmd --set-default-zone=home || true
    firewall-cmd --reload || true

    info "=== Phase 2: logind restart ==="
    case "$MACHINE" in
      thinkpad) reload_thinkpad_udev ;;
    esac
    restart_logind

    etckeeper commit -m 'endeavour-sway: phase-2 first-boot config.' 2>/dev/null || true

    info "=== Phase 2: warnings displayer ==="
    install_warnings_displayer "$target_home"

    info ""
    info "Phase 2 complete. Log in to Sway, then run:"
    info "  ${INSTALL_SCRIPT_DEST} --phase 3"
    # The service unit deletes itself via ExecStartPost.
}

# ── Phase 3: first Sway session ───────────────────────────────────────────────

phase3() {
    require_sudo
    detect_machine

    info "=== Phase 3: gaming: GPU check ==="
    lspci | grep -i vga || true

    info "=== Phase 3: yay installs (common) ==="
    yay -S --noconfirm \
        timeshift-autosnap \
        1password \
        helium-browser-bin ungoogled-chromium-bin webapp-manager \
        localsend-bin \
        slack-electron \
        zoom teams-for-linux-electron-bin \
        rclone \
        minecraft-launcher \
        clion clion-jre \
        intellij-idea-ultimate-edition \
        goland goland-jre \
        webstorm webstorm-jre \
        pycharm \
        dawn-writer-bin \
        claude-code claude-desktop-bin claude-cowork-service

    info "=== Phase 3: timeshift ==="
    sudo pacman -S --noconfirm grub-btrfs snapper inotify-tools
    sudo systemctl enable --now cronie
    # XXX CLI equivalent: open the Timeshift app and follow the prompts
    # XXX snapper also? instead? does it integrate with pacman too?
    etckeeper_commit "Enable Timeshift."
    setup_pacman_cache

    info "=== Phase 3: web browser ==="
    append_once ~/.config/sway/config.d/application_defaults \
        'for_window [app_id="helium"] inhibit_idle fullscreen'
    sed -i 's|exec firefox|exec xdg-open https://|g' ~/.config/sway/config.d/default
    mkdir -p ~/.local/share/applications/kde4
    printf '[Desktop Entry]\nHidden=true\n' > ~/.local/share/applications/chromium.desktop
    printf '[Desktop Entry]\nHidden=true\n' > ~/.local/share/applications/kde4/webapp-manager.desktop
    info "Launch Helium and assign an empty keyring passphrase when prompted."
    # Geolocation (disabled):
    # sudo pacman -S --noconfirm xdg-desktop-portal-gtk
    # systemctl --user enable --now xdg-desktop-portal xdg-desktop-portal-gtk
    # sed -i 's/import-environment DISPLAY WAYLAND_DISPLAY SWAYSOCK/import-environment DISPLAY WAYLAND_DISPLAY SWAYSOCK XDG_CURRENT_DESKTOP/' \
    #     ~/.config/sway/config.d/autostart_applications
    # swaymsg_reload

    info "=== Phase 3: passwords ==="
    append_once ~/.config/sway/config.d/autostart_applications 'exec 1password'
    [[ -n "${SWAYSOCK:-}" ]] && 1password &

    info "=== Phase 3: networking ==="
    sudo tailscale set --operator="$USER"
    append_once ~/.config/sway/config.d/autostart_applications 'exec tailscale systray'
    [[ -n "${SWAYSOCK:-}" ]] && tailscale systray &
    tailscale up
    tailscale set --accept-dns=true
    tailscale set --accept-routes
    etckeeper_commit "Enable Tailscale."
    # XXX the more I logout and login, the more tailscale systray icons I have
    # XXX is this true for other systray icons as well?
    # XXX maybe exit node also isn't working? admin console says:
    # XXX   "This machine is misconfigured and cannot relay traffic."
    # XXX but maybe that's enough for Plex (or Jellyfin)
    append_once ~/.config/sway/config.d/autostart_applications 'exec localsend --hidden'
    [[ -n "${SWAYSOCK:-}" ]] && localsend --hidden &
    # XXX configure LocalSend to use the real system hostname
    # XXX T60: 'unable to create a GL context' — try: sudo pacman -S vulkan-radeon
    info "Log out and back in for Thunar Network view to show shares."
    # XXX clicking URLs in Foot?

    info "=== Phase 3: etckeeper commits ==="
    etckeeper_commit "Enable autologin."
    etckeeper_commit "Enable Mac-like accents with Right-Alt."
    etckeeper_commit "Enable Bluetooth."
    setup_power_saving
    etckeeper_commit "Set default firewall zone to 'home'."
    etckeeper_commit "Allow LocalSend through firewall."
    etckeeper_commit "Enable Helium 1Password integration."

    info "=== Phase 3: firmware updates ==="
    fwupdmgr get-updates || true
    fwupdmgr update || true
    # MrChromebox firmware: https://docs.mrchromebox.tech/docs/firmware/updating-firmware.html

    info "=== Phase 3: screen sharing ==="
    # XXX these already seem to be installed
    append_once ~/.config/zoomus.conf 'enableWaylandShare=true'
    # XXX has screen sharing actually worked?

    info "=== Phase 3: update notifier ==="
    eos-update-notifier -init
    etckeeper_commit "Configure eos-update-notifier."
    # XXX runs on a timer -- how often?
    # XXX show up in Waybar?

    info "=== Phase 3: other tools ==="
    sed -i 's/htop/btop/g' ~/.config/waybar/config
    sed -i 's/waybar_htop/waybar_btop/g' ~/.config/sway/config.d/application_defaults
    pkill -USR2 waybar || true

    etckeeper_commit "Install development tools."

    info "=== Phase 3: cloud storage ==="
    rclone config
    # After authentication error: log into icloud.com in a browser, open Chrome
    # Dev Tools → Network tab, click a request, grab the full Cookie header and
    # X-APPLE-WEBAUTH-HSA-TRUST value, then:
    #   rclone config update icloud cookies='' trust_token=""
    # Token expires monthly (~30 days).
    # https://forum.rclone.org/t/icloud-connect-not-working-http-error-400/52019/44

    info "=== Phase 3: machine-specific ==="
    case "$MACHINE" in
      chromebook)
        setup_chromebook_audio
        setup_chromebook_fkeys
        configure_chromebook_swayidle
        install_lid_handler
        add_sway_poweroff_binding "$USER"
        etckeeper_commit "endeavour-sway: chromebook power/lid/sleep"
        ;;
      macbook)
        yay -S --noconfirm iio-sensor-proxy clight mbpfan facetimehd-dkms
        sudo systemctl enable --now clightd
        append_once ~/.config/sway/config.d/autostart_applications 'exec clight'
        [[ -n "${SWAYSOCK:-}" ]] && clight &
        ls /sys/class/leds/ | grep -i kbd || true
        brightnessctl --list | grep -i kbd || true
        # XXX replace 'your-device-here' with detected device name from above
        # brightnessctl --device='your-device-here' set 50%
        # XXX keyboard brightness sway bindings (edit smc::kbd_backlight device name first):
        # sed -i '/XF86MonBrightnessDown/a\        XF86KbdBrightnessUp exec brightnessctl -d smc::kbd_backlight set +5%\n        XF86KbdBrightnessDown exec brightnessctl -d smc::kbd_backlight set 5%-' \
        #     ~/.config/sway/config.d/default
        ls /sys/bus/iio/devices/*/in_illuminance* || true
        # XXX what about autotuned screen brightness on ThinkPad?
        # XXX what about backlit keys on HP? autotuned clight?
        setup_mac_fan
        setup_mac_light_sensors
        setup_webcam
        setup_nvidia_display
        setup_zswap
        add_sway_poweroff_binding "$USER"
        etckeeper_commit "endeavour-sway: macbook power/display/fan config"
        ;;
      thinkpad)
        setup_infrared_receiver
        setup_thinkpad_goodies
        setup_zswap
        add_sway_poweroff_binding "$USER"
        etckeeper_commit "endeavour-sway: thinkpad power-key config"
        info "Note: the udev grab release requires a re-login or reboot to take full effect."
        ;;
      unknown)
        accumulate_warning "Machine class unknown — machine-specific setup skipped."
        ;;
    esac

    swaymsg_reload

    info ""
    info "Phase 3 complete."
    info "  Remaining interactive steps: tailscale up (if not done), rclone config, launch 1Password."
    # XXX lid close: mute, lock, suspend
    # XXX cursor to lower right: lock and sleep display
    # XXX cursor to upper right: lock
    # XXX desktop picture showing the hostname
}

# ── Phase detection ───────────────────────────────────────────────────────────

detect_phase() {
    if [[ $EUID -ne 0 ]] || [[ -n "${SWAYSOCK:-}" ]]; then
        echo 3
    elif [[ "$(cat /proc/1/comm 2>/dev/null)" != "systemd" ]]; then
        echo 1   # chroot — systemd is not PID 1
    else
        echo 2   # first boot — systemd running, no user session
    fi
}

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
    local phase="" from_installer=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --phase) phase="${2:-}"; shift 2 ;;
            *) die "Unknown argument: $1. Usage: $0 [--phase 1|2|3]" ;;
        esac
    done

    if [[ -z "$phase" ]]; then
        phase=$(detect_phase)
        # No explicit --phase means we were invoked directly (e.g. curl | bash
        # from the Welcome app). Run the Sway CE baseline before phase 1.
        [[ "$phase" == "1" ]] && from_installer=true
    fi

    case "$phase" in
        1)
            if $from_installer; then
                info "Fetching Sway CE baseline ..."
                curl -fsSL "$SWAY_CE_URL" | bash
            fi
            phase1
            ;;
        2) phase2 ;;
        3) phase3 ;;
        *) die "Unknown phase '${phase}'. Must be 1, 2, or 3." ;;
    esac
}

main "$@"
