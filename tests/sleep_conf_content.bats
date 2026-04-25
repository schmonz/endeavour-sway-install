#!/usr/bin/env bats

load helpers

setup() {
    load_script
}

@test "sleep_conf_content: starts with [Sleep] section" {
    sleep_conf_content | grep -q '^\[Sleep\]'
}

@test "sleep_conf_content: disables Hibernation" {
    sleep_conf_content | grep -q '^AllowHibernation=no'
}

@test "sleep_conf_content: disables HybridSleep" {
    sleep_conf_content | grep -q '^AllowHybridSleep=no'
}

@test "sleep_conf_content: disables SuspendThenHibernate" {
    sleep_conf_content | grep -q '^AllowSuspendThenHibernate=no'
}

@test "sleep_conf_content: disables Suspend" {
    sleep_conf_content | grep -q '^AllowSuspend=no'
}
