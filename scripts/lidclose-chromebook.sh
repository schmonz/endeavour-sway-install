#!/usr/bin/env bash
# sway-endeavour-chromebook-lidclose.sh
#
# Configures lid-close to lock the screen (and blank the display) on
# EndeavourOS/Sway, without triggering suspend (which is disabled because
# resume is broken on this Chromebook hardware).
#
# ── Root cause ────────────────────────────────────────────────────────────────
# The EC (Embedded Controller) on this Chromebook handles the lid switch
# internally and never generates a kernel input event. Specifically, EV_SW
# SW_LID never fires on /dev/input/event0, even though the kernel ACPI button
# driver registers the device and logind watches it. Confirmed by reading raw
# events with Python directly from /dev/input/event0 while closing the lid:
# nothing arrives.
#
# ── What doesn't work and why ─────────────────────────────────────────────────
# 1. logind HandleLidSwitch=lock
#    Looks right in theory. logind watches /dev/input/event0 ("Lid Switch") and
#    is configured to send a D-Bus Lock signal on lid-close. But it never sees
#    the event, so it never fires. Confirmed with `busctl monitor` on the system
#    bus: no Lock signal appears when the lid is closed.
#
# 2. swayidle lock/unlock handlers
#    swayidle subscribes to logind's Lock/Unlock D-Bus signals and responds with
#    gtklock + dpms off / dpms on. This works correctly for manual locking
#    (loginctl lock-session triggers it fine) but is useless for lid-close
#    because logind never sends the signal.
#
# 3. sway bindswitch lid:on / lid:off
#    Sway reads lid events via libinput, independent of logind. bindswitch
#    should fire even when logind doesn't. But libinput also gets its events
#    from /dev/input/event0, which is silent on this hardware, so bindswitch
#    never fires either. Confirmed by replacing the exec with `date >
#    /tmp/lid-on.txt` — the file was never created.
#    Note: the screen appeared to blank on lid-close during testing, but that
#    was the hardware backlight going off, not any dpms command we issued.
#
# ── What works ────────────────────────────────────────────────────────────────
# /proc/acpi/button/lid/LID0/state does update when the lid closes ("closed")
# and opens ("open"), even though no input event is generated. A polling loop
# on that file is the only reliable hook available on this hardware.
#
# ── What this script does ─────────────────────────────────────────────────────
#   1. Tells logind to lock on lid-close (harmless; logind never sees the event)
#   2. Updates the swayidle autostart command to:
#        - lock after 600s idle
#        - blank display 5s after the idle lock kicks in
#        - restore display when activity resumes after idle blanking
#        - respond to logind Lock/Unlock signals (e.g. loginctl lock-session)
#   3. Installs ~/.local/bin/sway-lid-handler — a poller that watches the ACPI
#      sysfs lid state and calls loginctl lock-session on close (which triggers
#      swayidle's lock handler: gtklock + dpms off) and dpms on on open
#   4. Installs and enables a systemd user service to run the poller
#   5. Adds an exec line to the sway autostart to start the service on login
#
# Run once as your normal user (sudo is used only where needed).
# After running, reload Sway: $mod+Shift+c  or  swaymsg reload

set -euo pipefail

LOGIND_CONF=/etc/systemd/logind.conf.d/suspend.conf
SWAY_AUTOSTART=~/.config/sway/config.d/autostart_applications
LID_HANDLER=~/.local/bin/sway-lid-handler
SYSTEMD_SERVICE=~/.config/systemd/user/sway-lid-handler.service

# ── 1. logind: lid-close → lock (harmless; logind never sees the event) ──────
echo "==> Updating $LOGIND_CONF ..."
sudo sed -i \
    -e 's/^HandleLidSwitch=ignore/HandleLidSwitch=lock/' \
    -e 's/^HandleLidSwitchExternalPower=ignore/HandleLidSwitchExternalPower=lock/' \
    "$LOGIND_CONF"

echo "    Current lid-switch settings:"
grep 'HandleLidSwitch' "$LOGIND_CONF" | sed 's/^/      /'

echo "==> Restarting systemd-logind ..."
sudo systemctl restart systemd-logind
echo "    Done."

# ── 2. swayidle: idle lock/blank + logind lock/unlock signal handling ─────────
echo ""
echo "==> Updating swayidle command in $SWAY_AUTOSTART ..."

