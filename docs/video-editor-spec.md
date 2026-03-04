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

## 12. Implementation Notes for Current Repo

1. `VideoEditorWindowController` was removed and must be replaced with a new generic editor surface aligned to this spec.
2. Existing Rust timeline/session work remains valid foundation and should be reused.
3. Existing post-record panel remains the handoff point and must keep `Edit Video` as a first-class action.
