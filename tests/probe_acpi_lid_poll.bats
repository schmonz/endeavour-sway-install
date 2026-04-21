#!/usr/bin/env bats

load helpers

setup() {
    load_script
    reset_flags
}

teardown() {
    teardown_probe_root
}

# chromebook-100e: has LID0 state file but also "Lid Switch" input → no poll needed
@test "probe_acpi_lid_poll: chromebook-100e leaves ACPI_LID_POLL=false" {
    need_specimen "chromebook-100e/proc-acpi-button-lid-LID0-state"
    need_specimen "chromebook-100e/sys-class-input-names.txt"
    PROBE_ROOT=$(make_probe_root chromebook-100e)
    probe_acpi_lid_poll
    [[ "$ACPI_LID_POLL" == "false" ]]
}

# thinkpad-x270: no LID0 state file
@test "probe_acpi_lid_poll: thinkpad-x270 leaves ACPI_LID_POLL=false" {
    PROBE_ROOT=$(make_probe_root thinkpad-x270)
    probe_acpi_lid_poll
    [[ "$ACPI_LID_POLL" == "false" ]]
}

# macbookair-71: has LID0 state and "Lid Switch" input → should NOT poll
@test "probe_acpi_lid_poll: macbookair-71 leaves ACPI_LID_POLL=false" {
    need_specimen "macbookair-71/proc-acpi-button-lid-LID0-state"
    need_specimen "macbookair-71/sys-class-input-names.txt"
    PROBE_ROOT=$(make_probe_root macbookair-71)
    probe_acpi_lid_poll
    [[ "$ACPI_LID_POLL" == "false" ]]
}
