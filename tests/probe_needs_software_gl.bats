#!/usr/bin/env bats

load helpers

setup() {
    load_script
    reset_flags
}

@test "probe_needs_software_gl: t60 sets NEEDS_SOFTWARE_GL=true" {
    need_specimen "t60/lspci-n.txt"
    probe_needs_software_gl "$(specimen t60/lspci-n.txt)"
    [[ "$NEEDS_SOFTWARE_GL" == "true" ]]
}

@test "probe_needs_software_gl: thinkpad-x270 leaves NEEDS_SOFTWARE_GL=false" {
    need_specimen "thinkpad-x270/lspci-n.txt"
    probe_needs_software_gl "$(specimen thinkpad-x270/lspci-n.txt)"
    [[ "$NEEDS_SOFTWARE_GL" == "false" ]]
}

@test "probe_needs_software_gl: 1002:5b60 sets NEEDS_SOFTWARE_GL=true" {
    probe_needs_software_gl "01:00.0 0300: 1002:5b60"
    [[ "$NEEDS_SOFTWARE_GL" == "true" ]]
}

@test "probe_needs_software_gl: 1002:5b62 sets NEEDS_SOFTWARE_GL=true" {
    probe_needs_software_gl "01:00.0 0300: 1002:5b62"
    [[ "$NEEDS_SOFTWARE_GL" == "true" ]]
}

@test "probe_needs_software_gl: other ATI ID leaves NEEDS_SOFTWARE_GL=false" {
    probe_needs_software_gl "01:00.0 0300: 1002:1234"
    [[ "$NEEDS_SOFTWARE_GL" == "false" ]]
}
