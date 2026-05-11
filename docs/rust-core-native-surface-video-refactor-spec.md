# Rust Core / Native Surface Video Refactor Spec

## Status

- Proposed
- Date: 2026-05-11
- Scope: macOS video recording, post-recording review, overlay preview, and export architecture.
- Related:
  - `AGENTS.md`
  - `docs/rust-core-ffi-refactor-spec.md`
  - `docs/video-editor-spec.md`
  - `docs/post-recording-export-options-spec.md`
  - `docs/pro-preview-and-export-trial-spec.md`
  - `macos/Sources/App/Features/Capture/VideoCaptureComponents.swift`
  - `macos/Sources/App/Features/Capture/VideoCaptureUI.swift`
  - `macos/Sources/App/Interop/RustCore/`
  - `vivyshot-rs/crates/vivyshot-core/`
  - `vivyshot-rs/crates/vivyshot-ffi/`

## 1. Problem Statement

VivyShot's stated architecture is:

1. Rust-first capture and editing core.
2. Stable C ABI boundary.
3. Native host surfaces that provide UI and platform capabilities.

For screenshots, geometry, statistics, and parts of stitching, the macOS app already follows this direction reasonably well.

For video recording and post-recording export, the current architecture only partially follows it. Swift owns the current shipping video project model, overlay model, preview composition rules, export gating, and much of the compositor/export loop. Rust provides useful helper decisions and session wrappers, but the macOS video flow does not consistently treat Rust as the source of truth.

This creates a multi-surface risk:

1. Future Windows/Linux surfaces would need to duplicate Swift's video project/export behavior.
2. Preview and export behavior can drift because they are computed in separate Swift paths.
3. Rust timeline/video APIs exist but are underused by the shipping post-recording flow.
4. The product has two architectural styles at once: Rust-owned screenshot editing and Swift-owned video editing/export.

The goal of this refactor is not to make Rust call macOS media APIs. The goal is to make Rust own the portable video product state and decisions while Swift remains the native surface that executes macOS-specific capture, preview, rendering, and file operations.

## 2. Decision

Perform one focused architecture refactor:

1. Move portable video product logic from Swift into `vivyshot-core`.
2. Keep `vivyshot-ffi` as a thin C ABI adapter.
3. Keep macOS Swift as the native capability and UI surface.
4. Make preview and export query the same Rust project/render-plan state.
5. Do not transport raw video frames through FFI.

Short rule:

```text
Swift owns native capabilities and pixels.
Rust owns portable product state and decisions.
```

## 3. Current Findings

### 3.0 Relationship To Existing Specs

This spec is an architecture correction for the current post-recording video path.

It does not discard the product decisions in the older specs. It changes where those decisions should live:

1. `docs/post-recording-export-options-spec.md` intentionally kept review-window export options local for a smaller v1. That was a useful product slice, but the long-term source of truth should now move to Rust.
2. `docs/pro-preview-and-export-trial-spec.md` defines the preview-first commercial model and one successful free Pro export. Those rules still stand, but `ProExportRequirement` should be derived by Rust from project/export state rather than by Swift from `PostRecordingProject`.
3. `docs/video-editor-spec.md` already says Rust owns project/timeline truth and Swift must not keep divergent timeline copies. This spec applies that same rule to the existing post-recording review/export flow before the full editor exists.

### 3.1 What Already Aligns

The current code has several strong Rust-first surfaces:

1. Screenshot annotation creates a `RustDocumentSession` and sends edits through Rust:
   - `RegionSelectionOverlay+Annotation.swift`
   - `RustDocumentSession.swift`
   - `vivyshot-rs/crates/vivyshot-core/src/document.rs`
2. Geometry conversion and selection math are bridged through Rust:
   - `RustCoreBridge.viewRectToImageRect(...)`
   - `RustCoreBridge.imageRectToViewRect(...)`
   - `RustCoreBridge.resizeRect(...)`
   - `RustCoreBridge.clampPanOffset(...)`
3. Statistics aggregation is Rust-backed while storage remains native SQLite:
   - `CaptureStatisticsStore.swift`
   - `RustStatsSession.swift`
   - `vivyshot-rs/crates/vivyshot-core/src/stats.rs`
