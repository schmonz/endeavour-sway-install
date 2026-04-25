#!/bin/bash

notes="${HOME}/.config/endeavour-post-phase3.txt"
sway_autostart="${HOME}/.config/sway/config.d/autostart_applications"

case "${1:-}" in
  --show-notes)
    # Runs in first Sway session after the reboot that follows Phase 3.
    [[ -f "${notes}" ]] || exit 0
    xdg-open 'https://chromewebstore.google.com/detail/1password-%E2%80%93-password-mana/aeblfdkhhhdcdjpifhhbdiojplfjncoa' &
    foot -e sh -c "cat '${notes}'; echo; read -r -p 'Press Enter to dismiss.' _"
    rm -f "${notes}"
    sed -i "\|exec $0 --show-notes|d" "${sway_autostart}" 2>/dev/null || true
    ;;
  *)
    # Runs in TTY login shell (bash --login autologin via greetd).
    log="${HOME}/.config/endeavour-phase3.log"
    warnings="${HOME}/.config/endeavour-warnings"
    if [[ -f "${warnings}" ]]; then
        echo '=== Phase 2 notes ==='
        cat "${warnings}"
        echo
    fi
    endeavour-sway-install "${USER}" --phase 3 2>&1 | tee "${log}"
    rc=${PIPESTATUS[0]}
    echo
    if [[ $rc -eq 0 ]]; then
        rm -f "${warnings}"
        printf 'Manual steps remaining:\n\n  tailscale up\n  tailscale set --accept-dns=true\n  tailscale set --accept-routes\n  rclone config (optional)\n' > "${notes}"
        grep -qF "$0 --show-notes" "${sway_autostart}" 2>/dev/null || \
            printf '\nexec %s --show-notes\n' "$0" >> "${sway_autostart}"
        sed -i "\|$0|d" "${HOME}/.bash_profile" 2>/dev/null || true
        systemctl reboot
    else
        echo "Phase 3 FAILED (exit code $rc). Log: ${log}"
        read -r -p 'Press Enter to dismiss.' _
    fi
    ;;
esac
