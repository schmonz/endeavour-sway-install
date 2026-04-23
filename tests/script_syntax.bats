#!/usr/bin/env bats

@test "script has valid bash syntax" {
    bash -n "$BATS_TEST_DIRNAME/../endeavour-sway-install.bash"
}