4. Timeline primitives are now core-backed through FFI:
   - `RustTimelineSession.swift`
   - `vivyshot-rs/crates/vivyshot-core/src/timeline.rs`
   - `vivyshot-rs/crates/vivyshot-ffi/src/timeline.rs`
5. Rust video helpers already own some useful policy:
   - export container preference
   - export preset selection
   - file length estimate
   - composition transform
   - GIF frame timing
   - key overlay fallback layout
   - click normalization and duplicate checks

Key token display normalization is currently Rust FFI-backed, but it is still host/platform-shaped. Portable core should only own key display semantics after macOS `NSEvent` data is converted into a platform-neutral key event model.

These pieces should be preserved and extended.

### 3.2 What Does Not Align

The current macOS video flow is Swift-owned in the areas that should become portable:

1. `VideoCaptureCoordinator` creates a `RustVideoSession`, but the session is not used as the source of truth for the post-recording project or export plan.
2. `PostRecordingProject` is a Swift struct that owns the durable in-memory project state used by review and export.
3. `VideoExportOverlayConfiguration` is a Swift struct that owns webcam/key overlay settings, events, and placement changes.
4. `PostRecordingOverlayPreviewLayer` computes preview overlay rects, visible keystroke windows, and placement state in Swift.
5. `PostRecordingProjectExporter` computes and renders composited export frames in Swift.
6. Preview and export each implement their own placement lookup and keystroke visibility rules.
7. `RustTimelineSession` exists but is not wired into the post-recording video flow.
8. `RustVideoSession.exportPlan()`, `setExportContext(...)`, and JSON serialization exist but are not used by the app outside the wrapper.
9. `ProExportRequirement.evaluate(...)` is Swift-owned and derives product gating from Swift project structs.
10. `VideoWebcamOverlayAspectRatioOption.constrainedFrame(...)`, normalized placement clamping, and overlay size defaults are Swift-owned even though they affect exported output.
11. Mouse click highlights are ambiguous: macOS can bake click rendering through ScreenCaptureKit, while click events are also recorded into Swift project state. The Rust project model must decide whether clicks become render-plan items or source-baked metadata.
12. Circle webcam geometry is inconsistent: capture-time placement can force a square frame for circles, but post-recording preview/export apply the stored aspect-ratio option directly.
13. Preview and export use different coordinate mappings. Preview maps normalized Y into a SwiftUI/AppKit view rectangle with inversion; export denormalizes directly into CoreGraphics render space.
14. The current post-recording action model has no `Edit Video` path yet, while the editor spec expects a Rust-owned project/timeline. The new post-recording project must be the editor seed, not a second project model.

### 3.3 Code Evidence Snapshot

The strongest evidence that the current architecture is split incorrectly is the recording handoff:

1. `VideoCaptureCoordinator` creates `rustVideoSession` during recording startup.
2. On stop, key and click events are added to that Rust session.
3. The session is then set to `nil`.
4. A new Swift `PostRecordingProject` is built from Swift structs and arrays.

Current code references:

1. `macos/Sources/App/Features/Capture/VideoCaptureComponents.swift:23` stores `private var rustVideoSession: RustVideoSession?`.
2. `macos/Sources/App/Features/Capture/VideoCaptureComponents.swift:94` creates the Rust video session.
3. `macos/Sources/App/Features/Capture/VideoCaptureComponents.swift:243` and `:248` add key/click events into Rust.
4. `macos/Sources/App/Features/Capture/VideoCaptureComponents.swift:269` clears `rustVideoSession`.
5. `macos/Sources/App/Features/Capture/VideoCaptureComponents.swift:272` creates `PostRecordingProject` after the Rust session has been discarded.
6. `macos/Sources/App/Features/Capture/VideoCaptureComponents.swift:699` defines `PostRecordingProject`.
7. `macos/Sources/App/Features/Capture/VideoCaptureComponents.swift:725` defines `VideoExportOverlayConfiguration`.

Duplicated preview/export rules:

