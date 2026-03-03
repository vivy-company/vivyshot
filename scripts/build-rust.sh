#!/usr/bin/env zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CORE_DIR="$ROOT_DIR/vivyshot-rs"

if [ ! -f "$CORE_DIR/Cargo.toml" ]; then
  echo "Missing $CORE_DIR/Cargo.toml"
  exit 1
fi

cd "$CORE_DIR"
cargo build --release
