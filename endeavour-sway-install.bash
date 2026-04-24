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
FIRSTBOOT_SERVICE="/etc/systemd/system/endeavour-sway-firstboot.service"
SELF_URL="https://raw.githubusercontent.com/schmonz/endeavour-sway-install/main/endeavour-sway-install.bash"
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

# Append LINE to FILE only if not already present.
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

# Register CMD in the Sway autostart config and launch it now if in a session.
# Pass pkill=true to kill any prior instance first (for systray singletons).
configure_sway_autostart() {
    local cmd="$1" pkill="${2:-false}"
    local autostart="${3:-${HOME}/.config/sway/config.d/autostart_applications}"
    local line
    if $pkill; then
        line="exec sh -c \"pkill -f '$cmd' 2>/dev/null; $cmd\""
    else
        line="exec $cmd"
    fi
    append_once "$autostart" "$line"
}

# Clone URL into DIR only if DIR doesn't already exist.
clone_if_missing() { local url="$1" dir="$2"; [[ -d "$dir" ]] || git clone "$url" "$dir"; }

# ── Machine capability flags ──────────────────────────────────────────────────
#
# detect_machine_capabilities() adjusts these.

HAS_RESUME=true            # system has working suspend/resume
ACPI_LID_POLL=false        # poll /proc/acpi for lid; EC never fires events
POWER_KEY_UDEV_STRIP=false # strip power-switch udev tag so logind releases grab
SWAY_POWER_KEY=false       # add XF86PowerOff bindsym in Sway config
CHROMEBOOK_AUDIO=false     # run chromebook-linux-audio AVS setup
CHROMEBOOK_FKEYS=false     # install cros-keyboard-map
AMBIENT_LIGHT_SENSOR=false # install iio-sensor-proxy + clight, enable clightd
KBD_BACKLIGHT=false        # auto-detect keyboard backlight and add Sway bindings
NEEDS_MBPFAN=false         # install + enable mbpfan
HAS_FACETIMEHD=false       # install facetimehd-dkms (FaceTime HD webcam)
PHANTOM_LVDS2=false        # disable phantom second internal display
NEEDS_ZSWAP=false          # enable zswap in GRUB_CMDLINE_LINUX_DEFAULT
HAS_IR_RECEIVER=false      # set up LIRC infrared receiver
THINKPAD_GOODIES=false     # ThinkPad-specific: smart card, buttons, fingerprint
NEEDS_SOFTWARE_GL=false    # set LIBGL_ALWAYS_SOFTWARE=1 (GPU can't handle modern GL)

report_capabilities() {
    local fmt='  %-34s %s\n'
    local text
    text=$(
        printf "Hardware capability detection (verify these look right for this machine):\n"
        printf "$fmt" "HAS_RESUME=$HAS_RESUME"                     "system has working suspend/resume"
        printf "$fmt" "ACPI_LID_POLL=$ACPI_LID_POLL"               "poll /proc/acpi for lid (EC silent)"
        printf "$fmt" "POWER_KEY_UDEV_STRIP=$POWER_KEY_UDEV_STRIP" "strip power-switch udev tag"
        printf "$fmt" "SWAY_POWER_KEY=$SWAY_POWER_KEY"             "XF86PowerOff bindsym in Sway"
        printf "$fmt" "CHROMEBOOK_FKEYS=$CHROMEBOOK_FKEYS"         "cros-keyboard-map"
        printf "$fmt" "CHROMEBOOK_AUDIO=$CHROMEBOOK_AUDIO"         "chromebook-linux-audio AVS setup"
        printf "$fmt" "AMBIENT_LIGHT_SENSOR=$AMBIENT_LIGHT_SENSOR" "iio-sensor-proxy + clight"
        printf "$fmt" "KBD_BACKLIGHT=$KBD_BACKLIGHT"               "keyboard backlight auto-setup"
        printf "$fmt" "NEEDS_MBPFAN=$NEEDS_MBPFAN"                 "mbpfan Mac fan control"
        printf "$fmt" "HAS_FACETIMEHD=$HAS_FACETIMEHD"             "facetimehd-dkms"
        printf "$fmt" "PHANTOM_LVDS2=$PHANTOM_LVDS2"               "disable phantom LVDS-2 display"
        printf "$fmt" "NEEDS_ZSWAP=$NEEDS_ZSWAP"                   "enable zswap"
        printf "$fmt" "HAS_IR_RECEIVER=$HAS_IR_RECEIVER"           "LIRC infrared"
        printf "$fmt" "THINKPAD_GOODIES=$THINKPAD_GOODIES"         "ThinkPad smart card/buttons/fingerprint"
        printf "$fmt" "NEEDS_SOFTWARE_GL=$NEEDS_SOFTWARE_GL"       "LIBGL_ALWAYS_SOFTWARE=1"
        printf "If any flag looks wrong, improve its probe in detect_machine_capabilities().\n"
    )
    info "$text"
    [[ $EUID -ne 0 ]] || echo "$text" >> "$WARNINGS_FILE"
}

