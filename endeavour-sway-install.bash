#!/usr/bin/env bash
#
# Usage:
#   Phase 1 — installer chroot (root, no systemd, no graphical session):
#     bash endeavour-sway-install.bash <username> --phase 1
#   Phase 2 — first-boot systemd service (root, systemd running):
#     Invoked automatically by endeavour-sway-firstboot.service.
#   Phase 3 — first TTY login (normal user, no Sway session needed):
#     endeavour-sway-install <username> --phase 3

set -euo pipefail

WARNINGS_FILE="/root/endeavour-setup-warnings.txt"
INSTALL_SCRIPT_DEST="/usr/local/bin/endeavour-sway-install"
MACHINE_CAPS_DEST="/usr/local/bin/machine-caps"
SWAY_LID_HANDLER_DEST="/usr/local/bin/sway-lid-handler"
PHASE3_RUNNER_DEST="/usr/local/bin/endeavour-run-phase3"
FIRSTBOOT_SERVICE="/etc/systemd/system/endeavour-sway-firstboot.service"
SELF_URL="https://raw.githubusercontent.com/schmonz/endeavour-sway-install/main/endeavour-sway-install.bash"
MACHINE_CAPS_URL="https://raw.githubusercontent.com/schmonz/endeavour-sway-install/main/machine-caps.bash"
SWAY_LID_HANDLER_URL="https://raw.githubusercontent.com/schmonz/endeavour-sway-install/main/sway-lid-handler.bash"
PHASE3_RUNNER_URL="https://raw.githubusercontent.com/schmonz/endeavour-sway-install/main/endeavour-run-phase3.bash"
SWAY_CE_URL="https://raw.githubusercontent.com/EndeavourOS-Community-Editions/sway/main/setup_sway_isomode.bash"

# ── Helpers ───────────────────────────────────────────────────────────────────

die()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo "==> $*"; }
warn() { echo "WARN: $*" >&2; }

accumulate_warning() {
    warn "$*"
    [[ $EUID -eq 0 ]] && echo "$*" >> "$WARNINGS_FILE" || true
}

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

append_once() {
    local file="$1" line="$2"
    grep -qF "$line" "$file" 2>/dev/null || printf '%s\n' "$line" >> "$file"
}

pacman_install()    { _sudo pacman -S --noconfirm --needed "$@"; }
aur_install()       { yay -S --noconfirm --needed "$@"; }
system_systemctl() {
    local yes_now=true
    [[ "${1:-}" == "--not-now" ]] && { yes_now=false; shift; }
    if [[ "${1:-}" == "enable" ]] && $yes_now; then
        _sudo systemctl enable --now "${@:2}"
    else
        _sudo systemctl "$@"
    fi
}
user_systemctl() {
    local yes_now=true
    [[ "${1:-}" == "--not-now" ]] && { yes_now=false; shift; }
    if [[ "${1:-}" == "enable" ]] && $yes_now; then
        systemctl --user enable --now "${@:2}"
    else
        systemctl --user "$@"
    fi
}

sway_autostart() {
    local cmd="$1" file="${2:-${HOME}/.config/sway/config.d/autostart_applications}"
    append_once "$file" "exec $cmd"
}

sway_autostart_singleton() {
    local cmd="$1" file="${2:-${HOME}/.config/sway/config.d/autostart_applications}"
    append_once "$file" "exec sh -c \"pkill -f '$cmd' 2>/dev/null; $cmd\""
}

fetch()         { curl -fsSL "$1" -o "$2"; }
source_fetched() { local t; t=$(mktemp); fetch "$1" "$t"; source "$t"; rm -f "$t"; }
run_fetched()    { local t; t=$(mktemp); fetch "$1" "$t"; bash "$t" "${@:2}"; rm -f "$t"; }

clone_if_missing() { local url="$1" dir="$2"; [[ -d "$dir" ]] || git clone "$url" "$dir"; }

# ── Machine capabilities ──────────────────────────────────────────────────────

_source_machine_caps() {
    local dir mc
    dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || dir=""
    mc="${dir}/machine-caps.bash"
    [[ -f "$mc" ]] || mc="${dir}/machine-caps"
    if [[ -f "$mc" ]]; then
        source "$mc"
    else
        source_fetched "$MACHINE_CAPS_URL"
    fi
}
_source_machine_caps
unset -f _source_machine_caps

report_capabilities() {
    local text
    text=$(
        printf "Hardware capability detection (verify these look right for this machine):\n"
        report_machine_caps
        printf "If any flag looks wrong, improve its probe in machine-caps.bash.\n"
    )
    info "$text"
    [[ $EUID -ne 0 ]] || echo "$text" >> "$WARNINGS_FILE"
}

