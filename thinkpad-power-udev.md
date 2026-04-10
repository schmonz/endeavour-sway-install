Create `/etc/udev/rules.d/99-power-button-sway.rules` with this content (run as root):

```bash
sudo tee /etc/udev/rules.d/99-power-button-sway.rules <<'EOF'
# Stop logind from grabbing the power button exclusively.
# This lets libinput/Sway handle it via bindsym XF86PowerOff.
SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_PATH}=="acpi-LNXPWRBN:00", \
    TAG-="power-switch", TAG+="seat", TAG+="uaccess"
EOF
```

- `TAG-="power-switch"` — stops logind from watching/grabbing the device (runs after `70-power-switch.rules`)
- `TAG+="seat"` — makes it a seat-managed device so logind's `TakeDevice` hands it to the active session
- `TAG+="uaccess"` — gives the logged-in user direct ACL access as a fallback

Then reload and re-evaluate:

```bash
sudo udevadm control --reload-rules
sudo udevadm trigger /dev/input/event2
```

Verify the tag is gone:

```bash
udevadm info /dev/input/event2 | grep -E "TAGS|CURRENT_TAGS"
```

You should see `seat` and `uaccess` but **not** `power-switch`. Then either reboot, or restart Sway — because logind opened the grab at boot and a `trigger` updates the udev database but can't retroactively release an already-held `EVIOCGRAB`. A re-login/reboot is needed for logind to not re-grab it on startup.

After that, your existing `bindsym XF86PowerOff exec $powermenu` line in the Sway config takes over with no acpid needed at all.
