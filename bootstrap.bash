#!/usr/bin/env bash
#
# Calamares shellprocess hook: runs inside the installer chroot.
# Installs Ansible, clones this repo, and registers the first-boot service.
# Everything else runs via ansible-playbook on first boot.
#
set -euo pipefail
export LANG=C.UTF-8

REPO_URL="https://github.com/schmonz/endeavour-sway-install.git"
DEST="/usr/local/lib/endeavour-setup"
SWAY_CE_URL="https://raw.githubusercontent.com/EndeavourOS-Community-Editions/sway/main/setup_sway_isomode.bash"

target_user=$(awk -F: '$3 >= 1000 && $3 < 65534 { print $1; exit }' /etc/passwd)

curl -fsSL "$SWAY_CE_URL" | bash -s -- "$target_user"

pacman -S --noconfirm --needed ansible git

[[ -d "$DEST/.git" ]] || git clone "$REPO_URL" "$DEST"

install -m 644 "$DEST/endeavour-setup.service" /etc/systemd/system/endeavour-setup.service
systemctl enable endeavour-setup.service
