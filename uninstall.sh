#!/usr/bin/env bash
set -euo pipefail
CLI="${XDG_BIN_HOME:-$HOME/.local/bin}/shutdown-timer"
if [[ -x "$CLI" ]]; then "$CLI" cancel >/dev/null 2>&1 || true; fi
systemctl --user stop shutdown-timer-warning.service shutdown-timer-poweroff.service >/dev/null 2>&1 || true
rm -f -- "$CLI" "${XDG_DATA_HOME:-$HOME/.local/share}/shutdown-timer/shutdown-timer"
printf 'CLI retirada; configuración y logs del usuario se conservaron.\n'
printf 'Retira el plugin con: omarchy plugin remove io.github.omargond.shutdown-timer --yes\n'
