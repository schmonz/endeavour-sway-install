#!/usr/bin/env bash
# sway-endeavour-chromebook-sleep-nonroot.sh
#
# Patches the Sway autostart config to disable suspend-triggering swayidle
# behaviour on a Chromebook where resume after suspend is broken.
# No root required.
#
# What this replaces:
#   exec swayidle idlehint 1
#     — set the logind idle hint after 1 second, which tripped
#       logind's IdleAction=suspend almost immediately
#   exec_always swayidle -w before-sleep "gtklock -d"
#     — locked the screen just before sleep (before-sleep hook never
#       fires once sleep is prevented, so this was also redundant)
#
# What this installs instead:
#   exec_always swayidle -w timeout 600 'gtklock -d'
#     — locks the screen after 10 minutes of inactivity; no sleep
#       actions involved
#
# The system-level changes (logind drop-in, masked sleep targets,
# sleep.conf drop-in) live in sway-endeavour-chromebook-sleep.sh
# and require sudo.

set -euo pipefail

SWAY_AUTOSTART="$HOME/.config/sway/config.d/autostart_applications"

if [[ ! -f "$SWAY_AUTOSTART" ]]; then
    echo "ERROR: $SWAY_AUTOSTART not found — nothing to do" >&2
    exit 1
fi

# Back up before touching.
BACKUP="${SWAY_AUTOSTART}.bak.$(date +%Y%m%d%H%M%S)"
echo "==> Backing up $SWAY_AUTOSTART to $BACKUP"
cp "$SWAY_AUTOSTART" "$BACKUP"

echo "==> Patching swayidle lines in $SWAY_AUTOSTART"
sed -i \
    '/^exec swayidle idlehint/d;
     s|^exec_always swayidle -w before-sleep.*|exec_always swayidle -w timeout 600 '"'"'gtklock -d'"'"'|' \
    "$SWAY_AUTOSTART"

# Reload the running Sway instance so the change takes effect immediately.
if command -v swaymsg &>/dev/null; then
    echo "==> Reloading Sway config"
    swaymsg reload
else
    echo "NOTE: swaymsg not found — reload Sway manually (default: \$mod+Shift+c)"
fi

echo ""
echo "==> Verification (running swayidle processes):"
pgrep -a swayidle || echo "(none — will start fresh on next Sway reload/login)"
