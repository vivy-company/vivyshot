# VivyShot Paid Capture Overlays And Effects Spec

- Status: Superseded
- Date: 2026-05-05
- Owner: VivyShot
- Superseded by:
  - `docs/pro-preview-and-export-trial-spec.md`
- Related:
  - `docs/video-editor-spec.md`
  - `docs/post-recording-export-options-spec.md`
  - `macos/Sources/App/Features/Capture/VideoCaptureComponents.swift`
  - `macos/Sources/App/Features/Capture/VideoCaptureUI.swift`
  - `macos/Sources/App/Features/RegionSelection/RegionSelectionOverlay.swift`
  - `macos/Sources/App/Features/Settings/SettingsWindowController.swift`
  - `macos/Sources/App/Features/Store/StoreDomain.swift`
  - `macos/Sources/App/Features/Store/StoreViews.swift`
  - `vivyshot-rs/crates/vivyshot-core/src/video.rs`

This document describes the first lock-first paid-feature implementation. The current product direction is now preview-first with a central Pro export gate. Use `docs/pro-preview-and-export-trial-spec.md` for future implementation decisions.

## 1. Product Goal

VivyShot paid access should unlock features that feel like real production value without making the free product feel broken.

The paid package should focus on:

1. Visual polish:
   - capture enter/exit transition effects
   - customizable webcam overlay
   - customizable keystroke overlay
2. Recording upgrades:
   - microphone recording
   - webcam overlay recording
   - keystroke overlay recording
3. Export upgrades:
   - GIF export
   - existing advanced video export options

The final product should feel like:

1. Free: complete screenshot, annotation, and basic screen recording.
2. Paid: creator/demo/polish features for people who make shareable recordings.
3. Supporter: same paid access plus supporter identity, not a separate functional tier.

## 2. Non-Goals

Initial implementation does not include:

1. Scrolling capture. It stays disabled until auto-scroll and stitching are production-ready.
2. A full video editor UI.
3. Arbitrary multi-track user editing.
4. Animated user-authored overlay keyframes beyond live placement changes captured during recording.
5. Cloud sync, accounts, or online storage.
6. Paid restrictions on basic screenshots, annotations, standard screen recording, system audio, mouse click highlights, or local-only data.

## 3. Locked Product Decisions

### 3.1 Paid Access Definition

Use the current `StoreManager.hasPaidAccess` behavior for all functional paid gates.

Current code treats both products as paid access:

1. Lifetime unlock.
2. Supporter.

That should remain the product model:

1. Lifetime unlocks all paid functionality.
2. Supporter unlocks the same paid functionality and adds a visible supporter badge.
3. Supporter must not have exclusive functional features, so the higher price reads as voluntary support rather than a hidden higher tier.

### 3.2 Free Product Boundary

Free users keep:

1. Screenshots.
2. Annotation tools.
3. Standard screen recording.
4. System audio recording.
5. Mouse click highlights.
6. H.264 export.
7. 30 fps export.
8. Standard quality/bitrate export.
9. Export scale options.
10. Local-only data.

Paid users get:

1. Capture transition effects.
2. Microphone recording.
3. Webcam overlay recording.
4. Webcam overlay customization.
5. Keystroke overlay recording.
6. Keystroke overlay customization.
7. GIF export.
8. HEVC export.
9. 60 fps export.
10. High quality/high bitrate export.
11. Statistics.

### 3.3 No Stubbed Paid Controls

A paid control must not ship as a dead toggle.

If a control is visible and paid-unlocked, it must:

1. Affect recording, export, or visible UI.
2. Save settings correctly.
3. Survive the normal post-recording save path.
4. Be represented honestly in the paywall comparison table.

### 3.4 Reviewed Product Decisions

These decisions are locked for the first implementation:

1. Webcam placement changes during recording should be keyframed in v1 so export matches what the user saw while moving the overlay.
2. Locked paid toolbar tools should be visible by default for free users, but subtle. They explain paid value without blocking the core workflow.
3. GIF export should live inside the export sheet, not as a separate top-level toolbar button.
4. Microphone should be a separate paywall table row from system audio because system audio remains free and microphone is a creator upgrade.
5. Mouse click highlights remain free. They make basic screen recording useful without weakening the paid package.

