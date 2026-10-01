#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
export XDG_CONFIG_HOME="$HOME/.config" XDG_STATE_HOME="$HOME/.state" XDG_DATA_HOME="$HOME/.local/share" XDG_RUNTIME_DIR="$TMP/run"
unset XDG_BIN_HOME
mkdir -p "$HOME" "$XDG_RUNTIME_DIR" "$TMP/bin" "$TMP/units"
LOG="$TMP/mock.log"
cat > "$TMP/bin/systemd-run" <<'EOF'
#!/usr/bin/env bash
printf 'systemd-run %s\n' "$*" >> "$MOCK_LOG"
EOF
cat > "$TMP/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >> "$MOCK_LOG"
case "$*" in
  *'is-active'*) exit 1 ;;
  *' show '*) last=${*: -1}; [[ -f "$MOCK_UNITS/$last" ]] && cat "$MOCK_UNITS/$last"; exit 0 ;;
  *) exit 0 ;;
esac
EOF
cat > "$TMP/bin/paplay" <<'MOCKEOF'
#!/usr/bin/env bash
printf 'paplay %s\n' "$*" >> "$MOCK_LOG"
MOCKEOF
cat > "$TMP/bin/omarchy-notification-send" <<'MOCKEOF'
#!/usr/bin/env bash
printf 'omarchy-notification-send %s\n' "$*" >> "$MOCK_LOG"
MOCKEOF
cat > "$TMP/bin/notify-send" <<'EOF'
#!/usr/bin/env bash
printf 'notify-send %s\n' "$*" >> "$MOCK_LOG"
EOF
chmod +x "$TMP/bin"/*
export MOCK_LOG="$LOG" MOCK_UNITS="$TMP/units" PATH="$TMP/bin:$PATH"
CLI="$ROOT/bin/shutdown-timer"
pass=0
ok() { printf 'ok - %s\n' "$1"; pass=$((pass + 1)); }
fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
assert_ok() { "$@" >/dev/null 2>&1 || fail "$1"; }
assert_fail() { if "$@" >/dev/null 2>&1; then fail "$1"; fi; }
assert_ok "$CLI" --dry-run 30m; ok 'programar 30 minutos'
assert_ok "$CLI" --dry-run cancel; ok 'cancelar simulación 30m'
assert_ok "$CLI" --dry-run 45m; ok 'programar 45 minutos'
assert_ok "$CLI" --dry-run cancel; ok 'cancelar simulación 45m'
assert_ok "$CLI" --dry-run 1h; ok 'programar 1 hora'
assert_ok "$CLI" --dry-run cancel; ok 'cancelar simulación 1h'
assert_ok "$CLI" --dry-run 3h; ok 'programar varias horas'
assert_ok "$CLI" --dry-run cancel; ok 'cancelar varias horas'
assert_ok "$CLI" --dry-run 2.5h; ok 'aceptar 2.5h'
assert_fail "$CLI" --dry-run 0h; ok 'rechazar cero'
assert_fail "$CLI" --dry-run -1h; ok 'rechazar negativos'
assert_fail "$CLI" --dry-run texto; ok 'rechazar texto'
assert_fail "$CLI" --dry-run 169h; ok 'rechazar máximo excedido'
$CLI --dry-run cancel >/dev/null
output=$($CLI --dry-run 30m); grep -q 'para:' <<<"$output" || fail 'mostrar hora prevista'; ok 'mostrar hora prevista'
$CLI --dry-run status >/dev/null; ok 'consultar estado'
$CLI --dry-run cancel >/dev/null; ok 'cancelar temporizador'
$CLI --dry-run 1h >/dev/null; $CLI --dry-run --replace 2h >/dev/null; ok 'reemplazar temporizador'
$CLI --dry-run --keep 3h >/dev/null; grep -q 'duration":"2h' "$XDG_STATE_HOME/shutdown-timer/state.json" || fail 'conservar temporizador'; ok 'conservar temporizador'
old=$(date +%s -d '2 hours ago'); sed -i "s/\"target_epoch\":[0-9]*/\"target_epoch\":$old/" "$XDG_STATE_HOME/shutdown-timer/state.json"; $CLI --dry-run status >/dev/null; [[ ! -f "$XDG_STATE_HOME/shutdown-timer/state.json" ]] || fail 'limpiar estado obsoleto'; ok 'recuperarse de estado obsoleto'
$CLI --dry-run 30m >/dev/null & p1=$!; $CLI --dry-run 45m >/dev/null 2>&1 & p2=$!; wait "$p1" || true; wait "$p2" || true; jq empty "$XDG_STATE_HOME/shutdown-timer/state.json"; ok 'concurrencia sin corrupción'
$CLI --dry-run cancel >/dev/null
assert_ok "$ROOT/install.sh"; assert_ok "$ROOT/install.sh"; [[ -x "$HOME/.local/bin/shutdown-timer" ]] || fail 'instalación idempotente'; ok 'instalar dos veces sin duplicar'
assert_ok "$ROOT/uninstall.sh"; assert_ok "$ROOT/uninstall.sh"; ok 'desinstalar dos veces'
$CLI --dry-run 30m >/dev/null; ! grep -q 'systemctl poweroff' "$LOG" || fail 'dry-run no llama poweroff'; ok 'dry-run nunca apaga realmente'
$CLI --dry-run --replace --action reboot 30m >/dev/null; grep -q '"action":"reboot"' "$XDG_STATE_HOME/shutdown-timer/state.json" || fail 'acción reboot'; ok 'programar con --action reboot'
$CLI --dry-run --replace --action lock 30m >/dev/null; grep -q '"action":"lock"' "$XDG_STATE_HOME/shutdown-timer/state.json" || fail 'lock'; ok 'programar con --action lock'
assert_fail "$CLI" --dry-run --action formatear 30m; ok 'rechazar acción inválida'
$CLI --dry-run status | grep -q 'Restante:' || fail 'restante'; ok 'status muestra tiempo restante'
[[ -n $($CLI --dry-run status --short) ]] || fail 'short'; ok 'status --short devuelve cuenta regresiva'
$CLI --dry-run extend 30m >/dev/null; grep -q 'duration":"30m+30m' "$XDG_STATE_HOME/shutdown-timer/state.json" || fail 'extend'; ok 'extender temporizador'
$CLI --dry-run cancel >/dev/null
assert_fail "$CLI" --dry-run extend 30m; ok 'extender sin temporizador falla'
[[ -z $($CLI --dry-run status --short) ]] || fail 'short vacío'; ok 'status --short vacío sin temporizador'
$CLI --dry-run --action lock now | grep -q 'SIMULACIÓN' || fail 'now'; ok 'now en simulación'
assert_fail "$CLI" --dry-run --action formatear now; ok 'now rechaza acción inválida'
out=$($CLI timer 20m apagar la cocina); grep -q 'apagar la cocina' <<<"$out" || fail 'crear timer'; ok 'crear temporizador con mensaje'
$CLI timer 5m >/dev/null; [[ $(jq length "$XDG_STATE_HOME/shutdown-timer/alarms.json") -eq 2 ]] || fail 'dos timers'; ok 'varios temporizadores a la vez'
grep -q 'shutdown-timer-alarm-' "$LOG" || fail 'systemd-run alarm'; ok 'crea unidad systemd por temporizador'
$CLI timers | grep -q 'apagar la cocina' || fail 'listar'; ok 'listar temporizadores'
assert_fail "$CLI" timer texto; ok 'rechazar duración inválida en timer'
assert_fail "$CLI" timer-cancel noexiste; ok 'cancelar id inexistente falla'
id=$(jq -r '.[0].id' "$XDG_STATE_HOME/shutdown-timer/alarms.json")
: > "$LOG"; "$CLI" --internal-alarm "$id"; grep -q 'omarchy-notification-send.*-u critical.*-t 0' "$LOG" || fail 'alerta'; grep -q 'paplay' "$LOG" || fail 'sonido'; ok 'al vencer avisa con notificación crítica y sonido'
[[ $(jq length "$XDG_STATE_HOME/shutdown-timer/alarms.json") -eq 1 ]] || fail 'quitar disparado'; ok 'temporizador disparado se elimina'
: > "$LOG"; "$CLI" --internal-alarm "$id"; ! grep -q omarchy-notification-send "$LOG" || fail 'doble alerta'; ok 'no avisa dos veces'
id2=$(jq -r '.[0].id' "$XDG_STATE_HOME/shutdown-timer/alarms.json"); $CLI timer-cancel "$id2" >/dev/null; [[ $(jq length "$XDG_STATE_HOME/shutdown-timer/alarms.json") -eq 0 ]] || fail 'cancelar'; ok 'cancelar temporizador'
$CLI timer 1h >/dev/null; $CLI timer 2h >/dev/null; $CLI timer-cancel all >/dev/null; [[ $(jq length "$XDG_STATE_HOME/shutdown-timer/alarms.json") -eq 0 ]] || fail 'cancelar todos'; ok 'cancelar todos'
$CLI timers | grep -q 'No hay' || fail 'vacío'; ok 'lista vacía'
# --- unit ownership: never stop a unit this plugin did not create ----------------
unit_file() { # unit load transient fragment description [execstart]
  printf 'LoadState=%s\nTransient=%s\nFragmentPath=%s\nDescription=%s\nExecStart=%s\n' "$2" "$3" "$4" "$5" "${6:-}" > "$MOCK_UNITS/$1"
}
ours_unit() { # unit mode
  local kind=${1##*.} exec_start=''
  [[ $kind == service ]] && exec_start="{ path=/opt/shutdown-timer ; argv[]=/opt/shutdown-timer --internal-$2 ; ignore_errors=no }"
  unit_file "$1" loaded yes "/run/user/1000/systemd/transient/$1" "[systemd-run] /opt/shutdown-timer --internal-$2" "$exec_start"
}
reset_units() { rm -f "$MOCK_UNITS"/*; : > "$LOG"; rm -f "$XDG_STATE_HOME/shutdown-timer/state.json"; }
no_stop() { ! grep -qE 'systemctl .*(stop|reset-failed)' "$LOG"; }

reset_units
unit_file shutdown-timer-warning.timer loaded no /etc/systemd/user/shutdown-timer-warning.timer 'My backup job'
assert_fail "$CLI" --yes --replace 30m; no_stop || fail 'ajena: se paró'; ! grep -q 'systemd-run' "$LOG" || fail 'ajena: se creó encima'; ok 'unidad ajena con el mismo nombre: se conserva y no se programa'

reset_units
unit_file shutdown-timer-poweroff.service loaded no /home/u/.config/systemd/user/shutdown-timer-poweroff.service '[systemd-run] /opt/shutdown-timer --internal-poweroff' '{ path=/bin/true ; argv[]=/bin/true ; }'
assert_fail "$CLI" --yes --replace 30m; no_stop || fail 'falsa: se paró'; ok 'descripción falsificada en una unidad persistente se trata como ajena'

reset_units
unit_file shutdown-timer-warning.service loaded yes /run/user/1000/systemd/transient/shutdown-timer-warning.service '[systemd-run] /bin/true' '{ path=/bin/true ; argv[]=/bin/true ; }'
assert_fail "$CLI" --yes --replace 30m; no_stop || fail 'transitoria ajena: se paró'; ok 'unidad transitoria de otro programa se trata como ajena'

reset_units
unit_file shutdown-timer-warning.timer loaded no /etc/systemd/user/x.timer 'Mine'
"$CLI" reset >/dev/null 2>&1 && fail 'reset con ajena debería avisar'; no_stop || fail 'reset: se paró una ajena'; ok 'reset no toca unidades ajenas'

reset_units
for u in warning poweroff; do ours_unit "shutdown-timer-$u.timer" "$u"; ours_unit "shutdown-timer-$u.service" "$u"; done
"$CLI" --yes --replace 30m >/dev/null || fail 'propias: no se pudo reprogramar'
for u in warning poweroff; do grep -q "systemctl --user stop shutdown-timer-$u.timer" "$LOG" || fail "propias: no se paró $u.timer"; done
grep -q 'systemd-run' "$LOG" || fail 'propias: no se creó'; ok 'unidades propias verificadas se paran y se reprograma'

reset_units
"$CLI" timer 20m x >/dev/null; aid=$(jq -r '.[0].id' "$XDG_STATE_HOME/shutdown-timer/alarms.json"); : > "$LOG"
unit_file "shutdown-timer-alarm-$aid.timer" loaded no /etc/systemd/user/y.timer 'Unrelated'
"$CLI" timer-cancel "$aid" >/dev/null 2>&1; no_stop || fail 'alarma ajena: se paró'
[[ $(jq length "$XDG_STATE_HOME/shutdown-timer/alarms.json") -eq 0 ]] || fail 'alarma ajena: no se quitó el registro'; ok 'cancelar un temporizador no para una unidad ajena homónima'

reset_units
"$CLI" timer 20m x >/dev/null; aid=$(jq -r '.[0].id' "$XDG_STATE_HOME/shutdown-timer/alarms.json"); : > "$LOG"
ours_unit "shutdown-timer-alarm-$aid.timer" "alarm $aid"; ours_unit "shutdown-timer-alarm-$aid.service" "alarm $aid"
"$CLI" timer-cancel "$aid" >/dev/null 2>&1; grep -q "systemctl --user stop shutdown-timer-alarm-$aid.timer" "$LOG" || fail 'alarma propia: no se paró'; ok 'cancelar un temporizador propio sí para su unidad'

reset_units
"$ROOT/install.sh" >/dev/null 2>&1
unit_file shutdown-timer-warning.service loaded no /etc/systemd/user/shutdown-timer-warning.service 'Mine'
unit_file shutdown-timer-poweroff.service loaded no /etc/systemd/user/shutdown-timer-poweroff.service 'Mine'
"$ROOT/uninstall.sh" >/dev/null 2>&1; no_stop || fail 'uninstall paró unidades ajenas'; [[ ! -e "$HOME/.local/bin/shutdown-timer" ]] || fail 'uninstall no retiró la CLI'; ok 'uninstall.sh no para unidades ajenas y retira la CLI'
reset_units
printf '\n%d pruebas superadas\n' "$pass"
