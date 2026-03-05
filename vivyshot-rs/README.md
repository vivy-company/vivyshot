# vivyshot-rs

Rust workspace for VivyShot portable core + FFI adapter.

## Layout

- `crates/vivyshot-core`: portable domain logic (no C ABI)
- `crates/vivyshot-ffi`: `extern "C"` adapter + staticlib (`libvivyshot_core.a`)
- `crates/vivyshot-ffi/src/bin/memory_bench.rs`: memory/perf smoke benchmark
- `crates/vivyshot-ffi/tests/*`: FFI contract and property tests
- ABI policy/versioning: [`../docs/ffi-abi-policy.md`](../docs/ffi-abi-policy.md)

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
../scripts/ci-bench-gate.sh 20
../scripts/ci-perf-gate.sh 20
```

## Rustdocs

Build workspace docs:

```bash
cargo doc --workspace --no-deps
```

Open the generated docs:

- `target/doc/vivyshot_domain/index.html` (`vivyshot-core`)
- `target/doc/vivyshot_core/index.html` (`vivyshot-ffi`)
- `target/doc/vivyshot_domain/video/index.html`
- `target/doc/vivyshot_domain/timeline/index.html`
- `target/doc/vivyshot_domain/geometry/index.html`
- `target/doc/vivyshot_domain/stitch/index.html`
