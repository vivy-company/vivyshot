# VivyShot v1 Spec

## 1. Product

- Name: `VivyShot`
- Type: macOS screenshot + annotation utility
- Positioning: fast, minimal, low-memory alternative to heavy screenshot tools
- Initial release targets:
- Mac App Store build
- direct notarized build

## 2. Goals

- Capture and annotate screenshots with near-zero friction.
- Keep memory usage stable across repeated captures.
- Ship a focused v1 quickly, while keeping the core portable to Windows/Linux hosts later.

## 3. Non-Goals (v1)

- No cloud sync.
- No collaborative editing.
- No plugin system.
- No advanced image editing suite (layers, masks, filter catalog).
- No screen recording workflow.

Note: this section is for screenshot-only v1 scope. Planned recorder/editor scope is defined in `docs/video-editor-spec.md`.
Planned screenshot/recording history scope is defined in `docs/capture-history-spec.md`.

## 4. Platform Baseline

- v1 deployment target: `macOS 15.2+`
- Reason:
- `SCScreenshotManager.captureImage(in:completionHandler:)` exists on macOS 15.2 and simplifies region capture significantly.
- Legacy capture APIs in CoreGraphics are marked obsolete and should not be used for new builds.
- Optional future compatibility track:
- Add fallback path for macOS 14.x using `SCShareableContent` + `SCContentFilter` + `SCScreenshotManager.captureImage(contentFilter:configuration:)`.

## 5. Architecture

### 5.1 Swift Host (macOS surface)

- App lifecycle, menu bar, and windows
- Global hotkey registration
- Region selection overlay
- Permission checks and screen capture API calls
- Clipboard, save panel, share sheet integration
- App Sandbox, signing, notarization, App Store packaging

### 5.2 Rust Core (`staticlib`)

- Annotation document model and command history
- Rendering and compositing into BGRA8 buffers
- Undo/redo state machine
- Blur/pixelate operations
- Image export (PNG/JPEG)
- Memory pooling and runtime counters

### 5.3 FFI Boundary

- C ABI with explicit ownership rules
- Stable `vs_*` function surface
- No Objective-C or Swift-only types crossing the boundary

## 6. Dependency Matrix

### 6.1 Swift Host Dependencies (v1)

- Zero third-party runtime dependencies by default.
- Apple frameworks:
- `AppKit` for UI and windowing
- `ScreenCaptureKit` for screenshot capture
- `CoreGraphics` for permission check helpers and image interop
- `Carbon` (`RegisterEventHotKey`) for global hotkeys
- `UniformTypeIdentifiers` for export MIME/UTType mapping
- `OSLog` for structured logs and signposts

### 6.2 Rust Core Dependencies (v1)

- `tiny-skia = 0.12.x`
- Purpose: shape/path rasterization for rectangle/line/arrow primitives.
- `ab_glyph = 0.2.x`
- Purpose: text glyph rasterization for v1 text annotations.
- `fontdb = 0.23.x`
- Purpose: discover and resolve system fonts on macOS.
- `png = 0.18.x`
- Purpose: PNG export.
- `jpeg-encoder = 0.7.x`
- Purpose: JPEG export.
- `serde = 1.x` and `serde_json = 1.x`
- Purpose: project/session persistence (not hot-path rendering).
- `smallvec = 1.x`
- Purpose: reduce heap allocations for small command/rect lists.
- `thiserror = 2.x`
- Purpose: typed error handling across core layers.
- `tracing = 0.1.x`
- Purpose: structured internal diagnostics and perf markers.

### 6.3 Build and Tooling Dependencies

- Rust toolchain:
- `rustc/cargo >= 1.89` (current local: 1.92.0)
- Swift/Xcode:
- `Xcode >= 26.2` (current local: 26.2)
- `Swift >= 6.2` (current local: 6.2.3)
- FFI tooling:
- `cbindgen = 0.29.x` to generate C headers from Rust public API.

### 6.4 Deferred/Optional Dependencies

- `cosmic-text` only if we need advanced shaping/fallback beyond `ab_glyph`.
- `rayon` only if profiling proves CPU blur/pixelate parallelization is needed.
- No auto-launch, analytics, or updater frameworks in v1.

## 7. Capture Pipeline (v1 Technical Design)

### 7.1 Permission Flow

- On capture request:
- call `CGPreflightScreenCaptureAccess()`
- if false, call `CGRequestScreenCaptureAccess()`
- if denied, show in-app guidance and abort capture path

### 7.2 Region Capture Flow

- User triggers hotkey.
- Show transparent overlay for region selection.
- Resolve selected rect in display points.
- Call `SCScreenshotManager.captureImage(in:completionHandler:)`.
- Convert resulting `CGImage` into canonical BGRA8 pixel buffer for Rust core.
- Initialize Rust document with base image pointer + metadata.

