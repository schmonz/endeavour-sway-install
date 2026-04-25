#!/usr/bin/env bash
#
# Detect hardware capabilities and emit KEY=value lines for eval by the caller.
#
# Usage
#   eval "$(curl -fsSL "${MACHINE_CAPS_URL}"| bash)"

set -euo pipefail

PROBE_ROOT="${PROBE_ROOT:-}"

_sudo() {
    if [[ $EUID -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

# ── Machine capability flags ──────────────────────────────────────────────────
#
# reset_flags() sets defaults; machine_caps_main() adjusts them via probes.

reset_flags() {
    HAS_RESUME=true                  # system has working suspend/resume
    HAS_LID_EVENTS=true              # kernel input events for lid (e.g. Lid Switch)
    HAS_POWERBUTTON_EVENTS=true      # events reach the UI (not grabbed by logind)
    HAS_AVS_AUDIO=false              # run chromebook-linux-audio AVS setup
    HAS_CROS_FKEYS=false             # install cros-keyboard-map
    HAS_AMBIENT_LIGHT_SENSOR=false   # install iio-sensor-proxy + clight, enable clightd
    HAS_KBD_BACKLIGHT=false          # auto-detect keyboard backlight and add Sway bindings
    HAS_APPLESMC=false               # install + enable mbpfan
    HAS_FACETIMEHD=false             # install facetimehd-dkms (FaceTime HD webcam)
    HAS_PHANTOM_SECOND_DISPLAY=false # disable phantom second internal display
    HAS_PLENTY_OF_RAM=false          # skip zswap (GRUB_CMDLINE_LINUX_DEFAULT)
    HAS_IR_RECEIVER=false            # set up LIRC infrared receiver
    HAS_THINKPAD_HARDWARE=false      # ThinkPad-specific: smart card, buttons, fingerprint
    HAS_GL_CAPABLE_GPU=true          # GPU handles modern OpenGL (false → LIBGL_ALWAYS_SOFTWARE=1)
}
reset_flags

# ── Hardware probes ───────────────────────────────────────────────────────────
#
# Each probe sets one or more capability flags.
# File/device probes read from ${PROBE_ROOT} (default empty = real system root).
# Command-output probes accept pre-collected output as their first argument.
# Tests set PROBE_ROOT to a fixture directory and pass synthetic strings.

# HAS_RESUME: MrChromebox firmware = Chromebook with broken suspend/resume.
probe_has_resume() {          # arg: bios-version string
    [[ "${1:-}" == MrChromebox* ]] && HAS_RESUME=false || true
}

# HAS_LID_EVENTS: kernel input events for lid are reliable.
# Chromebook firmware handles lid events via EC; "Lid Switch" node exists but never fires.
probe_has_lid_events() {
    [[ -f "${PROBE_ROOT}/proc/acpi/button/lid/LID0/state" ]] || return 0
    [[ -e "${PROBE_ROOT}/dev/cros_ec" ]] && { HAS_LID_EVENTS=false; return; }
    grep -rql "Lid Switch" "${PROBE_ROOT}/sys/class/input/input"*/name 2>/dev/null \
        && return 0
    HAS_LID_EVENTS=false
}

# HAS_POWERBUTTON_EVENTS: LNXPWRBN power button events reach the UI, so there's
# no "exclusive grab" from logind that we need to override with udev.
# A non-LNXPWRBN "Power Button" (e.g. Apple firmware button on Mac) bypasses
# logind's exclusive grab and delivers events directly to libinput, so HAS_POWERBUTTON_EVENTS
# stays true even if the LNXPWRBN device has the power-switch tag.
probe_has_powerbutton_events() { # args: LNXPWRBN udevadm output, has_non_lnxpwrbn_power_button
    ${2:-false} && return 0
    grep -q "power-switch" <<< "${1:-}" && HAS_POWERBUTTON_EVENTS=false || true
}

# HAS_CROS_FKEYS + HAS_AVS_AUDIO: Chrome EC present.
probe_has_cros_ec() {
    if [[ -d "${PROBE_ROOT}/sys/class/chromeos/cros_ec" ]] \
       || [[ -e "${PROBE_ROOT}/dev/cros_ec" ]]; then
        HAS_CROS_FKEYS=true
        HAS_AVS_AUDIO=true
    fi
}

# HAS_AMBIENT_LIGHT_SENSOR: IIO illuminance sensor visible in sysfs.
probe_has_ambient_light_sensor() {
    ls "${PROBE_ROOT}"/sys/bus/iio/devices/*/in_illuminance* 2>/dev/null \
        | grep -q . && HAS_AMBIENT_LIGHT_SENSOR=true || true
}

# HAS_KBD_BACKLIGHT: keyboard backlight LED device in sysfs.
probe_has_kbd_backlight() {
    ls "${PROBE_ROOT}/sys/class/leds/" 2>/dev/null \
        | grep -qiE "kbd|keyboard" && HAS_KBD_BACKLIGHT=true || true
}

# HAS_APPLESMC: Apple MacBook — applesmc present, needs mbpfan for fan control.
probe_has_applesmc() {    # args: vendor, product
    [[ "${1:-}" == "Apple Inc." ]] \
        && [[ "${2:-}" == MacBook* ]] \
        && HAS_APPLESMC=true || true
}

# HAS_FACETIMEHD: Broadcom FaceTime HD camera (PCIe ID 14e4:1570).
probe_has_facetimehd() {      # arg: lspci -n output
    grep -q "14e4:1570" <<< "${1:-}" && HAS_FACETIMEHD=true || true
}

# HAS_PHANTOM_SECOND_DISPLAY: second internal LVDS output enumerated by DRM.
# Requires GPU driver to be loaded — may be false during phase 1 chroot.
probe_has_phantom_second_display() {
    ls "${PROBE_ROOT}/sys/class/drm/" 2>/dev/null \
        | grep -q "LVDS-2" && HAS_PHANTOM_SECOND_DISPLAY=true || true
}

# HAS_PLENTY_OF_RAM: total RAM at least 8 GiB; machines with less get zswap.
probe_has_plenty_of_ram() {   # arg: MemTotal value in kB
    local kb="${1:-0}"
    (( kb >= 8*1024*1024 )) && HAS_PLENTY_OF_RAM=true || true
}

# HAS_IR_RECEIVER: LIRC character device present.
probe_has_ir_receiver() {
    ls "${PROBE_ROOT}"/dev/lirc* 2>/dev/null | grep -q . && HAS_IR_RECEIVER=true || true
}

# HAS_THINKPAD_HARDWARE: Lenovo ThinkPad SMBIOS — TrackPoint buttons, smart card,
# ThinkVantage button, fingerprint reader are ThinkPad-specific.
probe_has_thinkpad_hardware() {    # args: vendor, product, version
    if [[ "${1:-}" == "LENOVO" ]] \
       && { echo "${2:-}" | grep -qi "ThinkPad" \
            || echo "${3:-}" | grep -qi "ThinkPad"; }; then
        HAS_THINKPAD_HARDWARE=true
    fi
}

# HAS_GL_CAPABLE_GPU: GPU can drive modern OpenGL; r300-family ATI/AMD cannot
# and require llvmpipe via LIBGL_ALWAYS_SOFTWARE=1.
# 1002:5b6x = RV370 (Radeon X300/X600); 1002:7145 = M26 (Mobility Radeon X1400)
probe_has_gl_capable_gpu() {  # arg: lspci -n output
    grep -qE "1002:(5b6|7145)" <<< "${1:-}" && HAS_GL_CAPABLE_GPU=false || true
}

# ── Capability orchestrator ───────────────────────────────────────────────────

run_machine_cap_probes() {
    local vendor product version bios lspci_out total_mem_kb
    local input_dir name phys udev_power_out evdir

    vendor=$(_sudo dmidecode -s system-manufacturer 2>/dev/null || true)
    product=$(_sudo dmidecode -s system-product-name 2>/dev/null || true)
    version=$(_sudo dmidecode -s system-version 2>/dev/null || true)
    bios=$(_sudo dmidecode -s bios-version 2>/dev/null || true)
    lspci_out=$(_sudo lspci -n 2>/dev/null || true)
    total_mem_kb=$(awk '/MemTotal/{print $2}' /proc/meminfo 2>/dev/null || echo 0)

    udev_power_out=""
    local has_non_lnx_power_button=false
    for input_dir in /sys/class/input/input*/; do
        name=$(cat "${input_dir}name" 2>/dev/null || true)
        phys=$(cat "${input_dir}phys" 2>/dev/null || true)
        [[ "$name" == "Power Button" ]] || continue
        if [[ "$phys" == *LNXPWRBN* ]]; then
            for evdir in "${input_dir}"event*/; do
                udev_power_out+=$(_sudo udevadm info "/dev/input/$(basename "$evdir")" 2>/dev/null || true)
            done
        else
            has_non_lnx_power_button=true
        fi
    done

    probe_has_resume                 "$bios"
    probe_has_lid_events
    probe_has_powerbutton_events     "$udev_power_out" "$has_non_lnx_power_button"
    probe_has_cros_ec
    probe_has_ambient_light_sensor
    probe_has_kbd_backlight
    probe_has_applesmc               "$vendor" "$product"
    probe_has_facetimehd             "$lspci_out"
    probe_has_phantom_second_display
    probe_has_plenty_of_ram          "$total_mem_kb"
    probe_has_ir_receiver
    probe_has_thinkpad_hardware      "$vendor" "$product" "$version"
    probe_has_gl_capable_gpu         "$lspci_out"
}

machine_caps_main() {
    reset_flags
    run_machine_cap_probes

    if [[ "${1:-}" == "--verbose" ]]; then
        report_machine_caps
    else
        printf 'HAS_RESUME=%s\n'                 "$HAS_RESUME"
        printf 'HAS_LID_EVENTS=%s\n'             "$HAS_LID_EVENTS"
        printf 'HAS_POWERBUTTON_EVENTS=%s\n'     "$HAS_POWERBUTTON_EVENTS"
        printf 'HAS_AVS_AUDIO=%s\n'              "$HAS_AVS_AUDIO"
        printf 'HAS_CROS_FKEYS=%s\n'             "$HAS_CROS_FKEYS"
        printf 'HAS_AMBIENT_LIGHT_SENSOR=%s\n'   "$HAS_AMBIENT_LIGHT_SENSOR"
        printf 'HAS_KBD_BACKLIGHT=%s\n'          "$HAS_KBD_BACKLIGHT"
        printf 'HAS_APPLESMC=%s\n'               "$HAS_APPLESMC"
        printf 'HAS_FACETIMEHD=%s\n'             "$HAS_FACETIMEHD"
        printf 'HAS_PHANTOM_SECOND_DISPLAY=%s\n' "$HAS_PHANTOM_SECOND_DISPLAY"
        printf 'HAS_PLENTY_OF_RAM=%s\n'          "$HAS_PLENTY_OF_RAM"
        printf 'HAS_IR_RECEIVER=%s\n'            "$HAS_IR_RECEIVER"
        printf 'HAS_THINKPAD_HARDWARE=%s\n'      "$HAS_THINKPAD_HARDWARE"
        printf 'HAS_GL_CAPABLE_GPU=%s\n'         "$HAS_GL_CAPABLE_GPU"
    fi
}

report_machine_caps() {
    local fmt='  %-34s %s\n'
    printf "$fmt" "HAS_RESUME=$HAS_RESUME"                                 "system has working suspend/resume"
    printf "$fmt" "HAS_LID_EVENTS=$HAS_LID_EVENTS"                         "kernel input events for lid (e.g. Lid Switch)"
    printf "$fmt" "HAS_POWERBUTTON_EVENTS=$HAS_POWERBUTTON_EVENTS"         "events reach the UI (not grabbed by logind)"
    printf "$fmt" "HAS_AVS_AUDIO=$HAS_AVS_AUDIO"                           "chromebook-linux-audio AVS setup"
    printf "$fmt" "HAS_CROS_FKEYS=$HAS_CROS_FKEYS"                         "cros-keyboard-map"
    printf "$fmt" "HAS_AMBIENT_LIGHT_SENSOR=$HAS_AMBIENT_LIGHT_SENSOR"     "iio-sensor-proxy + clight"
    printf "$fmt" "HAS_KBD_BACKLIGHT=$HAS_KBD_BACKLIGHT"                   "keyboard backlight auto-setup"
    printf "$fmt" "HAS_APPLESMC=$HAS_APPLESMC"                             "mbpfan Mac fan control"
    printf "$fmt" "HAS_FACETIMEHD=$HAS_FACETIMEHD"                         "facetimehd-dkms"
    printf "$fmt" "HAS_PHANTOM_SECOND_DISPLAY=$HAS_PHANTOM_SECOND_DISPLAY" "phantom second display"
    printf "$fmt" "HAS_PLENTY_OF_RAM=$HAS_PLENTY_OF_RAM"                   "skip zswap"
    printf "$fmt" "HAS_IR_RECEIVER=$HAS_IR_RECEIVER"                       "LIRC infrared"
    printf "$fmt" "HAS_THINKPAD_HARDWARE=$HAS_THINKPAD_HARDWARE"           "ThinkPad smart card/buttons/fingerprint"
    printf "$fmt" "HAS_GL_CAPABLE_GPU=$HAS_GL_CAPABLE_GPU"                 "GPU handles modern OpenGL"
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && machine_caps_main "$@"
