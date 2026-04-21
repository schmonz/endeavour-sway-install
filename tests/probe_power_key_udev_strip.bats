#!/usr/bin/env bats

load helpers

setup() {
    load_script
    reset_flags
}

@test "probe_power_key_udev_strip: chromebook-100e specimen result is boolean" {
    need_specimen "chromebook-100e/udevadm-power-buttons.txt"
    probe_power_key_udev_strip "$(specimen chromebook-100e/udevadm-power-buttons.txt)"
    [[ "$POWER_KEY_UDEV_STRIP" == "true" || "$POWER_KEY_UDEV_STRIP" == "false" ]]
}

@test "probe_power_key_udev_strip: output containing power-switch sets flag" {
    probe_power_key_udev_strip "$(printf 'E: ID_INPUT_KEY=1\nE: TAGS=:power-switch:seat:\nP: /devices/LNXSYSTM:00')"
    [[ "$POWER_KEY_UDEV_STRIP" == "true" ]]
}

@test "probe_power_key_udev_strip: output without power-switch leaves flag false" {
    probe_power_key_udev_strip "$(printf 'E: ID_INPUT_KEY=1\nE: TAGS=:seat:\nP: /devices/LNXSYSTM:00')"
    [[ "$POWER_KEY_UDEV_STRIP" == "false" ]]
}

@test "probe_power_key_udev_strip: empty string leaves flag false" {
    probe_power_key_udev_strip ""
    [[ "$POWER_KEY_UDEV_STRIP" == "false" ]]
}
