# VivyShot Video Editor Spec (Production Baseline)

- Status: Active Draft
- Date: 2026-03-04
- Owner: VivyShot
- Replaces: `docs/video-gif-recorder-spec.md`

## 1. Product Direction

VivyShot video flow must support:

1. A post-recording window with an explicit `Edit Video` action.
2. A reusable editor that can open both:
   - from post-recording flow
   - from app toolbar/menu as a standalone compositor
3. Basic but production-ready timeline editing from day one:
   - video clips
   - audio clips
   - text clips
   - image/screenshot clips
   - transitions
   - zoom
   - trim

No placeholder UI, stub actions, or "coming soon" controls in the shipped scope.

## 2. Locked Product Decisions

### 2.1 Post-Recording Window

After recording stops, open a post-recording action window with:

1. `Save as MP4`
2. `Save as GIF`
3. `Edit Video`

`Edit Video` must always open the editor reliably and is the primary path for edited export.

### 2.2 Generic Editor Entry

Editor is a generic project editor, not a one-off trim popup.

It must support:

1. Opening a fresh empty project from toolbar/menu.
2. Opening a project seeded by a newly recorded clip.
3. Manual track creation and manual media insertion.

### 2.3 Timeline Model Choice

Use **lane-based multi-track timeline** (DAW / Final Cut style), not one-line storyboard.

Rationale:

1. User explicitly wants manual track composition.
2. Video/audio/text/image tools require independent per-track controls.
3. Transitions are cleaner when clips are first-class items in lanes.
4. This model scales without re-architecture when features grow.

## 3. UX Specification

### 3.1 Editor Layout (Final Cut Inspired)

Desktop layout:

1. Left: preview monitor.
2. Right: inspector pane.
3. Bottom: multi-track timeline.

Inspector behavior:

1. If clip/track selected: show type-specific controls.
2. If nothing selected: show project controls (`background`, `aspect ratio`, `resolution`, `frame rate`, default transition).

### 3.2 Liquid Glass Requirement

Editor chrome uses Liquid Glass styling where platform APIs permit.

Apply Liquid Glass to:

1. Toolbar shell and segmented controls.
2. Inspector cards/panels.
3. Timeline top controls.
4. Context menus and lightweight overlays.

Implementation rule set:

1. On `macOS 26.0+`, use native Liquid Glass APIs (`GlassEffectContainer`, `.glassEffect(...)`, `.buttonStyle(.glass/.glassProminent)`).
2. Apply `.glassEffect(...)` after layout/shape/background modifiers so visuals stay consistent.
3. Use interactive glass only for controls users can click/drag.
4. Fallback on lower versions must use material-based surfaces (`.ultraThinMaterial` / bordered controls), not custom shader blur.

Do not apply heavy glass blur to timeline content lanes or preview raster itself; keep content readable and performant.

### 3.3 Core Interaction

1. Space: play/pause.
2. `I` / `O`: set in/out on selected clip or playhead context.
3. `Cmd+B`: split selected clip at playhead.
4. `Cmd+Z` / `Cmd+Shift+Z`: undo/redo.
5. Drag and drop media from Finder into timeline and media bin.
6. Snap-to-playhead and snap-to-adjacent-clip edges enabled by default.
7. Clip edge drag must perform trim/resize directly on timeline with frame-accurate feedback.
8. Track lanes must support height resize and timeline vertical zoom for dense projects.

## 4. Editing Scope (Production v1)

### 4.1 Track Types

Supported track kinds:

1. Video track.
2. Audio track.
3. Text track.
4. Image track (screenshots and still assets).

Each track has:

1. Visibility/mute toggles where relevant.
2. Lock toggle.
3. Reorder support.
4. Resizable lane height (small/medium/large and free drag within min/max limits).

### 4.2 Video Tools

1. Trim in/out.
2. Split clip.
3. Position/scale transform.
4. Zoom behavior via simple 2-keyframe transform per clip (`start`, `end`) with selectable interpolation curve.
5. Basic speed presets (`0.5x`, `1x`, `1.5x`, `2x`) are optional for first ship if stable; if omitted, UI must not expose speed.

### 4.3 Audio Tools

1. Trim/split.
2. Clip gain.
3. Mute.
4. Fade in/out with selectable curve (`linear`, `ease-in`, `ease-out`, `ease-in-out`).

