#!/usr/bin/env zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MACOS_DIR="$ROOT_DIR/macos"
PROJECT_PATH="$MACOS_DIR/VivyShot.xcodeproj"
SCHEME="VivyShot"
DERIVED_DATA_PATH="$ROOT_DIR/.build/DerivedData"
RELEASE_PRODUCTS_DIR="$DERIVED_DATA_PATH/Build/Products/Release"
INSTALL_APP_PATH="/Applications/VivyShot.app"

if [ ! -d "$PROJECT_PATH" ]; then
  echo "Missing Xcode project: $PROJECT_PATH"
  exit 1
fi

echo "==> Building Rust core (universal static library)..."
"$SCRIPT_DIR/build-rust-universal.sh"

echo "==> Building macOS app (Release)..."
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

APP_SOURCE_PATH="$(find "$RELEASE_PRODUCTS_DIR" -maxdepth 1 -type d -name '*.app' | head -n 1)"
if [ -z "${APP_SOURCE_PATH:-}" ] || [ ! -d "$APP_SOURCE_PATH" ]; then
  echo "Release app bundle not found in: $RELEASE_PRODUCTS_DIR"
  exit 1
fi

echo "==> Installing to $INSTALL_APP_PATH..."
pkill -x VivyShot >/dev/null 2>&1 || true
pkill -x VivyShotDev >/dev/null 2>&1 || true

rm -rf "$INSTALL_APP_PATH" 2>/dev/null || true
if ! ditto "$APP_SOURCE_PATH" "$INSTALL_APP_PATH"; then
  echo "Install failed. You may need elevated permissions for /Applications."
  echo "Try: sudo $0"
  exit 1
fi

xattr -dr com.apple.quarantine "$INSTALL_APP_PATH" >/dev/null 2>&1 || true

echo "==> Launching installed app..."
open -na "$INSTALL_APP_PATH"

echo "Done."
echo "Installed: $INSTALL_APP_PATH"
echo "Tip: grant Screen Recording permission to this app once, then keep using this installed Release app."
