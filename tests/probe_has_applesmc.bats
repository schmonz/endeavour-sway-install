#!/usr/bin/env bats

load helpers

setup() {
    load_script
    reset_flags
}

@test "probe_has_applesmc: macbookair-71 sets HAS_APPLESMC=true" {
    need_specimen "macbookair-71/dmidecode-system-manufacturer.txt"
    need_specimen "macbookair-71/dmidecode-system-product-name.txt"
    probe_has_applesmc \
        "$(specimen macbookair-71/dmidecode-system-manufacturer.txt)" \
        "$(specimen macbookair-71/dmidecode-system-product-name.txt)"
    [[ "$HAS_APPLESMC" == "true" ]]
}

@test "probe_has_applesmc: macbookpro-52 sets HAS_APPLESMC=true" {
    need_specimen "macbookpro-52/dmidecode-system-manufacturer.txt"
    need_specimen "macbookpro-52/dmidecode-system-product-name.txt"
    probe_has_applesmc \
        "$(specimen macbookpro-52/dmidecode-system-manufacturer.txt)" \
        "$(specimen macbookpro-52/dmidecode-system-product-name.txt)"
    [[ "$HAS_APPLESMC" == "true" ]]
}

@test "probe_has_applesmc: thinkpad-x270 leaves HAS_APPLESMC=false" {
    need_specimen "thinkpad-x270/dmidecode-system-manufacturer.txt"
    need_specimen "thinkpad-x270/dmidecode-system-product-name.txt"
    probe_has_applesmc \
        "$(specimen thinkpad-x270/dmidecode-system-manufacturer.txt)" \
        "$(specimen thinkpad-x270/dmidecode-system-product-name.txt)"
    [[ "$HAS_APPLESMC" == "false" ]]
}
