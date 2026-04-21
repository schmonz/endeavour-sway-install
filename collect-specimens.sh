#!/usr/bin/env bash
# Run on a live machine to capture probe inputs into specimens/<machine-slug>/.
set -euo pipefail

usage() {
    echo "Usage: $0 <machine-slug>"
    echo "  e.g.: $0 thinkpad-x270"
    exit 1
}

[[ $# -eq 1 ]] || usage
SLUG="$1"
DEST="$(dirname "$0")/specimens/$SLUG"

mkdir -p "$DEST"

# Write stdin to $DEST/$1 only if non-empty; preserve existing file otherwise.
save_if_nonempty() {
    local label="$1"
    local tmp; tmp=$(mktemp)
    cat > "$tmp"
    if [[ -s "$tmp" ]]; then
        cp "$tmp" "$DEST/$label" && rm -f "$tmp"
        echo "  OK  $label"
    else
        rm -f "$tmp"
        echo "  --  $label (not present)"
    fi
}

# Run command; write output to $DEST/$1 on success, preserve existing on failure.
run() {
    local label="$1"; shift
    local tmp; tmp=$(mktemp)
    if "$@" > "$tmp" 2>&1; then
        cp "$tmp" "$DEST/$label" && rm -f "$tmp"
        echo "  OK  $label"
    else
        rm -f "$tmp"
        echo "  --  $label (exit $?, existing file preserved)"
    fi
}

echo "Collecting specimens for: $SLUG"
echo "Destination: $DEST"
echo

# ── dmidecode strings ────────────────────────────────────────────────────────
run dmidecode-bios-version.txt        sudo dmidecode -s bios-version
run dmidecode-system-manufacturer.txt sudo dmidecode -s system-manufacturer
run dmidecode-system-product-name.txt sudo dmidecode -s system-product-name
run dmidecode-system-version.txt      sudo dmidecode -s system-version

# ── lspci ────────────────────────────────────────────────────────────────────
run lspci-n.txt  lspci -n

# ── /proc ────────────────────────────────────────────────────────────────────
run proc-meminfo.txt  cat /proc/meminfo

if [[ -f /proc/acpi/button/lid/LID0/state ]]; then
    cp /proc/acpi/button/lid/LID0/state "$DEST/proc-acpi-button-lid-LID0-state"
    echo "  OK  proc-acpi-button-lid-LID0-state"
else
    echo "  --  proc-acpi-button-lid-LID0-state (not present)"
fi

# ── udevadm power buttons ─────────────────────────────────────────────────────
{
    found=false
    while IFS= read -r uevent; do
        dev="${uevent%/uevent}"
        if grep -q "LNXPWRBN" "$uevent" 2>/dev/null; then
            found=true
            udevadm info --query=all --path="$dev"
            echo "---"
        fi
    done < <(find /sys/devices -name uevent 2>/dev/null)
    $found || echo "(no LNXPWRBN devices found)"
} > "$DEST/udevadm-power-buttons.txt"
echo "  OK  udevadm-power-buttons.txt"

# ── sysfs ─────────────────────────────────────────────────────────────────────
# input device names: "inputN<TAB>name" per line (for probe_acpi_lid_poll,
# probe_sway_power_key)
{
    for f in /sys/class/input/input*/name; do
        [[ -f "$f" ]] || continue
        printf '%s\t%s\n' "$(basename "$(dirname "$f")")" "$(cat "$f")"
    done
} | save_if_nonempty sys-class-input-names.txt

# LED names: one per line (for probe_kbd_backlight)
ls /sys/class/leds/ 2>/dev/null | save_if_nonempty sys-class-leds.txt

# hwmon names: "hwmonN<TAB>name" per line (for probe_needs_mbpfan)
{
    for f in /sys/class/hwmon/hwmon*/name; do
        [[ -f "$f" ]] || continue
        printf '%s\t%s\n' "$(basename "$(dirname "$f")")" "$(cat "$f")"
    done
} | save_if_nonempty sys-class-hwmon-names.txt

# DRM entries: one per line (for probe_phantom_lvds2)
ls /sys/class/drm/ 2>/dev/null | save_if_nonempty sys-class-drm.txt

# IIO illuminance paths: present = ALS exists (for probe_ambient_light_sensor)
find /sys/bus/iio/devices -name 'in_illuminance*' 2>/dev/null \
    | save_if_nonempty sys-bus-iio-illuminance.txt

# Chromeos entries: one per line (for probe_chromebook)
ls /sys/class/chromeos/ 2>/dev/null | save_if_nonempty sys-class-chromeos.txt

# V4L device names: one per line (for probe_has_webcam)
ls /sys/class/video4linux/ 2>/dev/null | save_if_nonempty sys-class-video4linux.txt

# ── device nodes ─────────────────────────────────────────────────────────────
run dev-lirc.txt    bash -c 'ls /dev/lirc* 2>&1 || true'
run dev-video.txt   bash -c 'ls /dev/video* 2>&1 || true'
run dev-cros_ec.txt bash -c 'ls /dev/cros_ec 2>&1 || true'

# ── summary ──────────────────────────────────────────────────────────────────
echo
echo "Done. Sanity check:"
echo "  BIOS:         $(cat "$DEST/dmidecode-bios-version.txt" 2>/dev/null || echo '?')"
echo "  Manufacturer: $(cat "$DEST/dmidecode-system-manufacturer.txt" 2>/dev/null || echo '?')"
echo "  Product:      $(cat "$DEST/dmidecode-system-product-name.txt" 2>/dev/null || echo '?')"
echo "  MemTotal:     $(grep MemTotal "$DEST/proc-meminfo.txt" 2>/dev/null || echo '?')"
echo "  lspci IDs:    $(wc -l < "$DEST/lspci-n.txt" 2>/dev/null || echo '?') lines"
echo "  lirc:         $(cat "$DEST/dev-lirc.txt")"
echo "  video:        $(cat "$DEST/dev-video.txt")"
echo "  cros_ec:      $(cat "$DEST/dev-cros_ec.txt")"