### 7.3 Why This Path

- Single capture call for region mode.
- No stream queue management in v1.
- Lower memory overhead versus long-lived streaming capture for one-shot screenshots.

## 8. Core Data and Rendering Details

### 8.1 Data Model

- `Document`:
- base image metadata (`width`, `height`, `stride`, color space tag)
- immutable base buffer
- mutable composited buffer
- command list
- undo cursor
- pooled scratch buffers

- `Command` variants:
- `Rect`
- `Line`
- `Arrow`
- `Text`
- `PixelateRect`
- `BlurRect`

### 8.2 Rendering Strategy

- Keep one immutable base capture buffer.
- Keep one mutable composited output buffer.
- For each edit:
- compute dirty rect
- restore dirty rect from base into output
- replay only intersecting commands for that rect
- avoid full-frame rerender where possible

### 8.3 Text Strategy (v1)

- `ab_glyph + fontdb` with system font lookup.
- v1 scope:
- single style run per text object
- basic line breaks
- no rich text

## 9. FFI Contract (Refined)

### 9.1 Handles and Ownership

- `vs_document_handle` is opaque pointer/ID owned by Rust.
- Swift must call explicit destroy function.
- All output buffers either:
- caller-provided mutable memory
- or Rust-allocated with paired free function

### 9.2 Initial Function Surface

- `vs_create_document_from_bgra(width, height, stride, ptr, len) -> handle`
- `vs_destroy_document(handle)`
- `vs_add_rect(handle, rect_params) -> status`
- `vs_add_line(handle, line_params) -> status`
- `vs_add_arrow(handle, arrow_params) -> status`
- `vs_add_text(handle, text_ptr, len, text_params) -> status`
- `vs_add_pixelate_rect(handle, pixelate_params) -> status`
- `vs_add_blur_rect(handle, blur_params) -> status`
- `vs_undo(handle) -> status`
- `vs_redo(handle) -> status`
- `vs_render_full(handle, out_ptr, out_len) -> status`
- `vs_render_dirty(handle, out_ptr, out_len, dirty_rects_ptr, dirty_rects_cap, dirty_rects_written_ptr) -> status`
- `vs_export_png(handle, path_ptr, len) -> status`
- `vs_export_jpeg(handle, path_ptr, len, quality) -> status`
- `vs_last_error_message(handle, out_ptr, out_len) -> written_len`

### 9.3 Protocol Notes

- Keep hot-path APIs struct-based, not JSON-based.
- Use JSON only for debug/session serialization endpoints.
- All structs in FFI header use fixed-size integer/float fields.

## 10. UX and Interaction Requirements

- Hotkey to capture-ready overlay: target `< 250 ms` (warm app).
- Tool switch response: target `< 16 ms`.
- Primary user flow target:
- hotkey -> select region -> annotate -> copy/save in `< 10 s`.

## 11. Performance and Memory Budgets

- Idle RSS after launch: target `< 40 MB`.
- Single 4K active edit session: target `< 140 MB`.
- Repeated capture test (`100` captures):
- RSS should return near baseline after finalize/close cycle
- no unbounded upward trend

### 11.1 Memory Design Rules

- Never store full-frame bitmap snapshots for undo.
- Undo/redo stores command history and minimal metadata only.
- Reuse scratch buffers from a pool.
- Avoid per-frame allocations in render loop.

### 11.2 Measurement Protocol

- Use Instruments:
- `Allocations`
- `Leaks`
- `VM Tracker`
- Use command-line checks:
- `leaks`
- `vmmap -summary`
- Capture benchmark scenario:
- 100 region captures at mixed resolutions
- apply 10 random annotations each
- export and close each document
- record median and p95 peak RSS deltas

## 12. Packaging, Sandbox, and Distribution

- Mac App Store build:
- enable App Sandbox
- use user-selected file access for save/export workflows
- configure signing and archive pipeline in Xcode
- Direct build:
- sign and notarize `.app`

- v1 intentionally avoids restricted capabilities:
- no microphone capture
- no background helper daemons
- no network requirement

## 13. Monetization

- v1: paid upfront (`$2.99`) to keep business logic simple.
- Future option:
- free base + one-time pro unlock if feature set expands.

## 14. Repository Layout (Proposed)

```text
vivyshot/
  SPEC.md
  macos/
    VivyShot.xcodeproj
    VivyShot/
  vivyshot-rs/
    Cargo.toml
    crates/
      vivyshot-core/
        src/
      vivyshot-ffi/
        src/
  ffi/
    vivyshot_core.h
  scripts/
    build-rust.sh
    build-rust-universal.sh
  docs/
    perf.md
    release.md
```

