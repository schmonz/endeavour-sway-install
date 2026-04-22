# Per-machine wallpaper from AI image + hostname stamp

## 1. Generate the image

Use Grok (grok.com) or Gemini (gemini.google.com) to generate an image.
Craft a prompt for your preferred style, e.g.:

> "Dark atmospheric landscape, moody lighting, painterly, wide aspect ratio, no text"

Download the image and save it somewhere, e.g. `~/Downloads/base.png`.

## 2. Stamp the hostname

```bash
convert ~/Downloads/base.png \
  -font DejaVu-Sans-Bold \
  -pointsize 48 \
  -fill white \
  -gravity SouthEast \
  -annotate +40+40 "$(hostname)" \
  ~/.local/share/wallpaper.png
```

Adjust as needed:

- `-gravity` — position: `SouthEast`, `SouthWest`, `NorthEast`, etc.
- `-pointsize` — font size
- `-fill` — text color; use `rgba(0,0,0,0.6)` style values for transparency
- `-font` — run `convert -list font` to see available fonts

To add a subtle dark background behind the text for legibility:

```bash
convert ~/Downloads/base.png \
  -font DejaVu-Sans-Bold \
  -pointsize 48 \
  -fill black \
  -annotate +42+42 "$(hostname)" \
  -fill white \
  -annotate +40+40 "$(hostname)" \
  -gravity SouthEast \
  ~/.local/share/wallpaper.png
```

(The black annotation slightly offset creates a drop shadow.)

## 3. Set as desktop wallpaper (swaybg)

In `~/.config/sway/config`:

```
output * bg ~/.local/share/wallpaper.png fill
```

Reload sway (`$mod+Shift+c`) to apply.

## 4. Set as lock screen image (swaylock)

In your lock keybind or swayidle config, pass `-i`:

```
bindsym $mod+l exec swaylock -i ~/.local/share/wallpaper.png
```

Or in your swayidle config:

```
exec swayidle -w \
  timeout 300 'swaylock -i ~/.local/share/wallpaper.png' \
  timeout 600 'swaymsg "output * dpms off"' \
  resume 'swaymsg "output * dpms on"'
```

## 5. Automate per machine

Wrap steps 1–2 in a script, e.g. `~/bin/gen-wallpaper`:

```bash
#!/bin/sh
# Usage: gen-wallpaper /path/to/base-image.png
set -e
BASE="${1:?usage: gen-wallpaper <base-image>}"
OUT="$HOME/.local/share/wallpaper.png"
convert "$BASE" \
  -font DejaVu-Sans-Bold \
  -pointsize 48 \
  -fill white \
  -gravity SouthEast \
  -annotate +40+40 "$(hostname)" \
  "$OUT"
echo "Wallpaper written to $OUT"
echo "Reload sway to apply desktop wallpaper."
```

Run once after provisioning a new machine with your downloaded base image.