1. Preview normalizes and denormalizes overlay frames in `VideoCaptureUI.swift:833`.
2. Preview applies webcam aspect constraints in `VideoCaptureUI.swift:847`.
3. Preview looks up placement keyframes in `VideoCaptureUI.swift:858`.
4. Preview filters visible keystrokes with a 1.35 second window and suffix count in `VideoCaptureUI.swift:874`.
5. Export repeats placement lookup in `VideoCaptureComponents.swift:2080`.
6. Export repeats the 1.35 second keystroke visibility window and suffix count in `VideoCaptureComponents.swift:1994`.
7. Export applies webcam aspect constraints in `VideoCaptureComponents.swift:1955`.
8. Preview maps normalized Y with inversion in `VideoCaptureUI.swift:839`, while export denormalizes without that inversion in `VideoCaptureComponents.swift:2091`.
9. Capture-time circle placement has shape-aware sizing, but preview/export apply the raw aspect-ratio option in `VideoCaptureUI.swift:851` and `VideoCaptureComponents.swift:1955`.

Mouse click ambiguity:

1. Mouse click events are recorded into Rust and Swift state in `VideoCaptureComponents.swift:248` and `:281`.
2. The compositor currently draws webcam and keystroke overlays, but not click overlays, in `VideoCaptureComponents.swift:1919` and `:1935`.
3. Core export planning accepts click event counts, but click counts do not currently drive `overlay_item_count` or compositor selection in `vivyshot-core/src/video.rs:27`.

Existing Rust surfaces that are useful but not yet authoritative:

1. `RustVideoSession` exposes export-plan, export-context, serialization, and deserialization wrappers in `RustVideoSession.swift:86`, `:118`, and `:129`.
2. A search of `macos/Sources/App` shows those video-session export-plan and serialization methods are not used outside the wrapper.
3. `vivyshot-core/src/video.rs:16` computes a portable `VideoExportPlan`.
4. `vivyshot-core/src/video.rs:90` derives export decisions for MP4/GIF targets.
5. `vivyshot-ffi/src/video.rs:17` still defines the stateful `vs_video_session`, so video session state has not fully moved into core.
6. `RustTimelineSession` exists, but a search of `macos/Sources/App` only finds construction through `RustCoreBridge.makeTimelineSession`; it is not part of the post-recording review/export path.
7. Key token normalization helpers exist in `vivyshot-ffi/src/video.rs`, but should not be moved unchanged into portable core because the current helper is platform-shaped.

### 3.4 Current FFI/Core Gaps

The older `docs/rust-core-ffi-refactor-spec.md` called out that FFI owned too much state. The current repository has improved in some areas:

1. `document.rs` in FFI now wraps `vivyshot_domain::Document`.
2. `timeline.rs` in FFI now wraps `vivyshot_domain::Timeline`.
3. `stats.rs` in FFI wraps `DomainCaptureStatisticsSession`.

Remaining gaps:

1. `vivyshot-ffi/src/video.rs` still owns `vs_video_session`, key/click event storage, trim state, export context state, and snapshot JSON.
2. `vivyshot-ffi/src/stitch.rs` still owns `vs_stitch_session`, working image state, last-frame state, direction lock, expected rows, and segment count.
3. `vivyshot-core/src/video.rs` owns planning helpers, but not a durable post-recording project/session domain.
4. Rust has no single API that answers "what should be visible at time T for this project and render size?"

## 4. Target Ownership Model

### 4.1 Swift macOS Surface Owns

Swift remains responsible for:

1. ScreenCaptureKit setup and recording.
2. AVCapture camera/microphone sessions.
3. AVFoundation playback surfaces.
4. Permission prompts and TCC behavior.
5. Native windows, toolbars, sheets, menus, and SwiftUI/AppKit views.
6. Save/open panels and sandbox-scoped file access.
7. Native file paths and temporary working directories.
8. Actual `AVAssetReader`, `AVAssetWriter`, `AVAssetExportSession`, `CGContext`, and `AVPlayer` execution.
9. Converting native media metadata and input events into FFI-safe Rust calls.
10. Drawing pixels when Rust returns render instructions.

### 4.2 Rust Core Owns

Rust owns portable video product state and decisions:

1. Post-recording project/session model.
2. Timeline tracks, clips, overlays, and visibility.
3. Platform-neutral key event and click event storage and validation.
4. Webcam overlay placement changes.
5. Keystroke overlay placement changes.
6. Text overlay clips.
7. Trim ranges.
8. Export target/options model.
9. Pro export requirement derivation.
10. Preview/export render-plan parity.
11. Per-time overlay visibility.
12. Overlay placement normalization and aspect-ratio clamping.
13. Overlay layout decisions that must match across platforms.
14. Export plan derivation: passthrough vs compositor, audio inclusion, webcam inclusion, GIF intermediate requirements.
15. Persistence snapshots for portable project state.

