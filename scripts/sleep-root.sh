#!/usr/bin/env bash
# sway-endeavour-chromebook-sleep.sh
#
# Disables suspend/sleep on an EndeavourOS + Sway Chromebook where
# resume after suspend is broken. Operates at two levels:
#
#   1. SYSTEMIC  — systemd (logind + sleep targets + sleep.conf)
#   2. UI        — Sway autostart (swayidle)
#
# Run once as your normal user (sudo will be invoked internally for
# system-level changes). Safe to re-run; all writes are idempotent.
#
# Tested on: EndeavourOS rolling / kernel 6.x / Sway / Wayland

set -euo pipefail

# ────────────────────────────────────────────────────────────────────────────
# 1. LOGIND DROP-IN
#    logind is the gatekeeper for power-key, lid-switch, and idle actions.
#    The original drop-in at /etc/systemd/logind.conf.d/suspend.conf was
#    shipping IdleAction=suspend, which caused the machine to suspend after
#    10 minutes of idle. We override every relevant handle here.
# ────────────────────────────────────────────────────────────────────────────

LOGIND_DROP_IN="/etc/systemd/logind.conf.d/suspend.conf"

echo "==> Writing $LOGIND_DROP_IN"
sudo tee "$LOGIND_DROP_IN" > /dev/null << 'EOF'
[Login]
# Do nothing when the session has been idle — the default is "ignore" in
# upstream systemd but was shipped as "suspend" in this EndeavourOS config.
IdleAction=ignore

# Do nothing when the lid is closed, with or without external power.
# Default upstream behaviour is "suspend" for both.
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
EOF

# logind must be restarted to pick up drop-in changes.
# This will briefly disconnect your session's login tracking but is safe.
echo "==> Restarting systemd-logind"
sudo systemctl restart systemd-logind

# ────────────────────────────────────────────────────────────────────────────
# 2. MASK SLEEP TARGETS
#    Masking a systemd target replaces it with a symlink to /dev/null, making
#    it impossible for any process (including systemd itself) to activate it.
#    This is the hard stop: even if logind is misconfigured in future, or
#    something calls `systemctl suspend` directly, the kernel will not sleep.
# ────────────────────────────────────────────────────────────────────────────

echo "==> Masking sleep/suspend/hibernate targets"
sudo systemctl mask \
    sleep.target \
    suspend.target \
    hibernate.target \
    hybrid-sleep.target

# ────────────────────────────────────────────────────────────────────────────
# 3. SLEEP.CONF DROP-IN
#    /etc/systemd/sleep.conf controls which sleep states systemd-sleep is
#    allowed to enter. Setting Allow*=no here is a third layer of defence:
#    even if a target were unmasked, systemd-sleep would refuse to proceed.
# ────────────────────────────────────────────────────────────────────────────

SLEEP_DROP_IN="/etc/systemd/sleep.conf.d/nosuspend.conf"

echo "==> Writing $SLEEP_DROP_IN"
sudo mkdir -p "$(dirname "$SLEEP_DROP_IN")"
sudo tee "$SLEEP_DROP_IN" > /dev/null << 'EOF'
[Sleep]
AllowSuspend=no
AllowHibernation=no
AllowSuspendThenHibernate=no
AllowHybridSleep=no
EOF

# ────────────────────────────────────────────────────────────────────────────
# 4. SWAY AUTOSTART — swayidle
#    Two swayidle instances were configured:
#
#      a) swayidle idlehint 1
#         Sets the logind "idle hint" after just 1 second of inactivity.
#         This was the proximate trigger for logind's IdleAction=suspend.
#
#      b) swayidle -w before-sleep "gtklock -d"
#         Locks the screen just before sleep. Harmless once sleep is
#         prevented, but the before-sleep hook never fires anyway.
#
#    Both are replaced with a single swayidle invocation that locks the
#    screen after 10 minutes of inactivity — no sleep actions involved.
# ────────────────────────────────────────────────────────────────────────────

SWAY_AUTOSTART="$HOME/.config/sway/config.d/autostart_applications"

if [[ ! -f "$SWAY_AUTOSTART" ]]; then
    echo "WARNING: $SWAY_AUTOSTART not found — skipping Sway edit"
else
    # Back up the original before touching it.
    BACKUP="${SWAY_AUTOSTART}.bak.$(date +%Y%m%d%H%M%S)"
    echo "==> Backing up $SWAY_AUTOSTART to $BACKUP"
    cp "$SWAY_AUTOSTART" "$BACKUP"

    echo "==> Patching swayidle lines in $SWAY_AUTOSTART"
    # Replace the old two-line swayidle block with a single idle-lock line.
    # sed -i operates in-place; the pattern matches either old line and
    # replaces the first match with the new line, deleting the second.
    sed -i \
        '/^exec swayidle idlehint/d;
         s|^exec_always swayidle -w before-sleep.*|exec_always swayidle -w timeout 600 '"'"'gtklock -d'"'"'|' \
        "$SWAY_AUTOSTART"

    # Tell the running Sway instance to reload its config.
    if command -v swaymsg &>/dev/null; then
        echo "==> Reloading Sway config"
        swaymsg reload
    else
        echo "NOTE: swaymsg not found — reload Sway manually (default: \$mod+Shift+c)"
    fi
fi

# ────────────────────────────────────────────────────────────────────────────
# VERIFY
# ────────────────────────────────────────────────────────────────────────────

echo ""
echo "==> Verification"
echo ""

echo "-- logind effective config (IdleAction / HandleLid*):"
systemd-analyze cat-config systemd/logind.conf \
    | grep -E "^\s*(IdleAction|HandleLidSwitch)" || true

echo ""
echo "-- sleep target mask status:"
systemctl show sleep.target suspend.target hibernate.target hybrid-sleep.target \
    -p Id,LoadState,UnitFileState | paste - - - | column -t

echo ""
echo "-- sleep.conf effective AllowSuspend:"
systemd-analyze cat-config systemd/sleep.conf \
    | grep -E "^\s*Allow" || true

echo ""
echo "==> Done. Suspend is now disabled at all three systemd layers"
echo "    and swayidle will only lock the screen (after 10 min idle)."
