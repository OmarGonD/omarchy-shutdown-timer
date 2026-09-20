#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
BIN_HOME=${XDG_BIN_HOME:-$HOME/.local/bin}
DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
TARGET="$DATA_HOME/shutdown-timer/shutdown-timer"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/shutdown-timer"
mkdir -p "$DATA_HOME/shutdown-timer" "$BIN_HOME" "$CONFIG_DIR"
install -m 0755 "$ROOT/bin/shutdown-timer" "$TARGET"
ln -sfn "$TARGET" "$BIN_HOME/shutdown-timer"
if [[ ! -f "$CONFIG_DIR/config.ini" ]]; then install -m 0644 "$ROOT/config/config.ini" "$CONFIG_DIR/config.ini"; fi
printf 'CLI instalada en %s\n' "$BIN_HOME/shutdown-timer"
printf 'La activación oficial del plugin es: omarchy plugin enable io.github.omargond.shutdown-timer\n'
