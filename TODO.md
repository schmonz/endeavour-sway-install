# endeavour-sway-install.sh — outstanding items

## Stubs / placeholders needing real implementations

- **`setup_mac_light_sensors`**: sensor floor done. Still needed: dimmer module config (40% target, 60s battery timeout) — verify exact key names against `man clight` or `/usr/share/clight/modules.conf.d/` on a live machine before writing.

- **`setup_pacman_cache`** (line 492): calls `etckeeper_commit` but never actually sets up paccache. Add `systemctl enable --now paccache.timer` (from `pacman-contrib`).

- **`setup_power_saving`** (line 498): empty stub. Decide on TLP vs. power-profiles-daemon and implement.

- **`setup_webcam`**: currently runs for all known machines (including T60 which has no webcam). Gate on actual webcam detection — e.g. check for `/dev/video*` or a populated `v4l2-ctl --list-devices` before installing guvcview.

- **`setup_infrared_receiver`** (line 502): empty stub. Implement LIRC setup or drop if not needed.

- **`setup_thinkpad_goodies`** (line 506): empty stub. Investigate and implement:
  - Smart card reader
  - T60 volume/power/ThinkVantage buttons
  - Fingerprint reader

## Phase 3 TODOs needing decisions/implementation

### Timeshift (line 772)
- Find CLI equivalent to the Welcome-app GUI for Timeshift initial config.
- Decide: snapper instead of / in addition to Timeshift? Does snapper integrate with pacman hooks?

### Networking (lines 804–813)
- Tailscale exit node misconfigured ("cannot relay traffic") — investigate admin console.
- LocalSend: configure to use real system hostname instead of default.

### Screen sharing (line 832)
- Confirm whether Zoom screen sharing actually works under Sway/wlroots (xdg-desktop-portal-wlr). Document result.

### Update notifier (line 836)
- Determine `eos-update-notifier` timer frequency.
- Decide whether to surface notifications in Waybar; implement if yes.

### MacBook-specific
- Investigate autotuned screen brightness for ThinkPad (clight or similar).

### General UX / cosmetics (end of phase3)
- Lid close: mute + lock + suspend (non-Chromebook machines).
- Hot corners: lower-right → lock + sleep display; upper-right → lock.
- Desktop wallpaper showing hostname.

## Header / pre-install notes needing resolution

- Font size for small screens (foot, text editor, system UI).
- Captive portal auto-browsing.
- AUR packages for TI calculator backup programs (need to create them).
- Pre-populate known WiFi configs in NetworkManager.
- Swap partition sizing for hibernate (and whether Chromebook needs it differently).
- Geolocation: decide whether to enable via `xdg-desktop-portal-gtk` or punt entirely.
