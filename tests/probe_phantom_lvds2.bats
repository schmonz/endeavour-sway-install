#!/usr/bin/env bats

load helpers

setup() {
    load_script
    reset_flags
}

teardown() {
    teardown_probe_root
}

@test "probe_phantom_lvds2: thinkpad-t60 leaves PHANTOM_LVDS2=false" {
    need_specimen "thinkpad-t60/sys-class-drm.txt"
    PROBE_ROOT=$(make_probe_root thinkpad-t60)
    probe_phantom_lvds2
    [[ "$PHANTOM_LVDS2" == "false" ]]
}

@test "probe_phantom_lvds2: thinkpad-x270 leaves PHANTOM_LVDS2=false" {
    need_specimen "thinkpad-x270/sys-class-drm.txt"
    PROBE_ROOT=$(make_probe_root thinkpad-x270)
    probe_phantom_lvds2
    [[ "$PHANTOM_LVDS2" == "false" ]]
}
