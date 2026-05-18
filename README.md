# gatherd

## Why?

I want to be able to USB-boot a random old laptop, install an OS configured to perform reasonably well, keep pace with future adjustments, and not have to click or remember much to accomplish this.

## How

1. Boot the EndeavourOS live install environment
2. From the Welcome app, choose "Fetch your install customization file"
3. Enter this URL, then click OK:
```
https://raw.githubusercontent.com/schmonz/gatherd/main/postinstall
```
4. Start the installer, choosing online installation and no desktop
   - Whole disk, encrypted, one big btrfs, swap with hibernate
5. On reboot, once the setup job completes, what you get is primarily [EOS Sway Community Edition](https://github.com/EndeavourOS-Community-Editions/sway)
   -- plus customizations to suit my hardware and personal taste.

## Which hardware?

- Apple MacBook Air 7,1 (11", 2015)
- Apple MacBook Pro 5,2 (17", 2009)
- IBM ThinkPad T60
- Lenovo Chromebook 100e
- Lenovo ThinkPad X270

## Which customizations?

- **Apps**: 1Password, Helium browser (default), Tailscale, LocalSend, Discord, Signal, Slack, Zoom, Teams, LibreOffice, rclone, CLion, Claude Code + Desktop, btop, tmux, etckeeper, and more
- **System**: Tailscale with DNS push and firewall; CUPS printing; etckeeper for `/etc`; reflector-sorted mirrors; Sway autologin via greetd
- **Desktop**: macOS-style keyboard layout; Helium replaces Firefox as default browser; gtklock screen locker; custom swayidle; waybar uses btop; 1Password, Tailscale, and LocalSend autostarted; gnome-keyring unlocked at login; `pbcopy`/`pbpaste` wrappers via `wl-copy`/`wl-paste`
- **Hardware** (autodetected per machine): Apple fan control and FaceTime HD camera driver; Chromebook function keys and AVS audio; phantom second display fix; software GL for old ATI GPUs; zswap for low-RAM machines; ambient light sensor; keyboard backlight; lid and power-button handling
- **Dotfiles**: `gitconfig` and `tmux.conf` symlinked from [schmonz/dotfiles](https://github.com/schmonz/dotfiles)
