# VivyShot Performance Notes

## Rust Core Memory Benchmark

Run:

```sh
./scripts/memory-bench.sh
```

Optional custom session count:

```sh
./scripts/memory-bench.sh 150
```

What it does:

- Runs 100 (or custom) synthetic edit sessions in Rust core.
- Each session creates a new document buffer, applies:
  - rect
  - line
  - arrow
  - text
  - pixelate
  - blur
  - undo/redo
- Forces full + dirty renders and destroys the document.

Output includes:

- `sessions`
- `elapsed_ms`
- `avg_ms_per_session`
- `median_ms_per_session`
- `p95_ms_per_session`
- `p99_ms_per_session`
- `checksum` (sanity signal that render pipeline actually ran)
- `/usr/bin/time -l` metrics including max resident set size.

## Latest Local Run (2026-02-24)

Command:

```sh
./scripts/memory-bench.sh
```

Result highlights:

- `sessions=100`
- `elapsed_ms=2958.36`
- `avg_ms_per_session=29.58`
- `median_ms_per_session=30.67`
- `p95_ms_per_session=48.11`
- `p99_ms_per_session=50.39`
- `maximum resident set size=113491968` bytes
- `peak memory footprint=113001536` bytes

Compared to prior baseline in this project (`avg_ms_per_session=73.28`), this run is substantially faster while keeping memory usage in the same range.
