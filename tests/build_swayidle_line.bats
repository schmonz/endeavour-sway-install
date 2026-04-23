#!/usr/bin/env bats

load helpers

setup() {
    load_script
}

@test "build_swayidle_line: with lid polling starts with exec swayidle" {
    build_swayidle_line true | grep -q '^exec swayidle -w'
}

@test "build_swayidle_line: with lid polling includes idlehint timeout lock unlock" {
    result=$(build_swayidle_line true)
    echo "$result" | grep -q 'idlehint'
    echo "$result" | grep -q 'timeout 300'
    echo "$result" | grep -q 'lock '
    echo "$result" | grep -q 'unlock '
}

@test "build_swayidle_line: with lid polling omits before-sleep and after-resume" {
    result=$(build_swayidle_line true)
    ! echo "$result" | grep -q 'before-sleep'
    ! echo "$result" | grep -q 'after-resume'
}

@test "build_swayidle_line: without lid polling starts with exec swayidle" {
    build_swayidle_line false | grep -q '^exec swayidle -w'
}

@test "build_swayidle_line: without lid polling includes before-sleep and after-resume" {
    result=$(build_swayidle_line false)
    echo "$result" | grep -q 'before-sleep'
    echo "$result" | grep -q 'after-resume'
}

@test "build_swayidle_line: without lid polling has line continuation on unlock line" {
    build_swayidle_line false | grep -q 'unlock.*\\'
}
