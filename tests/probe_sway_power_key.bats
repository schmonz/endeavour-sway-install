#!/usr/bin/env bats

load helpers

setup() {
    load_script
    reset_flags
}

teardown() {
    teardown_probe_root
}

@test "probe_sway_power_key: thinkpad-x270 sets SWAY_POWER_KEY=true" {
    need_specimen "thinkpad-x270/sys-class-input-names.txt"
    PROBE_ROOT=$(make_probe_root thinkpad-x270)
    probe_sway_power_key
    [[ "$SWAY_POWER_KEY" == "true" ]]
}

@test "probe_sway_power_key: chromebook-100e sets SWAY_POWER_KEY=true" {
    need_specimen "chromebook-100e/sys-class-input-names.txt"
    PROBE_ROOT=$(make_probe_root chromebook-100e)
    probe_sway_power_key
    [[ "$SWAY_POWER_KEY" == "true" ]]
}