## 4. Current Code Reality

### 4.1 Disabled Feature Flags

The current app has hidden flags for:

1. Capture transition effects:
   - `captureTransitionEffectsVisible`
   - `captureTransitionEffectsEnabled`
2. Microphone recording:
   - `videoMicrophoneFeatureVisible`
   - `videoMicrophoneFeatureEnabled`
3. Webcam overlay:
   - `videoWebcamFeatureVisible`
   - `videoWebcamFeatureEnabled`
4. Keystroke highlights:
   - `videoKeystrokesFeatureVisible`
   - `videoKeystrokesFeatureEnabled`
5. Scrolling capture:
   - `stitchCaptureFeatureVisible`

Scrolling capture is intentionally excluded from this spec.

### 4.2 Existing Useful Plumbing

Already present:

1. Settings fields for microphone, webcam, webcam size, webcam shape, mouse clicks, and keystrokes.
2. Toolbar tool definitions for microphone, webcam, mouse clicks, keystrokes, and countdown.
3. Webcam recorder that records a separate camera asset.
4. Input monitor that records keystroke and mouse click events.
5. Rust timeline/export concepts for webcam, audio, text overlays, key overlays, and custom compositor decisions.
6. Rust GIF export planning helpers.
7. Post-recording export gating for HEVC, 60 fps, high quality, and high bitrate.

### 4.3 Missing Production Pieces

Missing or incomplete:

1. Webcam asset is not composited into final exported video.
2. Keystroke events are not rendered into final exported video.
3. Webcam placement cannot be previewed or dragged during recording.
4. Keystroke placement cannot be previewed or dragged during recording.
5. Overlay placement/customization is not represented as a durable export model.
6. GIF export is not implemented in the macOS save path.
7. Camera and microphone entitlements/usage descriptions are absent.
8. Paid gates do not exist for the disabled feature groups.

## 5. Paid Feature UX

### 5.1 Capture Transitions

Settings:

1. Show an `Effects` section when paid access is active.
2. Free users see either:
   - no section, or
   - a locked row that opens the paywall.
3. Transition choices:
   - None
   - Fade
   - Ripple
   - Liquid Drop
   - Zoom Blur
   - Water Wave
4. Speed and strength controls are enabled only when the style is not `None`.

Runtime:

1. Free users always resolve to `None`.
2. Paid users can use the selected transition on capture overlay enter/exit.
3. If paid access is lost or unavailable, stored non-free transition settings must not affect runtime.

### 5.2 Microphone Recording

Toolbar:

1. Microphone button is visible as a paid tool.
2. Free click opens paywall.
3. Paid click toggles microphone recording.
4. Button is disabled once recording starts.

Settings:

1. Show `Record microphone` in video settings.
2. Free users see it locked or hidden, depending on final UI direction.
3. Paid users can set the default.

Permissions:

1. Add microphone entitlement if required by the sandbox target.
2. Add `NSMicrophoneUsageDescription`.
3. Prompt only when the user turns on or starts recording with microphone enabled.

Recording/export:

1. Microphone audio must be present in the saved file.
2. Failure to get permission must explain the issue and continue with microphone disabled only if the user explicitly chooses that path.

### 5.3 Webcam Overlay

Toolbar and recording preview:

1. Webcam button is visible as a paid tool.
2. Free click opens paywall.
3. Paid click toggles webcam overlay.
4. When enabled, show a live webcam preview overlay inside the capture region before recording starts.
5. Keep the overlay visible during recording.
6. User can drag the webcam overlay during recording.
7. User can drag from any visible part of the overlay, not only a small handle.
8. Overlay must stay inside the captured region with sensible padding.
9. Overlay must not be captured as part of the raw screen recording. It is a preview/control surface; final output comes from compositor.

Placement behavior:

