# EndeavourOS Sway (Community Edition)

XXX `~/.config/sway/config.d/*`
XXX `/etc/sudo*`
XXX `clight` configs
XXX sway autologin bug report to Sway Community Edition
XXX maybe punt on geolocation?

## Install steps

From the live installer, pull in [Sway Community Edition](https://github.com/EndeavourOS-Community-Editions/sway?tab=readme-ov-file#with-the-eos-installer).

Options:
- whole disk
- swap as big as RAM
- btrfs
- encrypted

## Post-install steps

### Clear pacman cache

"Package Cleanup Configuration"
XXX what's the systemd job that gets enabled, and how?
`paccache` timer and service

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

### Timeshift rollback, too

```sh
yay -S timeshift-autosnap
sudo systemctl enable --now cronie
```

Then open the Timeshift app and follow the prompts.

```sh
sudo etckeeper commit -m "Enable Timeshift."
```

### Other dotfiles

```sh
ln -s ~/trees/dotfiles/tmux.conf ~/.tmux.conf
```

### Hardware support

#### Mac fan control

```sh
yay -S mbpfan
sudo cp /usr/lib/systemd/system/mbpfan.service /etc/systemd/system/
sudo systemctl enable --now mbpfan.service
sudo etckeeper commit -m "Enable mbpfan Mac fan control."
```

#### Keyboard backlighting

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

#### FaceTime webcam driver

For instance, on 2015 11" MacBook Air (MacBookAir7,1):
```sh
yay -S facetimehd-dkms
sudo modprobe
```

#### Lightweight webcam capture

```sh
sudo pacman -S guvcview
```

#### NVIDIA display workaround

For instance, on 2009 17" MacBook Pro (MacBookPro5,2), there's a phantom second internal display to disable, so that the display manager comes up on the real screen:
```sh
sudo sed -i 's/$/ video=LVDS-2:d/' /etc/kernel/cmdline
sudo reinstall-kernels
```

#### zswap for RAM-limited machines

```sh
sudo sed -i 's/$/ zswap.enabled=1 zswap.compressor=zstd zswap.zpool=z3fold zswap.max_pool_percent=20/' /etc/kernel/cmdline
sudo reinstall-kernels
```


XXX sound on Chromebooks
XXX F1 keys on Chromebooks

XXX power button does what? prompt?
XXX lid close does what? mute, lock, and suspend
XXX cursor to lower right does what? lock and sleep display
XXX cursor to upper right does what? lock
XXX desktop picture with the hostname, somehow

### Passwords

```sh
sudo pacman -S seahorse
yay -S 1password
```

### Web

```sh
sudo pacman -Rs firefox
yay -S helium-browser-bin ungoogled-chromium-bin webapp-manager
echo 'for_window [app_id="helium"] inhibit_idle fullscreen' >> ~/.config/sway/config.d/application_defaults
sed -i 's|exec firefox|exec xdg-open https://|g' ~/.config/sway/config.d/default
swaymsg reload
echo -e '[Desktop Entry]\nHidden=true' > ~/.local/share/applications/chromium.desktop
mkdir -p ~/.local/share/applications/kde4
echo -e '[Desktop Entry]\nHidden=true' > ~/.local/share/applications/kde4/webapp-manager.desktop
```

### Geolocation

```sh
sudo pacman -S xdg-desktop-portal-gtk
systemctl --user enable --now xdg-desktop-portal xdg-desktop-portal-gtk
sed -i 's/import-environment DISPLAY WAYLAND_DISPLAY SWAYSOCK/import-environment DISPLAY WAYLAND_DISPLAY SWAYSOCK XDG_CURRENT_DESKTOP/' ~/.config/sway/config.d/autostart_applications
swaymsg reload

### Local network share discovery

```sh
sudo firewall-cmd --set-default-zone=home
sudo firewall-cmd --reload
sudo pacman -S gvfs-dnssd
```

Log out and log back in. Thunar's Network view should show stuff.

### Device-to-device communication

```sh
sudo pacman -S tailscale
sudo systemctl enable --now tailscaled
sudo tailscale up
```

XXX by default it won't allow using a specified exit node
XXX [a systray applet](https://wiki.archlinux.org/title/Tailscale#Third-party_clients)

```sh
yay -S localsend-bin
sudo firewall-cmd --add-port=53317/tcp --permanent
sudo firewall-cmd --add-port=53317/udp --permanent
sudo firewall-cmd --reload
echo 'exec localsend --hidden' >> ~/.config/sway/config.d/autostart_applications
```

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

### Coding

```sh
sudo pacman -S apostrophe
yay -S clion clion-jre \
intellij-idea-ultimate-edition \
goland goland-jre \
webstorm webstorm-jre \
pycharm
yay -S pi-coding-agent
```

### Officing

```sh
sudo pacman -S zoom libreoffice-fresh abiword
yay -S teams-for-linux-electron-bin
```

### Gaming

```sh
lspci | grep -i vga
sudo pacman -S steam prismlauncher
yay -S minecraft-launcher
```

### Other

```sh
sudo pacman -S btop fastfetch tmux the_silver_searcher
sed -i 's/htop/btop/g' ~/.config/waybar/config
sed -i 's/waybar_htop/waybar_btop/g' ~/.config/sway/config.d/application_defaults
pkill -USR2 waybar
swaymsg reload
```
