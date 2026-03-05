#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE_DIR="$ROOT_DIR/vivyshot-rs"
SESSIONS="${1:-20}"
DOC_MAX_AVG_MS="${VIVYSHOT_DOC_BENCH_MAX_AVG_MS:-180}"
DOC_MAX_P95_MS="${VIVYSHOT_DOC_BENCH_MAX_P95_MS:-280}"
DOC_MAX_BASELINE_RSS_MB="${VIVYSHOT_DOC_BENCH_MAX_BASELINE_RSS_MB:-100}"
DOC_MAX_PEAK_RSS_MB="${VIVYSHOT_DOC_BENCH_MAX_PEAK_RSS_MB:-200}"
SHOT_MAX_AVG_MS="${VIVYSHOT_SHOT_BENCH_MAX_AVG_MS:-100}"
SHOT_MAX_P95_MS="${VIVYSHOT_SHOT_BENCH_MAX_P95_MS:-140}"
SHOT_MAX_BASELINE_RSS_MB="${VIVYSHOT_SHOT_BENCH_MAX_BASELINE_RSS_MB:-100}"
SHOT_MAX_PEAK_RSS_MB="${VIVYSHOT_SHOT_BENCH_MAX_PEAK_RSS_MB:-200}"

if [ ! -f "$WORKSPACE_DIR/Cargo.toml" ]; then
  echo "Missing workspace Cargo.toml at $WORKSPACE_DIR"
  exit 1
fi

extract_metric() {
  local output="$1"
  local key="$2"
  printf "%s\n" "$output" | awk -F= -v k="$key" '$1 == k { print $2 }' | tail -n 1
}

require_positive_metric() {
  local label="$1"
  local value="$2"
  if ! awk -v v="$value" 'BEGIN { exit !(v + 0 > 0) }'; then
    echo "Invalid $label: $value"
    exit 1
  fi
}

require_metric_at_most() {
  local label="$1"
  local value="$2"
  local max="$3"
  if ! awk -v v="$value" -v max="$max" 'BEGIN { exit !(v <= max) }'; then
    echo "Benchmark gate failed: $label=$value exceeds $max"
    exit 1
  fi
}

echo "Running document benchmark gate with sessions=$SESSIONS"
DOC_OUTPUT="$(cd "$WORKSPACE_DIR" && cargo run --release -p vivyshot-ffi --bin memory_bench -- "$SESSIONS")"
echo "$DOC_OUTPUT"

DOC_AVG_MS="$(extract_metric "$DOC_OUTPUT" "avg_ms_per_session")"
DOC_P95_MS="$(extract_metric "$DOC_OUTPUT" "p95_ms_per_session")"
DOC_BASELINE_RSS_MB="$(extract_metric "$DOC_OUTPUT" "baseline_rss_mb")"
DOC_PEAK_RSS_MB="$(extract_metric "$DOC_OUTPUT" "peak_rss_mb")"
DOC_CHECKSUM="$(extract_metric "$DOC_OUTPUT" "checksum")"

if [ -z "$DOC_AVG_MS" ] || [ -z "$DOC_P95_MS" ] || [ -z "$DOC_BASELINE_RSS_MB" ] || [ -z "$DOC_PEAK_RSS_MB" ] || [ -z "$DOC_CHECKSUM" ]; then
  echo "Document benchmark output missing required metrics"
  exit 1
fi

require_positive_metric "doc avg_ms_per_session" "$DOC_AVG_MS"
require_positive_metric "doc p95_ms_per_session" "$DOC_P95_MS"
require_positive_metric "doc baseline_rss_mb" "$DOC_BASELINE_RSS_MB"
require_positive_metric "doc peak_rss_mb" "$DOC_PEAK_RSS_MB"
require_positive_metric "doc checksum" "$DOC_CHECKSUM"

require_metric_at_most "doc avg_ms_per_session" "$DOC_AVG_MS" "$DOC_MAX_AVG_MS"
require_metric_at_most "doc p95_ms_per_session" "$DOC_P95_MS" "$DOC_MAX_P95_MS"
require_metric_at_most "doc baseline_rss_mb" "$DOC_BASELINE_RSS_MB" "$DOC_MAX_BASELINE_RSS_MB"
require_metric_at_most "doc peak_rss_mb" "$DOC_PEAK_RSS_MB" "$DOC_MAX_PEAK_RSS_MB"

echo "Running screenshot benchmark gate with sessions=$SESSIONS"
SHOT_OUTPUT="$(cd "$WORKSPACE_DIR" && cargo run --release -p vivyshot-ffi --bin screenshot_bench -- "$SESSIONS")"
echo "$SHOT_OUTPUT"

SHOT_AVG_MS="$(extract_metric "$SHOT_OUTPUT" "avg_ms_per_session")"
SHOT_P95_MS="$(extract_metric "$SHOT_OUTPUT" "p95_ms_per_session")"
SHOT_BASELINE_RSS_MB="$(extract_metric "$SHOT_OUTPUT" "baseline_rss_mb")"
SHOT_PEAK_RSS_MB="$(extract_metric "$SHOT_OUTPUT" "peak_rss_mb")"
SHOT_CHECKSUM="$(extract_metric "$SHOT_OUTPUT" "checksum")"

if [ -z "$SHOT_AVG_MS" ] || [ -z "$SHOT_P95_MS" ] || [ -z "$SHOT_BASELINE_RSS_MB" ] || [ -z "$SHOT_PEAK_RSS_MB" ] || [ -z "$SHOT_CHECKSUM" ]; then
  echo "Screenshot benchmark output missing required metrics"
  exit 1
fi

require_positive_metric "shot avg_ms_per_session" "$SHOT_AVG_MS"
require_positive_metric "shot p95_ms_per_session" "$SHOT_P95_MS"
require_positive_metric "shot baseline_rss_mb" "$SHOT_BASELINE_RSS_MB"
require_positive_metric "shot peak_rss_mb" "$SHOT_PEAK_RSS_MB"
require_positive_metric "shot checksum" "$SHOT_CHECKSUM"

require_metric_at_most "shot avg_ms_per_session" "$SHOT_AVG_MS" "$SHOT_MAX_AVG_MS"
require_metric_at_most "shot p95_ms_per_session" "$SHOT_P95_MS" "$SHOT_MAX_P95_MS"
require_metric_at_most "shot baseline_rss_mb" "$SHOT_BASELINE_RSS_MB" "$SHOT_MAX_BASELINE_RSS_MB"
require_metric_at_most "shot peak_rss_mb" "$SHOT_PEAK_RSS_MB" "$SHOT_MAX_PEAK_RSS_MB"

echo "Benchmark gate passed."
