# TODO

## Stubs needing implementation

- **clight**: installed on any machine with screen or keyboard backlight, but
  intentionally inoperative (clightd not enabled, not in sway autostart). Caused
  blank screen on resume from sleep on MacBook Air 11" (maps dark room to 0%).
  To activate: enable clightd service, add `exec clight` to sway autostart, and
  set a brightness floor (e.g. `min_backlight_pct = 0.15` in `clight.conf`) and
  dimmer config (40% target, 60s battery timeout) — verify key names against
  `man clight` or `/usr/share/clight/modules.conf.d/` on a live machine.
- **`setup_power_saving`**: empty stub. Decide TLP vs. power-profiles-daemon.
- **`setup_infrared_receiver`**: empty stub. Implement LIRC setup or drop.
- **`setup_thinkpad_goodies`**: empty stub. Investigate: smart card reader,
  T60 volume/power/ThinkVantage buttons, fingerprint reader.

## Phase 3 decisions needed

- **Timeshift**: find CLI equivalent to Welcome-app GUI for initial config.
  Decide snapper vs. Timeshift (snapper + pacman hooks?).
- **arch-update timer**: currently a systemd user timer; will need a different mechanism on Artix/s6.
- **ThinkPad screen brightness**: investigate clight or similar for autotuning.

## UX / pre-install

- **webapp-manager** generates non-spec-compliant `Exec` lines (`--app="url"` instead of `--app=url`), causing fuzzel to refuse to launch them. `gatherd-fix-webapps` auto-fixes new entries via inotifywait. Consider filing an upstream bug.
- Lid close: mute + lock + suspend (non-Chromebook).
- Hot corners: lower-right → lock + sleep display; upper-right → lock.
- Font size for small screens (foot, text editor, system UI).
- AUR packages for TI calculator backup programs (need to create them).
- Swap partition sizing for hibernate (Chromebook may differ).
- Geolocation: enable via `xdg-desktop-portal-gtk` or punt.

- **More dotfiles from dotfiles repo**: currently only `.gitconfig` and `.tmux.conf` are symlinked. Want to use more without losing system-provided defaults (sway configs, waybar, foot, etc. come from `sway-install.sh` and are patched by Ansible). Options: (a) for tools that support includes/fragments, have the personal dotfile source the system one; (b) for Sway specifically, already using `config.d/` — personal dotfiles can add more fragments; (c) for files that don't compose, decide whether personal or system default wins and manage accordingly.

## Backlog

- clamp `clight` values so as not to have a blank screen in the dark
- detect iSight camera and install `isight-firmware` (AUR)