### 4.4 Text Tools

1. Add text clip.
2. Edit text content.
3. Font family, size, color, background/border basics.
4. Text clip duration and timeline placement.

### 4.5 Screenshot/Image Tools

Image clips can be:

1. Imported image files.
2. Existing VivyShot screenshot exports.

Supported operations:

1. Duration control.
2. Transform/position.
3. Optional pan/zoom (same simple 2-keyframe model as video).

### 4.6 Transitions

Minimum transition set:

1. Cut (default).
2. Cross dissolve.
3. Dip to black.

Transitions are clip-boundary objects with explicit duration and no hidden automation.

### 4.7 Motion Curves and Easing

Easing curves are first-class settings for zoom and other animatable effects.

Minimum curve set:

1. `linear`
2. `ease-in`
3. `ease-out`
4. `ease-in-out`
5. `spring` (damped spring preset, deterministic sampling for export parity)

Rules:

1. Curves are stored in project data, not inferred from UI state.
2. Playback preview and exported output must use the same curve evaluation logic.
3. `spring` must expose bounded presets (for example `soft`, `medium`, `snappy`) instead of free-form physics values in v1.

## 5. Project Model and Architecture

### 5.1 Rust Core Ownership

Rust core remains source of truth for:

1. Timeline/project model.
2. Clip/track mutations.
3. Validation rules.
4. Undo/redo history.
5. Export plan derivation.

### 5.2 Swift Host Ownership

Swift host owns:

1. macOS windows and SwiftUI/AppKit presentation.
2. Playback preview and input handling.
3. Drag/drop UX and local file pickers.
4. Platform capture adapters and permission prompts.

### 5.3 FFI Boundary

FFI stays control-plane focused:

1. Create/open/close project session.
2. Add/remove/reorder tracks.
3. Add/remove/move/trim/split clips.
4. Update clip properties (transform/text/style/audio/easing).
5. Add/remove/update transition objects at clip boundaries.
6. Query timeline snapshots for UI render.
7. Build export plan.

No per-frame raw video transport over FFI.

## 6. Entry Flows

### 6.1 Post-Record -> Edit Video

1. Recorder finalizes source media into app-managed working location.
2. Post-recording window appears.
3. User taps `Edit Video`.
4. Editor opens with one seeded video track and one seeded clip.
5. Overlay metadata (clicks/keys/webcam) maps into project overlays if enabled.

### 6.2 Open Editor From Toolbar

1. User opens editor with no active recording.
2. Start with empty project template.
3. User imports media and builds timeline manually.

## 7. Export

Export targets:

1. MP4
2. GIF

Rules:

1. Export uses current timeline selection and track visibility.
2. Keep source assets untouched.
3. For GIF, enforce guardrails (`max duration`, `max dimension`) with clear UI messaging.
4. If codec path fails, deterministic fallback path is required, not silent failure.

## 8. Sandbox and Permissions (Mandatory)

The feature must work in sandboxed builds.

### 8.1 Entitlements and Access

1. App Sandbox enabled.
2. User-selected read/write for save/import/export.
3. Camera entitlement only if webcam feature is enabled.
4. Microphone entitlement only if mic recording is enabled.

### 8.2 TCC Handling

1. Screen recording permission for capture flow.
2. Camera/mic prompts only when required by toggles.
3. Accessibility/input monitoring only for keystroke overlay recording.
4. Graceful degradation on denial with actionable UI guidance.

### 8.3 File Strategy

1. Working media and cache in app container temp/cache.
2. Final exports only to explicit user-selected destination.
3. No hidden writes outside sandbox/container paths.

## 9. Reliability and Performance Targets

1. Editor open from post-record action: 95th percentile < 800 ms for 1080p clips.
2. Timeline interaction response (select, trim drag): target < 16 ms UI update.
3. No action in UI that can no-op silently.
4. Zero known stub controls in production UI.

## 10. Test and Release Gates

Release requires:

1. Unit tests for timeline mutation contracts (trim/split/transition insertion/track-lane resize metadata).
2. FFI contract tests for new editor-facing APIs.
3. UI integration tests for:
   - post-record `Edit Video` opens editor
   - toolbar open path
   - import -> edit -> export flow
   - clip edge trim drag updates duration correctly
   - track lane resize persists per project
