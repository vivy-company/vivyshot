# AGENTS.md

## Mission

Build VivyShot as a Rust-first capture and editing core that can power multiple desktop surfaces.

## Product Goals

- Keep the Rust core (`vivyshot-rs/`) as the cross-surface source of truth for geometry, timeline, and export logic.
- Officially supported app surface today: macOS (`macos/`).
- Planned future official surfaces: Windows and Linux.
- Preserve a stable C ABI boundary via `ffi/vivyshot_core.h` for host integrations.

## Licensing Goals

- Rust core and generated FFI header (`vivyshot-rs/`, `ffi/`): MIT.
- macOS app sources (`macos/`): GPL-3.0-only.
- App Store binaries: Apple App Store EULA + VivyShot binary terms (`LICENSE-APPSTORE.md`).

## Distribution And Commercial Goals

- Official macOS distribution is expected through the App Store.
- The app is likely to be paid in the App Store, but pricing and tiers are still TBD.

## Agent Working Rules

- Keep repo messaging aligned with goals above (README, description, policy docs).
- Do not collapse the split license model into a single repo-wide source license.
- Prioritize Rust-core changes for behavior that should be shared across surfaces.
- If ABI changes are needed, regenerate header via `./scripts/gen-ffi.sh` and keep contract tests passing.
- Keep CI and governance files (`.github/workflows`, legal docs, CLA config) consistent with this strategy.

## Greenfield Policy

- VivyShot is currently a greenfield, pre-1.0 project.
- Breaking changes are acceptable across data fields, APIs, ABI shapes, and internal architecture when they improve the product.
- Do not preserve backward compatibility by default.
- Do not add compatibility shims, migration layers, or deprecation overhead unless explicitly requested.
- Optimize for the best long-term design and multi-surface evolution rather than legacy constraints.
