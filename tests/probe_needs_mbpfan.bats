#!/usr/bin/env bats

load helpers

setup() {
    load_script
    reset_flags
}

@test "probe_needs_mbpfan: macbookair-71 sets NEEDS_MBPFAN=true" {
    need_specimen "macbookair-71/dmidecode-system-manufacturer.txt"
    need_specimen "macbookair-71/dmidecode-system-product-name.txt"
    probe_needs_mbpfan \
        "$(specimen macbookair-71/dmidecode-system-manufacturer.txt)" \
        "$(specimen macbookair-71/dmidecode-system-product-name.txt)"
    [[ "$NEEDS_MBPFAN" == "true" ]]
}

@test "probe_needs_mbpfan: macbookpro-52 sets NEEDS_MBPFAN=true" {
    need_specimen "macbookpro-52/dmidecode-system-manufacturer.txt"
    need_specimen "macbookpro-52/dmidecode-system-product-name.txt"
    probe_needs_mbpfan \
        "$(specimen macbookpro-52/dmidecode-system-manufacturer.txt)" \
        "$(specimen macbookpro-52/dmidecode-system-product-name.txt)"
    [[ "$NEEDS_MBPFAN" == "true" ]]
}

@test "probe_needs_mbpfan: thinkpad-x270 leaves NEEDS_MBPFAN=false" {
    need_specimen "thinkpad-x270/dmidecode-system-manufacturer.txt"
    need_specimen "thinkpad-x270/dmidecode-system-product-name.txt"
    probe_needs_mbpfan \
        "$(specimen thinkpad-x270/dmidecode-system-manufacturer.txt)" \
        "$(specimen thinkpad-x270/dmidecode-system-product-name.txt)"
    [[ "$NEEDS_MBPFAN" == "false" ]]
}
