#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE_DIR="$ROOT_DIR/vivyshot-rs"
SESSIONS="${1:-20}"
MAX_AVG_MS="${VIVYSHOT_BENCH_MAX_AVG_MS:-180}"
MAX_P95_MS="${VIVYSHOT_BENCH_MAX_P95_MS:-280}"
MAX_BASELINE_RSS_MB="${VIVYSHOT_BENCH_MAX_BASELINE_RSS_MB:-100}"
MAX_PEAK_RSS_MB="${VIVYSHOT_BENCH_MAX_PEAK_RSS_MB:-200}"

if [ ! -f "$WORKSPACE_DIR/Cargo.toml" ]; then
  echo "Missing workspace Cargo.toml at $WORKSPACE_DIR"
  exit 1
fi

echo "Running benchmark gate with sessions=$SESSIONS max_avg_ms=$MAX_AVG_MS max_p95_ms=$MAX_P95_MS"

OUTPUT="$(cd "$WORKSPACE_DIR" && cargo run --release -p vivyshot-ffi --bin memory_bench -- "$SESSIONS")"
echo "$OUTPUT"

AVG_MS="$(printf "%s\n" "$OUTPUT" | awk -F= '/^avg_ms_per_session=/{print $2}' | tail -n 1)"
P95_MS="$(printf "%s\n" "$OUTPUT" | awk -F= '/^p95_ms_per_session=/{print $2}' | tail -n 1)"
BASELINE_RSS_MB="$(printf "%s\n" "$OUTPUT" | awk -F= '/^baseline_rss_mb=/{print $2}' | tail -n 1)"
PEAK_RSS_MB="$(printf "%s\n" "$OUTPUT" | awk -F= '/^peak_rss_mb=/{print $2}' | tail -n 1)"
CHECKSUM="$(printf "%s\n" "$OUTPUT" | awk -F= '/^checksum=/{print $2}' | tail -n 1)"

if [ -z "$AVG_MS" ] || [ -z "$P95_MS" ] || [ -z "$BASELINE_RSS_MB" ] || [ -z "$PEAK_RSS_MB" ] || [ -z "$CHECKSUM" ]; then
  echo "Benchmark output missing required metrics (avg/p95/baseline_rss_mb/peak_rss_mb/checksum)"
  exit 1
fi

if ! awk -v v="$AVG_MS" 'BEGIN { exit !(v + 0 > 0) }'; then
  echo "Invalid avg_ms_per_session: $AVG_MS"
  exit 1
fi

if ! awk -v v="$P95_MS" 'BEGIN { exit !(v + 0 > 0) }'; then
  echo "Invalid p95_ms_per_session: $P95_MS"
  exit 1
fi

if ! awk -v v="$BASELINE_RSS_MB" 'BEGIN { exit !(v + 0 > 0) }'; then
  echo "Invalid baseline_rss_mb: $BASELINE_RSS_MB"
  exit 1
fi

if ! awk -v v="$PEAK_RSS_MB" 'BEGIN { exit !(v + 0 > 0) }'; then
  echo "Invalid peak_rss_mb: $PEAK_RSS_MB"
  exit 1
fi

if ! awk -v v="$CHECKSUM" 'BEGIN { exit !(v + 0 > 0) }'; then
  echo "Invalid checksum: $CHECKSUM"
  exit 1
fi

if ! awk -v v="$AVG_MS" -v max="$MAX_AVG_MS" 'BEGIN { exit !(v <= max) }'; then
  echo "Benchmark gate failed: avg_ms_per_session=$AVG_MS exceeds $MAX_AVG_MS"
  exit 1
fi

if ! awk -v v="$P95_MS" -v max="$MAX_P95_MS" 'BEGIN { exit !(v <= max) }'; then
  echo "Benchmark gate failed: p95_ms_per_session=$P95_MS exceeds $MAX_P95_MS"
  exit 1
fi

if ! awk -v v="$BASELINE_RSS_MB" -v max="$MAX_BASELINE_RSS_MB" 'BEGIN { exit !(v <= max) }'; then
  echo "Benchmark gate failed: baseline_rss_mb=$BASELINE_RSS_MB exceeds $MAX_BASELINE_RSS_MB"
  exit 1
fi

if ! awk -v v="$PEAK_RSS_MB" -v max="$MAX_PEAK_RSS_MB" 'BEGIN { exit !(v <= max) }'; then
  echo "Benchmark gate failed: peak_rss_mb=$PEAK_RSS_MB exceeds $MAX_PEAK_RSS_MB"
  exit 1
fi

echo "Benchmark gate passed."
