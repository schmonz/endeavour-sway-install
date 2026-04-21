# Shared helpers for bats tests.
# Source the main script in "library mode" so it defines functions and flags
# but does not execute any install phases.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

load_script() {
    # Prevent the script from auto-running by stubbing _sudo and phase functions.
    # We source it with BATS_LIB_SOURCED so we can gate on that if needed.
    export SOURCED_FOR_TESTING=1

    # Stub out everything that would run commands or require root.
    _sudo()  { true; }
    warn()   { true; }
    inform() { true; }

    # Source the script; phase functions are defined but not called here.
    # shellcheck disable=SC1090
    source "$SCRIPT_DIR/endeavour-sway-install.sh" || true
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
