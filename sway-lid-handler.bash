#!/bin/bash
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
