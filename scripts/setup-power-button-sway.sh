#!/usr/bin/env bash
# setup-power-button-sway.sh
# Configures the ACPI power button to trigger Sway's power menu
# instead of being grabbed exclusively by systemd-logind.
#
# Must be run as root, outside of a Sway session.

set -euo pipefail

die()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo "==> $*"; }

# Global state set by find_acpi_power_button_input_device()
EVENT_DEV=""
EVENT_NODE=""
ID_PATH=""

# Global state set by find_sway_user_and_config()
SWAY_USER=""
SWAY_CONFIG=""

bail_if_running_inside_sway() {
    [[ -z "${SWAYSOCK:-}" ]] \
        || die "Running inside a Sway session. Log out to a plain text VT (Ctrl-Alt-F2), log in there, and run this script again."
}

bail_if_not_root() {
    [[ "$EUID" -eq 0 ]] \
        || die "Run as root (sudo $0)."
}

find_acpi_power_button_input_device() {
    info "Searching for ACPI power button input device..."

    local input_dir name phys
    local power_button_input=""

    for input_dir in /sys/class/input/input*/; do
        name=$(cat "${input_dir}name" 2>/dev/null || true)
        if [[ "$name" == "Power Button" ]]; then
            phys=$(cat "${input_dir}phys" 2>/dev/null || true)
            # Prefer the ACPI virtual one (LNXPWRBN), not the motherboard one
            if [[ "$phys" == *LNXPWRBN* ]]; then
                power_button_input="$input_dir"
                break
            fi
        fi
    done

    [[ -n "$power_button_input" ]] \
        || die "Could not find a Power Button input device with phys matching LNXPWRBN. Check 'cat /proc/bus/input/devices'."

    local evdir
    for evdir in "${power_button_input}"event*/; do
        EVENT_NODE=$(basename "$evdir")
        break
    done

    [[ -n "$EVENT_NODE" ]] \
        || die "Found power button input dir ${power_button_input} but no event node inside it."

    EVENT_DEV="/dev/input/${EVENT_NODE}"
    [[ -c "$EVENT_DEV" ]] \
        || die "${EVENT_DEV} is not a character device."

    info "Found power button at ${EVENT_DEV}."
}

get_udev_id_path_for_power_button() {
    info "Querying udev for ID_PATH..."

    ID_PATH=$(udevadm info "$EVENT_DEV" | awk -F= '/^E: ID_PATH=/{print $2}')

    [[ -n "$ID_PATH" ]] \
        || die "udevadm info reported no ID_PATH for ${EVENT_DEV}. Cannot write a safe udev rule."

    info "ID_PATH=${ID_PATH}"
}

confirm_logind_is_grabbing_power_button() {
    info "Checking whether systemd-logind is watching this device..."

    local logind_watching
    logind_watching=$(journalctl -b --no-pager -q -u systemd-logind 2>/dev/null \
        | grep -i "Watching system buttons" \
        | grep -F "$EVENT_NODE" || true)

    if [[ -z "$logind_watching" ]]; then
        # Softer check: see if power-switch tag is present
        local current_tags
        current_tags=$(udevadm info "$EVENT_DEV" | grep -E "CURRENT_TAGS|^E: TAGS" || true)
        if echo "$current_tags" | grep -q "power-switch"; then
            info "logind journal entry not found, but device has power-switch tag. Proceeding."
        else
            die "logind does not appear to be watching ${EVENT_DEV} and device lacks power-switch tag. Is this the right device? Check 'udevadm info ${EVENT_DEV}'."
        fi
    else
        info "Confirmed: logind is watching ${EVENT_DEV}."
    fi
}

configure_logind_to_ignore_power_key() {
    local logind_conf_dir="/etc/systemd/logind.conf.d"
    local logind_conf="${logind_conf_dir}/power-button-sway.conf"

    info "Writing ${logind_conf}..."
    mkdir -p "$logind_conf_dir"

    [[ -f "$logind_conf" ]] && info "${logind_conf} already exists, overwriting."

    cat > "$logind_conf" <<EOF
# Created by setup-power-button-sway.sh
# Prevents logind from acting on the power button so Sway can handle it.
[Login]
HandlePowerKey=ignore
EOF
}

create_udev_rule_to_release_power_button_from_logind() {
    local udev_rule="/etc/udev/rules.d/99-power-button-sway.rules"

    info "Writing ${udev_rule}..."

    cat > "$udev_rule" <<EOF
# Created by setup-power-button-sway.sh
# Strips the power-switch tag so logind does not grab the device exclusively.
# This allows libinput to hand XF86PowerOff events to Sway normally.
SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_PATH}=="${ID_PATH}", \\
    TAG-="power-switch", TAG+="seat", TAG+="uaccess"
EOF
}

