#!/usr/bin/env bats

load helpers

setup() {
    load_script
    reset_flags
}

teardown() {
    teardown_probe_root
}

@test "probe_needs_mbpfan: macbookpro-52 leaves NEEDS_MBPFAN=false (applesmc not loaded at collection time)" {
    need_specimen "macbookpro-52/sys-class-hwmon-names.txt"
    PROBE_ROOT=$(make_probe_root macbookpro-52)
    probe_needs_mbpfan
    [[ "$NEEDS_MBPFAN" == "false" ]]
}

@test "probe_needs_mbpfan: thinkpad-x270 leaves NEEDS_MBPFAN=false" {
    need_specimen "thinkpad-x270/sys-class-hwmon-names.txt"
    PROBE_ROOT=$(make_probe_root thinkpad-x270)
    probe_needs_mbpfan
    [[ "$NEEDS_MBPFAN" == "false" ]]
}
