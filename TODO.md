# TODO

## Hardware

- **clight**: installed on any machine with screen or keyboard backlight, but
  intentionally inoperative (clightd not enabled, not in sway autostart). Caused
  blank screen on resume from sleep on MacBook Air 11" (maps dark room to 0%).
  To activate: enable clightd service, add `exec clight` to sway autostart, and
  set a brightness floor (e.g. `min_backlight_pct = 0.15` in `clight.conf`) and
  dimmer config (40% target, 60s battery timeout) — verify key names against
  `man clight` or `/usr/share/clight/modules.conf.d/` on a live machine.

- **iSight camera**: detect and install `isight-firmware` (AUR).

- **ThinkPad fingerprint reader**: investigate `fprintd` + PAM integration.
  Needs per-model enrollment testing (T60 optical sensor vs. newer swipe/touch
  sensors).

- **ThinkPad smart card reader**: investigate `pcscd` + `opensc`. T60 has a
  built-in reader; verify other models.

- **ThinkPad docking**: investigate `dockd` or udev rules for dock/undock events
  (display reconfiguration, power profile switch).

## Electron app UI scaling

Five Electron apps are installed. Their UI may be fine at default scale on 1080p,
but if they ever look too small, here's how to scale each:

- **Slack** (`slack-electron`, system `electron39`) and **Teams**
  (`teams-for-linux-electron`, system `electron41`): both wrapper scripts fall back
  to `~/.config/electron-flags.conf`. Add `--force-device-scale-factor=1.4` there.
  Teams also reads its own app-specific conf
  (`~/.config/teams-for-linux-electron-flags.conf`) which avoids the double-application
  that happens when using `electron-flags.conf` (Teams reads it, then `electron41` reads
  it again).

- **Signal**: has `~/.config/signal-desktop-flags.conf` support built into its launcher.

- **Claude**: runs native Wayland automatically (no flags.conf hook). Options: local
  desktop override at `~/.local/share/applications/claude.desktop`, or a wrapper at
  `~/.local/bin/claude-desktop`.

- **1Password**: already wrapped by `gatherd-systray-1password`; add the flag there.

Ansible hook: write `~/.config/electron-flags.conf` (covers Slack + Teams) and
`~/.config/signal-desktop-flags.conf` from the desktop role, using
`--force-device-scale-factor={{ foot_font_size | float / 10.0 }}`.

## Desktop / UX

- **Lid close**: mute + lock + suspend (non-Chromebook).
- **Hot corners**: lower-right → lock + sleep display; upper-right → lock.
- **Font size for small screens**: foot, text editor, and system UI all need
  adjustment on screens narrower than 1920px (currently only foot is auto-sized).
- **Geolocation**: enable via `xdg-desktop-portal-gtk` or punt.
- **More dotfiles**: currently only `.gitconfig` and `.tmux.conf` are symlinked.
  Want to use more without losing system-provided defaults (sway configs, waybar,
  foot, etc. come from `sway-install.sh` and are patched by Ansible). Options:
  (a) for tools that support includes/fragments, have the personal dotfile source
  the system one; (b) for Sway specifically, already using `config.d/` — personal
  dotfiles can add more fragments; (c) for files that don't compose, decide whether
  personal or system default wins and manage accordingly.

## Setup

- **Snapshots**: find CLI equivalent to Welcome-app GUI for Timeshift initial
  config. Decide snapper vs. Timeshift (snapper + pacman hooks?).
- **Swap for hibernate**: size swap partition appropriately; Chromebook may differ.
- **TI calculator AUR packages**: create AUR packages for TI calculator backup
  programs; install here once they exist.

## Portability

- **arch-update timer**: currently a systemd user timer; will need a different
  mechanism on Artix/s6.
- **webapp-manager** generates non-spec-compliant `Exec` lines (`--app="url"`
  instead of `--app=url`), causing fuzzel to refuse to launch them.
  `gatherd-fix-webapps` auto-fixes new entries via inotifywait. Consider filing
  an upstream bug.
