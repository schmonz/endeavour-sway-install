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

run() {
    local label="$1"; shift
    local file="$DEST/$label"
    local tmp; tmp=$(mktemp)
    if "$@" > "$tmp" 2>&1; then
        mv "$tmp" "$file"
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
    mkdir -p "$DEST/proc/acpi/button/lid/LID0"
    cp /proc/acpi/button/lid/LID0/state "$DEST/proc/acpi/button/lid/LID0/state"
    echo "  OK  proc/acpi/button/lid/LID0/state"
else
    echo "  --  proc/acpi/button/lid/LID0/state (not present)"
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

# ── sysfs trees ─────────────────────────────────────────────────────────────
copy_sysfs_tree() {
    local src="$1"
    local label="${src#/}"; label="${label//\//-}"   # /sys/class/input → sys-class-input
    local dest="$DEST/$label"
    if [[ -d "$src" ]]; then
        mkdir -p "$dest"
        cp -a "$src/." "$dest/" 2>/dev/null || true
        local count
        count=$(find "$dest" 2>/dev/null | wc -l)
        echo "  OK  $label ($count entries)"
    else
        echo "  --  $label (not present)"
    fi
}

copy_sysfs_tree /sys/class/input
copy_sysfs_tree /sys/class/leds
copy_sysfs_tree /sys/class/hwmon
copy_sysfs_tree /sys/class/drm
copy_sysfs_tree /sys/bus/iio/devices
copy_sysfs_tree /sys/class/chromeos
copy_sysfs_tree /sys/class/video4linux

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
