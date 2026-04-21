#!/usr/bin/env bats

load helpers

setup() {
    load_script
    reset_flags
}

teardown() {
    teardown_probe_root
}

@test "probe_chromebook: chromebook-100e sets CHROMEBOOK_FKEYS and CHROMEBOOK_AUDIO" {
    PROBE_ROOT=$(make_probe_root chromebook-100e)
    probe_chromebook
    [[ "$CHROMEBOOK_FKEYS" == "true" ]]
    [[ "$CHROMEBOOK_AUDIO" == "true" ]]
}

@test "probe_chromebook: thinkpad-x270 leaves flags false" {
    PROBE_ROOT=$(make_probe_root thinkpad-x270)
    probe_chromebook
    [[ "$CHROMEBOOK_FKEYS" == "false" ]]
    [[ "$CHROMEBOOK_AUDIO" == "false" ]]
}
