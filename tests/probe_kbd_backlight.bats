#!/usr/bin/env bats

load helpers

setup() {
    load_script
    reset_flags
}

teardown() {
    teardown_probe_root
}

@test "probe_kbd_backlight: macbookair-71 sets HAS_KBD_BACKLIGHT=true" {
    need_specimen "macbookair-71/sys-class-leds.txt"
    PROBE_ROOT=$(make_probe_root macbookair-71)
    probe_kbd_backlight
    [[ "$HAS_KBD_BACKLIGHT" == "true" ]]
}

@test "probe_kbd_backlight: thinkpad-x270 leaves HAS_KBD_BACKLIGHT=false" {
    need_specimen "thinkpad-x270/sys-class-leds.txt"
    PROBE_ROOT=$(make_probe_root thinkpad-x270)
    probe_kbd_backlight
    [[ "$HAS_KBD_BACKLIGHT" == "false" ]]
}