### 4.3 FFI Owns

`vivyshot-ffi` owns only C ABI concerns:

1. Opaque handle lifecycle.
2. Pointer and length validation.
3. Conversion between C structs and core Rust structs.
4. Output buffer ownership.
5. Status-code mapping.
6. Header generation compatibility.

It must not own video or stitch state machines long-term.

## 5. Non-Goals

This refactor does not require:

1. Porting ScreenCaptureKit or AVFoundation to Rust.
2. Moving raw video frame transport through FFI.
3. Replacing native SwiftUI/AppKit preview UI.
4. Rewriting the paywall UI.
5. Implementing the full multi-track video editor in one pass.
6. Preserving internal Swift structs for compatibility.

VivyShot is pre-1.0, so internal data shapes, ABI shapes, and Swift bridge names may break if it produces a cleaner long-term architecture.

## 6. Target Data Model

Add a Rust-owned post-recording project model. This can initially be a lighter project than the full editor project from `docs/video-editor-spec.md`, but it must be shaped to evolve into that editor project instead of becoming a parallel model.

Suggested core model:

```rust
pub struct VideoProject {
    pub source: VideoSource,
    pub timeline: Timeline,
    pub overlays: OverlaySet,
    pub recording: RecordingMetadata,
}

pub struct VideoSource {
    pub duration_ms: u32,
    pub width: u32,
    pub height: u32,
    pub frame_rate: u32,
    pub has_audio: bool,
    pub has_webcam_asset: bool,
}

pub struct OverlaySet {
    pub key_events: Vec<KeyOverlayEvent>,
    pub click_events: Vec<ClickOverlayEvent>,
    pub webcam: Option<WebcamOverlay>,
    pub keystroke: KeystrokeOverlay,
    pub text_clips: Vec<TextOverlayClip>,
}

pub struct WebcamOverlay {
    pub shape: WebcamShape,
    pub aspect_ratio: OverlayAspectRatio,
    pub placement: Vec<OverlayPlacementKeyframe>,
}

pub struct KeystrokeOverlay {
    pub style: KeystrokeStyle,
    pub size: KeystrokeSize,
    pub placement: Vec<OverlayPlacementKeyframe>,
}

pub struct OverlayPlacementKeyframe {
    pub timestamp_ms: u32,
    pub frame: NormalizedRect,
}
```

Rules:

1. Rust project stores media references as opaque asset IDs or host-provided handles/paths, not as platform media objects.
2. Rust state must not depend on `AVAsset`, `NSImage`, `URL`, `NSColor`, or Swift enum raw values.
3. Swift can maintain a short-lived UI snapshot, but every product mutation goes through Rust.
4. Swift can cache native players/image generators, but those caches are not project truth.
5. Click events must be classified explicitly as either render-plan overlay items or source-baked/native metadata. The decision must live in Rust so future hosts do not infer different behavior.
6. The post-recording `VideoProject` must reuse or wrap the editor `Timeline` and leave room for asset references, project settings, transitions, image clips, easing/zoom envelopes, and project persistence.

## 7. Render Plan API

The key new API is a Rust render-plan query.

Swift should ask Rust:

```text
Given project, target, render size, and time:
what should be included and where?
```

Example FFI-level shape:

```c
typedef struct vs_video_render_plan_query {
  uint32_t time_ms;
  uint32_t render_width;
  uint32_t render_height;
  uint8_t target;
} vs_video_render_plan_query;

typedef struct vs_video_render_item {
  uint8_t kind;
  float x;
  float y;
  float width;
  float height;
  float opacity;
  uint32_t style_flags;
  uint32_t text_offset;
  uint32_t text_len;
  uint32_t asset_id;
} vs_video_render_item;

int32_t vs_video_project_render_plan(
  const void *project,
  struct vs_video_render_plan_query query,
  struct vs_video_render_item *out_items,
  uint32_t out_cap,
  uint32_t *out_written
);
```

The exact C shape may differ, but the semantic contract must hold:

1. Preview and export call the same Rust render-plan logic.
2. Swift executes platform rendering from returned items.
3. Rust decides item visibility, placement, target inclusion, and portable style tokens.
4. Swift decides how to draw a returned item using AppKit/CoreGraphics/AVFoundation.
5. Render-plan rectangles are expressed in project render coordinates with an explicit origin and unit.
6. Initial contract: pixel coordinates in target render space, origin at the top-left, X increasing right, Y increasing down, width/height in pixels.
7. Swift preview/export adapters may transform those coordinates for SwiftUI/AppKit/CoreGraphics, but they must not reinterpret placement or visibility.

## 8. Export Plan API

Rust must own export plan derivation from the project and options.

Required decisions:

1. Does target require a compositor?
2. Does GIF require an intermediate composited video?
3. Should source audio be included?
4. Should webcam asset be included?
5. Which overlay item counts are active?
6. Is the output free or Pro-gated?
7. Which Pro reasons apply?
8. What is the normalized trim range?
9. What is the GIF frame plan?
10. Which frame times should be sampled?

Existing Rust helpers can remain building blocks:

1. `compute_video_export_plan`
2. `derive_video_export_decision`
3. `build_gif_export_plan`
4. `gif_frame_time_ms`
5. `best_video_export_preset`
6. `estimated_video_file_length_limit`
7. `post_recording_video_composition_plan`

But Swift should stop independently deciding the same product rules.

## 9. Pro Export Gate Ownership

`ProExportRequirement.evaluate(...)` currently lives in Swift and reads Swift project structs.

Move the portable requirement derivation to Rust:

```rust
pub enum ProExportReason {
    WebcamOverlay,
    KeystrokeOverlay,
    MicrophoneAudio,
    GifExport,
    HevcExport,
    SixtyFps,
    HighQuality,
    HighBitrate,
    BakedTransition,
}

pub struct ProExportRequirement {
    pub reasons: Vec<ProExportReason>,
}
```

Swift remains responsible for:

1. Displaying localized reason titles.
2. Showing trial/paywall UI.
3. Reading StoreKit paid access.
4. Persisting local trial consumption.

Rust owns:

1. Which reasons apply for a project, options, and target.
2. Whether a requested output contains export-bearing Pro value.

## 10. Preview/Export Parity Rules

The current code has separate Swift calculations for preview and export.

Replace them with these rules:

1. For any `(project, target, render_size, time_ms)`, Rust returns the same render item set regardless of whether the host is previewing or exporting.
2. Host-specific rendering may differ in implementation, but not in item selection, placement, timing, or style identity.
3. Placement lookup is Rust-owned.
4. Keystroke visibility window is Rust-owned.
5. Overlay aspect-ratio constraints are Rust-owned.
6. Default/fallback overlay rects are Rust-owned.
7. Export and review preview must both respect timestamped placement changes.

Swift preview and export can still use different native primitives:

1. Preview can use `AVPlayer`, `AVPlayerLayer`, SwiftUI, and AppKit views.
2. Export can use `AVAssetImageGenerator`, `AVAssetWriter`, `CGContext`, and `AVAssetExportSession`.

Both paths must use Rust render-plan decisions.

## 11. Phased Work Plan

### Phase 1: Move Shared Overlay Policy Into Rust

Move these from Swift into `vivyshot-core`:

1. `VideoCaptureOverlayState.normalizedFrame(...)`.
2. `VideoWebcamOverlayAspectRatioOption.constrainedFrame(...)`.
3. Webcam circle/aspect-ratio square enforcement.
4. Keystroke visible-event selection and suffix count.
5. Placement keyframe lookup by timestamp.
6. Keystroke overlay fallback rect calculation.
7. Click overlay policy, or an explicit source-baked click metadata policy if clicks remain native-rendered.

Shape-aware webcam constraints must override stored aspect-ratio options. A circle webcam render item is always square in project/render-plan space.

Add tests for:

1. invalid/empty normalized frame fallback.
2. aspect-ratio clamping inside render bounds.
3. circle webcam always square.
4. placement lookup before, at, between, and after keyframes.
5. keystroke visibility at exact cutoff thresholds.
6. preview/export render-plan parity for a sample project.
7. circle webcam parity across capture, preview, and export.
8. click event policy for render-plan or source-baked metadata behavior.

### Phase 2: Add Rust Video Project Session

Create a core-owned session:

```text
vivyshot-rs/crates/vivyshot-core/src/video/project.rs
vivyshot-rs/crates/vivyshot-core/src/video/render_plan.rs
vivyshot-rs/crates/vivyshot-core/src/video/pro_gate.rs
```