4. Sandboxed smoke tests for capture, import, and export.
5. Repeatability test:
   - 50 open/edit/close cycles with stable memory trend.

## 11. Out of Scope For This Spec

1. Advanced color grading.
2. Complex keyframe curve editor.
3. Multi-cam sync editing.
4. Cloud collaboration/sharing.

## 12. Current Code Baseline (Audit: 2026-03-04)

### 12.1 Post-Recording Flow (Current)

Current capture/post-record code is in:

1. `macos/Sources/App/Features/Capture/VideoCaptureUI.swift`
2. `macos/Sources/App/Features/Capture/VideoCaptureComponents.swift`

Current behavior:

1. `PostRecordingAction` only has `.saveMP4` and `.saveGIF` (no `.editVideo`).
2. Post-record window buttons only expose `Save as MP4` and `Save as GIF`.
3. Closing the post-record window defaults to `.saveMP4`.
4. GIF quick-save path currently shows "temporarily unavailable" toast.

Conclusion: editor handoff is currently missing by design and must be reintroduced as first-class flow.

### 12.2 Editor Entry Points (Current)

Current menu bar app entry (`macos/Sources/App/Application/main.swift`) exposes:

1. `Capture Region`
2. `Settings…`
3. `Quit VivyShot`

There is no generic `Open Video Editor…` action and no active editor feature module under `macos/Sources/App/Features/`.

### 12.3 Rust Side Already Implemented (Reusable Now)

Reusable timeline/session APIs already exist:

1. Swift bridge:
   - `macos/Sources/App/Interop/RustCore/RustTimelineSession.swift`
   - `macos/Sources/App/Interop/RustCore/RustVideoSession.swift`
2. C ABI:
   - `ffi/vivyshot_core.h` (`vs_timeline_*`, `vs_video_*`)
3. Rust implementation:
   - `vivyshot-rs/crates/vivyshot-ffi/src/lib.rs`
   - `vivyshot-rs/crates/vivyshot-ffi/src/ffi/timeline.rs`
   - `vivyshot-rs/crates/vivyshot-core/src/lib.rs`

Capabilities already in place:

1. Track lifecycle: add/remove/reorder/show-hide.
2. Clip lifecycle: add/remove/move/resize/split.
3. Clip transform update.
4. Text clip content/style update.
5. Shape style update/read.
6. Zoom scale set/get (`ClipData::Zoom { scale }`).
7. Undo/redo.
8. Export context derivation and text clip export queries.
9. Timeline and FFI contract tests for split/text/export/zoom paths.

### 12.4 Rust Gaps vs Required Editor Scope

Missing for target editor:

1. No transition domain object (cut/dissolve/dip-to-black not modeled).
2. No easing curve model (`ease-*`, `spring`) persisted in timeline/project.
3. No image/screenshot clip kind in current track-kind enum.
4. No track metadata for lock/mute/name/lane height persistence.
5. No project-level persistence API for full editor document (timeline + assets + UI metadata).
6. Zoom model is scalar-only; no 2-keyframe envelope with interpolation.

### 12.5 Sandbox Baseline (Current)

1. Entitlements file currently exists at `macos/Config/VivyShot.entitlements` but is empty.
2. `Info.plist` is minimal and does not yet define media usage description keys.
3. Project already targets sandbox-capable packaging path, but required editor import/export entitlements are not yet configured.

## 13. Target Implementation Architecture

### 13.1 Ownership Split

1. Rust (`vivyshot-core` + `vivyshot-ffi`) owns project/timeline truth, mutation rules, validation, and deterministic export planning.
2. Swift (`macOS app`) owns windowing, playback preview, drag/drop/import/export UI, and sandbox/TCC orchestration.
3. Swift must not keep divergent timeline state copies; UI state derives from Rust snapshots.

### 13.2 Project Domain (Normative)

Editor project model must include:

```text
EditorProject {
  id: UUID
  video_info: { width, height, duration_ms, frame_rate }
  settings: { background, aspect_ratio, resolution_preset, default_transition }
  tracks: [Track]
  transitions: [Transition]
  assets: [AssetRef]
}

Track {
  id: u32
  kind: video | audio | text | image
  name: String
  visible: bool
  muted: bool            // audio tracks
  locked: bool
  lane_height_px: u16
  clips: [Clip]
}

Clip {
  id: u32
  track_id: u32
  kind: video | audio | text | image
  asset_id: u32?
  timeline_start_ms: u32
  timeline_end_ms: u32
  source_in_ms: u32
  source_out_ms: u32
  transform: { x, y, width, height, rotation, opacity }
  zoom: { start_scale, end_scale, curve }
  text_style: optional
  audio_style: optional
}

Transition {
  id: u32
  left_clip_id: u32
  right_clip_id: u32
  kind: cut | cross_dissolve | dip_to_black
  duration_ms: u32
  curve: linear | ease_in | ease_out | ease_in_out | spring_<preset>
}
```

