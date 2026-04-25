#!/usr/bin/env bats

load helpers

setup() {
    load_script
    reset_flags
}

teardown() {
    teardown_probe_root
}

@test "probe_ambient_light_sensor: thinkpad-x270 leaves HAS_AMBIENT_LIGHT_SENSOR=false" {
    PROBE_ROOT=$(make_probe_root thinkpad-x270)
    probe_ambient_light_sensor
    [[ "$HAS_AMBIENT_LIGHT_SENSOR" == "false" ]]
}

@test "probe_ambient_light_sensor: chromebook-100e leaves HAS_AMBIENT_LIGHT_SENSOR=false" {
    PROBE_ROOT=$(make_probe_root chromebook-100e)
    probe_ambient_light_sensor
    [[ "$HAS_AMBIENT_LIGHT_SENSOR" == "false" ]]
}
