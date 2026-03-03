#!/usr/bin/env zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE_DIR="$ROOT_DIR/vivyshot-rs"
FFI_DIR="$WORKSPACE_DIR/crates/vivyshot-ffi"
OUT_HEADER="$ROOT_DIR/ffi/vivyshot_core.h"

if ! command -v cbindgen >/dev/null 2>&1; then
  echo "cbindgen is not installed. Install with: cargo install cbindgen"
  exit 1
fi

cd "$WORKSPACE_DIR"
cbindgen --config "$FFI_DIR/cbindgen.toml" --crate vivyshot-ffi --output "$OUT_HEADER"
echo "Generated header: $OUT_HEADER"