Expose through FFI:

1. `vs_video_project_create_from_recording(...)`
2. `vs_video_project_destroy(...)`
3. `vs_video_project_add_key_event(...)`
4. `vs_video_project_add_click_event(...)`
5. `vs_video_project_set_webcam_overlay(...)`
6. `vs_video_project_push_webcam_placement(...)`
7. `vs_video_project_set_keystroke_overlay(...)`
8. `vs_video_project_push_keystroke_placement(...)`
9. `vs_video_project_render_plan(...)`
10. `vs_video_project_export_plan(...)`
11. `vs_video_project_pro_requirement(...)`
12. `vs_video_project_serialize_json(...)`
13. `vs_video_project_deserialize_json(...)`

Deprecate or merge the current `RustVideoSession` wrapper once `RustVideoProjectSession` exists.

The post-recording `VideoProject` must be a constrained editor project seed. It should not block the full editor from adding transitions, image clips, easing curves, zoom envelopes, project settings, and persistence without another model migration.

### Phase 3: Rewire macOS Post-Recording Flow

Replace Swift-owned durable project state with a Rust-backed session:

1. `VideoCaptureCoordinator` creates a Rust project after recording stops.
2. Input events are added directly to the project.
3. Webcam and keystroke placement changes are added directly to the project.
4. `PostRecordingActionPanel` receives a `RustVideoProjectSession` plus native asset URLs.
5. Swift UI reads project snapshots for display.
6. Mutations flow to Rust first, then Swift refreshes snapshots.

Temporary native values that can remain in Swift:

1. screen recording URL.
2. webcam recording URL.
3. loaded thumbnail.
4. cached video size from `AVAsset`.
5. active `AVPlayer` and image generators.

### Phase 4: Rewire Preview And Export To Render Plan

Change:

1. `PostRecordingOverlayPreviewLayer`
2. `PostRecordingProjectExporter.drawCompositedFrame(...)`
3. `drawWebcamOverlay(...)`
4. `drawKeystrokeOverlay(...)`

Target:

1. Both preview and export ask Rust for render items.
2. Swift draws those items.
3. Swift no longer computes visibility windows or placement lookup.
4. Swift no longer derives Pro feature reasons.
5. Swift no longer decides independently whether click events are overlay render items or native/source-baked metadata.

### Phase 5: Fold Into Editor Architecture

Once post-recording project state is Rust-owned, wire it into the future editor project from `docs/video-editor-spec.md`.

Rules:

1. Do not build a second Rust model for the full editor if post-recording model can evolve into it.
2. The post-recording project can be a constrained editor project seeded from a capture.
3. `Edit Video` should open the same Rust project session, not convert from a Swift project.
4. Any short-term post-recording API must leave room for asset refs, project settings, transitions, image clips, easing/zoom envelopes, and project persistence from the editor spec.

## 12. File-Level Target Changes

### Rust

Suggested additions:

```text
vivyshot-rs/crates/vivyshot-core/src/video/
  mod.rs
  project.rs
  render_plan.rs
  overlay.rs
  pro_gate.rs
  export_plan.rs

vivyshot-rs/crates/vivyshot-ffi/src/video_project.rs
vivyshot-rs/crates/vivyshot-ffi/src/ffi/video_project.rs
```

Suggested migrations:

1. Move `vs_video_session` state from FFI to core or replace it with `VideoProject`.
2. Move stitch session state from FFI to core in a separate follow-up if not included here.
3. Keep `ffi/video.rs` and `ffi/domain.rs` as type-conversion modules.

### Swift

Suggested additions:

```text
macos/Sources/App/Interop/RustCore/RustVideoProjectSession.swift
macos/Sources/App/Interop/RustCore/RustVideoProjectTypes.swift
```

Suggested changes:

1. `VideoCaptureComponents.swift`
   - replace `PostRecordingProject` as product truth with `RustVideoProjectSession`.
   - keep native asset URL container separately if needed.
   - remove Swift placement lookup and export product decisions.
2. `VideoCaptureUI.swift`
   - preview overlays query Rust render plan.
   - Pro requirement queries Rust.
3. `AppSettings.swift`
   - settings may still persist user defaults, but exported-output normalization should be delegated to Rust project creation/update.
