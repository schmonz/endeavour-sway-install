#!/bin/sh
# Tell logind to ignore the power key (so Sway can handle it instead)
DROPIN=/etc/systemd/logind.conf.d/suspend.conf

if grep -q '^HandlePowerKey=' "$DROPIN"; then
    echo "HandlePowerKey already set in $DROPIN — no change made"
else
    echo 'HandlePowerKey=ignore' >> "$DROPIN"
    echo "Added HandlePowerKey=ignore to $DROPIN"
fi

systemctl restart systemd-logind
loginctl show-session | grep HandlePowerKey
