# ThinkPad X270 Power Button → Sway Power Menu

## The Problem

On modern kernels, the ACPI power button (`LNXPWRBN`) sends events exclusively
via **evdev** (`/dev/input/eventN`), not via the ACPI netlink socket. systemd-logind
watches any input device tagged `power-switch` in udev and holds an exclusive
`EVIOCGRAB` on it — even when `HandlePowerKey=ignore` is configured. This means
Sway/libinput never sees the key event, and `bindsym XF86PowerOff` is dead code.

acpid (which listens on the ACPI netlink socket) also won't help — it never sees
evdev-only devices.

## The Fix

Create a udev rule that runs after `70-power-switch.rules` and strips the
`power-switch` tag from the power button device. Without that tag, logind won't
grab it, and libinput can hand the key event to Sway normally.

### 1. Identify the power button device

```bash
# Find input devices by name
grep -r "" /sys/class/input/*/name | grep -i "power\|button"

# Get the event node
for input in /sys/class/input/input*/; do
    name=$(cat "$input/name" 2>/dev/null)
    if [[ "$name" == "Power Button" ]]; then
        echo "device: $input"
        ls "$input" | grep event
    fi
done

# Get the udev ID_PATH (used in the rule below)
udevadm info /dev/input/eventN | grep ID_PATH
```

On the ThinkPad X270 the answers are `/dev/input/event2` and `acpi-LNXPWRBN:00`.

### 2. Confirm logind is grabbing it

```bash
journalctl -b | grep -i "event2\|power button\|LNXPWRBN"
# Expect: systemd-logind[...]: Watching system buttons on /dev/input/event2 (Power Button)
```

### 3. Create the udev override rule

`/etc/udev/rules.d/99-power-button-sway.rules`:

```
# Stop logind from grabbing the power button exclusively.
# This lets libinput/Sway handle it via bindsym XF86PowerOff.
SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_PATH}=="acpi-LNXPWRBN:00", \
    TAG-="power-switch", TAG+="seat", TAG+="uaccess"
```

- `TAG-="power-switch"` — prevents logind from watching/grabbing the device
- `TAG+="seat"` — makes it a seat-managed device so logind's `TakeDevice` hands it to the active session
- `TAG+="uaccess"` — grants the logged-in user direct ACL access as a fallback

### 4. Apply and verify

```bash
sudo udevadm control --reload-rules
sudo udevadm trigger /dev/input/event2

# power-switch should be absent from CURRENT_TAGS
udevadm info /dev/input/event2 | grep -E "TAGS|CURRENT_TAGS"
```

### 5. Force libinput to rediscover the device

libinput may not have opened the device at Sway startup (logind held the grab).
Simulate a remove/add cycle, or log out and back in:

```bash
sudo udevadm trigger --action=remove /dev/input/event2
sudo udevadm trigger --action=add /dev/input/event2
```

## Sway Config

In `~/.config/sway/config.d/default` there's an existing binding for `$powermenu`.
Next to that one, add this one:

```
bindsym XF86PowerOff exec $powermenu
```

## logind Config

Append to `/etc/systemd/logind.conf.d/suspend.conf`:

```
HandlePowerKey=ignore
```

This prevents logind from acting on the power button
if something causes the `power-switch` tag to come back (e.g., a systemd upgrade
overwriting udev rules).