Implementation constraints:

1. Keep existing track kind numeric assignments stable; add new `image` kind without re-numbering existing kinds.
2. Transition and curve values must be persisted as data, not recomputed from UI defaults.

## 14. Rust and FFI Work Plan (Concrete)

### 14.1 Extend Timeline Model in Rust

In `vivyshot-rs/crates/vivyshot-ffi/src/lib.rs`:

1. Extend `TimelineTrack` with `locked`, `muted`, `name`, `lane_height_px`.
2. Extend `ClipData` with `Image` payload and zoom envelope payload (`start_scale`, `end_scale`, `curve`).
3. Add `TimelineTransition` collection on timeline session.
4. Add undo/redo actions for:
   - transition add/remove/update
   - lane height update
   - track lock/mute/name changes
   - clip curve/zoom envelope updates

In `vivyshot-rs/crates/vivyshot-core/src/lib.rs`:

1. Add pure policy helpers for:
   - transition duration validation
   - clip-boundary transition eligibility
   - easing/spring preset normalization
   - curve sampling parity helpers for preview/export

### 14.2 FFI Surface Additions

Add new C structs/functions in `vivyshot-rs/crates/vivyshot-ffi/src/lib.rs`, export via `cbindgen.toml`, regenerate `ffi/vivyshot_core.h`:

1. Track metadata APIs:
   - `vs_timeline_set_track_locked`
   - `vs_timeline_set_track_muted`
   - `vs_timeline_set_track_name`
   - `vs_timeline_set_track_lane_height`
2. Clip motion/easing APIs:
   - `vs_timeline_set_clip_zoom_envelope`
   - `vs_timeline_get_clip_zoom_envelope`
3. Transition APIs:
   - `vs_timeline_add_transition`
   - `vs_timeline_remove_transition`
   - `vs_timeline_update_transition`
   - `vs_timeline_get_transitions`
4. Project persistence APIs:
   - `vs_timeline_serialize_project_json`
   - `vs_timeline_deserialize_project_json`

Compatibility requirement:

1. Existing `vs_timeline_*` and `vs_video_*` calls remain valid; new APIs are additive.

### 14.3 Rust Test Expansion

Add/extend tests in:

1. `vivyshot-rs/crates/vivyshot-ffi/tests/timeline_ffi_contract.rs`
2. `vivyshot-rs/crates/vivyshot-ffi/tests/property_geometry.rs` (for curve sampling determinism if needed)

Required new test cases:

1. transition create/update/remove + undo/redo.
2. invalid transition rejection (same clip, overlap violations, out-of-range duration).
3. zoom envelope + curve persistence round-trip.
4. lane height/lock/mute metadata persistence round-trip.
5. project JSON serialize/deserialize parity.

### 14.4 Rust File Split (Recommended)

Current timeline logic is concentrated in `vivyshot-rs/crates/vivyshot-ffi/src/lib.rs`.
For maintainability, split by domain responsibility:

```text
vivyshot-rs/crates/vivyshot-core/src/
  lib.rs                         // re-exports only
  timeline/
    mod.rs
    model.rs                     // Track/Clip/Transition data types
    validation.rs                // trim/split/transition/easing normalization rules
    easing.rs                    // curve + spring preset sampling
    export_context.rs            // derive export context helpers

vivyshot-rs/crates/vivyshot-ffi/src/
  lib.rs                         // extern "C" entrypoints + handle registry only
  timeline/
    mod.rs
    session.rs                   // VsTimeline struct + history stack
    tracks.rs                    // track ops (add/reorder/lock/mute/lane height)
    clips.rs                     // clip ops (add/move/resize/split/text/zoom envelope)
    transitions.rs               // transition CRUD and queries
    project_io.rs                // serialize/deserialize project JSON
```

Rule:

