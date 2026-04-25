#!/usr/bin/env bats

load helpers

setup() {
    load_script
}

fake_passwd() {
    getent() { printf '%s\n' "$@"; }
}

@test "detect_target_user finds first user with uid 1000" {
    getent() { printf 'root:x:0:0::/root:/bin/bash\nalice:x:1000:1000::/home/alice:/bin/bash\n'; }
    [[ "$(detect_target_user)" == "alice" ]]
}

@test "detect_target_user skips system accounts below uid 1000" {
    getent() { printf 'root:x:0:0::/root:/bin/bash\ndaemon:x:1:1::/:/usr/bin/nologin\nalice:x:1000:1000::/home/alice:/bin/bash\n'; }
    [[ "$(detect_target_user)" == "alice" ]]
}

@test "detect_target_user skips nobody at uid 65534" {
    getent() { printf 'nobody:x:65534:65534::/:/usr/bin/nologin\nalice:x:1000:1000::/home/alice:/bin/bash\n'; }
    [[ "$(detect_target_user)" == "alice" ]]
}

@test "detect_target_user returns first of multiple regular users" {
    getent() { printf 'alice:x:1000:1000::/home/alice:/bin/bash\nbob:x:1001:1001::/home/bob:/bin/bash\n'; }
    [[ "$(detect_target_user)" == "alice" ]]
}