detect_machine_capabilities() {
    run_machine_cap_probes
    report_capabilities
}

detect_target_user() {
    getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 { print $1; exit }'
}

# ── etckeeper ─────────────────────────────────────────────────────────────────

configure_root_git_identity() {
    local root_id="root@$(cat /etc/hostname)"
    git config --global user.email "$root_id"
    git config --global user.name "$root_id"
}

init_etckeeper() {
    etckeeper vcs log --oneline -1 &>/dev/null && return 0
    etckeeper init
    git -C /etc branch -m "$(cat /etc/hostname)"
}

etckeeper_catch_up() {
    etckeeper commit -m 'Track /etc after phase-1 install.' 2>/dev/null || true
    git -C /etc gc --prune 2>/dev/null || warn "git gc failed (non-fatal)."
}

etckeeper_commit() {
    local msg="$1"
    info "etckeeper commit: ${msg}"
    _sudo etckeeper commit -m "$msg"
}

# ── Dotfiles ──────────────────────────────────────────────────────────────────

setup_dotfiles() {
    local target_user="$1" target_home="$2"
    if [[ ! -d "${target_home}/trees/dotfiles" ]]; then
        su - "$target_user" -c \
            "mkdir -p ~/trees && git clone https://github.com/schmonz/dotfiles.git ~/trees/dotfiles"
    fi
    su - "$target_user" -c \
        "ln -sf ~/trees/dotfiles/gitconfig ~/.gitconfig && ln -sf ~/trees/dotfiles/tmux.conf ~/.tmux.conf"
    ln -sf "${target_home}/trees/dotfiles/gitconfig" /root/.gitconfig
}

# ── Logind drop-ins ───────────────────────────────────────────────────────────
#
# All machines: HandlePowerKey=ignore so Sway can handle XF86PowerOff.
# Without suspend/resume: also IdleAction=ignore, HandleLidSwitch=lock,
#   sleep targets masked, sleep.conf drop-in.

write_logind_dropin() {
    local file="$1" content="$2"
    info "Writing ${file} ..."
    _sudo mkdir -p "$(dirname "$file")"
    echo "$content" | _sudo tee "$file" > /dev/null
}

logind_dropin_content() {    # arg: has_resume
    if ${1:-true}; then
        printf '[Login]\nHandlePowerKey=ignore\n'
    else
        printf '[Login]\nIdleAction=ignore\nHandleLidSwitch=lock\nHandleLidSwitchExternalPower=lock\nHandlePowerKey=ignore\nHandlePowerKeyLongPress=ignore\n'
    fi
}

sleep_conf_content() {
    printf '[Sleep]\nAllowHibernation=no\nAllowHybridSleep=no\nAllowSuspendThenHibernate=no\nAllowSuspend=no\n'
}

configure_logind() {
    local has_resume="$1"
    local file
    $has_resume && file="/etc/systemd/logind.conf.d/power-key.conf" \
               || file="/etc/systemd/logind.conf.d/disable-sleep.conf"
    write_logind_dropin "$file" "$(logind_dropin_content "$has_resume")"

    $has_resume && return

    info "Masking sleep/suspend/hibernate targets ..."
    # systemctl mask creates /dev/null symlinks — works in chroot and live system.
    system_systemctl mask \
        hibernate.target \
        hybrid-sleep.target \
        sleep.target \
        suspend-then-hibernate.target \
        suspend.target

    info "Writing /etc/systemd/sleep.conf.d/disable-sleep.conf ..."
    _sudo mkdir -p /etc/systemd/sleep.conf.d
    sleep_conf_content | _sudo tee /etc/systemd/sleep.conf.d/disable-sleep.conf > /dev/null
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

    local powermenu_conf
    powermenu_conf=$(grep -rlE '^\s*set\s+\$powermenu\b' "$sway_conf_dir" 2>/dev/null | head -1 || true)
    if [[ -z "$powermenu_conf" ]]; then
        powermenu_conf="${sway_conf_dir}/config.d/default"
        warn "No \$powermenu definition found; appending to ${powermenu_conf}. Edit exec command if needed."
    fi
    if [[ ! -f "$powermenu_conf" ]]; then
        accumulate_warning "${powermenu_conf} does not exist — XF86PowerOff binding skipped."
        return
    fi

    # Binding may already exist in a different config.d file than powermenu_conf.
    if grep -rlE '^\s*bindsym\s+XF86PowerOff\b' "$sway_conf_dir" 2>/dev/null | grep -q .; then
        info "XF86PowerOff binding already present — skipping."
        return
    fi

    info "Adding XF86PowerOff binding to ${powermenu_conf} ..."
    printf '\nbindsym XF86PowerOff exec $powermenu\n' >> "$powermenu_conf"
    chown "${sway_user}:" "$powermenu_conf"
}