1. Keep `lib.rs` thin; move business logic into module files so ABI glue remains auditable.

## 15. macOS App Work Plan and File Split

### 15.1 New Feature Module

Create a new module under current structure:

```text
macos/Sources/App/Features/VideoEditor/
  Coordinator/VideoEditorCoordinator.swift
  Window/VideoEditorWindowController.swift
  Window/VideoEditorRootView.swift
  State/VideoEditorStore.swift
  State/VideoEditorSelection.swift
  State/VideoEditorCommands.swift
  Timeline/TimelineView.swift
  Timeline/TimelineRulerView.swift
  Timeline/TrackLaneView.swift
  Timeline/ClipBlockView.swift
  Timeline/TransitionBadgeView.swift
  Inspector/InspectorContainerView.swift
  Inspector/ProjectInspectorView.swift
  Inspector/ClipInspectorView.swift
  Preview/PreviewPlayerView.swift
  Toolbar/EditorToolbarView.swift
  Import/MediaImportController.swift
  Export/VideoEditorExportCoordinator.swift
  Project/VideoEditorProjectStore.swift
```

### 15.2 Interop Layer Additions

Under `macos/Sources/App/Interop/RustCore/`:

1. Add `RustEditorProjectSession.swift` (or extend `RustTimelineSession.swift`) to wrap new transition/curve/metadata/persistence FFI.
2. Keep `RustVideoSession.swift` for capture overlay metadata ingestion.
3. Keep `RustCoreBridge.swift` as creation factory and version/ABI gate.

### 15.3 Capture and Menu Wiring Changes

Update existing files:

1. `macos/Sources/App/Features/Capture/VideoCaptureUI.swift`
   - add `.editVideo` to `PostRecordingAction`
   - add `Edit Video` primary action button
   - remove implicit save-on-close default for editor flow
2. `macos/Sources/App/Features/Capture/VideoCaptureComponents.swift`
   - handle `.editVideo` by opening editor with seeded project
3. `macos/Sources/App/Application/main.swift`
   - add `Open Video Editor…` menu action for empty project entry
4. `macos/Sources/App/Application/StatusItemController.swift`
   - own/route generic editor open action

### 15.4 Liquid Glass Implementation Notes (macOS)

For editor chrome:

1. Group toolbar + inspector cards in `GlassEffectContainer` on macOS 26+.
2. Use `.glassEffect(... .interactive())` only on interactive controls.
3. Keep timeline lanes and preview content non-glass for readability and frame stability.
4. Provide strict fallback branch for < macOS 26 with material/bordered controls.

## 16. Sandbox and Permission Implementation Details

### 16.1 Entitlements

`macos/Config/VivyShot.entitlements` must include:

1. `com.apple.security.app-sandbox = true`
2. `com.apple.security.files.user-selected.read-write = true`
3. `com.apple.security.device.camera = true` (if webcam feature shipped)
4. `com.apple.security.device.microphone = true` (if mic feature shipped)

### 16.2 File Access Strategy

1. Imported assets are copied into app-managed project workspace to avoid stale external permissions during edit session.
2. External save/export uses explicit user destination via save panel.
3. For reopen support of external linked assets (future), security-scoped bookmarks are required.

### 16.3 Project Workspace Layout

```text
~/Library/Containers/<bundle-id>/Data/Library/Application Support/VivyShot/editor/
  projects/<project-id>/project.json
  projects/<project-id>/assets/<asset-id>.<ext>
  projects/<project-id>/cache/
```

## 17. Delivery Slices (No Stubs)

### Slice A: Wiring + Editor Shell

1. `Edit Video` opens editor from post-record reliably.
2. Menu opens empty editor project.
3. Timeline/preview/inspector shell loads real Rust-backed state.

### Slice B: Core Editing

1. Track create/reorder/lock/mute/lane-resize.
2. Clip add/move/trim/split.
3. Text/image import/edit basics.
4. Zoom envelope with easing presets.

### Slice C: Transitions + Export

1. Transition create/edit/remove (cut/dissolve/dip-to-black).
2. MP4 and GIF export from edited timeline with deterministic curve behavior.
3. Sandboxed import/export smoke tests green.

### Slice D: Hardening

1. Undo/redo robustness across all editor operations.
2. 50 open/edit/close memory trend test.
3. UI integration tests for both editor entry paths and trim/lane-resize persistence.
