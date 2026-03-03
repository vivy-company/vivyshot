# vivyshot-rs

Rust workspace for VivyShot portable core + FFI adapter.

## Layout

- `crates/vivyshot-core`: portable domain logic (no C ABI)
- `crates/vivyshot-ffi`: `extern "C"` adapter + staticlib (`libvivyshot_core.a`)
- `crates/vivyshot-ffi/src/bin/memory_bench.rs`: memory/perf smoke benchmark
- `crates/vivyshot-ffi/tests/*`: FFI contract and property tests

## Commands

```bash
cargo test
cargo test -p vivyshot-core
cargo test -p vivyshot-ffi
cargo test -p vivyshot-ffi --test document_ffi_contract
cargo test -p vivyshot-ffi --test video_ffi_contract
cargo test -p vivyshot-ffi --test geometry_ffi_contract
cargo test -p vivyshot-ffi --test stitch_ffi_contract
cargo test -p vivyshot-ffi --test timeline_ffi_contract
cargo test -p vivyshot-ffi --test property_geometry
```
