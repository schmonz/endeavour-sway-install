#!/usr/bin/env bats

load helpers

setup() {
    load_script
    reset_flags
}

@test "probe_needs_zswap: t60 (<8G RAM) sets NEEDS_ZSWAP=true" {
    need_specimen "t60/proc-meminfo.txt"
    local kb
    kb="$(grep MemTotal "$(specimen_path t60/proc-meminfo.txt)" | awk '{print $2}')"
    probe_needs_zswap "$kb"
    [[ "$NEEDS_ZSWAP" == "true" ]]
}

@test "probe_needs_zswap: 4G RAM sets NEEDS_ZSWAP=true" {
    probe_needs_zswap $((4 * 1024 * 1024))
    [[ "$NEEDS_ZSWAP" == "true" ]]
}

@test "probe_needs_zswap: 8G RAM leaves NEEDS_ZSWAP=false" {
    probe_needs_zswap $((8 * 1024 * 1024))
    [[ "$NEEDS_ZSWAP" == "false" ]]
}

@test "probe_needs_zswap: 16G RAM leaves NEEDS_ZSWAP=false" {
    probe_needs_zswap $((16 * 1024 * 1024))
    [[ "$NEEDS_ZSWAP" == "false" ]]
}

@test "probe_needs_zswap: 0 leaves NEEDS_ZSWAP=false" {
    probe_needs_zswap 0
    [[ "$NEEDS_ZSWAP" == "false" ]]
}
