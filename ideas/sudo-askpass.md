# Configuring sudo askpass

## Step 1: Set the askpass helper in `/etc/sudo.conf`

Edit `/etc/sudo.conf` as root and add (or uncomment and change) the `Path askpass` line:

```
Path askpass /usr/lib/gcr4-ssh-askpass
```

This tells sudo to use a graphical Wayland-compatible dialog when it needs a
password but has no terminal available.

## Step 2: Fix credential caching in `/etc/sudoers.d/custom`

Run `sudo visudo -f /etc/sudoers.d/custom` and add:

```
Defaults:schmonz timestamp_type=global
Defaults:schmonz timestamp_timeout=2
```

By default sudo caches credentials per-TTY, so each subprocess invocation (e.g.
from an agent) would trigger a separate prompt. `timestamp_type=global` makes the
cache shared across all processes for the user. `timestamp_timeout=2` shortens the
window to 2 minutes as a modest security tradeoff.
