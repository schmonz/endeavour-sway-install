#!/usr/bin/env bash
# endeavour-sway-postinstall.sh
#
# Post-install setup for EndeavourOS Sway edition.
# Run as your normal user (sudo used internally where needed).
# Safe to re-run; writes are idempotent where practical.
#
# Boot repair references (not run by this script — for emergencies):
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

swaymsg_reload() {
    if [[ -n "${SWAYSOCK:-}" ]]; then
        info "Reloading Sway config ..."
        swaymsg reload
    else
        warn "Not in a Sway session — reload manually with: swaymsg reload"
    fi
}

# Append LINE to FILE only if not already present.
append_once() {
    local file="$1" line="$2"
    grep -qF "$line" "$file" 2>/dev/null || printf '%s\n' "$line" >> "$file"
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

# ── etckeeper ─────────────────────────────────────────────────────────────────

etckeeper_commit() {
    local msg="$1"
    if command -v etckeeper &>/dev/null; then
        info "etckeeper commit: ${msg}"
        sudo etckeeper commit -m "$msg" 2>/dev/null || warn "etckeeper commit failed (non-fatal)."
    fi
}

# ── Revision-controlled /etc ──────────────────────────────────────────────────

setup_etckeeper() {
    info "Setting up dotfiles and etckeeper ..."

    mkdir -p ~/trees
    if [[ ! -d ~/trees/dotfiles ]]; then
        git clone https://github.com/schmonz/dotfiles.git ~/trees/dotfiles
    fi
    ln -sf ~/trees/dotfiles/gitconfig ~/.gitconfig
    sudo ln -sf ~/trees/dotfiles/gitconfig /root/.gitconfig

    sudo pacman -Syuu --noconfirm
    sudo pacman -S --noconfirm etckeeper git-delta

    if ! sudo etckeeper vcs log --oneline -1 &>/dev/null; then
        sudo etckeeper init
        sudo etckeeper commit -m 'Track /etc in revision control.'
    fi

    local current_branch
    current_branch=$(sudo git -C /etc symbolic-ref --short HEAD 2>/dev/null || true)
    if [[ "$current_branch" != "$(hostname)" ]]; then
        sudo git -C /etc branch -m "$(hostname)"
        sudo git -C /etc gc --prune
    fi
}

# ── pacman cache cleanup ──────────────────────────────────────────────────────

setup_pacman_cache() {
    info "Configuring pacman cache cleanup ..."
    # XXX CLI equivalent for "Package Cleanup Configuration" from the Welcome screen
    # (that GUI creates paccache.service + paccache.timer)
    etckeeper_commit "Periodically clean pacman cache."
}

# ── Timeshift rollback ────────────────────────────────────────────────────────

setup_timeshift() {
    info "Setting up Timeshift ..."
    yay -S --noconfirm timeshift-autosnap
    sudo pacman -S --noconfirm grub-btrfs xorg-xhost snapper inotify-tools
    sudo systemctl enable --now cronie
    # XXX CLI equivalent: open the Timeshift app and follow the prompts
    # XXX snapper also? instead? does it integrate with pacman too?
    etckeeper_commit "Enable Timeshift."
}

# ── Autologin ─────────────────────────────────────────────────────────────────

setup_autologin() {
    info "Configuring autologin for ${USER} ..."
    # https://github.com/EndeavourOS-Community-Editions/sway/issues/105
    if ! grep -q 'initial_session' /etc/greetd/greetd.conf; then
        sudo tee -a /etc/greetd/greetd.conf > /dev/null << EOF

[initial_session]
command = "sway"
user = "$USER"
EOF
        etckeeper_commit "Enable autologin."
    else
        info "Autologin already configured."
    fi
}

# ── Dotfiles ──────────────────────────────────────────────────────────────────

setup_dotfiles() {
    info "Linking dotfiles ..."
    ln -sf ~/trees/dotfiles/tmux.conf ~/.tmux.conf
}

# ── macOS habits ──────────────────────────────────────────────────────────────

setup_macos_habits() {
    info "Configuring macOS-compatible accents ..."
    sudo localectl set-x11-keymap us "" mac
    etckeeper_commit "Enable Mac-like accents with Right-Alt."
    swaymsg_reload

    info "Installing pbcopy/pbpaste ..."
    printf '#!/bin/sh\nexec wl-copy "$@"\n' | sudo tee /usr/local/bin/pbcopy > /dev/null
    printf '#!/bin/sh\nexec wl-paste --no-newline "$@"\n' | sudo tee /usr/local/bin/pbpaste > /dev/null
    sudo chmod +x /usr/local/bin/pbcopy /usr/local/bin/pbpaste
}

# ── Firmware updates ──────────────────────────────────────────────────────────

setup_firmware_updates() {
    info "Checking firmware updates ..."
    sudo pacman -S --noconfirm fwupd
    fwupdmgr get-updates || true
    fwupdmgr update || true
    # MrChromebox firmware: https://docs.mrchromebox.tech/docs/firmware/updating-firmware.html
}

# ── Bluetooth ─────────────────────────────────────────────────────────────────

setup_bluetooth() {
    info "Enabling Bluetooth ..."
    sudo systemctl enable --now bluetooth
    sudo pacman -S --noconfirm blueman
    # XXX what's --needed (skips already-installed packages)
    # bluetoothctl pairing: https://wiki.archlinux.org/title/Bluetooth#Pairing
}

# ── Power-saving ──────────────────────────────────────────────────────────────

setup_power_saving() {
    : # TLP: https://wiki.archlinux.org/title/TLP
}

# ── Keyboard backlight and screen brightness ──────────────────────────────────

setup_keyboard_backlight() {
    info "Setting up keyboard backlight and screen brightness ..."
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
    yay -S --noconfirm iio-sensor-proxy clight
    sudo systemctl enable --now clightd
    append_once ~/.config/sway/config.d/autostart_applications 'exec clight'
    [[ -n "${SWAYSOCK:-}" ]] && clight &
}

# ── Mac fan control ───────────────────────────────────────────────────────────

setup_mac_fan() {
    info "Installing mbpfan ..."
    yay -S --noconfirm mbpfan
    sudo cp /usr/lib/systemd/system/mbpfan.service /etc/systemd/system/
    sudo systemctl enable --now mbpfan.service
    etckeeper_commit "Enable mbpfan Mac fan control."
}

# ── Mac light sensors ─────────────────────────────────────────────────────────

setup_mac_light_sensors() {
    : # lightum: https://github.com/poliva/lightum
      # macbook-lighter: https://github.com/harttle/macbook-lighter
      # pommed: https://packages.debian.org/trixie/pommed
      # pommed-light: https://github.com/bytbox/pommed-light
      # Debian Mactel Team: https://qa.debian.org/developer.php?login=team%2Bpkg-mactel-devel%40tracker.debian.org
}

# ── Webcam ────────────────────────────────────────────────────────────────────

setup_webcam() {
    info "Setting up webcam ..."
    # FaceTime webcam (e.g. MacBookAir7,1)
    yay -S --noconfirm facetimehd-dkms
    sudo modprobe  # XXX missing module name
    # iSight webcam — not sure who needs this:
    # yay -S --noconfirm isight-firmware
    sudo pacman -S --noconfirm guvcview
}

# ── NVIDIA display workaround ─────────────────────────────────────────────────

setup_nvidia_display() {
    : # For MacBookPro5,2: disable phantom second internal display (LVDS-2) so
      # the display manager comes up on the real screen.
      # XXX doesn't match — verify correct pattern before uncommenting:
      # sudo sed -i "/^GRUB_CMDLINE_LINUX_DEFAULT'=/"'{
      #   /video=LVDS-2:d/! s/"$/ video=LVDS-2:d/
      # }' /etc/default/grub
      # sudo grub-mkconfig -o /boot/grub/grub.cfg
      # etckeeper_commit "Disable second internal display."
}

# ── zswap ─────────────────────────────────────────────────────────────────────

setup_zswap() {
    : # For RAM-limited machines.
      # XXX doesn't match — verify correct pattern before uncommenting:
      # sudo sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT=/{
      #   /zswap.enabled=1/! s/"$/ zswap.enabled=1 zswap.compressor=zstd zswap.zpool=z3fold zswap.max_pool_percent=20/
      # }' /etc/default/grub
      # sudo grub-mkconfig -o /boot/grub/grub.cfg
      # etckeeper_commit "Enable zswap."
}

# ── Chromebook audio ──────────────────────────────────────────────────────────

setup_chromebook_audio() {
    info "Setting up Chromebook audio ..."
    if [[ ! -d ~/trees/chromebook-linux-audio ]]; then
        git clone https://github.com/WeirdTreeThing/chromebook-linux-audio ~/trees/chromebook-linux-audio
    fi
    cd ~/trees/chromebook-linux-audio
    echo "WHATEVER IT WANTS ME TO SAY" | ./setup-audio --force-avs-install  # XXX placeholder response
    cd -
}

# ── Chromebook F-keys ─────────────────────────────────────────────────────────

setup_chromebook_fkeys() {
    info "Setting up Chromebook F-keys ..."
    if [[ ! -d ~/trees/cros-keyboard-map ]]; then
        git clone https://github.com/WeirdTreeThing/cros-keyboard-map ~/trees/cros-keyboard-map
    fi
    cd ~/trees/cros-keyboard-map
    ./install.sh
    cd -
}

# ── Infrared receiver ─────────────────────────────────────────────────────────

setup_infrared_receiver() {
    : # LIRC: https://wiki.archlinux.org/title/LIRC
}

# ── ThinkPad goodies ──────────────────────────────────────────────────────────

setup_thinkpad_goodies() {
    : # XXX smart card?
      # XXX T60 volume and power buttons, ThinkVantage button, fingerprint reader
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
    printf '\n# Power button → power menu (added by endeavour-sway-postinstall.sh)\nbindsym XF86PowerOff exec $powermenu\n' \
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

# ── Passwords ─────────────────────────────────────────────────────────────────

setup_passwords() {
    info "Setting up password manager ..."
    sudo pacman -S --noconfirm seahorse
    yay -S --noconfirm 1password
    append_once ~/.config/sway/config.d/autostart_applications 'exec 1password'
    [[ -n "${SWAYSOCK:-}" ]] && 1password &
}

# ── Web ───────────────────────────────────────────────────────────────────────

setup_web() {
    info "Setting up web browser ..."
    sudo pacman -Rs --noconfirm firefox
    sudo mkdir -p /etc/1password
    echo 'helium' | sudo tee -a /etc/1password/custom_allowed_browsers > /dev/null
    etckeeper_commit "Enable Helium 1Password integration."
    yay -S --noconfirm helium-browser-bin ungoogled-chromium-bin webapp-manager
    append_once ~/.config/sway/config.d/application_defaults \
        'for_window [app_id="helium"] inhibit_idle fullscreen'
    sed -i 's|exec firefox|exec xdg-open https://|g' ~/.config/sway/config.d/default
    swaymsg_reload
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
}

# ── Networking ────────────────────────────────────────────────────────────────

setup_networking() {
    info "Configuring local network and Tailscale ..."
    # XXX clicking URLs in Foot how?

    sudo firewall-cmd --set-default-zone=home
    sudo firewall-cmd --reload
    etckeeper_commit "Set default firewall zone to 'home'."
    sudo pacman -S --noconfirm gvfs-dnssd
    info "Log out and back in for Thunar Network view to show shares."

    sudo systemctl enable --now systemd-resolved
    sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
    sudo pacman -S --noconfirm tailscale
    sudo systemctl enable --now tailscaled
    etckeeper_commit "Enable Tailscale."
    sudo tailscale set --operator="$USER"
    append_once ~/.config/sway/config.d/autostart_applications 'exec tailscale systray'
    [[ -n "${SWAYSOCK:-}" ]] && tailscale systray &
    tailscale up
    # XXX the more I logout and login, the more tailscale systray icons I have
    # XXX is this true for other systray icons as well?
    # XXX maybe exit node also isn't working? admin console says:
    # XXX   "This machine is misconfigured and cannot relay traffic."
    # XXX but maybe that's enough for Plex (or Jellyfin)
    tailscale set --accept-dns=true
    tailscale set --accept-routes

    yay -S --noconfirm localsend-bin
    sudo firewall-cmd --add-port=53317/tcp --permanent
    sudo firewall-cmd --add-port=53317/udp --permanent
    sudo firewall-cmd --reload
    etckeeper_commit "Allow LocalSend through firewall."
    append_once ~/.config/sway/config.d/autostart_applications 'exec localsend --hidden'
    [[ -n "${SWAYSOCK:-}" ]] && localsend --hidden &
    # XXX configure LocalSend to use the real system hostname
    # XXX T60: 'unable to create a GL context' — try: sudo pacman -S vulkan-radeon
}

# ── Social ────────────────────────────────────────────────────────────────────

setup_social() {
    info "Installing social apps ..."
    sudo pacman -S --noconfirm discord signal-desktop
    yay -S --noconfirm slack-electron
}

# ── Cloud storage ─────────────────────────────────────────────────────────────

setup_cloud_storage() {
    info "Setting up rclone / iCloud ..."
    yay -S --noconfirm rclone
    rclone config
    # After authentication error: log into icloud.com in a browser, open Chrome
    # Dev Tools → Network tab, click a request, grab the full Cookie header and
    # X-APPLE-WEBAUTH-HSA-TRUST value, then:
    #   rclone config update icloud cookies='' trust_token=""
    # Token expires monthly (~30 days).
    # https://forum.rclone.org/t/icloud-connect-not-working-http-error-400/52019/44
}

# ── Code ──────────────────────────────────────────────────────────────────────

setup_code() {
    info "Installing development tools ..."
    sudo pacman -S --noconfirm apostrophe glow tig github-cli socat
    yay -S --noconfirm \
        clion clion-jre \
        intellij-idea-ultimate-edition \
        goland goland-jre \
        webstorm webstorm-jre \
        pycharm \
        dawn-writer-bin \
        claude-code claude-desktop-bin claude-cowork-service
}

# ── Office ────────────────────────────────────────────────────────────────────

setup_office() {
    info "Installing office and communication apps ..."
    sudo pacman -S --noconfirm libreoffice-fresh abiword cups cups-browsed system-config-printer
    yay -S --noconfirm zoom teams-for-linux-electron-bin
    # XXX other cups goodies the installer was offering?
}

# ── Screen sharing ────────────────────────────────────────────────────────────

setup_screen_sharing() {
    info "Configuring screen sharing ..."
    # XXX these already seem to be installed
    sudo pacman -S --noconfirm xdg-desktop-portal xdg-desktop-portal-wlr
    append_once ~/.config/zoomus.conf 'enableWaylandShare=true'
    # XXX has this actually worked?
}

# ── Gaming ────────────────────────────────────────────────────────────────────

setup_gaming() {
    info "Installing gaming tools ..."
    lspci | grep -i vga || true
    sudo pacman -S --noconfirm steam prismlauncher
    yay -S --noconfirm minecraft-launcher
}

# ── OS update notifications ───────────────────────────────────────────────────

setup_update_notifier() {
    info "Configuring OS update notifications ..."
    sudo pacman -S --noconfirm eos-update-notifier
    sudo sed -i 's|ShowHowAboutUpdates=notify|ShowHowAboutUpdates=notify+tray|' \
        /etc/eos-update-notifier.conf
    etckeeper_commit "Configure eos-update-notifier."
    eos-update-notifier -init
    # XXX runs on a timer -- how often?
    # XXX show up in the Waybar?
}

# ── Other tools ───────────────────────────────────────────────────────────────

setup_other_tools() {
    info "Installing other tools ..."
    sudo pacman -S --noconfirm btop fastfetch tmux the_silver_searcher xorg-xhost
    sed -i 's/htop/btop/g' ~/.config/waybar/config
    sed -i 's/waybar_htop/waybar_btop/g' ~/.config/sway/config.d/application_defaults
    pkill -USR2 waybar || true
    swaymsg_reload
}

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
    require_sudo
    detect_machine

    setup_etckeeper
    setup_pacman_cache
    setup_timeshift
    setup_autologin
    setup_dotfiles
    setup_macos_habits
    setup_firmware_updates
    setup_bluetooth
    setup_power_saving

    case "$MACHINE" in
      chromebook)
        setup_chromebook_audio
        setup_chromebook_fkeys
        ;;
      macbook)
        setup_keyboard_backlight
        setup_mac_fan
        setup_mac_light_sensors
        setup_webcam
        setup_nvidia_display
        setup_zswap
        ;;
      thinkpad)
        setup_infrared_receiver
        setup_thinkpad_goodies
        setup_zswap
        ;;
    esac

    # XXX lid close does what? mute, lock, and suspend
    # XXX cursor to lower right does what? lock and sleep display
    # XXX cursor to upper right does what? lock
    # XXX desktop picture with the hostname, somehow

    # Power / lid / sleep — requires running outside a Sway session.
    require_not_sway
    case "$MACHINE" in
      chromebook)
        configure_logind_chromebook
        restart_logind
        configure_chromebook_swayidle
        install_lid_handler
        add_sway_poweroff_binding
        etckeeper_commit "endeavour-sway-postinstall: chromebook power/lid/sleep"
        ;;
      macbook)
        configure_logind_common
        restart_logind
        add_sway_poweroff_binding
        etckeeper_commit "endeavour-sway-postinstall: macbook power-key config"
        ;;
      thinkpad)
        configure_logind_common
        configure_thinkpad_udev
        restart_logind
        add_sway_poweroff_binding
        etckeeper_commit "endeavour-sway-postinstall: thinkpad power-key config"
        ;;
    esac

    setup_passwords
    setup_web
    setup_networking
    setup_social
    setup_cloud_storage
    setup_code
    setup_office
    setup_screen_sharing
    setup_gaming
    setup_update_notifier
    setup_other_tools

    echo ""
    info "Done. Reload Sway to apply config changes: swaymsg reload"
    if [[ "$MACHINE" == "thinkpad" ]]; then
        info "Note: the udev grab release requires a re-login or reboot to take full effect."
    fi
}

main "$@"
