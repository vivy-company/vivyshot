# Rust Core / FFI Responsibility Refactor Spec

## Status

- Proposed
- Date: 2026-04-08

## Problem Statement

VivyShot’s stated architecture is "Rust-first core, thin C ABI bridge, native host surface." The current Rust workspace does not match that shape.

Today:

- `vivyshot-core` mostly contains stateless helper functions and ABI-shaped data structs.
- `vivyshot-ffi` contains the actual stateful editing engines for document editing, timeline editing, video session state, stitch session state, image encoding, text/font handling, and JSON snapshot policy.
- the only official host surface today is macOS, but that surface still contains some shared export/statistics behavior that should be owned by Rust core rather than the app host.

That is backwards for a multi-surface product. It makes the FFI crate the real engine, which means:

- cross-surface behavior is not actually owned by the core;
- the ABI layer contains product logic, rendering logic, and platform policy;
- future Windows/Linux hosts would either reuse the wrong layer or duplicate behavior;
- tests are concentrated at the ABI edge instead of around the real domain engine.

Current footprint, as reviewed on 2026-04-08:

- `vivyshot-ffi/src/*.rs`: about `8.9k` lines
- `vivyshot-core/src/*.rs`: about `2.6k` lines
- largest FFI implementation files:
  - `document.rs`: `2433` lines
  - `timeline.rs`: `1702` lines
  - `stitch.rs`: `690` lines
  - `video.rs`: `655` lines

## Review Summary

### 1. `vivyshot-core` is currently a helper library, not the shared engine

`vivyshot-core` advertises itself as the source of truth for timeline, stitching, and export logic, but the public surface in [`vivyshot-rs/crates/vivyshot-core/src/lib.rs`](../vivyshot-rs/crates/vivyshot-core/src/lib.rs) is mostly pure functions and ABI-shaped structs.

Examples:

- [`timeline.rs`](../vivyshot-rs/crates/vivyshot-core/src/timeline.rs) only exposes a few pure helpers for clip range normalization and export filtering.
- [`video.rs`](../vivyshot-rs/crates/vivyshot-core/src/video.rs) mostly computes export plans and overlay layout policy.
- [`types.rs`](../vivyshot-rs/crates/vivyshot-core/src/types.rs) uses raw numeric tags like `u8` for track kinds, plan modes, export targets, and stitch sides. Those are ABI concerns leaking inward.

### 2. The document engine lives almost entirely in `vivyshot-ffi`

[`vivyshot-rs/crates/vivyshot-ffi/src/document.rs`](../vivyshot-rs/crates/vivyshot-ffi/src/document.rs) owns:

- the document model (`vs_document`);
- the annotation command enum (`VsCommand`);
- undo/redo state via `commands` + `cursor`;
- dirty-region tracking;
- annotation mutation operations;
- affine transform/copy policy;
- rendering/compositing into BGRA buffers;
- text layout and rasterization;
- blur and pixelate implementations;
- system font discovery and file IO.

This is not bridge logic. This is the screenshot editor engine.

### 3. The timeline engine also lives in `vivyshot-ffi`

[`vivyshot-rs/crates/vivyshot-ffi/src/timeline.rs`](../vivyshot-rs/crates/vivyshot-ffi/src/timeline.rs) owns:

- `VsTimeline`;
- `TimelineTrack`, `TimelineClip`, `ClipData`, `ClipTransform`;
- timeline undo/redo history;
- track/clip creation, mutation, splitting, reordering, visibility;
- bootstrap behavior for capture tracks;
- clip text/style/shape/zoom data;
- visibility queries and export projections.

The core timeline module currently contains only a small subset of this behavior.

### 4. Session state is repeatedly implemented in the FFI crate

The same pattern appears in other subsystems:

- [`video.rs`](../vivyshot-rs/crates/vivyshot-ffi/src/video.rs): `vs_video_session`, key/click event storage, trim state, export context state, snapshot serde.
- [`stitch.rs`](../vivyshot-rs/crates/vivyshot-ffi/src/stitch.rs): `vs_stitch_session`, working image state, direction lock, expected row heuristics, merge orchestration, crop utility.
- [`stats.rs`](../vivyshot-rs/crates/vivyshot-ffi/src/stats.rs): `vs_stats_session`, snapshot serde shape, event parsing and persistence wrapping.

These should be core-owned domain/session objects with FFI wrappers around them.

### 5. Platform-specific behavior is mixed into the shared ABI layer

Two notable examples:

- [`document.rs`](../vivyshot-rs/crates/vivyshot-ffi/src/document.rs) loads fonts from hardcoded macOS, Windows, and Linux filesystem paths. That is platform support policy, not ABI bridging.
- [`video.rs`](../vivyshot-rs/crates/vivyshot-ffi/src/video.rs) normalizes key tokens from a macOS-style keycode/modifier model (`⌘`, `⌥`, arrow glyphs, function-key mapping). That is host/platform input mapping, not portable core logic.