1. Default placement: bottom-right.
2. Default size: medium.
3. Placement is stored as normalized geometry relative to the capture region.
4. Dragging before recording sets the initial placement.
5. Dragging during recording creates a placement change at the current recording timestamp.
6. Export uses those placement changes so the final video matches what the user saw.
7. If timestamped placement becomes too much for the first implementation, ship with a simpler rule only if documented in release notes:
   - final export uses the last placement for the full recording.
   This is acceptable for an internal iteration but not the preferred product behavior.

Settings/customization:

1. Camera picker:
   - System Default
   - discovered camera devices
   - unavailable saved camera fallback
2. Shape:
   - Rounded rectangle
   - Circle
3. Size:
   - Small
   - Medium
   - Large
4. Optional paid polish after the base feature:
   - border on/off
   - shadow on/off
   - corner radius for rounded rectangle
   - mirror preview toggle

Export:

1. Record webcam to a separate temporary asset.
2. Preserve raw screen recording untouched.
3. Compose webcam into exported MP4/HEVC/GIF.
4. Output placement, shape mask, and size must match preview.
5. If webcam recording fails, show a clear error and do not pretend the overlay was included.

### 5.4 Keystroke Overlay

Toolbar and recording preview:

1. Keystroke button is visible as a paid tool.
2. Free click opens paywall.
3. Paid click toggles keystroke overlay.
4. When enabled, show a placement preview label inside the capture region before recording.
5. Keep the overlay visible during recording when keys are being shown.
6. User can drag the keystroke overlay before and during recording.
7. Overlay must stay inside the captured region with sensible padding.
8. The overlay preview must not be captured as raw screen content. It is rendered again during export.

Placement behavior:

1. Default placement: lower center.
2. Placement is stored as normalized geometry relative to the capture region.
3. Dragging before recording sets the initial placement.
4. Dragging during recording creates a placement change at the current recording timestamp.
5. Export uses the placement active at each key event timestamp.

Settings/customization:

1. Position:
   - saved implicitly by drag
   - reset to default button
2. Style:
   - compact pill
   - floating glass pill
3. Size:
   - small
   - medium
   - large
4. Optional paid polish after the base feature:
   - background opacity
   - accent color
   - hold duration
   - modifier key style

Permissions/privacy:

1. Requires Accessibility permission.
2. Prompt only when the user turns on or starts recording with keystrokes enabled.
3. Store only display tokens needed for export.
4. Do not persist per-recording keystroke history beyond the temporary export flow.
5. Local-only behavior must stay true.

Export:

1. Render keystroke labels over MP4/HEVC/GIF exports.
2. Label timing must be derived from recorded key event timestamps.
3. Consecutive keys should combine or replace in a predictable way rather than flooding the screen.
4. Use Rust layout/timing helpers as the source of truth where available.

### 5.5 GIF Export

Post-recording UI:

1. Add an explicit `Save GIF` or `Export GIF` action in the post-recording review window.
2. Free click opens paywall.
3. Paid click opens a save panel.
4. If the recording has paid overlays, GIF export must include them.

Export policy:

1. Use Rust GIF plan helpers for frame rate, frame count, max dimension, and frame timing.
2. Keep hard guardrails:
   - max duration
   - max dimension
   - frame rate suitable for small screen recordings
3. Show clear failure messages when guardrails prevent export.
4. Do not ship a temporary-unavailable toast for a visible GIF action.

## 6. Composition Architecture

### 6.1 Source Of Truth

Rust core remains the source of truth for:

1. Overlay geometry normalization.
2. Overlay timing decisions.
3. Export plan decisions.
4. GIF export planning.
5. Whether export requires custom composition.

macOS remains responsible for:

1. ScreenCaptureKit recording.
2. Camera capture.
3. Live preview UI.
4. AVFoundation/CoreAnimation rendering.
5. Save panels and AppKit permission UX.

### 6.2 Overlay Model

Introduce a shared overlay model with normalized coordinates:

1. Webcam overlay:
   - normalized rect
   - shape
   - timestamped placement changes
   - source asset URL on macOS side
