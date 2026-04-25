# TODO

## Current issues

- is screen locking working as intended?
   - idle timeout -> what do I see on wiggle or tap?
   - lid close -> what do I see on lid open?
- the feature-detection variables need to be renamed to `HAS_*`,
  defaulting to `true` or `false` to match "typical" or "usual" computers

## Stubs needing implementation

- **`setup_mac_light_sensors`**: sensor floor done. Still needed: clight dimmer
  config (40% target, 60s battery timeout) — verify key names against
  `man clight` or `/usr/share/clight/modules.conf.d/` on a live machine.
- **`setup_power_saving`**: empty stub. Decide TLP vs. power-profiles-daemon.
- **`setup_infrared_receiver`**: empty stub. Implement LIRC setup or drop.
- **`setup_thinkpad_goodies`**: empty stub. Investigate: smart card reader,
  T60 volume/power/ThinkVantage buttons, fingerprint reader.

## Phase 3 decisions needed

- **Timeshift**: find CLI equivalent to Welcome-app GUI for initial config.
  Decide snapper vs. Timeshift (snapper + pacman hooks?).
- **Tailscale**: exit node misconfigured ("cannot relay traffic") — check admin
  console.
- **LocalSend**: configure to use real system hostname.
- **Zoom screen sharing**: confirm whether it works under Sway/wlroots
  (xdg-desktop-portal-wlr). Document result.
- **Update notifier**: determine `eos-update-notifier` timer frequency. Decide
  whether to surface in Waybar.
- **ThinkPad screen brightness**: investigate clight or similar for autotuning.

## UX / pre-install

- Lid close: mute + lock + suspend (non-Chromebook).
- Hot corners: lower-right → lock + sleep display; upper-right → lock.
- Desktop wallpaper showing hostname.
- Font size for small screens (foot, text editor, system UI).
- Captive portal auto-browsing.
- AUR packages for TI calculator backup programs (need to create them).
- Pre-populate known WiFi configs in NetworkManager.
- Swap partition sizing for hibernate (Chromebook may differ).
- Geolocation: enable via `xdg-desktop-portal-gtk` or punt.

## Backlog

- when Helium doesn't need `seahorse`, [1Password will](https://bookstack.bluecrow.net/books/linux/page/arch-linux-gnome-keyring-and-1password)
- clamp `clight` values so as not to have a blank screen in the dark
- detect iSight camera and install `isight-firmware` (AUR)

# References (not run by this script)

## Boot repair / emergency

- chroot via live USB: https://gist.github.com/EdmundGoodman/c057ce0c826fd0edde7917d15b709f4f
- mount btrfs root subvolume: https://wiki.archlinux.org/title/Btrfs#Mounting_subvolumes
- EndeavourOS system rescue: https://discovery.endeavouros.com/system-rescue/arch-chroot/
- Restore: `~/.config/sway/config.d/*`, `/etc/sudo*`, clight configs
- Pinebook Pro: https://endeavouros.com/endeavouros-arm-install/

## Install steps (done before running this script, via live installer)

- Options: whole disk, encrypted, one big btrfs

## Supported machines

**Chromebook 100e** (Google/MrChromebox firmware):
- Suspend disabled (resume is broken)
- Lid-close via ACPI sysfs poller (EC never generates input events)
- Power button: logind ignores it; Sway handles XF86PowerOff

**MacBookPro5,2 / MacBookAir7,1**:
- Suspend left alone
- Power button: HandlePowerKey=ignore + XF86PowerOff binding in Sway
  (no udev rule needed; libinput sees the event without it)

**ThinkPad X270 / T60**:
- Suspend left alone
- Power button: udev strips power-switch tag so logind releases the
  exclusive grab; HandlePowerKey=ignore as belt-and-suspenders;
  XF86PowerOff binding in Sway
