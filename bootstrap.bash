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

pacman -S --noconfirm --needed ansible git

[[ -d "$DEST/.git" ]] || git clone "$REPO_URL" "$DEST"

ansible-galaxy collection install --requirements-file "$DEST/requirements.yml"

install -m 644 "$DEST/endeavour-setup.service" /etc/systemd/system/endeavour-setup.service
systemctl enable endeavour-setup.service