OLD_SWAYIDLE="exec_always swayidle -w timeout 600 'gtklock -d'"
NEW_SWAYIDLE="exec_always swayidle -w \\\\
    timeout 600 'gtklock -d' \\\\
    timeout 605 'swaymsg \"output * dpms off\"' \\\\
    resume      'swaymsg \"output * dpms on\"' \\\\
    lock        'swaymsg \"output * dpms off\" ; gtklock -d' \\\\
    unlock      'swaymsg \"output * dpms on\"'"

if grep -qF "$OLD_SWAYIDLE" "$SWAY_AUTOSTART"; then
    sed -i "s|${OLD_SWAYIDLE}|${NEW_SWAYIDLE}|" "$SWAY_AUTOSTART"
    echo "    Replaced existing swayidle line."
else
    echo "    WARNING: expected swayidle line not found — check $SWAY_AUTOSTART"
    echo "    Expected:  $OLD_SWAYIDLE"
    echo "    Add manually if the line has changed."
fi

# ── 3. Install lid handler script ─────────────────────────────────────────────
echo ""
echo "==> Installing $LID_HANDLER ..."
mkdir -p "$(dirname "$LID_HANDLER")"
cat > "$LID_HANDLER" << 'SCRIPT'
#!/bin/bash
# sway-lid-handler
#
# Polls /proc/acpi/button/lid/LID0/state and acts on lid open/close.
#
# On this Chromebook hardware the EC handles the lid switch without generating
# kernel input events (EV_SW SW_LID never fires on /dev/input/event0), so
# logind and sway/libinput never see lid events. Polling the ACPI sysfs file
# is the only reliable detection mechanism.
#
# Lid close: loginctl lock-session → swayidle lock handler → gtklock + dpms off
# Lid open:  swaymsg output dpms on  (so the gtklock prompt is visible)
#
# Power efficiency: the loop uses only bash builtins (read) and sleep — no
# forked processes. This matters because process forks are CPU wakeup events
# that prevent the processor from staying in deep C-states. At 1s intervals
# the CPU gets one brief wakeup per second from the kernel timer; the rest of
# the time it can sleep deeply. Using awk or similar external tools instead of
# read would add a process-spawn wakeup on every iteration for no benefit.

LID_STATE=/proc/acpi/button/lid/LID0/state

read -r _ prev < "$LID_STATE"

while true; do
    read -r _ cur < "$LID_STATE"
    if [[ "$cur" != "$prev" ]]; then
        if [[ "$cur" == "closed" ]]; then
            loginctl lock-session
        else
            swaymsg "output * dpms on"
        fi
        prev="$cur"
    fi
    sleep 1
done
SCRIPT
chmod +x "$LID_HANDLER"
echo "    Done."

# ── 4. Install and enable systemd user service ────────────────────────────────
echo ""
echo "==> Installing systemd user service ..."
mkdir -p "$(dirname "$SYSTEMD_SERVICE")"
cat > "$SYSTEMD_SERVICE" << 'SERVICE'
[Unit]
Description=Sway lid close handler (ACPI sysfs poller)
Documentation=file://%h/.local/bin/sway-lid-handler
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=%h/.local/bin/sway-lid-handler
Restart=always
RestartSec=1

[Install]
WantedBy=graphical-session.target
SERVICE

systemctl --user daemon-reload
systemctl --user enable sway-lid-handler.service
systemctl --user restart sway-lid-handler.service
echo "    Service enabled and started."

# ── 5. Add exec line to sway autostart ───────────────────────────────────────
echo ""
echo "==> Updating sway autostart ..."

SERVICE_EXEC="exec systemctl --user start sway-lid-handler.service"
if grep -qF "$SERVICE_EXEC" "$SWAY_AUTOSTART"; then
    echo "    Autostart entry already present, skipping."
else
    cat >> "$SWAY_AUTOSTART" << EOF

# Lid-close handling via ACPI sysfs poller (see ~/.local/bin/sway-lid-handler).
# On this Chromebook the EC handles the lid switch without generating kernel
# input events, so logind and sway/libinput never see lid events. The poller
# watches /proc/acpi/button/lid/LID0/state and calls loginctl lock-session.
${SERVICE_EXEC}
EOF
    echo "    Added autostart entry."
fi

# ── 6. Summary ────────────────────────────────────────────────────────────────
echo ""
echo "==> All done. Reload Sway to apply changes:"
echo "      swaymsg reload"
echo "    (or press \$mod+Shift+c)"
echo ""
echo "    Lid-close behaviour:"
echo "      sway-lid-handler detects lid close via ACPI sysfs"
echo "        → loginctl lock-session"
echo "        → swayidle lock handler: gtklock + dpms off"
echo "      Lid open:"
echo "        → swaymsg output dpms on (gtklock remains until unlocked)"
