# EndeavourOS Sway

## Boot repair

- [chroot via live USB](https://gist.github.com/EdmundGoodman/c057ce0c826fd0edde7917d15b709f4f)
- [mount btrfs root subvolume](https://wiki.archlinux.org/title/Btrfs#Mounting_subvolumes)
- [EndeavourOS system rescue docs](https://discovery.endeavouros.com/system-rescue/arch-chroot/)

- `~/.config/sway/config.d/*`
- `/etc/sudo*`
- `clight` configs
- system (and foot, text editor, etc.) font size for small screens
- maybe punt on geolocation?
- I'll need to create AUR packages for the TI calc backup programs
- pre-populate known WiFi configs in NetworkManager?
- captive portal auto-browsering

[Pinebook Pro](https://endeavouros.com/endeavouros-arm-install/)

## Install steps

From the live installer, pull in [Sway Community Edition](https://github.com/EndeavourOS-Community-Editions/sway?tab=readme-ov-file#with-the-eos-installer).

Options:

- whole disk
- encrypted
- one big btrfs
- swap enough for hibernate (?) (different for Chromebook?)

## Post-install steps

### Revision-controlled `/etc`

```sh
mkdir trees && cd trees
git clone https://github.com/schmonz/dotfiles.git
ln -s ~/trees/dotfiles/gitconfig ~/.gitconfig
sudo -s
ln -s ~schmonz/trees/dotfiles/gitconfig ~root/.gitconfig
pacman -Syuu
pacman -S etckeeper
etckeeper init
etckeeper commit -m 'Track /etc in revision control.'
cd /etc
git branch -m $(hostname)
git gc --prune
pacman -S git-delta
```

### Clear pacman cache

"Package Cleanup Configuration" from the Welcome screen creates:

- `systemd/system/paccache.service`
- `systemd/system/paccache.timer`
- `systemd/system/timers.target.wants/paccache.timer`

```sh
sudo etckeeper commit -m 'Periodically clean pacman cache.'
```

XXX CLI equivalent

### Timeshift rollback, too

```sh
yay -S timeshift-autosnap
sudo pacman -S grub-btrfs xorg-xhost snapper inotify-tools
sudo systemctl enable --now cronie
```

Then open the Timeshift app and follow the prompts.

XXX CLI equivalent

```sh
sudo etckeeper commit -m "Enable Timeshift."
```

XXX snapper also? instead? does it integrate with pacman too?

### Actually autologin

```sh
sudo tee -a /etc/greetd/greetd.conf << 'EOF'

[initial_session]
command = "sway"
user = "schmonz"
EOF
sudo etckeeper commit -m "Enable autologin."
```

- [Sway Community Edition issue 105](https://github.com/EndeavourOS-Community-Editions/sway/issues/105)

### Other dotfiles

```sh
ln -s ~/trees/dotfiles/tmux.conf ~/.tmux.conf
```

### Accommodate macOS habits

#### Accents

```sh
sudo localectl set-x11-keymap us "" mac
sudo etckeeper commit -m "Enable Mac-like accents with Right-Alt."
swaymsg reload
```

#### Terminal copy/paste

```sh
printf '#!/bin/sh\nexec wl-copy "$@"\n' | sudo tee /usr/local/bin/pbcopy
printf '#!/bin/sh\nexec wl-paste --no-newline "$@"\n' | sudo tee /usr/local/bin/pbpaste
sudo chmod +x /usr/local/bin/pbcopy /usr/local/bin/pbpaste
```

### Hardware support

```bash
is_chromebook() {
    local firmware vendor
    firmware=$(sudo dmidecode -s bios-version)
    vendor=$(sudo dmidecode -s system-manufacturer)
    [[ "$vendor" == "Google" && "$firmware" == MrChromebox* ]]
}
```

#### Firmware updates

```sh
sudo pacman -S fwupd
fwupdmgr get-updates
fwupdmgr update
```

- [MrChromebox](https://docs.mrchromebox.tech/docs/firmware/updating-firmware.html)

#### Bluetooth

```sh
sudo systemctl enable --now bluetooth
sudo pacman -S --needed blueman
```

XXX what's `--needed`

[bluetoothctl, etc.](https://wiki.archlinux.org/title/Bluetooth#Pairing)

#### Chromebook can't resume, so prevent sleep

XXX remove `/etc/systemd/logind.conf.d/suspend.conf`?

```sh
sudo mkdir -p /etc/systemd/logind.conf.d
sudo tee -a /etc/systemd/logind.conf.d/disable-sleep.conf << 'EOF'
[Login]
IdleAction=ignore
HandleLidSwitch=lock
HandleLidSwitchExternalPower=lock
HandlePowerKey=ignore
HandlePowerKeyLongPress=ignore
EOF
sudo mkdir -p /etc/systemd/sleep.conf.d
sudo tee -a /etc/systemd/sleep.conf.d/disable-sleep.conf << 'EOF'
[Sleep]
AllowHibernation=no
AllowHybridSleep=no
AllowSuspendThenHibernate=no
AllowSuspend=no
EOF
sudo systemctl mask \
    hibernate.target \
    hybrid-sleep.target \
    sleep.target \
    suspend-then-hibernate.target \
    suspend.target
sudo systemctl daemon-reload
sudo etckeeper commit -m "Disable suspend (can't resume)."
```

- [Sway Community Edition pull request 104](https://github.com/EndeavourOS-Community-Editions/sway/pull/104)

#### Power button

##### Chromebook 100e

XXX this kills your Sway session and also you'll need to Ctrl-C to get back to greetd

```sh
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
```

XXX add an `XF86PowerOff` power menu binding in `~/.config/sway/config.d/default`


- XXX ThinkPad X270
- XXX ThinkPad T60
- XXX MacBookPro5,2
- XXX MacBookAir7,1

#### Lid close

##### Machines that suspend

In `~/.config/sway/config.d/autostart_applications`:

```txt
exec swayidle -w \
    idlehint 1 \
    timeout 300  'gtklock -d --lock-command "swaymsg output \* dpms off"' resume 'swaymsg "output * dpms on"' \
    lock         'gtklock -d --lock-command "swaymsg output \* dpms off"' \
    unlock       'swaymsg "output * dpms on"' \
    before-sleep 'gtklock -d; sleep 1' \
    after-resume 'swaymsg "output * dpms on"'
```

##### Machines that don't suspend

In `~/.config/systemd/user/sway-lid-handler.service`:

```ini
[Unit]
Description=Sway lid close handler (ACPI sysfs poller)
Documentation=file://%h/.local/bin/sway-lid-handler
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=%h/.local/bin/sway-lid-handler
Restart=always
RestartSec=1

[Install]
WantedBy=graphical-session.target
```

In `~/.local/bin/sway-lid-handler`:

```bash
#!/bin/bash
# sway-lid-handler
#
# Polls /proc/acpi/button/lid/LID0/state and acts on lid open/close.
#
# On this Chromebook hardware the EC handles the lid switch without generating
# kernel input events (EV_SW SW_LID never fires on /dev/input/event0), so
# logind and sway/libinput never see lid events. Polling the ACPI sysfs file
# is the only reliable detection mechanism.
#
# Lid close: loginctl lock-session → swayidle lock handler → gtklock + dpms off
# Lid open:  swaymsg output dpms on  (so the gtklock prompt is visible)
#
# Power efficiency: the loop uses only bash builtins (read) and sleep — no
# forked processes. This matters because process forks are CPU wakeup events
# that prevent the processor from staying in deep C-states. At 1s intervals
# the CPU gets one brief wakeup per second from the kernel timer; the rest of
# the time it can sleep deeply. Using awk or similar external tools instead of
# read would add a process-spawn wakeup on every iteration for no benefit.

LID_STATE=/proc/acpi/button/lid/LID0/state

read -r _ prev < "$LID_STATE"

while true; do
    read -r _ cur < "$LID_STATE"
    if [[ "$cur" != "$prev" ]]; then
        if [[ "$cur" == "closed" ]]; then
            loginctl lock-session
        else
            swaymsg "output * dpms on"
        fi
        prev="$cur"
    fi
    sleep 1
done
```

In `~/.config/sway/config.d/autostart_applications`:

```txt
exec systemctl --user start sway-lid-handler.service
exec swayidle -w \
    idlehint 1 \
    timeout 300  'gtklock -d --lock-command "swaymsg output \* dpms off"' resume 'swaymsg "output * dpms on"' \
    lock         'gtklock -d --lock-command "swaymsg output \* dpms off"' \
    unlock       'swaymsg "output * dpms on"'
```

XXX bug report to Sway community edition

#### Power-saving measures

- [TLP](https://wiki.archlinux.org/title/TLP)

#### Mac fan control

```sh
yay -S mbpfan
sudo cp /usr/lib/systemd/system/mbpfan.service /etc/systemd/system/
sudo systemctl enable --now mbpfan.service
sudo etckeeper commit -m "Enable mbpfan Mac fan control."
```

#### Mac light sensors

- [lightum](https://github.com/poliva/lightum)
- [macbook-lighter](https://github.com/harttle/macbook-lighter)
- [pommed](https://packages.debian.org/trixie/pommed)
- [pommed-light](https://github.com/bytbox/pommed-light)
- [Debian Mactel Team](https://qa.debian.org/developer.php?login=team%2Bpkg-mactel-devel%40tracker.debian.org)

#### Keyboard backlight

```sh
ls /sys/class/leds/ | grep -i kbd
brightnessctl --list | grep -i kbd
brightnessctl --device='your-device-here' set 50%
sed -i '/XF86MonBrightnessDown/a\        XF86KbdBrightnessUp exec brightnessctl -d smc::kbd_backlight set +5%\n        XF86KbdBrightnessDown exec brightnessctl -d smc::kbd_backlight set 5%-' ~/.config/sway/config.d/default
swaymsg reload
ls /sys/bus/iio/devices/*/in_illuminance*
yay -S iio-sensor-proxy clight
sudo systemctl enable --now clightd
echo 'exec clight' >> ~/.config/sway/config.d/autostart_applications
clight &
```

XXX what about autotuned screen brightness on ThinkPad?
XXX what about backlit keys on HP? autotuned clight?

#### FaceTime webcam

For instance, on 2015 11" MacBook Air (MacBookAir7,1):

```sh
yay -S facetimehd-dkms
sudo modprobe
```

#### iSight webcam

Not sure who needs this:

```sh
yay -S isight-firmware
```

#### Lightweight webcam capture

```sh
sudo pacman -S guvcview
```

#### NVIDIA display workaround

For instance, on 2009 17" MacBook Pro (MacBookPro5,2), there's a phantom second internal display to disable, so that the display manager comes up on the real screen:

XXX doesn't match

```sh
sudo sed -i "/^GRUB_CMDLINE_LINUX_DEFAULT'=/"'{
  /video=LVDS-2:d/! s/"$/ video=LVDS-2:d/
}' /etc/default/grub
sudo grub-mkconfig -o /boot/grub/grub.cfg
sudo etckeeper commit -m "Disable second internal display."
```

#### zswap for RAM-limited machines

XXX doesn't match

```sh
sudo sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT=/{
  /zswap.enabled=1/! s/"$/ zswap.enabled=1 zswap.compressor=zstd zswap.zpool=z3fold zswap.max_pool_percent=20/
}' /etc/default/grub
sudo grub-mkconfig -o /boot/grub/grub.cfg
sudo etckeeper commit -m "Enable zswap."
```

#### Chromebook audio

```sh
cd ~/trees
git clone https://github.com/WeirdTreeThing/chromebook-linux-audio
cd chromebook-linux-audio
echo "WHATEVER IT WANTS ME TO SAY" | ./setup-audio --force-avs-install
```

#### Chromebook F-keys

```sh
cd ~/trees
git clone https://github.com/WeirdTreeThing/cros-keyboard-map
cd cros-keyboard-map
./install.sh
```

#### Infrared receiver?

- [LIRC](https://wiki.archlinux.org/title/LIRC)

#### Other ThinkPad goodies?

- smart card?
- T60 volume and power buttons, ThinkVantage button, fingerprint reader



XXX lid close does what? mute, lock, and suspend
XXX cursor to lower right does what? lock and sleep display
XXX cursor to upper right does what? lock
XXX desktop picture with the hostname, somehow



### Passwords

```sh
sudo pacman -S seahorse
yay -S 1password
echo 'exec 1password' >> ~/.config/sway/config.d/autostart_applications
1password &
```

### Web

```sh
sudo pacman -Rs firefox
sudo mkdir /etc/1password
echo 'helium' | sudo tee -a /etc/1password/custom_allowed_browsers
sudo etckeeper commit -m "Enable Helium 1Password integration."
yay -S helium-browser-bin ungoogled-chromium-bin webapp-manager
echo 'for_window [app_id="helium"] inhibit_idle fullscreen' >> ~/.config/sway/config.d/application_defaults
sed -i 's|exec firefox|exec xdg-open https://|g' ~/.config/sway/config.d/default
swaymsg reload
echo -e '[Desktop Entry]\nHidden=true' > ~/.local/share/applications/chromium.desktop
mkdir -p ~/.local/share/applications/kde4
echo -e '[Desktop Entry]\nHidden=true' > ~/.local/share/applications/kde4/webapp-manager.desktop
```

Launch Helium. When prompted to assign a keyring passphrase, give an empty one.

<!--
### Geolocation

```sh
sudo pacman -S xdg-desktop-portal-gtk
systemctl --user enable --now xdg-desktop-portal xdg-desktop-portal-gtk
sed -i 's/import-environment DISPLAY WAYLAND_DISPLAY SWAYSOCK/import-environment DISPLAY WAYLAND_DISPLAY SWAYSOCK XDG_CURRENT_DESKTOP/' ~/.config/sway/config.d/autostart_applications
swaymsg reload
```
-->

### Local network share discovery

```sh
sudo firewall-cmd --set-default-zone=home
sudo firewall-cmd --reload
sudo etckeeper commit -m "Set default firewall zone to 'home'."
sudo pacman -S gvfs-dnssd
```

Log out and log back in. Thunar's Network view should show stuff.

### Device-to-device communication

XXX clicking URLs in Foot how?

```sh
sudo systemctl enable --now systemd-resolved
sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
sudo pacman -S tailscale
sudo systemctl enable --now tailscaled
sudo etckeeper commit -m "Enable Tailscale."
sudo tailscale set --operator=$USER
echo 'exec tailscale systray' >> ~/.config/sway/config.d/autostart_applications
tailscale systray &
tailscale up
```

Open the login link: `Ctrl-Shift-O` + the letter shown.

```sh
tailscale set --accept-dns=true
tailscale set --accept-routes
```

XXX the more I logout and login,the more tailscale systray icons I have
XXX is this true for other systray icons as well?

XXX maybe my exit node also isn't working? admin console says
XXX This machine is misconfigured and cannot relay traffic. Review this from the “Edit route settings...” option in the machine’s menu.
XXX but maybe that's enough for Plex (or Jellyfin)

```sh
yay -S localsend-bin
sudo firewall-cmd --add-port=53317/tcp --permanent
sudo firewall-cmd --add-port=53317/udp --permanent
sudo firewall-cmd --reload
sudo etckeeper commit -m "Allow LocalSend through firewall."
echo 'exec localsend --hidden' >> ~/.config/sway/config.d/autostart_applications
localsend --hidden &
```

XXX configure it to use the real system hostname

XXX T60 `unable to create a GL context`
XXX try `sudo pacman -S vulkan-radeon`

### Social

```sh
sudo pacman -S discord signal-desktop
yay -S slack-electron
```

### Cloud Storage

```sh
yay -S rclone
rclone config
```

After the authentication error, log into icloud.com in a browser, open Chrome Dev Tools, go to the Network tab, click a request, grab the full `Cookie` header and the `X-APPLE-WEBAUTH-HSA-TRUST` value, then feed them to rclone:

```sh
rclone config update icloud cookies='' trust_token=""
```

The token expires monthly, so you have to redo this every ~30 days. [Source](https://forum.rclone.org/t/icloud-connect-not-working-http-error-400/52019/44)

### Code

```sh
sudo pacman -S apostrophe glow tig github-cli socat
yay -S clion clion-jre \
intellij-idea-ultimate-edition \
goland goland-jre \
webstorm webstorm-jre \
pycharm \
dawn-writer-bin \
claude-code claude-desktop-bin claude-cowork-service
```

### Office

```sh
sudo pacman -S libreoffice-fresh abiword cups cups-browsed system-config-printer
yay -S zoom teams-for-linux-electron-bin
```

XXX other cups goodies the installer was offering?

### Screen sharing

XXX these already seem to be installed

```sh
sudo pacman -S xdg-desktop-portal xdg-desktop-portal-wlr
echo 'enableWaylandShare=true' >> ~/.config/zoomus.conf
```

XXX has this actually worked?

### Gaming

```sh
lspci | grep -i vga
sudo pacman -S steam prismlauncher
yay -S minecraft-launcher
```

### OS update notifications

```sh
sudo pacman -S eos-update-notifier
sudo sed -i 's|ShowHowAboutUpdates=notify|ShowHowAboutUpdates=notify+tray|' /etc/eos-update-notifier.conf
sudo etckeeper commit -m "Configure eos-update-notifier."
eos-update-notifier -init
```

XXX runs on a timer -- how often?
XXX show up in the Waybar?
 
### Other

```sh
sudo pacman -S btop fastfetch tmux the_silver_searcher xorg-xhost
sed -i 's/htop/btop/g' ~/.config/waybar/config
sed -i 's/waybar_htop/waybar_btop/g' ~/.config/sway/config.d/application_defaults
pkill -USR2 waybar
swaymsg reload
```
