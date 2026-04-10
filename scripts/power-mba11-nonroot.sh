#!/bin/sh
CONFIG=~/.config/sway/config.d/default
if ! grep -q 'bindsym XF86PowerOff exec \$powermenu' "$CONFIG"; then
    sed -i '/bindsym \$mod+Shift+e exec \$powermenu/a\    bindsym XF86PowerOff exec $powermenu' "$CONFIG"
fi
swaymsg reload
