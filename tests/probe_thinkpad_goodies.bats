#!/usr/bin/env bats

load helpers

setup() {
    load_script
    reset_flags
}

@test "probe_thinkpad_goodies: thinkpad-x270 sets THINKPAD_GOODIES=true" {
    need_specimen "thinkpad-x270/dmidecode-system-manufacturer.txt"
    need_specimen "thinkpad-x270/dmidecode-system-product-name.txt"
    need_specimen "thinkpad-x270/dmidecode-system-version.txt"
    probe_thinkpad_goodies \
        "$(specimen thinkpad-x270/dmidecode-system-manufacturer.txt)" \
        "$(specimen thinkpad-x270/dmidecode-system-product-name.txt)" \
        "$(specimen thinkpad-x270/dmidecode-system-version.txt)"
    [[ "$THINKPAD_GOODIES" == "true" ]]
}

@test "probe_thinkpad_goodies: macbookpro-52 leaves THINKPAD_GOODIES=false" {
    need_specimen "macbookpro-52/dmidecode-system-manufacturer.txt"
    need_specimen "macbookpro-52/dmidecode-system-product-name.txt"
    need_specimen "macbookpro-52/dmidecode-system-version.txt"
    probe_thinkpad_goodies \
        "$(specimen macbookpro-52/dmidecode-system-manufacturer.txt)" \
        "$(specimen macbookpro-52/dmidecode-system-product-name.txt)" \
        "$(specimen macbookpro-52/dmidecode-system-version.txt)"
    [[ "$THINKPAD_GOODIES" == "false" ]]
}

@test "probe_thinkpad_goodies: LENOVO ThinkPad X270 (version) sets THINKPAD_GOODIES=true" {
    probe_thinkpad_goodies "LENOVO" "20HMS6VR00" "ThinkPad X270"
    [[ "$THINKPAD_GOODIES" == "true" ]]
}

@test "probe_thinkpad_goodies: LENOVO ThinkPad X270 (product) sets THINKPAD_GOODIES=true" {
    probe_thinkpad_goodies "LENOVO" "ThinkPad X270" ""
    [[ "$THINKPAD_GOODIES" == "true" ]]
}

@test "probe_thinkpad_goodies: LENOVO IdeaPad leaves THINKPAD_GOODIES=false" {
    probe_thinkpad_goodies "LENOVO" "IdeaPad 330" "IdeaPad 330"
    [[ "$THINKPAD_GOODIES" == "false" ]]
}

@test "probe_thinkpad_goodies: Apple MacBookPro leaves THINKPAD_GOODIES=false" {
    probe_thinkpad_goodies "Apple Inc." "MacBookPro5,2" "MacBookPro5,2"
    [[ "$THINKPAD_GOODIES" == "false" ]]
}
