#!/usr/bin/env zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE_DIR="$ROOT_DIR/vivyshot-rs"
FFI_PACKAGE="vivyshot-ffi"
SESSIONS="${1:-100}"

if [ ! -f "$WORKSPACE_DIR/Cargo.toml" ]; then
  echo "Missing $WORKSPACE_DIR/Cargo.toml"
  exit 1
fi

echo "Running Rust core memory benchmark with $SESSIONS sessions..."
echo "Command: /usr/bin/time -l cargo run --release -p $FFI_PACKAGE --bin memory_bench -- $SESSIONS"

cd "$WORKSPACE_DIR"
/usr/bin/time -l cargo run --release -p "$FFI_PACKAGE" --bin memory_bench -- "$SESSIONS"
