#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DESTINATION="${VIVYSHOT_XCODE_DESTINATION:-platform=macOS}"

echo "Running VivyShot test gate..."
cd "$ROOT_DIR"
xcodebuild \
  -project VivyShot.xcodeproj \
  -scheme VivyShot \
  -destination "$DESTINATION" \
  test

echo "Test gate passed."
