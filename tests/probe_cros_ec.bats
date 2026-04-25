#!/usr/bin/env bats

load helpers

setup() {
    load_script
    reset_flags
}

teardown() {
    teardown_probe_root
}

@test "probe_cros_ec: chromebook-100e sets HAS_CROS_FKEYS and HAS_AVS_AUDIO" {
    PROBE_ROOT=$(make_probe_root chromebook-100e)
    probe_cros_ec
    [[ "$HAS_CROS_FKEYS" == "true" ]]
    [[ "$HAS_AVS_AUDIO" == "true" ]]
}

@test "probe_cros_ec: thinkpad-x270 leaves flags false" {
    PROBE_ROOT=$(make_probe_root thinkpad-x270)
    probe_cros_ec
    [[ "$HAS_CROS_FKEYS" == "false" ]]
    [[ "$HAS_AVS_AUDIO" == "false" ]]
}