2. Keystroke overlay:
   - normalized anchor or rect
   - style
   - size
   - timestamped placement changes
   - recorded key events
3. Mouse click highlights:
   - remain free
   - may use the same compositor path later, but should not block this spec

All capture-region-dependent data should be normalized so resizing/export scaling does not break placement.

### 6.3 Post-Recording Data Flow

Current problem:

1. `VideoCaptureCoordinator` records webcam/key/click data.
2. `rustVideoSession` is cleared before export.
3. `quickSaveVideo` only receives the screen recording URL and export options.

Required flow:

1. Stop screen recorder.
2. Stop webcam recorder if enabled.
3. Stop input monitor.
4. Build a durable `PostRecordingProject` or equivalent in-memory export model.
5. Pass that model into the post-recording panel.
6. Save/export actions use that model.
7. Temporary assets are cleaned up only after discard or successful export.

The export model must include:

1. Screen recording URL.
2. Optional webcam URL.
3. Recording duration.
4. Capture region size.
5. Microphone/system audio state.
6. Key events.
7. Mouse click events.
8. Webcam placement changes.
9. Keystroke placement changes.
10. Overlay customization values.

### 6.4 MP4/HEVC Export

Export must choose one of two paths:

1. Passthrough/transcode path:
   - no paid overlays
   - no compositor-only features
2. Composition path:
   - webcam overlay
   - keystroke overlay
   - future text overlay
   - overlay-bearing GIF intermediate

Composition path must:

1. Preserve export codec, frame rate, quality, scale, and bitrate choices.
2. Include microphone/system audio according to recording/export settings.
3. Render webcam below text/key overlays.
4. Render keystrokes above webcam.
5. Keep all overlay visuals inside the rendered frame.

### 6.5 GIF Export

GIF export should use the same composition model as video export.

Rules:

1. If no overlays are present, GIF can sample the source recording directly.
2. If overlays are present, GIF samples the composed video frames.
3. Use Rust GIF plan helpers for deterministic frame timing.
4. Exported GIF must match the preview placement and overlay shape.

## 7. Paid Gate UX

### 7.1 Capture Toolbar

Locked paid tools should be visible enough to teach value without cluttering the toolbar.

Recommended behavior:

1. Show microphone, webcam, and keystroke tools if they are enabled in toolbar configuration.
2. For free users:
   - draw a small lock marker or use locked tooltip text
   - clicking opens the paywall
   - do not toggle the setting
3. For paid users:
   - behave like normal toolbar toggles

### 7.2 Settings

Settings should show paid feature controls in context:

1. Video settings:
   - microphone
   - webcam
   - keystroke overlay
   - overlay customization
2. Effects settings:
   - capture transition effects
3. Export defaults:
   - existing advanced export controls

Free users should see locked rows only if the row helps explain value. Avoid turning settings into a paywall.

### 7.3 Paywall Copy

Update paid feature table to present concrete value:

1. Screenshots: Free and Paid.
2. Annotation tools: Free and Paid.
3. Screen recording: Free and Paid.
4. System audio: Free and Paid.
5. Microphone recording: Paid.
6. Webcam overlay: Paid.
7. Keystroke overlay: Paid.
8. Capture transitions: Paid.
9. GIF export: Paid.
10. Video codec: H.264 vs H.264 + HEVC.
11. Frame rate: 30 fps vs 30/60 fps.
12. Export quality: Standard vs High bitrate.
13. Statistics: Paid.
14. Local-only data: Free and Paid.

Supporter copy should say:

1. Same paid features as Lifetime.
2. Supporter badge.
3. Extra support for independent development.

## 8. Implementation Phases

### Phase 1: Product Gates And Paywall Alignment

1. Introduce a clear paid-feature gate helper instead of scattered `storeManager.hasPaidAccess` checks.
2. Define paid feature identifiers:
   - capture transitions
   - microphone
   - webcam overlay
   - keystroke overlay
   - GIF export
   - advanced export
   - statistics
