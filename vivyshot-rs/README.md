# vivyshot-rs

Portable Rust core for VivyShot.

## Layout

- `src/lib.rs`: FFI + core logic (current implementation)
- `src/bin/memory_bench.rs`: memory/perf smoke benchmark
- `tests/document_ffi_contract.rs`: document annotation/render FFI contracts
- `tests/video_ffi_contract.rs`: video session and input normalization contracts
- `tests/geometry_ffi_contract.rs`: geometry/trim/GIF policy contracts
- `tests/stitch_ffi_contract.rs`: stitch/crop/encode/autoscroll contracts
- `tests/timeline_ffi_contract.rs`: timeline contracts and history semantics
- `tests/property_geometry.rs`: property-based geometry invariants
- `tests/common/mod.rs`: shared test helpers

## Commands

```bash
cargo test
cargo test --test document_ffi_contract
cargo test --test video_ffi_contract
cargo test --test geometry_ffi_contract
cargo test --test stitch_ffi_contract
cargo test --test timeline_ffi_contract
cargo test --test property_geometry
```
