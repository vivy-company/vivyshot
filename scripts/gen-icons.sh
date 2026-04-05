#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_IMAGE="$ROOT_DIR/docs/branding/logo.png"
WEB_LOGO="$ROOT_DIR/web/public/logo.png"
APPICON_DIR="$ROOT_DIR/macos/Resources/Assets.xcassets/AppIcon.appiconset"
ICNS_PATH="$ROOT_DIR/macos/Resources/AppIcon.icns"

if [[ ! -f "$SOURCE_IMAGE" ]]; then
  echo "missing source image: $SOURCE_IMAGE" >&2
  exit 1
fi

for tool in sips iconutil; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "required tool not found: $tool" >&2
    exit 1
  fi
done

tmpdir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

normalized_png="$tmpdir/logo-1024.png"
sips -s format png "$SOURCE_IMAGE" --out "$normalized_png" >/dev/null

cp "$normalized_png" "$WEB_LOGO"

declare -a icon_specs=(
  "16:icon_16x16.png"
  "32:icon_16x16@2x.png"
  "32:icon_32x32.png"
  "64:icon_32x32@2x.png"
  "128:icon_128x128.png"
  "256:icon_128x128@2x.png"
  "256:icon_256x256.png"
  "512:icon_256x256@2x.png"
  "512:icon_512x512.png"
  "1024:icon_512x512@2x.png"
)

for spec in "${icon_specs[@]}"; do
  size="${spec%%:*}"
  name="${spec#*:}"
  sips -z "$size" "$size" "$normalized_png" --out "$APPICON_DIR/$name" >/dev/null
done

iconset_dir="$tmpdir/AppIcon.iconset"
mkdir -p "$iconset_dir"
cp "$APPICON_DIR"/icon_16x16.png "$iconset_dir/icon_16x16.png"
cp "$APPICON_DIR"/icon_16x16@2x.png "$iconset_dir/icon_16x16@2x.png"
cp "$APPICON_DIR"/icon_32x32.png "$iconset_dir/icon_32x32.png"
cp "$APPICON_DIR"/icon_32x32@2x.png "$iconset_dir/icon_32x32@2x.png"
cp "$APPICON_DIR"/icon_128x128.png "$iconset_dir/icon_128x128.png"
cp "$APPICON_DIR"/icon_128x128@2x.png "$iconset_dir/icon_128x128@2x.png"
cp "$APPICON_DIR"/icon_256x256.png "$iconset_dir/icon_256x256.png"
cp "$APPICON_DIR"/icon_256x256@2x.png "$iconset_dir/icon_256x256@2x.png"
cp "$APPICON_DIR"/icon_512x512.png "$iconset_dir/icon_512x512.png"
cp "$APPICON_DIR"/icon_512x512@2x.png "$iconset_dir/icon_512x512@2x.png"

iconutil -c icns "$iconset_dir" -o "$ICNS_PATH"

echo "regenerated web logo, macOS app icon set, and icns from $SOURCE_IMAGE"
