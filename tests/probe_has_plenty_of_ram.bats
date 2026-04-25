#!/usr/bin/env bats

load helpers

setup() {
    load_script
    reset_flags
}

@test "probe_has_plenty_of_ram: thinkpad-t60 (<8G RAM) leaves HAS_PLENTY_OF_RAM=false" {
    need_specimen "thinkpad-t60/proc-meminfo.txt"
    local kb
    kb="$(grep MemTotal "$(specimen_path thinkpad-t60/proc-meminfo.txt)" | awk '{print $2}')"
    probe_has_plenty_of_ram "$kb"
    [[ "$HAS_PLENTY_OF_RAM" == "false" ]]
}

@test "probe_has_plenty_of_ram: 4G RAM leaves HAS_PLENTY_OF_RAM=false" {
    probe_has_plenty_of_ram $((4 * 1024 * 1024))
    [[ "$HAS_PLENTY_OF_RAM" == "false" ]]
}

@test "probe_has_plenty_of_ram: 8G RAM sets HAS_PLENTY_OF_RAM=true" {
    probe_has_plenty_of_ram $((8 * 1024 * 1024))
    [[ "$HAS_PLENTY_OF_RAM" == "true" ]]
}

@test "probe_has_plenty_of_ram: 16G RAM sets HAS_PLENTY_OF_RAM=true" {
    probe_has_plenty_of_ram $((16 * 1024 * 1024))
    [[ "$HAS_PLENTY_OF_RAM" == "true" ]]
}

@test "probe_has_plenty_of_ram: 0 leaves HAS_PLENTY_OF_RAM=false" {
    probe_has_plenty_of_ram 0
    [[ "$HAS_PLENTY_OF_RAM" == "false" ]]
}
