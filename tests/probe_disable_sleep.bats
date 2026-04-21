#!/usr/bin/env bats

load helpers

setup() {
    load_script
    reset_flags
}

@test "probe_disable_sleep: chromebook-100e sets DISABLE_SLEEP=true" {
    need_specimen "chromebook-100e/dmidecode-bios-version.txt"
    probe_disable_sleep "$(specimen chromebook-100e/dmidecode-bios-version.txt)"
    [[ "$DISABLE_SLEEP" == "true" ]]
}

@test "probe_disable_sleep: thinkpad-x270 leaves DISABLE_SLEEP=false" {
    need_specimen "thinkpad-x270/dmidecode-bios-version.txt"
    probe_disable_sleep "$(specimen thinkpad-x270/dmidecode-bios-version.txt)"
    [[ "$DISABLE_SLEEP" == "false" ]]
}

@test "probe_disable_sleep: MrChromebox string sets DISABLE_SLEEP=true" {
    probe_disable_sleep "MrChromebox-4.21.0"
    [[ "$DISABLE_SLEEP" == "true" ]]
}

@test "probe_disable_sleep: non-MrChromebox string leaves DISABLE_SLEEP=false" {
    probe_disable_sleep "1.50 (ThinkPad-1.50)"
    [[ "$DISABLE_SLEEP" == "false" ]]
}

@test "probe_disable_sleep: empty string leaves DISABLE_SLEEP=false" {
    probe_disable_sleep ""
    [[ "$DISABLE_SLEEP" == "false" ]]
}
