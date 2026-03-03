# VivyShot FFI ABI Policy

This project treats the C ABI (`ffi/vivyshot_core.h`) as a stable contract for the macOS app and future non-Swift hosts.

## Versioning

- ABI version is exposed via:
  - `VS_CORE_ABI_VERSION_MAJOR`
  - `VS_CORE_ABI_VERSION_MINOR`
  - `VS_CORE_ABI_VERSION_PATCH`
  - `vs_core_abi_version(uint32_t* major, uint32_t* minor, uint32_t* patch)`
- Semantics:
  - `MAJOR`: breaking ABI change (layout/signature/removal/meaning change).
  - `MINOR`: additive ABI-safe change (new function/struct field at end only when safe).
  - `PATCH`: bugfix-only change with no ABI shape change.

## Compatibility Rules

- Stable status code contract:
  - `VS_STATUS_OK` (`0`)
  - `VS_STATUS_NO_CHANGE` (`1`)
  - negative values are failures (`VS_STATUS_*`).
- Never reorder or repack exported `#[repr(C)]` structs.
- Never change meaning of existing enum/constant values.
- Additive-only changes are preferred:
  - new functions
  - new constants
  - new structs
- If a struct must evolve, prefer adding a new struct + function instead of mutating an existing one.

## Deprecation

- Keep deprecated entry points for at least one minor release cycle after replacement lands.
- Mark deprecations in Rust docs and this document, then remove only on a major ABI bump.
- Swift bridge should migrate first, then consumers can update before removal.

## Required Gates

- `./scripts/gen-ffi.sh` must be run after FFI changes.
- CI must reject header drift (`git diff --exit-code ffi/vivyshot_core.h`).
- Rust FFI contract tests should assert success/error code behavior for new APIs.
