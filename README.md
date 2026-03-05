# VivyShot

[![macOS](https://img.shields.io/badge/macOS-15.2+-black?style=flat-square&logo=apple)](#requirements)
[![Swift](https://img.shields.io/badge/Swift-6.0-F05138?style=flat-square&logo=swift&logoColor=white)](https://swift.org)
[![Rust](https://img.shields.io/badge/Rust-stable-000000?style=flat-square&logo=rust)](https://www.rust-lang.org)
[![Rust Core License](https://img.shields.io/badge/Rust%20Core-MIT-green?style=flat-square)](LICENSE)
[![macOS License](https://img.shields.io/badge/macOS-GPL%203.0-blue?style=flat-square)](LICENSE-GPL-3.0)
[![Binary License](https://img.shields.io/badge/Binary-App%20Store%20EULA-6e7681?style=flat-square)](LICENSE-APPSTORE.md)
[![Sponsor](https://img.shields.io/badge/Sponsor-GitHub-ff69b4?style=flat-square&logo=github)](https://github.com/sponsors/vivy-company)

Capture, annotate, and compose polished screenshots and recordings on macOS.

## What Is VivyShot?

VivyShot is a macOS capture workflow app with a Rust core for deterministic geometry, timeline, and export logic. It is designed for fast region capture, editing, and export with a native SwiftUI shell.

## Features

### Capture
- Region selection and overlay-driven interactions
- Screenshot and recording workflows
- Keyboard-friendly quick actions

### Editing
- Annotation tools with inline text and drawing support
- Selection editing and overlay toolbars
- Planned timeline-driven video editing flow (see `docs/video-editor-spec.md`)

### Core Architecture
- SwiftUI macOS host app (`macos/`)
- Rust portable core + C ABI (`vivyshot-rs/` + `ffi/vivyshot_core.h`)
- ABI contract tests and property tests for FFI stability

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
```

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
