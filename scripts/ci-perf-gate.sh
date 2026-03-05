#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BENCH_SESSIONS="${1:-20}"
PIPELINE_MEDIAN_MS="${VIVYSHOT_PIPELINE_MEDIAN_MS:-75}"
PIPELINE_P95_MS="${VIVYSHOT_PIPELINE_P95_MS:-110}"
DESTINATION="${VIVYSHOT_XCODE_DESTINATION:-platform=macOS}"

echo "Running Rust benchmark gate..."
"$ROOT_DIR/scripts/ci-bench-gate.sh" "$BENCH_SESSIONS"

echo "Running macOS screenshot pipeline perf/memory gate..."
cd "$ROOT_DIR"
VIVYSHOT_PIPELINE_MEDIAN_MS="$PIPELINE_MEDIAN_MS" \
VIVYSHOT_PIPELINE_P95_MS="$PIPELINE_P95_MS" \
xcodebuild \
  -project macos/vivyshot.xcodeproj \
  -scheme VivyShot \
  -destination "$DESTINATION" \
  -only-testing:VivyShotTests/VivyShotTests/testScreenshotPipelineMemoryMetric \
  -only-testing:VivyShotTests/VivyShotTests/testScreenshotPipelineResidentMemoryBoundedAfterBurst \
  -only-testing:VivyShotTests/VivyShotTests/testScreenshotPipelineLatencyBoundedAfterBurst \
  test

echo "Performance gate passed."
