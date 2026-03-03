#!/usr/bin/env zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CORE_DIR="$ROOT_DIR/vivyshot-rs"
OUT_DIR="$CORE_DIR/target/universal-apple-darwin/release"

if [ ! -f "$CORE_DIR/Cargo.toml" ]; then
  echo "Missing $CORE_DIR/Cargo.toml"
  exit 1
fi

cd "$CORE_DIR"

cargo build --release --target aarch64-apple-darwin
cargo build --release --target x86_64-apple-darwin

mkdir -p "$OUT_DIR"
lipo -create \
  "$CORE_DIR/target/aarch64-apple-darwin/release/libvivyshot_core.a" \
  "$CORE_DIR/target/x86_64-apple-darwin/release/libvivyshot_core.a" \
  -output "$OUT_DIR/libvivyshot_core.a"

echo "Built universal static library at: $OUT_DIR/libvivyshot_core.a"