# ── Hardware probes ───────────────────────────────────────────────────────────
#
# Each probe sets one or more capability flags.
# File/device probes read from ${PROBE_ROOT} (default empty = real system root).
# Command-output probes accept pre-collected output as their first argument.
# Tests set PROBE_ROOT to a fixture directory and pass synthetic strings.

PROBE_ROOT="${PROBE_ROOT:-}"

# HAS_RESUME: MrChromebox firmware = Chromebook with broken suspend/resume.
probe_has_resume() {          # arg: bios-version string
    [[ "${1:-}" == MrChromebox* ]] && HAS_RESUME=false || true
}

# ACPI_LID_POLL: lid ACPI node exists but kernel input events are unreliable.
# Chrome EC handles lid events in firmware; "Lid Switch" input node exists but never fires.
probe_acpi_lid_poll() {
    [[ -f "${PROBE_ROOT}/proc/acpi/button/lid/LID0/state" ]] || return 0
    [[ -e "${PROBE_ROOT}/dev/cros_ec" ]] && { ACPI_LID_POLL=true; return; }
    grep -rql "Lid Switch" "${PROBE_ROOT}/sys/class/input/input"*/name 2>/dev/null \
        && return 0
    ACPI_LID_POLL=true
}

# POWER_KEY_UDEV_STRIP: LNXPWRBN power button still carries the power-switch udev
# tag, meaning logind holds an exclusive grab that blocks Sway from seeing the key.
probe_power_key_udev_strip() { # arg: concatenated udevadm info for LNXPWRBN devices
    grep -q "power-switch" <<< "${1:-}" && POWER_KEY_UDEV_STRIP=true || true
}

# SWAY_POWER_KEY: any input device named "Power Button" is present.
probe_sway_power_key() {
    local input_dir
    for input_dir in "${PROBE_ROOT}"/sys/class/input/input*/; do
        [[ "$(cat "${input_dir}name" 2>/dev/null)" == "Power Button" ]] \
            && { SWAY_POWER_KEY=true; return; }
    done; true
}

# CHROMEBOOK_FKEYS + CHROMEBOOK_AUDIO: Chrome EC present = Chromebook hardware.
probe_chromebook() {
    if [[ -d "${PROBE_ROOT}/sys/class/chromeos/cros_ec" ]] \
       || [[ -e "${PROBE_ROOT}/dev/cros_ec" ]]; then
        CHROMEBOOK_FKEYS=true
        CHROMEBOOK_AUDIO=true
    fi
}

