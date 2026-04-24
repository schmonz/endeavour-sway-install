#!/usr/bin/env bats

load helpers

setup() {
    load_script
    reset_flags
}

@test "probe_has_resume: chromebook-100e sets HAS_RESUME=false" {
    need_specimen "chromebook-100e/dmidecode-bios-version.txt"
    probe_has_resume "$(specimen chromebook-100e/dmidecode-bios-version.txt)"
    [[ "$HAS_RESUME" == "false" ]]
}

@test "probe_has_resume: thinkpad-x270 leaves HAS_RESUME=true" {
    need_specimen "thinkpad-x270/dmidecode-bios-version.txt"
    probe_has_resume "$(specimen thinkpad-x270/dmidecode-bios-version.txt)"
    [[ "$HAS_RESUME" == "true" ]]
}

@test "probe_has_resume: MrChromebox string sets HAS_RESUME=false" {
    probe_has_resume "MrChromebox-4.21.0"
    [[ "$HAS_RESUME" == "false" ]]
}

@test "probe_has_resume: non-MrChromebox string leaves HAS_RESUME=true" {
    probe_has_resume "1.50 (ThinkPad-1.50)"
    [[ "$HAS_RESUME" == "true" ]]
}

@test "probe_has_resume: empty string leaves HAS_RESUME=true" {
    probe_has_resume ""
    [[ "$HAS_RESUME" == "true" ]]
}