## Architectural Goals

The refactor should enforce the following:

1. `vivyshot-core` owns all cross-surface behavior and state machines.
2. `vivyshot-ffi` owns only C ABI concerns.
3. Host/platform policy stays in the host or in explicit platform-support modules, not in the generic ABI bridge.
4. Core Rust APIs should use typed enums, typed errors, and ordinary Rust ownership.
5. C ABI should translate to and from the core, not define the core’s internal model.
6. The macOS surface stays thin: it should own recording orchestration, UI, and OS integration, but not shared editor/export/history rules.

## Non-Goals

- Do not redesign product behavior during this refactor unless needed to repair ownership boundaries.
- Do not add compatibility shims just to preserve the current internal layout.
- Do not split into many micro-crates on day one unless a clear seam already exists.

## Target Layering

### Layer 1: Native Host

Examples:

- `macos/`

Responsibilities:

- OS permissions and screen capture APIs
- recording device/session orchestration through native frameworks
- windowing, overlay UI, clipboard, file dialogs
- platform key event interpretation
- platform font selection/resolution if needed
- local storage paths and native DB/file handles
- converting host-native data to FFI-safe structs

### Layer 2: C ABI Bridge (`vivyshot-ffi`)

Responsibilities:

- `extern "C"` exports
- `#[repr(C)]` structs and constants
- opaque handle lifecycle and stale-handle validation
- pointer/length/null validation
- conversion between C structs and core Rust structs
- mapping `CoreError` to `VS_STATUS_*`
- Rust-allocated output buffer ownership helpers

Non-responsibilities:

- no document/timeline/video/stitch/stats state machines
- no rendering algorithms
- no JSON schema ownership
- no image codec ownership
- no platform font lookup
- no host-specific keycode normalization

### Layer 3: Shared Rust Core (`vivyshot-core`)

Responsibilities:

- all stateful editing/session models
- all shared policy and validation rules
- rasterization/effects/encoding logic that should match across surfaces
- persistence snapshot schemas for shared session/domain state
- typed errors and typed enums

## Target Module Structure

Keep `vivyshot-core` as the main engine crate, but expand it so the engine actually lives there.

### `core::base`

Purpose:

- common scalar/value types
- strongly typed enums
- image buffer types
- IDs and shared small utilities

Move here:

- `TrimHandle`
- `ResizeCorner`
- `StitchSide`
- `TrackKind`
- `ClipKind`
- `VideoExportTarget`
- typed color/rect/point types

Rule:

- raw `u8`/`u32` tags exist only at the FFI boundary, not in the domain model.

### `core::document`

Own:

- `Document`
- `AnnotationCommand`
- dirty-region tracking
- command history / undo / redo
- annotation mutation operations
- annotation query APIs
- affine copy/transform behavior

Example target Rust API:

```rust
pub struct Document { ... }

impl Document {
    pub fn from_bgra(base: BgraImageOwned) -> Result<Self, CoreError>;
    pub fn apply(&mut self, cmd: AnnotationCommand) -> Result<DirtyRegion, CoreError>;
    pub fn move_annotation(&mut self, id: AnnotationId, delta: I32Point) -> Result<DirtyRegion, CoreError>;
    pub fn resize_annotation(&mut self, id: AnnotationId, rect: I32Rect) -> Result<DirtyRegion, CoreError>;
    pub fn render_full(&mut self, out: &mut [u8]) -> Result<(), CoreError>;
    pub fn render_dirty(&mut self, out: &mut [u8]) -> Result<Option<I32Rect>, CoreError>;
}
```

### `core::render`

Own:

- BGRA compositing
- shape/path rasterization
- text layout/rasterization abstractions
- blur/pixelate implementations

Text rule:

- core may own text rasterization behavior;
- platform font discovery must not live in the ABI bridge;
- use either:
  - an embedded fallback font path in core, or
  - a core `FontBook` / `FontProvider` abstraction fed by the host/platform layer.

### `core::timeline`

Own:

- `Timeline`
- `Track`, `Clip`, `ClipTransform`, `ClipData`
- track/clip mutation
- history / undo / redo
- clip queries
- bootstrap/default capture track policy
- export projections derived from timeline state

The existing pure helpers in `timeline.rs` stay, but as internal building blocks, not the whole module.

### `core::video`

Split into two concerns:

- `video::plan`: export planning and overlay policy
- `video::session`: key/click event storage, trim state, snapshot state

Move here:

- `vs_video_session` model equivalent
- session serialize/deserialize schema
- click normalization and duplicate detection

Do not move unchanged:

- `vs_normalize_key_token` as currently implemented should not become portable core logic. It is platform input mapping and belongs in the host or in an explicit platform-support layer.

### `core::stitch`

Keep the current stateless stitch helpers, but add:

- `StitchSession`
- merge orchestration state
- direction lock / expected row heuristics
- base image / last frame lifecycle
- crop helpers if they are shared image utilities

### `core::stats`

Keep the current domain logic, but add:

- `StatsSession` wrapper if session ownership is useful
- snapshot serde schema inside core

The FFI layer should not own the JSON schema for a shared stats state machine.

### `core::codec`

Own:

- PNG/JPEG encoding from BGRA/RGBA
- encoded byte containers

This removes `image` codec logic from `vivyshot-ffi`.

## FFI Design Rules After Refactor

Every exported FFI function should fit this template:

1. Validate pointers, capacities, and handle identity.
2. Convert C inputs to core types.
3. Call a core method or pure function.
4. Convert result/error back to C structs/status codes.
5. Return.

The FFI crate may keep small helper modules like the current `src/ffi/domain.rs`, `src/ffi/geometry.rs`, `src/ffi/video.rs`, etc. That pattern is correct. The mistake is that large subsystems bypass it and implement the engine in the ABI crate.

## Host vs Core vs FFI Responsibility Table

### Belongs in host/platform

- screen capture APIs
- capture device/session orchestration
- macOS keycode to human-readable token normalization
- platform font discovery / font asset selection
- clipboard/share/save dialogs
- native file handles, storage paths, SQLite/AVFoundation/ScreenCaptureKit integration

### Belongs in shared core

- annotation document semantics
- rendering/effect semantics
- timeline semantics and history
- export planning
- post-recording export policy and overlay/layout policy
- stitch session semantics
- stats semantics
- stats ledger schema, replay semantics, and projection rules
- shared snapshot schemas
- image codecs

### Belongs in FFI only

- handle validation
- struct translation
- pointer copying
- ABI version exposure
- buffer destroy functions

## macOS Surface Audit

The current macOS host is partially aligned with the intended architecture, but not fully.

### Already appropriately host-owned

- ScreenCaptureKit / AVFoundation capture setup, permissions, webcam selection, accessibility trust, and save panels.
- overlay windows, selection UI, target picking, clipboard, dialogs, and capture flow orchestration.
- native event taps and recording monitors as raw platform input sources.

These are host responsibilities and should remain in `macos/`.

### Already appropriately delegated to Rust

- screenshot editing session ownership via `RustDocumentSession`
- shared geometry helpers used by annotation/selection UI
- stitch session state and auto-scroll helpers used from `RustStitchSession`

This direction is correct and should be expanded, not reversed.

### Still too heavy in the macOS surface

- `macos/Sources/App/Features/Capture/VideoCaptureComponents.swift` currently owns shared export rules:
  - file type selection
  - export preset selection
  - bitrate / quality / frame-rate / scale heuristics
  - post-recording video composition transform and render-size policy
- `macos/Sources/App/Features/Statistics/CaptureStatisticsStore.swift` currently owns shared persistence semantics:
  - statistics ledger table schema
  - ledger replay into the Rust stats session
  - projection rewrite policy for summary/bucket tables

These are not inherently macOS-only behaviors. They are shared product rules and should live in Rust core, with the host acting as a transport/runtime layer.

### Thin macOS surface rule

For the current product phase, treat macOS as the reference host for boundary design:

- keep in macOS:
  - ScreenCaptureKit, AVFoundation, AppKit, Accessibility, save panels, clipboard, file locations, and native DB handles
  - UI state that is purely view/panel/window management
- move to Rust core:
  - durable session/domain state
  - export planning and quality policy
  - overlay/timeline/editor rules that are not tied to AppKit views
  - shared statistics schema semantics and replay/projection rules

The rule of thumb is simple: if Windows/Linux would need the same behavior, it should be in Rust core, not in the macOS app.

## Migration Plan

### Phase 1: Normalize the boundary

- Introduce rich Rust enums and error types in `vivyshot-core`.
- Stop using raw ABI numeric tags inside core internals.
- Add new core session/domain structs without deleting FFI APIs yet.
- Add core tests first, before moving behavior.

Exit criteria:

- core has typed representations for track kind, stitch side, export target, annotation kind, and similar concepts.

### Phase 2: Move the document engine

- Move `VsCommand`, `vs_document`, dirty-region logic, annotation transforms, and render/effect code into `vivyshot-core`.
- Keep `vs_*` document exports, but have them wrap `core::document::Document`.
- Move text/font strategy out of FFI:
  - either temporary embedded fallback in core, or
  - core-owned font provider abstraction.

Exit criteria:

