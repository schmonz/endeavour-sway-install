#!/usr/bin/env bats

load helpers

setup() {
    load_script
    reset_flags
}

teardown() {
    teardown_probe_root
}

@test "probe_has_webcam: macbookpro-52 sets HAS_WEBCAM=true (via /dev/video)" {
    PROBE_ROOT=$(make_probe_root macbookpro-52)
    probe_has_webcam ""
    [[ "$HAS_WEBCAM" == "true" ]]
}

@test "probe_has_webcam: thinkpad-x270 sets HAS_WEBCAM=true (via v4l)" {
    need_specimen "thinkpad-x270/sys-class-video4linux.txt"
    PROBE_ROOT=$(make_probe_root thinkpad-x270)
    probe_has_webcam ""
    [[ "$HAS_WEBCAM" == "true" ]]
}

@test "probe_has_webcam: thinkpad-t60 leaves HAS_WEBCAM=false" {
    PROBE_ROOT=$(make_probe_root thinkpad-t60)
    probe_has_webcam ""
    [[ "$HAS_WEBCAM" == "false" ]]
}
