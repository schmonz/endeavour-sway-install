#!/usr/bin/env bats

load helpers

setup() {
    load_script
    reset_flags
}

teardown() {
    teardown_probe_root
}

@test "probe_has_phantom_second_display: thinkpad-t60 leaves HAS_PHANTOM_SECOND_DISPLAY=false" {
    need_specimen "thinkpad-t60/sys-class-drm.txt"
    PROBE_ROOT=$(make_probe_root thinkpad-t60)
    probe_has_phantom_second_display
    [[ "$HAS_PHANTOM_SECOND_DISPLAY" == "false" ]]
}

@test "probe_has_phantom_second_display: thinkpad-x270 leaves HAS_PHANTOM_SECOND_DISPLAY=false" {
    need_specimen "thinkpad-x270/sys-class-drm.txt"
    PROBE_ROOT=$(make_probe_root thinkpad-x270)
    probe_has_phantom_second_display
    [[ "$HAS_PHANTOM_SECOND_DISPLAY" == "false" ]]
}
