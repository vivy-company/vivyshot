# VivyShot

[![macOS](https://img.shields.io/badge/macOS-15.2+-black?style=flat-square&logo=apple)](#requirements)
[![Website](https://img.shields.io/badge/Website-vivyshot.com-0a66c2?style=flat-square)](https://vivyshot.com)
[![Swift](https://img.shields.io/badge/Swift-6.0-F05138?style=flat-square&logo=swift&logoColor=white)](https://swift.org)
[![Rust](https://img.shields.io/badge/Rust-stable-000000?style=flat-square&logo=rust)](https://www.rust-lang.org)
[![Rust Core License](https://img.shields.io/badge/Rust%20Core-MIT-green?style=flat-square)](LICENSE)
[![macOS License](https://img.shields.io/badge/macOS-GPL%203.0-blue?style=flat-square)](LICENSE-GPL-3.0)
[![Binary License](https://img.shields.io/badge/Binary-App%20Store%20EULA-6e7681?style=flat-square)](LICENSE-APPSTORE.md)
[![Sponsor](https://img.shields.io/badge/Sponsor-GitHub-ff69b4?style=flat-square&logo=github)](https://github.com/sponsors/vivy-company)

Open source screen capture, annotation, and recording software with a portable Rust core and a native macOS app today.

![VivyShot screenshot](web/public/screenshot.png)

## What Is VivyShot?

VivyShot is a focused screenshot and recording tool for people who want to capture something, mark it up, copy it, and move on. It is built around a portable Rust core for shared geometry, timeline, and export logic, with a native macOS app as the official surface today.

The product direction is straightforward:

- Keep the workflow simple and keyboard-friendly.
- Keep the UI native on each platform instead of stretching one generic shell everywhere.
- Keep the project open source and inspectable.
- Keep pricing simple: free forever for the core workflow, with one-time upgrades instead of a subscription.

## Features

### Capture
- Area, window, and full-screen capture
- Screenshot and short recording workflows
- Keyboard-first flow, including quick copy/share actions

### Editing
- Shapes, arrows, paint, and text tools
- Blur and pixelate tools for cleanup and redaction
- Fast export to clipboard, PNG, and JPEG
- Recording options for audio and input overlays

### Architecture
- Native macOS host app in SwiftUI (`macos/`)
- Portable Rust core + C ABI (`vivyshot-rs/` + `ffi/vivyshot_core.h`)
- ABI contract tests and property tests around the shared core

## Surface Strategy

- Core engine in Rust (`vivyshot-rs`) is intentionally surface-agnostic.
- Stable C ABI (`ffi/vivyshot_core.h`) is used to integrate with app surfaces.
- Official supported surface today: macOS (`macos/`).
- More native desktop surfaces are planned over time.

## Distribution And Pricing

- Official macOS distribution is planned through Apple's App Store.
- Pricing direction:
  - Free forever for the core workflow
  - Lifetime unlock: `$9.99` one-time
  - Supporter: `$24.99` one-time, with the same full unlock plus a small in-app supporter badge
- No subscription.
- App Store binary license terms are documented in `LICENSE-APPSTORE.md`.

## Requirements

- macOS 15.2+
- Xcode 16.0+
- Rust stable toolchain
- `cbindgen` (`cargo install cbindgen`)

## Build From Source

```bash
git clone https://github.com/vivy-company/vivyshot.git
cd vivyshot

# Build universal Rust static library used by Xcode targets.
./scripts/build-rust-universal.sh

# (Optional) Regenerate C header after FFI changes.
./scripts/gen-ffi.sh

# Open in Xcode.
open macos/VivyShot.xcodeproj
```

## Test And CI Commands

```bash
# Rust checks
cd vivyshot-rs
cargo fmt --all --check
cargo clippy -p vivyshot-core --all-targets -- -D warnings
cargo clippy -p vivyshot-ffi --all-targets -- -D warnings
cargo test --workspace

# FFI and perf gate (from repo root)
./scripts/gen-ffi.sh
./scripts/ci-bench-gate.sh 20
./scripts/ci-perf-gate.sh 20
```

`ci-bench-gate.sh` enforces by default:
- Document benchmark (`memory_bench`):
  `avg_ms_per_session <= 180`, `p95_ms_per_session <= 280`,
  `baseline_rss_mb <= 100`, `peak_rss_mb <= 200`
- Screenshot benchmark (`screenshot_bench`):
  `avg_ms_per_session <= 100`, `p95_ms_per_session <= 140`,
  `baseline_rss_mb <= 100`, `peak_rss_mb <= 200`

Override with environment variables:
`VIVYSHOT_DOC_BENCH_MAX_AVG_MS`, `VIVYSHOT_DOC_BENCH_MAX_P95_MS`,
`VIVYSHOT_DOC_BENCH_MAX_BASELINE_RSS_MB`, `VIVYSHOT_DOC_BENCH_MAX_PEAK_RSS_MB`,
`VIVYSHOT_SHOT_BENCH_MAX_AVG_MS`, `VIVYSHOT_SHOT_BENCH_MAX_P95_MS`,
`VIVYSHOT_SHOT_BENCH_MAX_BASELINE_RSS_MB`, `VIVYSHOT_SHOT_BENCH_MAX_PEAK_RSS_MB`.

## Repository Layout

```text
macos/          # SwiftUI macOS app
vivyshot-rs/    # Rust workspace: core + FFI adapter
ffi/            # Generated C header for ABI boundary
scripts/        # Build/test/dev scripts
docs/           # Specs and engineering notes
```

## Third-Party Notices

See `THIRD_PARTY_NOTICES.md`.

## Contributing

See `CONTRIBUTING.md` for contribution workflow and `CLA.md` for CLA signing requirements.

## Security

See `SECURITY.md` for vulnerability reporting guidelines.

## License

VivyShot uses a split source-license model:

- Rust core + generated FFI header (`vivyshot-rs/`, `ffi/`): MIT (`LICENSE`)
- macOS app sources (`macos/`): GPL-3.0-only (`macos/LICENSE`, `LICENSE-GPL-3.0`)
- Official App Store binaries: App Store EULA + VivyShot binary terms (`LICENSE-APPSTORE.md`)

If you obtain VivyShot via Apple's App Store, App Store EULA and binary terms apply to that binary distribution.