# ── Swayidle ──────────────────────────────────────────────────────────────────

build_swayidle_line() {
    local has_lid_events="$1"
    local common_idle='exec swayidle -w \
    idlehint 1 \
    timeout 300  '"'"'gtklock -d --lock-command "swaymsg output \* dpms off"'"'"' resume '"'"'swaymsg "output * dpms on"'"'"' \
    lock         '"'"'gtklock -d --lock-command "swaymsg output \* dpms off"'"'"' \
    unlock       '"'"'swaymsg "output * dpms on"'"'"''

    local sleep_events='    before-sleep '"'"'gtklock -d; sleep 1'"'"' \
    after-resume '"'"'swaymsg "output * dpms on"'"'"''

    if $has_lid_events; then
        printf '%s' "${common_idle}"$' \\\n'"${sleep_events}"$'\n'
    else
        printf '%s\n' "$common_idle"
    fi
}

setup_swayidle() {
    local has_lid_events="$1"
    local autostart="$HOME/.config/sway/config.d/autostart_applications"
    if [[ ! -f "$autostart" ]]; then
        warn "${autostart} not found — skipping swayidle config."
        return
    fi

    sed -i '/^exec swayidle idlehint/d; /^exec_always swayidle -w before-sleep/d' "$autostart"

    local idle_line
    idle_line=$(build_swayidle_line "$has_lid_events")

    if grep -q 'swayidle' "$autostart"; then
        warn "swayidle line already present in ${autostart} — review manually."
        warn "Expected form:"
        echo "$idle_line" | sed 's/^/    /'
        return
    fi
    printf '\n%s\n' "$idle_line" >> "$autostart"
}

# ── Chromebook: lid handler service ──────────────────────────────────────────

