#!/usr/bin/env bats

load helpers

setup() {
    load_script
    reset_flags
}

@test "probe_has_thinkpad_hardware: thinkpad-x270 sets HAS_THINKPAD_HARDWARE=true" {
    need_specimen "thinkpad-x270/dmidecode-system-manufacturer.txt"
    need_specimen "thinkpad-x270/dmidecode-system-product-name.txt"
    need_specimen "thinkpad-x270/dmidecode-system-version.txt"
    probe_has_thinkpad_hardware \
        "$(specimen thinkpad-x270/dmidecode-system-manufacturer.txt)" \
        "$(specimen thinkpad-x270/dmidecode-system-product-name.txt)" \
        "$(specimen thinkpad-x270/dmidecode-system-version.txt)"
    [[ "$HAS_THINKPAD_HARDWARE" == "true" ]]
}

@test "probe_has_thinkpad_hardware: macbookpro-52 leaves HAS_THINKPAD_HARDWARE=false" {
    need_specimen "macbookpro-52/dmidecode-system-manufacturer.txt"
    need_specimen "macbookpro-52/dmidecode-system-product-name.txt"
    need_specimen "macbookpro-52/dmidecode-system-version.txt"
    probe_has_thinkpad_hardware \
        "$(specimen macbookpro-52/dmidecode-system-manufacturer.txt)" \
        "$(specimen macbookpro-52/dmidecode-system-product-name.txt)" \
        "$(specimen macbookpro-52/dmidecode-system-version.txt)"
    [[ "$HAS_THINKPAD_HARDWARE" == "false" ]]
}

@test "probe_has_thinkpad_hardware: LENOVO ThinkPad X270 (version) sets HAS_THINKPAD_HARDWARE=true" {
    probe_has_thinkpad_hardware "LENOVO" "20HMS6VR00" "ThinkPad X270"
    [[ "$HAS_THINKPAD_HARDWARE" == "true" ]]
}

@test "probe_has_thinkpad_hardware: LENOVO ThinkPad X270 (product) sets HAS_THINKPAD_HARDWARE=true" {
    probe_has_thinkpad_hardware "LENOVO" "ThinkPad X270" ""
    [[ "$HAS_THINKPAD_HARDWARE" == "true" ]]
}

@test "probe_has_thinkpad_hardware: LENOVO IdeaPad leaves HAS_THINKPAD_HARDWARE=false" {
    probe_has_thinkpad_hardware "LENOVO" "IdeaPad 330" "IdeaPad 330"
    [[ "$HAS_THINKPAD_HARDWARE" == "false" ]]
}

@test "probe_has_thinkpad_hardware: Apple MacBookPro leaves HAS_THINKPAD_HARDWARE=false" {
    probe_has_thinkpad_hardware "Apple Inc." "MacBookPro5,2" "MacBookPro5,2"
    [[ "$HAS_THINKPAD_HARDWARE" == "false" ]]
}