- `vivyshot-ffi/src/document.rs` becomes a thin wrapper file.

### Phase 3: Move the timeline engine

- Move `VsTimeline`, `TimelineTrack`, `TimelineClip`, `ClipData`, `TimelineAction`, and queries/history into `vivyshot-core`.
- Reuse existing pure timeline helpers as internal rules.
- Keep FFI exports as wrappers over a core `Timeline`.

Exit criteria:

- timeline behavior exists once, in core, with direct Rust tests independent of ABI.

### Phase 4: Move session models and codecs

- Move video session state and snapshot serde into core.
- Move stitch session state into core.
- Move stats snapshot serde into core.
- Move BGRA encode logic into core codec module.

Exit criteria:

- `vivyshot-ffi` no longer depends on owning session state or JSON schemas.

### Phase 5: Clean the ABI surface

After the internal move is complete, do one explicit ABI review.

Recommended cleanup targets:

- remove or relocate host-specific helpers like `vs_normalize_key_token`;
- rename ABI structs/functions that still reflect old internal shapes;
- regenerate `ffi/vivyshot_core.h`;
- update Swift wrappers and contract tests together.

Given the project’s pre-1.0 policy, an intentional ABI break is acceptable if it materially improves the long-term boundary. If the team wants lower host churn, phases 1-4 can land first without changing the public C ABI shape.

### Phase 6: Move shared host logic from macOS into Rust core

After the FFI crate is thin, do one more pass against the macOS app to enforce the same ownership rule at the host boundary.

Move into `vivyshot-core`:

- post-recording export policy:
  - output target selection rules
  - bitrate / quality / frame-rate / scale heuristics
  - overlay composition/layout rules that are portable
  - render-size / transform planning derived from recording metadata
- shared recording/session state that is currently encoded only in Swift but is not tied to AppKit
- shared statistics persistence semantics:
  - ledger event schema
  - replay ordering/rules
  - projection derivation rules

Keep in `macos/`:

- ScreenCaptureKit and AVFoundation capture execution
- permission prompts and accessibility integration
- save panels, clipboard, and filesystem location choice
- SQLite connection/file lifecycle if the storage engine remains host-owned

Design rule:

- core defines the domain schema and replay/projection behavior;
- host may still provide the concrete persistence backend and native media framework adapters.

Exit criteria:

- the macOS app contains no shared export heuristics that future hosts would need to duplicate;
- the macOS app contains no shared statistics schema/projection rules beyond concrete storage plumbing;
- shared recording/editor/export behavior is testable directly in Rust without AppKit/AVFoundation.

## Testing Strategy

### Core tests become primary

Add direct Rust tests for:

- `core::document`
- `core::timeline`
- `core::video::session`
- `core::stitch::session`
- `core::stats`
- `core::codec`

These should validate behavior without going through C ABI wrappers.

### FFI tests become contract-focused

Keep FFI tests for:

- null pointer behavior
- stale handle rejection
- buffer sizing and ownership
- ABI struct/status translation
- header compatibility expectations

This shrinks the FFI test suite from "behavior source of truth" to "interop contract gate."

## Acceptance Criteria

This refactor is complete when all of the following are true:

1. All stateful Rust engine types live in `vivyshot-core`.
2. `vivyshot-ffi` contains no rendering algorithm implementations.
3. `vivyshot-ffi` contains no timeline/document/session business rules beyond argument validation.
4. Platform-specific font and keycode policy is no longer embedded in the generic FFI layer.
5. Core types use typed enums/errors instead of ABI numeric tags.
6. FFI contract tests still pass.
7. Core subsystem tests exist for each moved engine.
8. `ffi/vivyshot_core.h` remains the integration boundary, but it reflects the refactored ownership model.
9. The macOS host is limited to UI, recording orchestration, and OS integration; portable product rules live in Rust core.

## Recommended First Moves

To maximize payoff and reduce risk, do the work in this order:

1. `document`
2. `timeline`
3. `video session`
4. `stitch session`
5. `stats snapshot + codec cleanup`
6. `macOS surface extraction for export/statistics policy`

Reason:

- `document.rs` and `timeline.rs` are the largest responsibility leaks and define the architecture direction.
- once those move, the FFI crate naturally collapses toward a thin adapter shape.

## Implementation Notes

- Keep the current two-crate workspace during the first pass. Do not split crates further until the ownership boundary is correct.
- Once the move is complete, consider whether `vivyshot-core` should be internally split into additional Rust crates such as `vivyshot-render` or `vivyshot-codec`. That decision should be driven by compile times and clear reuse seams, not by premature decomposition.
- Preserve the existing generated-header workflow with `./scripts/gen-ffi.sh`.
- Keep the Rust core MIT and the macOS host GPL-3.0-only. This refactor does not change the repo’s split license model.
