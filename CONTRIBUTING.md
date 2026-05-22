# Contributing to VivyShot

Thanks for your interest in contributing to VivyShot.

## Code of Conduct

By participating in this project, you agree to follow `CODE_OF_CONDUCT.md`.

## Before You Start

1. Search existing issues and pull requests to avoid duplicate work.
2. For large changes, open an issue first to align on approach and scope.
3. Keep pull requests focused and small when possible.

## Development Setup

Requirements:

- macOS 15.2+
- Xcode 16.0+
- Rust stable toolchain (`rustup`)
- `cbindgen` for FFI header generation: `cargo install cbindgen`

Setup:

```bash
git clone https://github.com/vivy-company/vivyshot.git
cd vivyshot

# Build universal Rust static library used by the macOS app
./scripts/build-rust-universal.sh

# Open project
open macos/VivyShot.xcodeproj
```

## Pull Request Guidelines

1. Create a branch from `main`.
2. Make your changes with clear commit messages.
3. Run relevant checks/tests locally before opening a PR.
4. Include screenshots or recordings for UI changes.
5. Include clear validation notes for capture/export behavior changes.

## CLA Requirement

This repository requires signing the Contributor License Agreement before a PR can be merged.

1. Read `CLA.md`.
2. Comment on your pull request with the exact text below:

```text
I have read the CLA Document and I hereby sign the CLA
```

CLA checks are enforced by the repository bot configuration in `.clabot`.

## License

By submitting contributions, you agree that your contributions may be distributed under the project's license model:

- Rust core + generated FFI header (`vivyshot-rs/`, `ffi/`): MIT (`LICENSE-MIT`, `vivyshot-rs/LICENSE`, `ffi/LICENSE`)
- macOS app sources (`macos/`): GPL-3.0-only (`macos/LICENSE`, `LICENSE-GPL-3.0`)
- Official App Store binary terms: `LICENSE-APPSTORE.md`
