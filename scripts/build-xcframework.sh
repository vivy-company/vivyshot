#!/usr/bin/env zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE_DIR="$ROOT_DIR/vivyshot-rs"
FFI_PACKAGE="vivyshot-ffi"
FFI_HEADER_DIR="$ROOT_DIR/ffi"
XCFRAMEWORK_OUTPUT="$ROOT_DIR/VivyShotKit.xcframework"

if [ ! -f "$WORKSPACE_DIR/Cargo.toml" ]; then
  echo "Missing $WORKSPACE_DIR/Cargo.toml"
  exit 1
fi

cd "$WORKSPACE_DIR"

echo "Building Rust static library for aarch64-apple-darwin..."
cargo build --release --target aarch64-apple-darwin -p "$FFI_PACKAGE"

echo "Building Rust static library for x86_64-apple-darwin..."
cargo build --release --target x86_64-apple-darwin -p "$FFI_PACKAGE"

UNIVERSAL_DIR="$WORKSPACE_DIR/target/universal-apple-darwin/release"
mkdir -p "$UNIVERSAL_DIR"
lipo -create \
  "$WORKSPACE_DIR/target/aarch64-apple-darwin/release/libvivyshot_core.a" \
  "$WORKSPACE_DIR/target/x86_64-apple-darwin/release/libvivyshot_core.a" \
  -output "$UNIVERSAL_DIR/libvivyshot_core.a"

HEADERS_STAGING="$WORKSPACE_DIR/target/xcframework-headers"
rm -rf "$HEADERS_STAGING"
mkdir -p "$HEADERS_STAGING"
cp "$FFI_HEADER_DIR/vivyshot_core.h" "$HEADERS_STAGING/"
cat > "$HEADERS_STAGING/module.modulemap" <<'MODULEMAP'
module VivyShotKit {
    header "vivyshot_core.h"
    export *
}
MODULEMAP

rm -rf "$XCFRAMEWORK_OUTPUT"
xcodebuild -create-xcframework \
  -library "$UNIVERSAL_DIR/libvivyshot_core.a" \
  -headers "$HEADERS_STAGING" \
  -output "$XCFRAMEWORK_OUTPUT"

echo "Built $XCFRAMEWORK_OUTPUT"