reload_udev_and_verify_power_switch_tag_is_gone() {
    info "Reloading udev rules..."
    udevadm control --reload-rules
    udevadm trigger --action=add "$EVENT_DEV"

    info "Verifying power-switch tag is gone..."
    sleep 1

    if udevadm info "$EVENT_DEV" | grep -E "^E: CURRENT_TAGS=" | grep -q "power-switch"; then
        die "power-switch tag is still present after udev reload. Something is overriding the rule. Check 'udevadm test \$(udevadm info -q path ${EVENT_DEV})'."
    fi

    info "power-switch tag removed successfully."
}

find_sway_user_and_config() {
    info "Looking for Sway config to update..."

    SWAY_USER="${SUDO_USER:-}"
    [[ -n "$SWAY_USER" ]] \
        || die "Cannot determine the target Sway user. Run via sudo rather than as root directly."

    local sway_user_home
    sway_user_home=$(getent passwd "$SWAY_USER" | cut -d: -f6)
    [[ -d "$sway_user_home" ]] \
        || die "Home directory ${sway_user_home} for ${SWAY_USER} does not exist."

    # Search all config files under the sway config directory for $powermenu.
    # Prefer the file that defines it; fall back to top-level config only if
    # $powermenu is nowhere to be found.
    local sway_conf_dir="${sway_user_home}/.config/sway"
    [[ -d "$sway_conf_dir" ]] \
        || sway_conf_dir="${sway_user_home}/.sway"
    [[ -d "$sway_conf_dir" ]] \
        || die "Could not find a Sway config directory for user ${SWAY_USER}."

    local powermenu_file
    powermenu_file=$(grep -rlE '^\s*set\s+\$powermenu\b' "$sway_conf_dir" 2>/dev/null | head -1 || true)

    if [[ -n "$powermenu_file" ]]; then
        SWAY_CONFIG="$powermenu_file"
        info "Found \$powermenu definition in ${SWAY_CONFIG}."
    else
        # No $powermenu anywhere; fall back to top-level config if it exists
        local fallback="${sway_conf_dir}/config"
        [[ -f "$fallback" ]] \
            || die "Could not find \$powermenu in any Sway config file and ${fallback} does not exist. Add 'bindsym XF86PowerOff exec \$powermenu' manually."
        SWAY_CONFIG="$fallback"
        info "No \$powermenu definition found; will append generic binding to ${SWAY_CONFIG}."
    fi
}

add_xf86poweroff_binding_to_sway_config() {
    # Check all sway config files for an existing XF86PowerOff binding, not just SWAY_CONFIG
    local sway_conf_dir
    sway_conf_dir=$(dirname "$SWAY_CONFIG")
    # Walk up one level if we're in config.d
    [[ "$(basename "$sway_conf_dir")" == "config.d" ]] && sway_conf_dir=$(dirname "$sway_conf_dir")

    if grep -rlE '^\s*bindsym\s+XF86PowerOff\b' "$sway_conf_dir" 2>/dev/null | grep -q .; then
        info "XF86PowerOff binding already present somewhere under ${sway_conf_dir}. Not modifying."
        return
    fi

    local binding_line
    if grep -qE '^\s*set\s+\$powermenu\b' "$SWAY_CONFIG"; then
        binding_line=$'\n# Power button \xe2\x86\x92 power menu (added by setup-power-button-sway.sh)\nbindsym XF86PowerOff exec $powermenu'
    else
        info "No \$powermenu variable found. Appending a generic binding; edit the command to suit."
        binding_line=$'\n# Power button (added by setup-power-button-sway.sh)\n# Replace the exec command with your actual power menu invocation.\nbindsym XF86PowerOff exec $powermenu'
    fi

    echo "$binding_line" >> "$SWAY_CONFIG"
    chown "${SWAY_USER}:" "$SWAY_CONFIG"
    info "Appended XF86PowerOff binding to ${SWAY_CONFIG}."
}

print_next_steps() {
    cat <<EOF

All done. Next steps:
  1. Log back into your Sway session.
  2. Press the power button (a brief tap should suffice).
  3. If it still does nothing, reload Sway config first: swaymsg reload

If the power button still doesn't work after logging back in, run:
  udevadm info ${EVENT_DEV} | grep -E 'TAGS|CURRENT_TAGS'
and confirm power-switch is absent.
EOF
}

main() {
    bail_if_running_inside_sway
    bail_if_not_root
    find_acpi_power_button_input_device
    get_udev_id_path_for_power_button
    confirm_logind_is_grabbing_power_button
    configure_logind_to_ignore_power_key
    create_udev_rule_to_release_power_button_from_logind
    reload_udev_and_verify_power_switch_tag_is_gone
    find_sway_user_and_config
    add_xf86poweroff_binding_to_sway_config
    print_next_steps
}

main "$@"
exit $?
