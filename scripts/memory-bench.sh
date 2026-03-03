#!/usr/bin/env zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CORE_DIR="$ROOT_DIR/vivyshot-rs"
SESSIONS="${1:-100}"

if [ ! -f "$CORE_DIR/Cargo.toml" ]; then
  echo "Missing $CORE_DIR/Cargo.toml"
  exit 1
fi

echo "Running Rust core memory benchmark with $SESSIONS sessions..."
echo "Command: /usr/bin/time -l cargo run --release --bin memory_bench -- $SESSIONS"

cd "$CORE_DIR"
/usr/bin/time -l cargo run --release --bin memory_bench -- "$SESSIONS"
