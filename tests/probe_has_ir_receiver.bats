#!/usr/bin/env bats

load helpers

setup() {
    load_script
    reset_flags
}

teardown() {
    teardown_probe_root
}

@test "probe_has_ir_receiver: thinkpad-x270 leaves HAS_IR_RECEIVER=false" {
    PROBE_ROOT=$(make_probe_root thinkpad-x270)
    probe_has_ir_receiver
    [[ "$HAS_IR_RECEIVER" == "false" ]]
}

@test "probe_has_ir_receiver: chromebook-100e leaves HAS_IR_RECEIVER=false" {
    PROBE_ROOT=$(make_probe_root chromebook-100e)
    probe_has_ir_receiver
    [[ "$HAS_IR_RECEIVER" == "false" ]]
}
