#!/usr/bin/env bats

load helpers

setup() {
    load_script
    reset_flags
}

@test "probe_has_facetimehd: macbookpro-52 sets HAS_FACETIMEHD=true" {
    need_specimen "macbookpro-52/lspci-n.txt"
    probe_has_facetimehd "$(specimen macbookpro-52/lspci-n.txt)"
    [[ "$HAS_FACETIMEHD" == "true" ]]
}

@test "probe_has_facetimehd: thinkpad-x270 leaves HAS_FACETIMEHD=false" {
    need_specimen "thinkpad-x270/lspci-n.txt"
    probe_has_facetimehd "$(specimen thinkpad-x270/lspci-n.txt)"
    [[ "$HAS_FACETIMEHD" == "false" ]]
}

@test "probe_has_facetimehd: 14e4:1570 sets HAS_FACETIMEHD=true" {
    probe_has_facetimehd "04:00.0 0280: 14e4:1570"
    [[ "$HAS_FACETIMEHD" == "true" ]]
}

@test "probe_has_facetimehd: other IDs leave HAS_FACETIMEHD=false" {
    probe_has_facetimehd "00:02.0 0300: 8086:1234"
    [[ "$HAS_FACETIMEHD" == "false" ]]
}
