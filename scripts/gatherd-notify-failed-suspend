#!/bin/bash
set -euo pipefail

result=$(systemctl show systemd-suspend.service --property=Result --value 2>/dev/null || true)

if [[ "$result" != "exit-code" ]]; then
    rm -f /tmp/suspend-failed-notified
    exit 0
fi

[[ -f /tmp/suspend-failed-notified ]] && exit 0
touch /tmp/suspend-failed-notified

notify-send --urgency=normal --icon=dialog-warning \
    --expire-time=300000 \
    "Suspend failed" \
    "A network filesystem (FUSE/SMB) blocked the system from sleeping. Unmount it before closing the lid."
