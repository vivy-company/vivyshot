#!/usr/bin/env zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE_DIR="$ROOT_DIR/vivyshot-rs"
FFI_PACKAGE="vivyshot-ffi"

if [ ! -f "$WORKSPACE_DIR/Cargo.toml" ]; then
  echo "Missing $WORKSPACE_DIR/Cargo.toml"
  exit 1
fi

cd "$WORKSPACE_DIR"
cargo build --release -p "$FFI_PACKAGE"
