#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$HOME/.config" XDG_STATE_HOME="$HOME/.state" XDG_RUNTIME_DIR="$TMP/run"
mkdir -p "$HOME" "$XDG_RUNTIME_DIR" "$TMP/bin"
LOG="$TMP/mock.log"
cat > "$TMP/bin/systemd-run" <<'EOF'
#!/usr/bin/env bash
printf 'systemd-run %s\n' "$*" >> "$MOCK_LOG"
EOF
cat > "$TMP/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >> "$MOCK_LOG"
case "$*" in *'is-active'*) exit 1 ;; *) exit 0 ;; esac
EOF
cat > "$TMP/bin/notify-send" <<'EOF'
#!/usr/bin/env bash
printf 'notify-send %s\n' "$*" >> "$MOCK_LOG"
EOF
chmod +x "$TMP/bin"/*
export MOCK_LOG="$LOG" PATH="$TMP/bin:$PATH"
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
printf '\n%d pruebas superadas\n' "$pass"
