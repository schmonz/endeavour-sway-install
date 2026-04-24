# TODO

- when Helium doesn't need `seahorse`, [1Password will](https://bookstack.bluecrow.net/books/linux/page/arch-linux-gnome-keyring-and-1password)
- clamp `clight` values so as not to have a blank screen in the dark
- detect iSight camera and install `isight-firmware` (AUR)

# Boot repair / emergency references (not run by this script):
#   chroot via live USB: https://gist.github.com/EdmundGoodman/c057ce0c826fd0edde7917d15b709f4f
#   mount btrfs root subvolume: https://wiki.archlinux.org/title/Btrfs#Mounting_subvolumes
#   EndeavourOS system rescue: https://discovery.endeavouros.com/system-rescue/arch-chroot/
#   Restore: ~/.config/sway/config.d/*, /etc/sudo*, clight configs
#   XXX system (and foot, text editor, etc.) font size for small screens
#   XXX maybe punt on geolocation?
#   XXX I'll need to create AUR packages for the TI calc backup programs
#   XXX pre-populate known WiFi configs in NetworkManager?
#   XXX captive portal auto-browsing
#   Pinebook Pro: https://endeavouros.com/endeavouros-arm-install/
#
# Install steps (done before running this script, via live installer):
#   Pull in Sway Community Edition:
#     https://github.com/EndeavourOS-Community-Editions/sway
#   Options: whole disk, encrypted, one big btrfs
#   XXX swap enough for hibernate? (different for Chromebook?)
#
# Supported machines:
#   Chromebook 100e (Google/MrChromebox firmware)
#     - Suspend disabled (resume is broken)
#     - Lid-close via ACPI sysfs poller (EC never generates input events)
#     - Power button: logind ignores it; Sway handles XF86PowerOff
#   MacBookPro5,2 / MacBookAir7,1
#     - Suspend left alone
#     - Power button: HandlePowerKey=ignore + XF86PowerOff binding in Sway
#       (no udev rule needed; libinput sees the event without it)
#   ThinkPad X270 / T60
#     - Suspend left alone
#     - Power button: udev strips power-switch tag so logind releases the
#       exclusive grab; HandlePowerKey=ignore as belt-and-suspenders;
#       XF86PowerOff binding in Sway


