#!/usr/bin/env bats

load helpers

setup() {
    load_script
}

@test "transform_grub_param: adds param to empty double-quoted value" {
    result=$(echo 'GRUB_CMDLINE_LINUX=""' | transform_grub_param GRUB_CMDLINE_LINUX video=LVDS-2:d video=LVDS-2:d)
    [[ "$result" == 'GRUB_CMDLINE_LINUX="video=LVDS-2:d"' ]]
}

@test "transform_grub_param: appends param to non-empty double-quoted value" {
    result=$(echo 'GRUB_CMDLINE_LINUX="quiet splash"' | transform_grub_param GRUB_CMDLINE_LINUX video=LVDS-2:d video=LVDS-2:d)
    [[ "$result" == 'GRUB_CMDLINE_LINUX="quiet splash video=LVDS-2:d"' ]]
}

@test "transform_grub_param: no-op when check string already present" {
    result=$(echo 'GRUB_CMDLINE_LINUX="video=LVDS-2:d"' | transform_grub_param GRUB_CMDLINE_LINUX video=LVDS-2:d video=LVDS-2:d)
    [[ "$result" == 'GRUB_CMDLINE_LINUX="video=LVDS-2:d"' ]]
}

@test "transform_grub_param: does not touch other variables" {
    result=$(printf 'GRUB_CMDLINE_LINUX_DEFAULT="quiet"\nGRUB_CMDLINE_LINUX=""\n' \
        | transform_grub_param GRUB_CMDLINE_LINUX video=LVDS-2:d video=LVDS-2:d)
    echo "$result" | grep -qF 'GRUB_CMDLINE_LINUX_DEFAULT="quiet"'
}

@test "transform_grub_param: adds multiple params to empty value" {
    result=$(echo 'GRUB_CMDLINE_LINUX_DEFAULT=""' \
        | transform_grub_param GRUB_CMDLINE_LINUX_DEFAULT zswap "zswap.enabled=1 zswap.compressor=lz4")
    [[ "$result" == 'GRUB_CMDLINE_LINUX_DEFAULT="zswap.enabled=1 zswap.compressor=lz4"' ]]
}

@test "transform_grub_param: appends multiple params to non-empty value" {
    result=$(echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet"' \
        | transform_grub_param GRUB_CMDLINE_LINUX_DEFAULT zswap "zswap.enabled=1 zswap.compressor=lz4")
    [[ "$result" == 'GRUB_CMDLINE_LINUX_DEFAULT="quiet zswap.enabled=1 zswap.compressor=lz4"' ]]
}
