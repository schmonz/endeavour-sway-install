#!/usr/bin/env bats

load helpers

setup() {
    load_script
    reset_flags
}

teardown() {
    teardown_probe_root
}

# chromebook-100e: has LID0 and cros_ec → Chrome EC owns lid events, does NOT have reliable kernel input events
@test "probe_has_lid_events: chromebook-100e sets HAS_LID_EVENTS=false" {
    need_specimen "chromebook-100e/proc-acpi-button-lid-LID0-state"
    need_specimen "chromebook-100e/sys-class-input-names.txt"
    PROBE_ROOT=$(make_probe_root chromebook-100e)
    probe_has_lid_events
    [[ "$HAS_LID_EVENTS" == "false" ]]
}

# thinkpad-x270: no LID0 state file → no lid detected, but default is true (assumes events if no LID0 to poll)
@test "probe_has_lid_events: thinkpad-x270 leaves HAS_LID_EVENTS=true" {
    PROBE_ROOT=$(make_probe_root thinkpad-x270)
    probe_has_lid_events
    [[ "$HAS_LID_EVENTS" == "true" ]]
}

# macbookair-71: has LID0 state and "Lid Switch" input → HAS_LID_EVENTS should be true
@test "probe_has_lid_events: macbookair-71 leaves HAS_LID_EVENTS=true" {
    need_specimen "macbookair-71/proc-acpi-button-lid-LID0-state"
    need_specimen "macbookair-71/sys-class-input-names.txt"
    PROBE_ROOT=$(make_probe_root macbookair-71)
    probe_has_lid_events
    [[ "$HAS_LID_EVENTS" == "true" ]]
}
