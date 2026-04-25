#!/usr/bin/env bats

load helpers

setup() {
    load_script
}

@test "logind_dropin_content: HAS_RESUME=true starts with [Login] section" {
    logind_dropin_content true | grep -q '^\[Login\]'
}

@test "logind_dropin_content: HAS_RESUME=true sets HandlePowerKey=ignore" {
    logind_dropin_content true | grep -q '^HandlePowerKey=ignore'
}

@test "logind_dropin_content: HAS_RESUME=true omits IdleAction" {
    ! logind_dropin_content true | grep -q 'IdleAction'
}

@test "logind_dropin_content: HAS_RESUME=true omits HandleLidSwitch" {
    ! logind_dropin_content true | grep -q 'HandleLidSwitch'
}

@test "logind_dropin_content: HAS_RESUME=false starts with [Login] section" {
    logind_dropin_content false | grep -q '^\[Login\]'
}

@test "logind_dropin_content: HAS_RESUME=false sets IdleAction=ignore" {
    logind_dropin_content false | grep -q '^IdleAction=ignore'
}

@test "logind_dropin_content: HAS_RESUME=false sets HandleLidSwitch=lock" {
    logind_dropin_content false | grep -q '^HandleLidSwitch=lock'
}

@test "logind_dropin_content: HAS_RESUME=false sets HandleLidSwitchExternalPower=lock" {
    logind_dropin_content false | grep -q '^HandleLidSwitchExternalPower=lock'
}

@test "logind_dropin_content: HAS_RESUME=false sets HandlePowerKey=ignore" {
    logind_dropin_content false | grep -q '^HandlePowerKey=ignore'
}

@test "logind_dropin_content: HAS_RESUME=false sets HandlePowerKeyLongPress=ignore" {
    logind_dropin_content false | grep -q '^HandlePowerKeyLongPress=ignore'
}