3. Update paywall comparison rows.
4. Keep scrolling capture disabled.

Acceptance:

1. Free users cannot enable paid features through toolbar/settings/defaults.
2. Paid users can see and enable paid controls.
3. Locked controls open the paywall.

### Phase 2: Capture Transitions

1. Gate transition settings by paid access.
2. Gate runtime transitions by paid access.
3. Stabilize enter/exit animations.
4. Remove old disabled flags for transitions once verified.

Acceptance:

1. Free runtime always uses `None`.
2. Paid runtime uses selected style.
3. Capture close/open does not hang or double-call completion.

### Phase 3: Microphone

1. Add entitlements and usage description.
2. Gate microphone toolbar/settings.
3. Verify ScreenCaptureKit microphone recording in sandboxed release build.
4. Show recording HUD microphone state.

Acceptance:

1. Paid recording with microphone exports audible microphone audio.
2. Denied permission gives clear recovery UI.
3. Free users cannot toggle microphone.

### Phase 4: Overlay Placement Preview

1. Add live webcam preview overlay.
2. Add keystroke placement preview overlay.
3. Add drag interaction inside capture region.
4. Persist default normalized placements.
5. Record timestamped placement changes during recording.

Acceptance:

1. User can position webcam before recording.
2. User can position webcam during recording.
3. User can position keystroke overlay before recording.
4. User can position keystroke overlay during recording.
5. Preview overlays do not appear in raw screen recording.

### Phase 5: Composition Export

1. Replace URL-only post-recording save flow with a post-recording export model.
2. Keep webcam/key events alive until export/discard.
3. Implement composed MP4/HEVC export.
4. Render webcam overlay with shape mask.
5. Render keystroke overlay with selected style/size.
6. Preserve existing export settings and paid gates.

Acceptance:

1. Exported video includes webcam at correct placement.
2. Exported video includes keystrokes at correct timing/placement.
3. Exported video honors codec, frame rate, scale, quality, and bitrate.
4. Export succeeds in Release build.

### Phase 6: GIF Export

1. Add paid GIF action to post-recording UI.
2. Implement source-only GIF export.
3. Implement composed GIF export when overlays exist.
4. Apply duration/dimension guardrails.

Acceptance:

1. Paid users can save GIFs.
2. Free users see paywall when choosing GIF.
3. GIF includes paid overlays when enabled.
4. Existing "temporarily unavailable" behavior is removed.

### Phase 7: Overlay Customization Polish

1. Webcam:
   - shape
   - size
   - camera
   - optional border/shadow/mirror
2. Keystrokes:
   - style
   - size
   - optional opacity/accent/hold duration
3. Reset placement actions.

Acceptance:

1. Customization affects preview and export consistently.
2. Defaults look good without user configuration.
3. Settings stay compact.

## 9. Validation Plan

Build validation:

1. `xcodebuild -project macos/VivyShot.xcodeproj -scheme VivyShot -configuration Release -derivedDataPath .build/DerivedData build`
2. `./scripts/install-macos-release.sh`

Core validation:

1. Rust unit tests for overlay geometry and timing helpers.
2. FFI contract tests if ABI changes are needed.
3. Swift tests for paid gate normalization and export plan decisions.

Manual validation:

1. Free user:
   - paid toolbar clicks open paywall
   - core recording still works
   - paid defaults cannot leak into runtime
2. Paid user:
   - microphone recording works
   - webcam preview appears and drags
   - keystroke preview appears and drags
   - MP4 export includes overlays
   - HEVC export includes overlays
   - GIF export includes overlays
3. Permission paths:
   - microphone denied
   - camera denied
   - Accessibility denied
4. Release/sandbox path:
   - installed app records and exports with all paid features enabled.

## 10. Decision Log

### 2026-05-05

The initial review resolved the first set of product questions:

1. Webcam drag changes during recording are keyframed in v1.
2. Locked paid toolbar tools are visible by default for free users.
3. GIF export lives inside the export sheet.
4. Microphone has a separate paywall comparison row from system audio.
5. Mouse click highlights remain free.
