#!/usr/bin/env bats

load helpers

setup() {
    load_script
    ORIG_HOME="$HOME"
    HOME=$(mktemp -d)
    mkdir -p "$HOME/.config/sway/config.d"
}

teardown() {
    rm -rf "$HOME"
    HOME="$ORIG_HOME"
}

eos_ce_autostart() {
    printf 'exec swayidle idlehint 10\nexec_always swayidle -w before-sleep gtklock\n' \
        > "$HOME/.config/sway/config.d/autostart_applications"
}

@test "setup_swayidle removes EOS CE exec swayidle idlehint entry" {
    eos_ce_autostart
    setup_swayidle false
    ! grep -q '^exec swayidle idlehint' "$HOME/.config/sway/config.d/autostart_applications"
}

@test "setup_swayidle removes EOS CE exec_always swayidle -w before-sleep entry" {
    eos_ce_autostart
    setup_swayidle false
    ! grep -q '^exec_always swayidle -w before-sleep' "$HOME/.config/sway/config.d/autostart_applications"
}