## 15. Delivery Plan (2-Day MVP Spike)

### Day 1

- Scaffold `macos` AppKit app with menu bar item + global hotkey.
- Build overlay selection UI and region rect output.
- Scaffold `vivyshot-rs` staticlib and FFI header generation.
- Implement document create/destroy + rectangle annotation + full render.
- Wire Swift host <-> Rust FFI end-to-end.

### Day 2

- Add line/arrow/text/pixelate/blur commands.
- Add undo/redo and dirty-rect rendering path.
- Add copy-to-clipboard and save PNG/JPEG.
- Run 100-capture memory loop and fix retention issues.
- Produce signed local build and release checklist draft.

## 16. Acceptance Criteria

- Region capture works reliably on macOS 15.2+.
- Core annotation tools function and export is correct.
- Undo/redo works for all v1 commands.
- No obvious memory growth trend in repeated-capture benchmark.
- Codebase cleanly separates portable Rust core from macOS host.

## 17. Open Decisions

- Confirm whether `ab_glyph` text rendering quality is sufficient for v1 or if we promote to `cosmic-text`.
- Decide whether to include fullscreen capture in Day 1 or Day 2.
- Decide whether to ship with only one default hotkey or customizable shortcuts in v1.

## 18. Validation Commands (Local)

- SDK and toolchain:
- `xcrun --sdk macosx --show-sdk-path`
- `xcodebuild -version`
- `rustc --version`
- `swift --version`

- API availability checks:
- `rg -n "CGPreflightScreenCaptureAccess|CGRequestScreenCaptureAccess" "$SDK/.../CoreGraphics.framework/Headers"`
- `rg -n "SCScreenshotManager|captureImageInRect|captureImageWithFilter" "$SDK/.../ScreenCaptureKit.framework/Headers"`
- `rg -n "SCREEN_CAPTURE_OBSOLETE" "$SDK/.../CoreGraphics.framework/Headers/CGWindow.h"`

- Dependency checks:
- `cargo search tiny-skia --limit 1`
- `cargo search ab_glyph --limit 1`
- `cargo search fontdb --limit 1`
- `cargo search png --limit 1`
- `cargo search jpeg-encoder --limit 1`
- `cargo search cbindgen --limit 1`

## 19. Implementation Status (Current)

### Completed

- Repo scaffold created:
- `macos/`, `vivyshot-rs/`, `ffi/`, `scripts/`, `docs/`
- Xcode project generation with `xcodegen` from `macos/project.yml`
- Rust core static library build scripts:
- `scripts/build-rust.sh`
- `scripts/build-rust-universal.sh`
- C FFI surface implemented in Rust:
- `vs_create_document_from_bgra`
- `vs_add_rect`
- `vs_add_line`
- `vs_add_arrow`
- `vs_add_text`
- `vs_add_pixelate_rect`
- `vs_add_blur_rect`
- `vs_render_full`
- `vs_undo`
- `vs_redo`
- `vs_render_dirty`
- `vs_destroy_document`
- Undo/redo command cursor and branch truncation implemented in Rust core
- Dirty-rect tracking + partial redraw path implemented in Rust core
- Rust core tests added for undo/redo and dirty-render behavior
- Swift <-> Rust bridge implemented and linked via static `.a`
- Persistent Rust document session wired into macOS editor flow
- macOS menu-bar app shell implemented
- Global hotkey registration implemented (default: `Cmd+Shift+2`)
- Region selection overlay implemented
- Region capture implemented via `SCScreenshotManager.captureImage(in:)`
- Captured image routed through Rust core and shown in preview window
- Interactive rectangle annotation implemented (drag in editor canvas)
- Interactive line and arrow annotations implemented (tool switch + drag)
- Interactive text/pixelate/blur annotations implemented
- In-canvas text editing implemented (inline editor anchored on canvas click)
- Text controls added in editor top bar (font size + color)
- Undo/redo keyboard shortcuts wired in editor (`Cmd+Z`, `Cmd+Shift+Z`)
- Copy image action implemented (`Cmd+C`)
- Save image action implemented (`Cmd+S`, PNG/JPEG)
- Rust-core memory benchmark automation added (`scripts/memory-bench.sh`, 100 sessions default)
- Blur pipeline optimized to separable sliding-window box blur (hot-path speedup)
- Pixelate hot-path loops tightened to reduce per-pixel overhead
- Memory benchmark now reports per-session tail latencies (median/p95/p99)

### Pending (Next)

- Optional: add richer text UX (multiline textarea, drag-to-reposition, style presets)
- Optional: add SIMD-specific blur/pixelate kernels if profiling on lower-end hardware requires it