install_lid_handler() {
    local handler="$HOME/.local/bin/sway-lid-handler"
    local service="$HOME/.config/systemd/user/sway-lid-handler.service"
    local autostart="$HOME/.config/sway/config.d/autostart_applications"

    info "Installing ${handler} ..."
    mkdir -p "$(dirname "$handler")"
    local dir
    dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || dir=""
    local src="${dir}/sway-lid-handler.bash"
    [[ -f "$src" ]] || src="${dir}/sway-lid-handler"
    if [[ -f "$src" ]]; then
        cp "$src" "$handler"
    else
        fetch "$SWAY_LID_HANDLER_URL" "$handler"
    fi
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

    user_systemctl daemon-reload
    user_systemctl --not-now enable sway-lid-handler.service
    # Only start now if we're in a graphical session; otherwise it starts at login.
    if [[ -n "${SWAYSOCK:-}" ]]; then
        user_systemctl restart sway-lid-handler.service
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

# ── Phase 3: setup steps ─────────────────────────────────────────────────────

setup_1password() {
    aur_install 1password
    sway_autostart '1password'
}

setup_localsend() {
    aur_install localsend-bin
    # XXX configure LocalSend to use the real system hostname
    # ~/.local/share/org.localsend.localsend_app/shared_preferences.json
    sway_autostart 'localsend --hidden'
}

setup_communication_apps() {
    aur_install slack-electron zoom teams-for-linux-electron-bin
    # Geolocation (disabled): xdg-desktop-portal-gtk + XDG_CURRENT_DESKTOP in sway autostart
    append_once ~/.config/zoomus.conf 'enableWaylandShare=true'
}

setup_cloud_sync() {
    aur_install rclone
    # After auth error: grab Cookie + X-APPLE-WEBAUTH-HSA-TRUST from browser devtools, then:
    #   rclone config update icloud cookies='' trust_token=""
    # Token expires monthly. https://forum.rclone.org/t/icloud-connect-not-working-http-error-400/52019/44
}

setup_dev_environment() {
    aur_install clion clion-jre
}

setup_writing_tools() {
    aur_install dawn-writer-bin
}

setup_claude_tools() {
    aur_install claude-code claude-desktop-bin claude-cowork-service
}

setup_tailscale_userspace() {
    local target_user="$1"
    # Group membership gives persistent socket access regardless of auth state.
    # --operator is belt-and-suspenders for CLI authorization.
    _sudo usermod -aG tailscale "$target_user" 2>/dev/null || true
    _sudo tailscale set --operator="$target_user"
    sway_autostart_singleton 'tailscale systray'
    # accept-dns and accept-routes require an authenticated session; moved to notes.
}

update_firmware() {
    echo y | fwupdmgr get-updates || true
    fwupdmgr update || true
    # MrChromebox firmware: https://docs.mrchromebox.tech/docs/firmware/updating-firmware.html
}

setup_update_notifier() {
    eos-update-notifier -init
}

configure_desktop_tools() {
    sed -i 's/htop/btop/g' ~/.config/waybar/config
    sed -i 's/waybar_htop/waybar_btop/g' ~/.config/sway/config.d/application_defaults
    sed -i 's|^# launch=xdg-open \${url}$|launch=xdg-open ${url}|' ~/.config/foot/foot.ini
}

revoke_phase3_sudo() {
    _sudo rm -f /etc/sudoers.d/99-phase3-nopasswd
    etckeeper_commit "Remove temporary phase-3 NOPASSWD sudo."
}

# ── Machine-specific stubs (phase 3) ─────────────────────────────────────────

setup_avs_audio() {
    info "Setting up Chromebook audio ..."
    clone_if_missing https://github.com/WeirdTreeThing/chromebook-linux-audio ~/trees/chromebook-linux-audio
    (cd ~/trees/chromebook-linux-audio && echo "I UNDERSTAND THE RISK OF PERMANENTLY DAMAGING MY SPEAKERS" | ./setup-audio --force-avs-install)
}

setup_cros_fkeys() {
    info "Setting up Chromebook F-keys ..."
    clone_if_missing https://github.com/WeirdTreeThing/cros-keyboard-map ~/trees/cros-keyboard-map
    (cd ~/trees/cros-keyboard-map && ./install.sh)
}

setup_mac_fan() {
    aur_install mbpfan
    _sudo cp /usr/lib/systemd/system/mbpfan.service /etc/systemd/system/
    system_systemctl enable mbpfan.service
}

setup_mac_light_sensors() {
    # clight is installed + started in the HAS_AMBIENT_LIGHT_SENSOR block above (iio-sensor-proxy + clightd).
    # Without a floor, clight maps a dark room to 0% brightness — invisible screen.
    _sudo mkdir -p /etc/clight/modules.conf.d
    _sudo tee /etc/clight/modules.conf.d/sensor.conf > /dev/null << 'EOF'
// Minimum brightness floor: dark room -> 10% screen, not 0%.
// Raise toward 0.15-0.20 if 10% still feels too dark.
ac_regression_points = (0.0, 0.10, 0.20, 0.40, 0.60, 0.80, 1.0);
batt_regression_points = (0.0, 0.10, 0.20, 0.40, 0.60, 0.80, 1.0);
EOF
    # XXX also configure the dimmer module: target 40% (not 0%) after 60s on battery.
    # Verify exact key names against `man clight` or /usr/share/clight/modules.conf.d/
    # before writing — likely something like:
    #   batt_timeouts = (60, 300);
    #   screen_targets = (0.4, 0.4);
    # in /etc/clight/modules.conf.d/dimmer.conf
}

# Idempotently add PARAMS to grub variable VAR, guarded by CHECK already present.
# Handles empty and non-empty values, single- or double-quoted.
transform_grub_param() {
    local var="$1" check="$2" params="$3"
    # Portably handle empty and non-empty quoted values using BRE.
    # BSD sed -E does not support backreferences in the search pattern.
    sed -e "/^${var}=/ {" \
        -e "/${check}/! {" \
        -e "s/^\(${var}=\([\"']\)\)\2$/\1${params}\2/" \
        -e "t" \
        -e "s/^\(${var}=\([\"']\).*\)\2$/\1 ${params}\2/" \
        -e "}" \
        -e "}"
}

add_grub_param() {
    local var="$1" check="$2" params="$3"
    local new_content
    new_content=$(transform_grub_param "$var" "$check" "$params" < /etc/default/grub)
    echo "$new_content" | _sudo tee /etc/default/grub > /dev/null
}

rebuild_grub() { _sudo grub-mkconfig -o /boot/grub/grub.cfg; }

setup_nvidia_display() {
    # For MacBookPro5,2 so the display manager comes up on the real screen.
    # Targets GRUB_CMDLINE_LINUX (not _DEFAULT) so recovery boots also get the fix.
    add_grub_param GRUB_CMDLINE_LINUX video=LVDS-2:d video=LVDS-2:d
    rebuild_grub
}

setup_zswap() {
    # Targets GRUB_CMDLINE_LINUX_DEFAULT — performance optimization, not needed in recovery.
    add_grub_param GRUB_CMDLINE_LINUX_DEFAULT zswap.enabled=1 \
        "zswap.enabled=1 zswap.compressor=zstd zswap.zpool=z3fold zswap.max_pool_percent=20"
    rebuild_grub
}

setup_web_browser() {
    aur_install helium-browser-bin ungoogled-chromium-bin webapp-manager
    append_once ~/.config/sway/config.d/application_defaults \
        'for_window [app_id="helium"] inhibit_idle fullscreen'
    sed -i 's|exec firefox|exec xdg-open https://|g' ~/.config/sway/config.d/default

    local wconf="$HOME/.config/EOS-greeter.conf"
    if grep -q "^Greeter=" "$wconf" 2>/dev/null; then
        sed -i 's|^Greeter=.*|Greeter=disable|' "$wconf"
    else
        printf 'Greeter=disable\nLastCheck=0\nOnceDaily=no\n' > "$wconf"
    fi

    mkdir -p ~/.local/share/applications/kde4
    printf '[Desktop Entry]\nHidden=true\n' > ~/.local/share/applications/chromium.desktop
    printf '[Desktop Entry]\nHidden=true\n' > ~/.local/share/applications/kde4/webapp-manager.desktop

    mkdir -p ~/.config
    cat > ~/.config/mimeapps.list << 'EOF'
[Default Applications]
x-scheme-handler/http=helium.desktop
x-scheme-handler/https=helium.desktop
text/html=helium.desktop
application/xhtml+xml=helium.desktop
EOF

    local _prefs='{"browser":{"check_default_browser":false},"session":{"restore_on_startup":1}}'
    local _init='{"browser":{"check_default_browser":false},"distribution":{"skip_first_run_ui":true,"suppress_first_run_bubble":true,"show_welcome_page":false},"session":{"restore_on_startup":1}}'
    mkdir -p ~/.config/net.imput.helium/Default ~/.config/chromium/Default
    printf '%s\n' "$_init" \
        | tee ~/.config/net.imput.helium/initial_preferences \
              ~/.config/chromium/initial_preferences > /dev/null
    printf '%s\n' "$_prefs" \
        | tee ~/.config/net.imput.helium/Default/Preferences \
              ~/.config/chromium/Default/Preferences > /dev/null

    printf -- '--password-store=basic\n' > ~/.config/helium-browser-flags.conf
    printf -- '--password-store=basic\n' > ~/.config/chromium-flags.conf
}

setup_clipboard_helpers() {
    mkdir -p /usr/local/bin
    printf '#!/bin/sh\nexec wl-copy "$@"\n' > /usr/local/bin/pbcopy
    printf '#!/bin/sh\nexec wl-paste --no-newline "$@"\n' > /usr/local/bin/pbpaste
    chmod +x /usr/local/bin/pbcopy /usr/local/bin/pbpaste
}

setup_pacman_cache() {
    pacman_install pacman-contrib
    system_systemctl enable paccache.timer
}

setup_power_saving() {
    : # TLP: https://wiki.archlinux.org/title/TLP
}

setup_timeshift() {
    aur_install timeshift-autosnap
    system_systemctl enable cronie
}

setup_ambient_light_sensor() {
    aur_install iio-sensor-proxy clight
    system_systemctl enable clightd
    sway_autostart 'clight'
    ls /sys/bus/iio/devices/*/in_illuminance* || true
}

setup_facetimehd() {
    aur_install facetimehd-dkms
}

setup_infrared_receiver() {
    : # LIRC: https://wiki.archlinux.org/title/LIRC
}

setup_thinkpad_goodies() {
    : # XXX smart card?
      # XXX T60 volume and power buttons, ThinkVantage button, fingerprint reader
}

setup_kbd_backlight() {
    local kbd_dev
    kbd_dev=$(brightnessctl --list 2>/dev/null | awk -F"'" '/[Kk]eyboard/{print $2; exit}')
    if [[ -n "$kbd_dev" ]]; then
        info "Keyboard backlight device: ${kbd_dev}"
        brightnessctl --device="$kbd_dev" set 50%
        if ! grep -q "XF86KbdBrightnessUp" ~/.config/sway/config.d/default 2>/dev/null; then
            sed -i "/XF86MonBrightnessDown/a\\        XF86KbdBrightnessUp exec brightnessctl -d '${kbd_dev}' set +5%\\n        XF86KbdBrightnessDown exec brightnessctl -d '${kbd_dev}' set 5%-" \
                ~/.config/sway/config.d/default
        fi
    else
        accumulate_warning "No keyboard backlight device found — skipping kbd brightness bindings."
    fi
}

setup_software_gl() {
    info "Enabling software GL rendering (LIBGL_ALWAYS_SOFTWARE=1) ..."
    mkdir -p ~/.config/environment.d
    echo 'LIBGL_ALWAYS_SOFTWARE=1' > ~/.config/environment.d/50-softgl.conf
}

# ── First-boot service (written by phase 1, runs as phase 2) ─────────────────

install_firstboot_service() {
    info "Installing ${FIRSTBOOT_SERVICE} ..."
    if [[ -f "$0" ]]; then
        local src
        src="$(dirname "$0")"
        cp "$0"                              "$INSTALL_SCRIPT_DEST"
        cp "${src}/machine-caps.bash"        "$MACHINE_CAPS_DEST"
        cp "${src}/sway-lid-handler.bash"    "$SWAY_LID_HANDLER_DEST"
        cp "${src}/endeavour-run-phase3.bash" "$PHASE3_RUNNER_DEST"
    else
        # Piped via curl | bash — $0 is not a real file; fetch the scripts directly.
        fetch "$SELF_URL"             "$INSTALL_SCRIPT_DEST"
        fetch "$MACHINE_CAPS_URL"     "$MACHINE_CAPS_DEST"
        fetch "$SWAY_LID_HANDLER_URL" "$SWAY_LID_HANDLER_DEST"
        fetch "$PHASE3_RUNNER_URL"    "$PHASE3_RUNNER_DEST"
    fi
    chmod +x "$INSTALL_SCRIPT_DEST" "$MACHINE_CAPS_DEST" "$SWAY_LID_HANDLER_DEST" "$PHASE3_RUNNER_DEST"

    cat > "$FIRSTBOOT_SERVICE" << EOF
[Unit]
Description=EndeavourOS Sway first-boot setup (phase 2)
Documentation=file://${INSTALL_SCRIPT_DEST}
After=network-online.target nss-lookup.target systemd-user-sessions.service
Wants=network-online.target nss-lookup.target
ConditionPathExists=${INSTALL_SCRIPT_DEST}

[Service]
Type=oneshot
ExecStart=${INSTALL_SCRIPT_DEST} ${target_user} --phase 2
RemainAfterExit=no
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    system_systemctl --not-now enable endeavour-sway-firstboot.service
    info "First-boot service installed and enabled."
    info "Script saved to ${INSTALL_SCRIPT_DEST} — call with --phase 3 after first login."
}

# ── Phase 3 auto-runner (set up in phase 2, fires on first Sway login) ────────

install_phase3_runner() {
    local target_home="$1" target_user="$2"
    local runner="${target_home}/.local/bin/endeavour-run-phase3"
    mkdir -p "$(dirname "$runner")"

    local dir src
    dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || dir=""
    src="${dir}/endeavour-run-phase3.bash"
    [[ -f "$src" ]] || src="${dir}/endeavour-run-phase3"
    if [[ -f "$src" ]]; then
        cp "$src" "$runner"
    else
        fetch "$PHASE3_RUNNER_URL" "$runner"
    fi
    chmod +x "$runner"

    # Register in .bash_profile so it runs on TTY login (not in the Sway autostart).
    local bash_profile="${target_home}/.bash_profile"
    touch "$bash_profile"
    chown "${target_user}:" "$bash_profile"
    append_once "$bash_profile" "$runner"
}

run_setup_step() {
    local func="$1" msg="$2" commit_msg="$3"
    shift 3
    info "$msg"
    "$func" "$@"
    etckeeper_commit "$commit_msg"
}

# ── Setup steps (called via run_setup_step) ───────────────────────────────────

setup_autologin() {
    local user="$1" session_cmd="${2:-sway}"
    local conf=/etc/greetd/greetd.conf
    # https://github.com/EndeavourOS-Community-Editions/sway/issues/105
    if grep -q 'initial_session' "$conf" 2>/dev/null; then
        if grep -qF "\"${session_cmd}\"" "$conf" 2>/dev/null; then
            info "Autologin already configured (${session_cmd})."
            return
        fi
        # Replace existing block (always the last section) with the new command.
        _sudo sed -i '/^\[initial_session\]/,$ d' "$conf"
    fi
    printf '\n[initial_session]\ncommand = "%s"\nuser = "%s"\n' \
        "$session_cmd" "$user" \
        | _sudo tee -a "$conf" > /dev/null
}

setup_keyboard_layout() {
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
}

setup_1password_browser_integration() {
    mkdir -p /etc/1password
    grep -qF 'helium' /etc/1password/custom_allowed_browsers 2>/dev/null \
        || echo 'helium' >> /etc/1password/custom_allowed_browsers
}

setup_eos_update_notifier_conf() {
    sed -i 's|ShowHowAboutUpdates=notify\b|ShowHowAboutUpdates=notify+tray|' \
        /etc/eos-update-notifier.conf 2>/dev/null || true
}

setup_firewall_zone() {
    firewall-cmd --set-default-zone=home
}

setup_firewall_localsend() {
    firewall-cmd --add-port=53317/tcp --permanent
    firewall-cmd --add-port=53317/udp --permanent
}

setup_systemd_resolved() {
    ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
    system_systemctl --not-now enable systemd-resolved
}

setup_logind_config() {
    configure_logind $HAS_RESUME
    $HAS_POWERBUTTON_EVENTS || write_thinkpad_udev_rule
}

setup_bluetooth() {
    system_systemctl enable bluetooth
    # bluetoothctl pairing: https://wiki.archlinux.org/title/Bluetooth#Pairing
}

setup_tailscaled() {
    system_systemctl enable tailscaled
}

remove_firstboot_service() {
    system_systemctl disable endeavour-sway-firstboot.service 2>/dev/null || true
    rm -f "$FIRSTBOOT_SERVICE"
}

write_phase3_sudoers() {
    local user="$1"
    local file="/etc/sudoers.d/99-phase3-nopasswd"
    printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$user" > "$file"
    chmod 440 "$file"
}

# ── Phase 1: install steps ────────────────────────────────────────────────────

remove_firefox()           { pacman -Rs --noconfirm firefox 2>/dev/null || true; }
install_version_control()  { pacman_install etckeeper git git-delta; }
install_bluetooth()        { pacman_install blueman; }
install_networking()       { pacman_install gvfs-dnssd tailscale; }
install_keyring()          { pacman_install seahorse; }
install_firmware_tools()   { pacman_install fwupd; }
install_communication()    { pacman_install discord signal-desktop guvcview; }
install_office_suite()     { pacman_install libreoffice-fresh abiword; }
install_printing()         { pacman_install cups cups-browsed system-config-printer; }
install_desktop_portals()  { pacman_install xdg-desktop-portal xdg-desktop-portal-wlr; }
install_update_notifier()  { pacman_install eos-update-notifier; }
install_system_tools()     { pacman_install btop fastfetch tmux the_silver_searcher xorg-xhost; }
install_dev_tools()        { pacman_install apostrophe glow tig github-cli socat bats; }
install_snapshot_support() { pacman_install grub-btrfs; }

# ── Phase 1: installer chroot ─────────────────────────────────────────────────

phase1() {
    [[ $EUID -eq 0 ]] || die "Phase 1 must run as root."

    local target_user target_home
    target_user=$(detect_target_user)
    [[ -n "$target_user" ]] \
        || die "No user found with uid >= 1000. Has Calamares created the user yet?"
    target_home=$(getent passwd "$target_user" | cut -d: -f6)

    detect_machine_capabilities
    configure_root_git_identity

    remove_firefox
    install_version_control
    init_etckeeper

    install_bluetooth
    install_networking
    install_keyring
    install_firmware_tools
    install_communication
    install_office_suite
    install_printing
    install_desktop_portals
    install_update_notifier
    install_system_tools
    install_dev_tools
    install_snapshot_support

    run_setup_step setup_autologin \
        "=== Phase 1: autologin ===" \
        "Enable autologin (TTY, for phase 3)." "$target_user" "bash --login"

    run_setup_step setup_keyboard_layout \
        "=== Phase 1: macOS keyboard layout ===" \
        "Enable Mac-like accents with Right-Alt."

    info "=== Phase 1: pbcopy / pbpaste ==="
    setup_clipboard_helpers

    run_setup_step setup_1password_browser_integration \
        "=== Phase 1: 1Password browser integration ===" \
        "Allow Helium browser in 1Password."

    run_setup_step setup_eos_update_notifier_conf \
        "=== Phase 1: eos-update-notifier ===" \
        "Configure eos-update-notifier to use system tray."

    run_setup_step setup_systemd_resolved \
        "=== Phase 1: systemd-resolved ===" \
        "Enable systemd-resolved."

    run_setup_step setup_logind_config \
        "=== Phase 1: logind / sleep config ===" \
        "Configure logind and sleep settings."

    run_setup_step install_firstboot_service \
        "=== Phase 1: first-boot service ===" \
        "Install first-boot service."

    info "=== Phase 1: phase 3 autostart ==="
    install_phase3_runner "$target_home" "$target_user"

    run_setup_step write_phase3_sudoers \
        "=== Phase 1: phase 3 passwordless sudo ===" \
        "Grant temporary NOPASSWD sudo for phase 3." "$target_user"

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

    detect_machine_capabilities

    info "=== Phase 2: dotfiles ==="
    setup_dotfiles "$target_user" "$target_home"

    info "=== Phase 2: etckeeper commit ==="
    etckeeper_catch_up

    run_setup_step setup_bluetooth \
        "=== Phase 2: Bluetooth ===" \
        "Enable Bluetooth."

    run_setup_step setup_tailscaled \
        "=== Phase 2: Tailscale ===" \
        "Enable Tailscale daemon."

    run_setup_step setup_pacman_cache \
        "=== Phase 2: pacman cache ===" \
        "Periodically clean pacman cache."

    run_setup_step setup_firewall_zone \
        "=== Phase 2: firewall zone ===" \
        "Set default firewall zone to 'home'."

    run_setup_step setup_firewall_localsend \
        "=== Phase 2: firewall LocalSend ===" \
        "Allow LocalSend through firewall."

    info "=== Phase 2: firewall reload ==="
    firewall-cmd --reload

    info "=== Phase 2: logind restart ==="
    $HAS_POWERBUTTON_EVENTS || reload_thinkpad_udev

    run_setup_step setup_autologin \
        "=== Phase 2: autologin (re-apply if installer overwrote greetd.conf) ===" \
        "Enable autologin (TTY, for phase 3)." "$target_user" "bash --login"

    run_setup_step remove_firstboot_service \
        "=== Phase 2: remove firstboot service ===" \
        "Remove phase-2 firstboot service."

    info "=== Phase 2: phase 3 autostart ==="
    if [[ -f "$WARNINGS_FILE" ]]; then
        install -D -o "$target_user" "$WARNINGS_FILE" "${target_home}/.config/endeavour-warnings"
        rm -f "$WARNINGS_FILE"
    fi
    install_phase3_runner "$target_home" "$target_user"

    info ""
    info "Phase 2 complete. Phase 3 will start automatically on first TTY login."
}

# ── Phase 3: first Sway session ───────────────────────────────────────────────

phase3() {
    local target_user="$1"
    require_sudo
    detect_machine_capabilities

    # XXX CLI equivalent: open the Timeshift app and follow the prompts
    # XXX once automated, this graduates to Phase 2
    run_setup_step setup_timeshift \
        "=== Phase 3: timeshift ===" \
        "Enable Timeshift."
    setup_1password
    setup_web_browser
    setup_localsend
    setup_communication_apps
    setup_cloud_sync
    setup_dev_environment
    setup_writing_tools
    setup_claude_tools
    setup_tailscale_userspace "$target_user"
    setup_power_saving
    update_firmware
    setup_update_notifier
    configure_desktop_tools
    setup_swayidle $HAS_LID_EVENTS

    $HAS_AVS_AUDIO              && setup_avs_audio
    $HAS_CROS_FKEYS             && setup_cros_fkeys
    $HAS_LID_EVENTS             || install_lid_handler
    $HAS_KBD_BACKLIGHT          && setup_kbd_backlight
    $HAS_APPLESMC               && run_setup_step setup_mac_fan \
        "Installing mbpfan ..." \
        "Enable mbpfan Mac fan control."
    $HAS_FACETIMEHD             && setup_facetimehd
    $HAS_PHANTOM_SECOND_DISPLAY && run_setup_step setup_nvidia_display \
        "Disabling phantom second internal display (LVDS-2) ..." \
        "Disable second internal display (MacBookPro5,2 LVDS-2)."
    $HAS_PLENTY_OF_RAM          || run_setup_step setup_zswap \
        "Enabling zswap ..." \
        "Enable zswap."
    $HAS_GL_CAPABLE_GPU         || setup_software_gl
    $HAS_IR_RECEIVER            && setup_infrared_receiver
    $HAS_THINKPAD_HARDWARE      && setup_thinkpad_goodies
    add_sway_poweroff_binding "$target_user"
    $HAS_POWERBUTTON_EVENTS     || \
        info "Note: the udev grab release requires a re-login or reboot to take full effect."

    run_setup_step setup_autologin \
        "=== Phase 3: reconfigure autologin to Sway ===" \
        "Switch greetd autologin from TTY to Sway." "$target_user"
    revoke_phase3_sudo

    info ""
    info "Phase 3 complete."
    info "  Remaining interactive steps after reboot: tailscale up; tailscale set --accept-dns=true; tailscale set --accept-routes; rclone config (optional)."
}

# ── Phase detection ───────────────────────────────────────────────────────────

in_user_session() { [[ ${EUID_OVERRIDE:-$EUID} -ne 0 ]] || [[ -n "${SWAYSOCK:-}" ]]; }
in_chroot()       { [[ ! -d "${PROBE_ROOT:-}/run/systemd/system" ]]; }

detect_phase() {
    if in_user_session; then
        echo 3
    elif in_chroot; then
        echo 1
    else
        echo 2   # first boot — systemd running, no user session
    fi
}

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
    local phase="" from_installer=false

    local username="$1"; shift

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --phase) phase="${2:-}"; shift 2 ;;
            *) die "Unknown argument: $1. Usage: $0 <username> [--phase 1|2|3]" ;;
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
                run_fetched "$SWAY_CE_URL" "$username"
            fi
            phase1
            ;;
        2) phase2 ;;
        3) phase3 "$username" ;;
        *) die "Unknown phase '${phase}'. Must be 1, 2, or 3." ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
