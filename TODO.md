# endeavour-sway-install.sh — outstanding items

## Bugs / syntax errors

- **Line 599**: backslash-then-comment breaks the `pacman -S` heredoc line:
  ```
  system-config-printer \  # XXX other cups goodies the installer was offering?
  ```
  The `\` must be on its own (no trailing comment). Fix: move the comment to the line above, or determine the correct cups packages and add them.

- **Warnings not delivered**: `WARNINGS_FILE` writes to `/root/endeavour-setup-warnings.txt` but `install_warnings_displayer` looks for `${target_home}/.config/endeavour-warnings`. The file is never copied between these paths, so accumulated warnings are never shown to the user.

## Stubs / placeholders needing real implementations

- **`setup_chromebook_audio`** (line 421): `echo "WHATEVER IT WANTS ME TO SAY"` is a literal placeholder — find the actual interactive prompt from `setup-audio --force-avs-install` and answer it correctly, or make it non-interactive.

- **`setup_mac_light_sensors`** (line 443): empty stub. Decide between lightum, macbook-lighter, pommed-light, or clight; implement or drop.

- **`setup_webcam`** (line 454): `sudo modprobe  # XXX missing module name` — fill in the facetimehd module name (`facetimehd`).

- **`setup_pacman_cache`** (line 492): calls `etckeeper_commit` but never actually sets up paccache. Add `systemctl enable --now paccache.timer` (from `pacman-contrib`).

- **`setup_power_saving`** (line 498): empty stub. Decide on TLP vs. power-profiles-daemon and implement.

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
- Tailscale systray multiplication on re-login — investigate and fix (likely needs `--replace` or a `WantedBy` fix).
- Tailscale exit node misconfigured ("cannot relay traffic") — investigate admin console.
- LocalSend: configure to use real system hostname instead of default.
- T60: test `sudo pacman -S vulkan-radeon` for the GL context error.
- Clickable URLs in Foot terminal — investigate `xdg-open` / `url-launcher` config.

### Screen sharing (line 832)
- Confirm whether Zoom screen sharing actually works under Sway/wlroots (xdg-desktop-portal-wlr). Document result.

### Update notifier (line 836)
- Determine `eos-update-notifier` timer frequency.
- Decide whether to surface notifications in Waybar; implement if yes.

### MacBook-specific (lines 874–879)
- Detect keyboard backlight device name dynamically instead of placeholder `'your-device-here'`.
- Uncomment and finalize the `brightnessctl` keyboard-brightness Sway bindings.
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

## Phase 2 minor note

- Line 716: `--needed` flag for pacman (skip already-installed) — decide if any `pacman -S` calls here should use it.
