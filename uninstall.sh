#!/usr/bin/env bash
set -euo pipefail
CLI="${XDG_BIN_HOME:-$HOME/.local/bin}/shutdown-timer"
# Units are stopped through the CLI, which only touches transient units this plugin
# created; a unit that merely shares one of our names is left alone.
if [[ -x "$CLI" ]]; then
  "$CLI" cancel >/dev/null 2>&1 || true
  "$CLI" timer-cancel all >/dev/null 2>&1 || true
  "$CLI" reset || true
else
  printf 'CLI no encontrada: no se detuvieron unidades de systemd. Los temporizadores activos terminan al cerrar la sesión.\n' >&2
fi
rm -f -- "$CLI" "${XDG_DATA_HOME:-$HOME/.local/share}/shutdown-timer/shutdown-timer"
printf 'CLI retirada; configuración y logs del usuario se conservaron.\n'
printf 'Retira el plugin con: omarchy plugin remove io.github.omargond.shutdown-timer --yes\n'
