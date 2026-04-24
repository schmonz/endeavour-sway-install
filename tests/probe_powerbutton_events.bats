#!/usr/bin/env bats

load helpers

setup() {
    load_script
    reset_flags
}

@test "probe_powerbutton_events: chromebook-100e specimen result is boolean" {
    need_specimen "chromebook-100e/udevadm-power-buttons.txt"
    probe_powerbutton_events "$(specimen chromebook-100e/udevadm-power-buttons.txt)"
    [[ "$HAS_POWERBUTTON_EVENTS" == "true" || "$HAS_POWERBUTTON_EVENTS" == "false" ]]
}

@test "probe_powerbutton_events: output containing power-switch sets flag to false" {
    probe_powerbutton_events "$(printf 'E: ID_INPUT_KEY=1\nE: TAGS=:power-switch:seat:\nP: /devices/LNXSYSTM:00')"
    [[ "$HAS_POWERBUTTON_EVENTS" == "false" ]]
}

@test "probe_powerbutton_events: output without power-switch leaves flag true" {
    probe_powerbutton_events "$(printf 'E: ID_INPUT_KEY=1\nE: TAGS=:seat:\nP: /devices/LNXSYSTM:00')"
    [[ "$HAS_POWERBUTTON_EVENTS" == "true" ]]
}

@test "probe_powerbutton_events: empty string leaves flag true" {
    probe_powerbutton_events ""
    [[ "$HAS_POWERBUTTON_EVENTS" == "true" ]]
}
