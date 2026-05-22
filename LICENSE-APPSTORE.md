# VivyShot App Store Binary License

This document defines the license model for official VivyShot binaries distributed through Apple's App Store.

## Scope

This license applies only to binary builds of VivyShot obtained from the App Store.

It does not apply to source code in this repository.

## Governing Terms

Use of App Store binaries is governed by:

1. Apple's Licensed Application End User License Agreement (including required minimum terms).
2. Any VivyShot product terms presented in-app or on official Vivy properties at the time of distribution.

## Source Code License

Source code in this repository uses a split model:

- Rust core + generated FFI header (`vivyshot-rs/`, `ffi/`): MIT (`LICENSE-MIT`, `vivyshot-rs/LICENSE`, `ffi/LICENSE`)
- macOS app sources (`macos/`): GPL-3.0-only (`macos/LICENSE`, `LICENSE-GPL-3.0`)

## License Summary

- Rust core source: MIT
- macOS app source: GPL-3.0-only
- Official App Store binaries: App Store EULA + VivyShot product terms

## Third-Party Software

Third-party notices for bundled dependencies are provided in `THIRD_PARTY_NOTICES.md`.
