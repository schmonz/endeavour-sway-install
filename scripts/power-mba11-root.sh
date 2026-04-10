#!/bin/sh
tee /etc/systemd/logind.conf.d/power-key.conf << 'EOF'
[Login]
HandlePowerKey=ignore
EOF
systemctl kill -s HUP systemd-logind
