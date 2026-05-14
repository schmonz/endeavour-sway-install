#!/bin/bash
set -euo pipefail

[[ "${1}" == "pre" ]] || exit 0

# Abort FUSE connections so any process blocked in fuse_dentry_revalidate
# gets EIO immediately and can be frozen for suspend.
for conn in /sys/fs/fuse/connections/*/; do
    echo 1 > "${conn}abort" 2>/dev/null || true
done

awk '$3 ~ /^fuse\./ { print $2 }' /proc/mounts \
    | xargs -r umount -l 2>/dev/null || true
