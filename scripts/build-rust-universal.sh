#!/usr/bin/env zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE_DIR="$ROOT_DIR/vivyshot-rs"
FFI_PACKAGE="vivyshot-ffi"
OUT_DIR="$WORKSPACE_DIR/target/universal-apple-darwin/release"

if [ ! -f "$WORKSPACE_DIR/Cargo.toml" ]; then
  echo "Missing $WORKSPACE_DIR/Cargo.toml"
  exit 1
fi

cd "$WORKSPACE_DIR"

cargo build --release --target aarch64-apple-darwin -p "$FFI_PACKAGE"
cargo build --release --target x86_64-apple-darwin -p "$FFI_PACKAGE"

mkdir -p "$OUT_DIR"
lipo -create \
  "$WORKSPACE_DIR/target/aarch64-apple-darwin/release/libvivyshot_core.a" \
  "$WORKSPACE_DIR/target/x86_64-apple-darwin/release/libvivyshot_core.a" \
  -output "$OUT_DIR/libvivyshot_core.a"

echo "Built universal static library at: $OUT_DIR/libvivyshot_core.a"