# AMBIENT_LIGHT_SENSOR: IIO illuminance sensor visible in sysfs.
probe_ambient_light_sensor() {
    ls "${PROBE_ROOT}"/sys/bus/iio/devices/*/in_illuminance* 2>/dev/null \
        | grep -q . && AMBIENT_LIGHT_SENSOR=true || true
}

# KBD_BACKLIGHT: keyboard backlight LED device in sysfs.
probe_kbd_backlight() {
    ls "${PROBE_ROOT}/sys/class/leds/" 2>/dev/null \
        | grep -qiE "kbd|keyboard" && KBD_BACKLIGHT=true || true
}

# NEEDS_MBPFAN: Apple MacBook — needs mbpfan to control fans via applesmc.
probe_needs_mbpfan() {    # args: vendor, product
    [[ "${1:-}" == "Apple Inc." ]] \
        && [[ "${2:-}" == MacBook* ]] \
        && NEEDS_MBPFAN=true || true
}

# HAS_FACETIMEHD: Broadcom FaceTime HD camera (PCIe ID 14e4:1570).
probe_has_facetimehd() {      # arg: lspci -n output
    grep -q "14e4:1570" <<< "${1:-}" && HAS_FACETIMEHD=true || true
}

# PHANTOM_LVDS2: second internal LVDS output enumerated by DRM.
# Requires GPU driver to be loaded — may be false during phase 1 chroot.
probe_phantom_lvds2() {
    ls "${PROBE_ROOT}/sys/class/drm/" 2>/dev/null \
        | grep -q "LVDS-2" && PHANTOM_LVDS2=true || true
}

# NEEDS_ZSWAP: total RAM under 8 GiB.
probe_needs_zswap() {         # arg: MemTotal value in kB
    local kb="${1:-0}"
    (( kb > 0 && kb < 8*1024*1024 )) && NEEDS_ZSWAP=true || true
}

# HAS_IR_RECEIVER: LIRC character device present.
probe_ir_receiver() {
    ls "${PROBE_ROOT}"/dev/lirc* 2>/dev/null | grep -q . && HAS_IR_RECEIVER=true || true
}

# THINKPAD_GOODIES: Lenovo ThinkPad SMBIOS — TrackPoint buttons, smart card,
# ThinkVantage button, fingerprint reader are ThinkPad-specific.
probe_thinkpad_goodies() {    # args: vendor, product, version
    if [[ "${1:-}" == "LENOVO" ]] \
       && { echo "${2:-}" | grep -qi "ThinkPad" \
            || echo "${3:-}" | grep -qi "ThinkPad"; }; then
        THINKPAD_GOODIES=true
    fi
}

# NEEDS_SOFTWARE_GL: old ATI/AMD GPU (r300 driver family) that cannot drive
# modern OpenGL; requires llvmpipe via LIBGL_ALWAYS_SOFTWARE=1.
# 1002:5b6x = RV370 (Radeon X300/X600); 1002:7145 = M26 (Mobility Radeon X1400)
probe_needs_software_gl() {   # arg: lspci -n output
    grep -qE "1002:(5b6|7145)" <<< "${1:-}" && NEEDS_SOFTWARE_GL=true || true
}

# ── Capability orchestrator ───────────────────────────────────────────────────

detect_machine_capabilities() {
    local vendor product version bios lspci_out total_mem_kb
    local input_dir name phys udev_power_out evdir

    vendor=$(_sudo dmidecode -s system-manufacturer 2>/dev/null || true)
    product=$(_sudo dmidecode -s system-product-name 2>/dev/null || true)
    version=$(_sudo dmidecode -s system-version 2>/dev/null || true)
    bios=$(_sudo dmidecode -s bios-version 2>/dev/null || true)
    lspci_out=$(_sudo lspci -n 2>/dev/null || true)
    total_mem_kb=$(awk '/MemTotal/{print $2}' /proc/meminfo 2>/dev/null || echo 0)

    # Collect udevadm output for LNXPWRBN power-button input devices.
    udev_power_out=""
    for input_dir in /sys/class/input/input*/; do
        name=$(cat "${input_dir}name" 2>/dev/null || true)
        phys=$(cat "${input_dir}phys" 2>/dev/null || true)
        if [[ "$name" == "Power Button" && "$phys" == *LNXPWRBN* ]]; then
            for evdir in "${input_dir}"event*/; do
                udev_power_out+=$(_sudo udevadm info "/dev/input/$(basename "$evdir")" 2>/dev/null || true)
            done
        fi
    done

    probe_has_resume            "$bios"
    probe_acpi_lid_poll
    probe_power_key_udev_strip  "$udev_power_out"
    probe_sway_power_key
    probe_chromebook
    probe_ambient_light_sensor
    probe_kbd_backlight
    probe_needs_mbpfan          "$vendor" "$product"
    probe_has_facetimehd        "$lspci_out"
    probe_phantom_lvds2
    probe_needs_zswap           "$total_mem_kb"
    probe_ir_receiver
    probe_thinkpad_goodies      "$vendor" "$product" "$version"
    probe_needs_software_gl     "$lspci_out"

    report_capabilities
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
    system_systemctl mask \
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

# ── Swayidle ──────────────────────────────────────────────────────────────────
#
# EOS CE ships two separate swayidle entries; one uses exec_always, so every
# Sway reload spawns a duplicate. setup_swayidle replaces them with a single
# exec_always that kills any prior instance before starting.
#
# With lid polling ($1=true): suspend is disabled, so no before-sleep/after-resume.
# Without lid polling ($1=false): also lock before sleep and restore dpms on resume.

build_swayidle_line() {
    local needs_lid_poll="$1"
    local common_idle='exec swayidle -w \
    idlehint 1 \
    timeout 300  '"'"'gtklock -d --lock-command "swaymsg output \* dpms off"'"'"' resume '"'"'swaymsg "output * dpms on"'"'"' \
    lock         '"'"'gtklock -d --lock-command "swaymsg output \* dpms off"'"'"' \
    unlock       '"'"'swaymsg "output * dpms on"'"'"''

    local sleep_events='    before-sleep '"'"'gtklock -d; sleep 1'"'"' \
    after-resume '"'"'swaymsg "output * dpms on"'"'"''

    if $needs_lid_poll; then
        printf '%s\n' "$common_idle"
    else
        printf '%s' "${common_idle}"$' \\\n'"${sleep_events}"$'\n'
    fi
}

setup_swayidle() {
    local needs_lid_poll="$1"
    local autostart="$HOME/.config/sway/config.d/autostart_applications"
    if [[ ! -f "$autostart" ]]; then
        warn "${autostart} not found — skipping swayidle config."
        return
    fi

    sed -i '/^exec swayidle idlehint/d; /^exec_always swayidle -w before-sleep/d' "$autostart"

    local idle_line
    idle_line=$(build_swayidle_line "$needs_lid_poll")

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
# Lid open:  swaymsg output dpms on  (so the gtklock prompt is visible)
#
# Power efficiency: the loop uses only bash builtins (read) and sleep — no
# forked processes. This matters because process forks are CPU wakeup events
# that prevent the processor from staying in deep C-states. At 1s intervals
# the CPU gets one brief wakeup per second from the kernel timer; the rest of
# the time it can sleep deeply. Using awk or similar external tools instead of
# read would add a process-spawn wakeup on every iteration for no benefit.

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

# ── Machine-specific stubs (phase 3) ─────────────────────────────────────────

setup_chromebook_audio() {
    info "Setting up Chromebook audio ..."
    clone_if_missing https://github.com/WeirdTreeThing/chromebook-linux-audio ~/trees/chromebook-linux-audio
    cd ~/trees/chromebook-linux-audio
    echo "I UNDERSTAND THE RISK OF PERMANENTLY DAMAGING MY SPEAKERS" | ./setup-audio --force-avs-install
    cd -
}

setup_chromebook_fkeys() {
    info "Setting up Chromebook F-keys ..."
    clone_if_missing https://github.com/WeirdTreeThing/cros-keyboard-map ~/trees/cros-keyboard-map
    cd ~/trees/cros-keyboard-map
    ./install.sh
    cd -
}

setup_mac_fan() {
    aur_install mbpfan
    sudo cp /usr/lib/systemd/system/mbpfan.service /etc/systemd/system/
    system_systemctl enable mbpfan.service
}

setup_mac_light_sensors() {
    # clight is installed + started in the AMBIENT_LIGHT_SENSOR block above (iio-sensor-proxy + clightd).
    # Without a floor, clight maps a dark room to 0% brightness — invisible screen.
    sudo mkdir -p /etc/clight/modules.conf.d
    sudo tee /etc/clight/modules.conf.d/sensor.conf > /dev/null << 'EOF'
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
    sed -E "
/^${var}=/{
    /${check}/! {
        s/=([\"'])\1\$/=\1${params}\1/
        t
        s/=([\"'])(.*)\1\$/=\1\2 ${params}\1/
    }
}"
}

add_grub_param() {
    local var="$1" check="$2" params="$3"
    local new_content
    new_content=$(transform_grub_param "$var" "$check" "$params" < /etc/default/grub)
    echo "$new_content" | sudo tee /etc/default/grub > /dev/null
}

setup_nvidia_display() {
    # For MacBookPro5,2 so the display manager comes up on the real screen.
    # Targets GRUB_CMDLINE_LINUX (not _DEFAULT) so recovery boots also get the fix.
    add_grub_param GRUB_CMDLINE_LINUX video=LVDS-2:d video=LVDS-2:d
    sudo grub-mkconfig -o /boot/grub/grub.cfg
}

setup_zswap() {
    # Targets GRUB_CMDLINE_LINUX_DEFAULT — performance optimization, not needed in recovery.
    add_grub_param GRUB_CMDLINE_LINUX_DEFAULT zswap.enabled=1 \
        "zswap.enabled=1 zswap.compressor=zstd zswap.zpool=z3fold zswap.max_pool_percent=20"
    sudo grub-mkconfig -o /boot/grub/grub.cfg
}

setup_pacman_cache() {
    pacman_install pacman-contrib
    system_systemctl enable paccache.timer
}

setup_power_saving() {
    : # TLP: https://wiki.archlinux.org/title/TLP
}

setup_timeshift() {
    system_systemctl enable cronie
}

setup_ambient_light_sensor() {
    aur_install iio-sensor-proxy clight
    system_systemctl enable clightd
    configure_sway_autostart 'clight'
    ls /sys/bus/iio/devices/*/in_illuminance* || true
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
    local sway_autostart="${target_home}/.config/sway/config.d/autostart_applications"
    mkdir -p "$(dirname "$runner")"

    # INSTALL_SCRIPT_DEST expands now; \${...} expands when the runner executes.
    cat > "$runner" << SCRIPT
#!/bin/bash
notes="\${HOME}/.config/endeavour-post-phase3.txt"
sway_autostart="\${HOME}/.config/sway/config.d/autostart_applications"

case "\${1:-}" in
  --show-notes)
    # Runs in first Sway session after the reboot that follows Phase 3.
    [[ -f "\${notes}" ]] || exit 0
    xdg-open 'https://chromewebstore.google.com/detail/1password-%E2%80%93-password-mana/aeblfdkhhhdcdjpifhhbdiojplfjncoa' &
    foot -e sh -c "cat '\${notes}'; echo; read -r -p 'Press Enter to dismiss.' _"
    rm -f "\${notes}"
    sed -i "\\|exec ${runner} --show-notes|d" "\${sway_autostart}" 2>/dev/null || true
    ;;
  *)
    # Runs in TTY login shell (bash --login autologin via greetd).
    log="\${HOME}/.config/endeavour-phase3.log"
    warnings="\${HOME}/.config/endeavour-warnings"
    if [[ -f "\${warnings}" ]]; then
        echo '=== Phase 2 notes ==='
        cat "\${warnings}"
        echo
    fi
    ${INSTALL_SCRIPT_DEST} "\${USER}" --phase 3 2>&1 | tee "\${log}"
    rc=\${PIPESTATUS[0]}
    echo
    if [[ \$rc -eq 0 ]]; then
        rm -f "\${warnings}"
        printf 'Manual steps remaining:\n\n  tailscale up\n  rclone config (optional)\n' > "\${notes}"
        grep -qF '${runner} --show-notes' "\${sway_autostart}" 2>/dev/null || \\
            printf '\nexec ${runner} --show-notes\n' >> "\${sway_autostart}"
        sed -i "\\|${runner}|d" "\${HOME}/.bash_profile" 2>/dev/null || true
        systemctl reboot
    else
        echo "Phase 3 FAILED (exit code \$rc). Log: \${log}"
        read -r -p 'Press Enter to dismiss.' _
    fi
    ;;
esac
SCRIPT
    chmod +x "$runner"

    # Register in .bash_profile so it runs on TTY login (not in the Sway autostart).
    local bash_profile="${target_home}/.bash_profile"
    touch "$bash_profile"
    chown "${target_user}:" "$bash_profile"
    append_once "$bash_profile" "$runner"
}

# Show MSG, run FUNC (with any extra args), then commit to etckeeper.
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
    firewall-cmd --set-default-zone=home --permanent \
        || warn "firewall-cmd --set-default-zone failed (will retry in phase 2)."
}

setup_firewall_localsend() {
    firewall-cmd --add-port=53317/tcp --permanent || true
    firewall-cmd --add-port=53317/udp --permanent || true
}

setup_systemd_resolved() {
    ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
    system_systemctl --not-now enable systemd-resolved
}

setup_logind_config() {
    if $HAS_RESUME; then
        configure_logind_common
    else
        configure_logind_chromebook
    fi
    $POWER_KEY_UDEV_STRIP && write_thinkpad_udev_rule
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

# ── Phase 1: installer chroot ─────────────────────────────────────────────────

phase1() {
    [[ $EUID -eq 0 ]] || die "Phase 1 must run as root."

    local target_user target_home
    target_user=$(detect_target_user)
    [[ -n "$target_user" ]] \
        || die "No user found with uid >= 1000. Has Calamares created the user yet?"
    target_home=$(getent passwd "$target_user" | cut -d: -f6)

    detect_machine_capabilities

    info "=== Phase 1: pacman installs ==="
    # Replaced by Helium in phase 3.
    pacman -Rs --noconfirm firefox || true

    # XXX other cups goodies the installer was offering?
    pacman_install \
        etckeeper git git-delta \
        blueman \
        gvfs-dnssd tailscale \
        seahorse \
        fwupd \
        discord signal-desktop guvcview \
        libreoffice-fresh abiword cups cups-browsed system-config-printer \
        xdg-desktop-portal xdg-desktop-portal-wlr \
        eos-update-notifier \
        btop fastfetch tmux the_silver_searcher xorg-xhost \
        apostrophe glow tig github-cli socat bats \
        grub-btrfs

    info "=== Phase 1: etckeeper init ==="
    if ! etckeeper vcs log --oneline -1 &>/dev/null; then
        etckeeper init
    fi

    run_setup_step setup_autologin \
        "=== Phase 1: autologin ===" \
        "Enable autologin (TTY, for phase 3)." "$target_user" "bash --login"

    run_setup_step setup_keyboard_layout \
        "=== Phase 1: macOS keyboard layout ===" \
        "Enable Mac-like accents with Right-Alt."

    info "=== Phase 1: pbcopy / pbpaste ==="
    mkdir -p /usr/local/bin
    printf '#!/bin/sh\nexec wl-copy "$@"\n' > /usr/local/bin/pbcopy
    printf '#!/bin/sh\nexec wl-paste --no-newline "$@"\n' > /usr/local/bin/pbpaste
    chmod +x /usr/local/bin/pbcopy /usr/local/bin/pbpaste

    run_setup_step setup_1password_browser_integration \
        "=== Phase 1: 1Password browser integration ===" \
        "Allow Helium browser in 1Password."

    run_setup_step setup_eos_update_notifier_conf \
        "=== Phase 1: eos-update-notifier ===" \
        "Configure eos-update-notifier to use system tray."

    run_setup_step setup_firewall_zone \
        "=== Phase 1: firewall zone ===" \
        "Set default firewall zone to 'home'."

    run_setup_step setup_firewall_localsend \
        "=== Phase 1: firewall LocalSend ===" \
        "Allow LocalSend through firewall."

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
    if [[ ! -d "${target_home}/trees/dotfiles" ]]; then
        su - "$target_user" -c \
            "mkdir -p ~/trees && git clone https://github.com/schmonz/dotfiles.git ~/trees/dotfiles"
    fi
    su - "$target_user" -c \
        "ln -sf ~/trees/dotfiles/gitconfig ~/.gitconfig && ln -sf ~/trees/dotfiles/tmux.conf ~/.tmux.conf"
    ln -sf "${target_home}/trees/dotfiles/gitconfig" /root/.gitconfig

    info "=== Phase 2: etckeeper commit ==="
    etckeeper commit -m 'Track /etc after phase-1 install.' 2>/dev/null || true
    git -C /etc gc --prune 2>/dev/null || warn "git gc failed (non-fatal)."

    local current_branch
    current_branch=$(git -C /etc symbolic-ref --short HEAD 2>/dev/null || true)
    if [[ -n "$current_branch" && "$current_branch" != "$(hostname)" ]]; then
        git -C /etc branch -m "$(hostname)"
    fi

    run_setup_step setup_bluetooth \
        "=== Phase 2: Bluetooth ===" \
        "Enable Bluetooth."

    run_setup_step setup_tailscaled \
        "=== Phase 2: Tailscale ===" \
        "Enable Tailscale daemon."

    run_setup_step setup_pacman_cache \
        "=== Phase 2: pacman cache ===" \
        "Periodically clean pacman cache."

    info "=== Phase 2: firewall (daemon now running) ==="
    firewall-cmd --set-default-zone=home
    firewall-cmd --reload

    info "=== Phase 2: logind restart ==="
    $POWER_KEY_UDEV_STRIP && reload_thinkpad_udev

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

    info "=== Phase 3: yay installs (common) ==="
    aur_install \
        timeshift-autosnap \
        1password \
        helium-browser-bin ungoogled-chromium-bin webapp-manager \
        localsend-bin \
        slack-electron \
        zoom teams-for-linux-electron-bin \
        rclone \
        clion clion-jre \
        dawn-writer-bin \
        claude-code claude-desktop-bin claude-cowork-service

    # XXX CLI equivalent: open the Timeshift app and follow the prompts
    # XXX once automated, this graduates to Phase 2
    run_setup_step setup_timeshift \
        "=== Phase 3: timeshift ===" \
        "Enable Timeshift."

    info "=== Phase 3: web browser ==="
    append_once ~/.config/sway/config.d/application_defaults \
        'for_window [app_id="helium"] inhibit_idle fullscreen'
    sed -i 's|exec firefox|exec xdg-open https://|g' ~/.config/sway/config.d/default

    # Mimic the user clicking "don't open at login" in EOS Welcome.
    local wconf="$HOME/.config/EOS-greeter.conf"
    if grep -q "^Greeter=" "$wconf" 2>/dev/null; then
        sed -i 's|^Greeter=.*|Greeter=disable|' "$wconf"
    else
        printf 'Greeter=disable\nLastCheck=0\nOnceDaily=no\n' > "$wconf"
    fi

    mkdir -p ~/.local/share/applications/kde4
    printf '[Desktop Entry]\nHidden=true\n' > ~/.local/share/applications/chromium.desktop
    printf '[Desktop Entry]\nHidden=true\n' > ~/.local/share/applications/kde4/webapp-manager.desktop

    # Set Helium as default browser via XDG mime associations.
    mkdir -p ~/.config
    cat > ~/.config/mimeapps.list << 'EOF'
[Default Applications]
x-scheme-handler/http=helium.desktop
x-scheme-handler/https=helium.desktop
text/html=helium.desktop
application/xhtml+xml=helium.desktop
EOF

    # Suppress first-run wizard and restore session on startup.
    # initial_preferences seeds preferences if Default/Preferences doesn't exist yet.
    # Writing Default/Preferences directly is a belt-and-suspenders fallback: its
    # presence alone signals "already configured" and skips the first-run wizard.
    local _prefs='{"browser":{"check_default_browser":false},"session":{"restore_on_startup":1}}'
    local _init='{"browser":{"check_default_browser":false},"distribution":{"skip_first_run_ui":true,"suppress_first_run_bubble":true,"show_welcome_page":false},"session":{"restore_on_startup":1}}'
    mkdir -p ~/.config/net.imput.helium/Default ~/.config/chromium/Default
    printf '%s\n' "$_init" \
        | tee ~/.config/net.imput.helium/initial_preferences \
              ~/.config/chromium/initial_preferences > /dev/null
    printf '%s\n' "$_prefs" \
        | tee ~/.config/net.imput.helium/Default/Preferences \
              ~/.config/chromium/Default/Preferences > /dev/null

    # Use basic password store so neither browser prompts for a keyring
    # password. Actual credentials live in 1Password; this only affects
    # Chromium's own Safe Storage key.
    printf -- '--password-store=basic\n' > ~/.config/helium-browser-flags.conf
    printf -- '--password-store=basic\n' > ~/.config/chromium-flags.conf


    # Geolocation (disabled):
    # sudo pacman -S --noconfirm xdg-desktop-portal-gtk
    # systemctl --user enable --now xdg-desktop-portal xdg-desktop-portal-gtk
    # sed -i 's/import-environment DISPLAY WAYLAND_DISPLAY SWAYSOCK/import-environment DISPLAY WAYLAND_DISPLAY SWAYSOCK XDG_CURRENT_DESKTOP/' \
    #     ~/.config/sway/config.d/autostart_applications

    info "=== Phase 3: passwords ==="
    configure_sway_autostart '1password'

    info "=== Phase 3: networking ==="
    sudo tailscale set --operator="$target_user"
    configure_sway_autostart 'tailscale systray' true
    tailscale set --accept-dns=true
    tailscale set --accept-routes
    # XXX maybe exit node also isn't working? admin console says:
    # XXX   "This machine is misconfigured and cannot relay traffic."
    # XXX but maybe that's enough for Plex (or Jellyfin)
    configure_sway_autostart 'localsend --hidden'
    # XXX configure LocalSend to use the real system hostname
    # ~/.local/share/org.localsend.localsend_app/shared_preferences.json

    info "=== Phase 3: power saving ==="
    setup_power_saving

    info "=== Phase 3: firmware updates ==="
    echo y | fwupdmgr get-updates || true
    fwupdmgr update || true
    # MrChromebox firmware: https://docs.mrchromebox.tech/docs/firmware/updating-firmware.html

    info "=== Phase 3: screen sharing ==="
    # XXX these already seem to be installed
    append_once ~/.config/zoomus.conf 'enableWaylandShare=true'
    # XXX has screen sharing actually worked?

    info "=== Phase 3: update notifier ==="
    eos-update-notifier -init
    # XXX runs on a timer -- how often?
    # XXX show up in Waybar?

    info "=== Phase 3: other tools ==="
    sed -i 's/htop/btop/g' ~/.config/waybar/config
    sed -i 's/waybar_htop/waybar_btop/g' ~/.config/sway/config.d/application_defaults

    info "Configuring Foot URL launching ..."
    sed -i 's|^# launch=xdg-open \${url}$|launch=xdg-open ${url}|' ~/.config/foot/foot.ini

    # info "=== Phase 3: cloud storage ==="
    # rclone config
    # After authentication error: log into icloud.com in a browser, open Chrome
    # Dev Tools → Network tab, click a request, grab the full Cookie header and
    # X-APPLE-WEBAUTH-HSA-TRUST value, then:
    #   rclone config update icloud cookies='' trust_token=""
    # Token expires monthly (~30 days).
    # https://forum.rclone.org/t/icloud-connect-not-working-http-error-400/52019/44

    info "=== Phase 3: swayidle ==="
    setup_swayidle $ACPI_LID_POLL

    info "=== Phase 3: machine-specific ==="

    $CHROMEBOOK_AUDIO && setup_chromebook_audio
    $CHROMEBOOK_FKEYS && setup_chromebook_fkeys
    $ACPI_LID_POLL    && install_lid_handler

    if $AMBIENT_LIGHT_SENSOR; then
        run_setup_step setup_ambient_light_sensor \
            "=== Phase 3: ambient light sensor ===" \
            "Enable ambient light sensor (iio-sensor-proxy + clightd)."
        run_setup_step setup_mac_light_sensors \
            "Configuring clight brightness floor ..." \
            "Configure clight brightness floor (prevent invisible screen)."
    fi

    if $KBD_BACKLIGHT; then
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
    fi

    $NEEDS_MBPFAN   && run_setup_step setup_mac_fan \
        "Installing mbpfan ..." \
        "Enable mbpfan Mac fan control."
    $HAS_FACETIMEHD && aur_install facetimehd-dkms
    $PHANTOM_LVDS2  && run_setup_step setup_nvidia_display \
        "Disabling phantom second internal display (LVDS-2) ..." \
        "Disable second internal display (MacBookPro5,2 LVDS-2)."
    $NEEDS_ZSWAP    && run_setup_step setup_zswap \
        "Enabling zswap ..." \
        "Enable zswap."

    if $NEEDS_SOFTWARE_GL; then
        info "Enabling software GL rendering (LIBGL_ALWAYS_SOFTWARE=1) ..."
        mkdir -p ~/.config/environment.d
        echo 'LIBGL_ALWAYS_SOFTWARE=1' > ~/.config/environment.d/50-softgl.conf
    fi

    $HAS_IR_RECEIVER   && setup_infrared_receiver
    $THINKPAD_GOODIES  && setup_thinkpad_goodies
    $SWAY_POWER_KEY    && add_sway_poweroff_binding "$target_user"

    $POWER_KEY_UDEV_STRIP && \
        info "Note: the udev grab release requires a re-login or reboot to take full effect."

    run_setup_step setup_autologin \
        "=== Phase 3: reconfigure autologin to Sway ===" \
        "Switch greetd autologin from TTY to Sway." "$target_user"

    info ""
    info "Phase 3 complete."
    info "  Remaining interactive steps after reboot: tailscale up; rclone config (optional)."
    # XXX lid close: mute, lock, suspend
    # XXX cursor to lower right: lock and sleep display
    # XXX cursor to upper right: lock
    # XXX desktop picture showing the hostname
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
                curl -fsSL "$SWAY_CE_URL" | bash -s -- $username
            fi
            phase1
            ;;
        2) phase2 ;;
        3) phase3 "$username" ;;
        *) die "Unknown phase '${phase}'. Must be 1, 2, or 3." ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
