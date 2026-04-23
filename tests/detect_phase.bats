#!/usr/bin/env bats

load helpers

setup() {
    load_script
    unset EUID_OVERRIDE
    unset SWAYSOCK
}

teardown() {
    teardown_probe_root
    unset EUID_OVERRIDE
    unset SWAYSOCK
}

# in_user_session

@test "in_user_session: non-root user is in user session" {
    EUID_OVERRIDE=1000 in_user_session
}

@test "in_user_session: root with SWAYSOCK is in user session" {
    EUID_OVERRIDE=0 SWAYSOCK=/run/sway/wayland-1 in_user_session
}

@test "in_user_session: root without SWAYSOCK is not in user session" {
    ! EUID_OVERRIDE=0 in_user_session
}

# in_chroot

@test "in_chroot: no systemd dir means in chroot" {
    PROBE_ROOT=$(mktemp -d)
    in_chroot
}

@test "in_chroot: systemd dir present means not in chroot" {
    PROBE_ROOT=$(mktemp -d)
    mkdir -p "$PROBE_ROOT/run/systemd/system"
    ! in_chroot
}

# detect_phase

@test "detect_phase: non-root user → phase 3" {
    export EUID_OVERRIDE=1000
    run detect_phase
    [[ "$output" == "3" ]]
}

@test "detect_phase: root with SWAYSOCK → phase 3" {
    export EUID_OVERRIDE=0
    export SWAYSOCK=/run/sway/wayland-1
    run detect_phase
    [[ "$output" == "3" ]]
}

@test "detect_phase: root, no SWAYSOCK, no systemd → phase 1 (chroot)" {
    export EUID_OVERRIDE=0
    export PROBE_ROOT; PROBE_ROOT=$(mktemp -d)
    run detect_phase
    [[ "$output" == "1" ]]
}

@test "detect_phase: root, no SWAYSOCK, systemd present → phase 2 (first boot)" {
    export EUID_OVERRIDE=0
    export PROBE_ROOT; PROBE_ROOT=$(mktemp -d)
    mkdir -p "$PROBE_ROOT/run/systemd/system"
    run detect_phase
    [[ "$output" == "2" ]]
}
