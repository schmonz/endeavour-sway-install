SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

load_script() {
    export SOURCED_FOR_TESTING=1
    _sudo()  { true; }
    warn()   { true; }
    inform() { true; }
    # shellcheck disable=SC1090
    source "$SCRIPT_DIR/endeavour-sway-install.bash" || true
}

need_specimen() {
    local path="${BATS_TEST_DIRNAME}/../specimens/$1"
    [[ -f "$path" ]] || skip "no specimen: specimens/$1"
}

specimen_path() {
    echo "${BATS_TEST_DIRNAME}/../specimens/$1"
}

specimen() {
    cat "${BATS_TEST_DIRNAME}/../specimens/$1"
}

make_probe_root() {
    local slug="$1"
    local base="${BATS_TEST_DIRNAME}/../specimens/$slug"
    local r; r=$(mktemp -d)

    if [[ -f "$base/sys-class-input-names.txt" ]]; then
        while IFS=$'\t' read -r dev name; do
            mkdir -p "$r/sys/class/input/$dev"
            printf '%s\n' "$name" > "$r/sys/class/input/$dev/name"
        done < "$base/sys-class-input-names.txt"
    fi

    if [[ -f "$base/sys-class-leds.txt" ]]; then
        while IFS= read -r led; do
            mkdir -p "$r/sys/class/leds/$led"
        done < "$base/sys-class-leds.txt"
    fi

    if [[ -f "$base/sys-class-hwmon-names.txt" ]]; then
        while IFS=$'\t' read -r dev name; do
            mkdir -p "$r/sys/class/hwmon/$dev"
            printf '%s\n' "$name" > "$r/sys/class/hwmon/$dev/name"
        done < "$base/sys-class-hwmon-names.txt"
    fi

    if [[ -f "$base/sys-class-drm.txt" ]]; then
        mkdir -p "$r/sys/class/drm"
        while IFS= read -r entry; do
            touch "$r/sys/class/drm/$entry"
        done < "$base/sys-class-drm.txt"
    fi

    if [[ -f "$base/sys-bus-iio-illuminance.txt" ]]; then
        mkdir -p "$r/sys/bus/iio/devices/iio:device0"
        touch "$r/sys/bus/iio/devices/iio:device0/in_illuminance_raw"
    fi

    if [[ -f "$base/sys-class-chromeos.txt" ]]; then
        while IFS= read -r entry; do
            mkdir -p "$r/sys/class/chromeos/$entry"
        done < "$base/sys-class-chromeos.txt"
    fi

    if [[ -f "$base/sys-class-video4linux.txt" ]]; then
        while IFS= read -r entry; do
            mkdir -p "$r/sys/class/video4linux/$entry"
        done < "$base/sys-class-video4linux.txt"
    fi

    if grep -q "^/dev/cros_ec" "$base/dev-cros_ec.txt" 2>/dev/null; then
        mkdir -p "$r/dev"
        touch "$r/dev/cros_ec"
    fi

    if ! grep -q "No such file" "$base/dev-lirc.txt" 2>/dev/null; then
        mkdir -p "$r/dev"
        while IFS= read -r path; do
            touch "$r/dev/$(basename "$path")"
        done < "$base/dev-lirc.txt"
    fi

    if ! grep -q "No such file" "$base/dev-video.txt" 2>/dev/null; then
        mkdir -p "$r/dev"
        while IFS= read -r path; do
            touch "$r/dev/$(basename "$path")"
        done < "$base/dev-video.txt"
    fi

    if [[ -f "$base/proc-acpi-button-lid-LID0-state" ]]; then
        mkdir -p "$r/proc/acpi/button/lid/LID0"
        cp "$base/proc-acpi-button-lid-LID0-state" "$r/proc/acpi/button/lid/LID0/state"
    fi

    echo "$r"
}

teardown_probe_root() {
    [[ -n "${PROBE_ROOT:-}" ]] && rm -rf "$PROBE_ROOT" || true
    unset PROBE_ROOT
}

reset_flags() {
    DISABLE_SLEEP=false
    ACPI_LID_POLL=false
    POWER_KEY_UDEV_STRIP=false
    SWAY_POWER_KEY=false
    CHROMEBOOK_AUDIO=false
    CHROMEBOOK_FKEYS=false
    AMBIENT_LIGHT_SENSOR=false
    KBD_BACKLIGHT=false
    NEEDS_MBPFAN=false
    HAS_FACETIMEHD=false
    PHANTOM_LVDS2=false
    NEEDS_ZSWAP=false
    HAS_IR_RECEIVER=false
    THINKPAD_GOODIES=false
    NEEDS_SOFTWARE_GL=false
    HAS_WEBCAM=false
}
