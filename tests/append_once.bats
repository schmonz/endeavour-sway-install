#!/usr/bin/env bats

load helpers

setup() {
    load_script
    tmpfile=$(mktemp)
}

teardown() {
    rm -f "$tmpfile"
}

@test "append_once: appends line to empty file" {
    append_once "$tmpfile" "net.ipv4.ip_forward=1"
    grep -qF "net.ipv4.ip_forward=1" "$tmpfile"
}

@test "append_once: does not duplicate already-present line" {
    echo "net.ipv4.ip_forward=1" > "$tmpfile"
    append_once "$tmpfile" "net.ipv4.ip_forward=1"
    [[ $(grep -cF "net.ipv4.ip_forward=1" "$tmpfile") -eq 1 ]]
}

@test "append_once: creates file when it does not exist" {
    rm -f "$tmpfile"
    append_once "$tmpfile" "net.ipv4.ip_forward=1"
    grep -qF "net.ipv4.ip_forward=1" "$tmpfile"
}

@test "append_once: does not append when line is a substring of existing content" {
    echo "net.ipv4.ip_forward=1" > "$tmpfile"
    append_once "$tmpfile" "net.ipv4"
    [[ $(wc -l < "$tmpfile") -eq 1 ]]
}