4. `CaptureMode.swift`
   - Swift enums remain UI labels and controls.
   - portable numeric mapping moves through explicit bridge conversion.

## 13. ABI Policy

Because VivyShot is pre-1.0, the project may break ABI shapes if doing so creates a better architecture.

Still required:

1. Regenerate `ffi/vivyshot_core.h` with `./scripts/gen-ffi.sh` for ABI changes.
2. Add FFI contract tests for every new exported function.
3. Keep handle lifecycle tests for create/destroy/null-pointer behavior.
4. Use explicit versioned JSON snapshots for project persistence.
5. Keep C structs simple and allocation ownership obvious.

## 14. Testing Requirements

### Rust Unit Tests

Add tests for:

1. project creation from recording metadata.
2. overlay placement normalization.
3. aspect-ratio and circle constraints.
4. key/click event insertion validation.
5. render-plan item ordering.
6. render-plan item visibility over time.
7. Pro requirement derivation.
8. export plan derivation.
9. JSON snapshot round-trip.
10. invalid snapshot rejection.

### FFI Contract Tests

Add tests for:

1. project handle lifecycle.
2. buffer-too-small behavior for snapshots/render-plan arrays.
3. null pointer handling.
4. invalid enum handling.
5. render-plan parity between two equivalent project creation paths.

### macOS Tests

Where feasible:

1. wrapper tests for Swift enum-to-FFI mapping.
2. UI preview smoke tests with fixed Rust render-plan snapshots.
3. export path smoke tests that assert Swift calls render-plan API instead of local placement functions.

## 15. Migration Rules

1. Do not keep a long-lived Swift `PostRecordingProject` and Rust `VideoProject` in parallel.
2. During migration, Swift may have lightweight view snapshots, but Rust must be the mutation target.
3. If Swift needs cached native values, name them as native cache or native assets, not project state.
4. Remove unused Rust wrappers after the new session is live.
5. Remove duplicated Swift placement/visibility helpers once Rust render-plan is live.
6. Keep each phase shippable and verifiable.

## 16. Success Criteria

The refactor is complete when:

1. Post-recording review is backed by a Rust project/session.
2. Preview and export use the same Rust render-plan query.
3. Pro export requirement derivation is Rust-owned.
4. Swift no longer owns durable overlay placement/event state after project creation.
5. Swift no longer has separate preview/export overlay timing rules.
6. `RustTimelineSession` or its successor is part of the real post-recording/editor path.
7. Future Windows/Linux hosts can reuse the same Rust project/export decisions and only implement native capture/render/file surfaces.

## 17. Explicit Boundary Examples

### Good Swift Logic To Keep

1. Requesting camera permission before opening a webcam device.
2. Selecting an `AVCaptureDevice`.
3. Configuring `SCStreamConfiguration`.
4. Creating an `NSSavePanel`.
5. Playing a preview with `AVPlayerView`.
6. Drawing a Rust-provided webcam item into a `CGContext`.
7. Showing localized paywall copy from Rust-provided reason codes.

### Logic To Move To Rust

1. "At this timestamp, which keystrokes are visible?"
2. "Where is the webcam overlay at this timestamp?"
3. "Does this export require Pro and why?"
4. "Does this project require a custom compositor?"
5. "Should audio be included?"
6. "What are the render items for this frame?"
7. "How should a normalized overlay frame be clamped?"
8. "How should a circle webcam overlay force square geometry?"
9. "What is the project snapshot schema?"
10. "Are mouse clicks render-plan overlay items, or are they source-baked/native metadata?"

## 18. Open Questions

1. Should key token normalization remain in Rust or move to a platform input mapping layer?
   - Current practical answer: keep macOS event interpretation in Swift/platform input code. Rust may own display normalization only after the host passes a platform-neutral key event.
2. Should Pro export requirement live in `video` or a separate `commerce` module?
   - Current practical answer: keep it in `video` because reasons depend on export-bearing media content.
3. Should the post-recording project immediately reuse `Timeline`, or start as `VideoProject` wrapping a `Timeline`?
   - Current practical answer: wrap a `Timeline` so post-recording flow can become the editor seed path.
4. Should stitch session state move in this same refactor?
   - Current practical answer: document the gap, but keep this spec focused on video unless the implementation naturally touches stitch.
