# VivyShot Recording Preview Polish Spec

- Status: Active Draft
- Date: 2026-05-12
- Owner: VivyShot
- Related:
  - `docs/pro-preview-and-export-trial-spec.md`
  - `docs/post-recording-export-options-spec.md`
  - `macos/Sources/App/Features/Capture/VideoCaptureUI.swift`
  - `macos/Sources/App/Features/Capture/VideoCaptureComponents.swift`
  - `macos/Sources/App/Features/RegionSelection/RegionSelectionOverlayController.swift`
  - `macos/Sources/App/Shared/UI/CaptureGlassViews.swift`

## 1. Product Goal

The recording review window should be simple and trustworthy:

1. What the user sees during recording is what appears in the review.
2. What the review plays is what gets saved.
3. Native Liquid Glass overlays keep their real system-rendered look.
4. App controls such as stop/pause bars are not burned into the recording.
5. The review window can trim and mute final output without changing the raw recording.
6. V1 ships this behavior from the start instead of adding a fake compositor first.

The core v1 rule is:

**Burn only recording content overlays into the captured video, and keep app control UI excluded.**

Content overlays:

1. Webcam overlay.
2. Keystroke overlay.
3. Future mouse-click overlay if we move away from ScreenCaptureKit's built-in click effect.

Control UI:

1. Stop/pause recording controls.
2. Capture toolbars.
3. Menubar/popover UI.
4. Settings, paywall, statistics, onboarding, and other app windows.

## 2. Current Code Reality

### 2.1 Screen Capture Filter

`ScreenRegionRecorder` currently excludes the whole VivyShot process:

```swift
let excludedApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
let filter = SCContentFilter(display: display, excludingApplications: excludedApps, exceptingWindows: [])
```

This keeps VivyShot UI out of recordings, but it also excludes the overlay panel that contains webcam and keystrokes.

ScreenCaptureKit supports `exceptingWindows` for app/display filters. That lets us keep excluding VivyShot as an app while making specific overlay windows exceptions to the exclusion.

### 2.2 Recording Overlay Window

`RecordingOverlayController` currently creates one transparent `NSPanel` over the selected capture region:

1. Borderless non-activating panel.
2. Screen-saver level.
3. Clear background.
4. Contains webcam overlay and keystroke overlay subviews.
5. Lets the user drag/resize overlays during recording.

That panel is the right candidate to burn in, but only if it contains content overlays and no recording controls.

### 2.3 Review Window

`PostRecordingActionPanel` currently plays the raw screen recording and separately overlays preview UI:

1. `PostRecordingPlayerPreview` plays `project.inputURL`.
2. `PostRecordingOverlayPreviewLayer` draws webcam/keystroke previews on top.
3. Export later redraws overlays again in `PostRecordingProjectExporter`.

With burn-in, the review should not need an overlay preview layer for webcam/keystrokes. The raw recorded video already includes them.

### 2.4 Export Path

Today the export path may custom-composite overlays:

1. `quickSaveVideo(...)` checks `exportPlan?.needsCustomCompositor`.
2. `PostRecordingProjectExporter.exportCompositedVideo(...)` redraws webcam/keystroke overlays.
3. GIF export also renders composited frames.

With burn-in, webcam and keystrokes are already pixels in `inputURL`. The export path should treat them like normal recorded content and only apply trim/transcode/GIF conversion.

## 3. Non-Goals

This v1 does not add:

1. Post-recording overlay disabling.
2. Post-recording overlay restyling.
3. Post-recording overlay repositioning.
4. A fake Liquid Glass renderer.
5. A full video editor.
6. A second internal screen-recording pass after capture.
7. Server-side licensing changes.

Important tradeoff:

**Burned overlays cannot be removed after recording.**

This is intentional for v1 because the priority is true native glass and 1:1 output. Users can still enable/disable webcam and keystroke overlays before recording starts.

## 4. Product Decisions

### 4.1 Burn-In Is V1 Overlay Architecture

V1 should record overlay pixels directly into the screen capture.

Benefits:

1. Preview is automatically 1:1 because it plays the recorded file.
2. Export is automatically 1:1 because it saves/transcodes the recorded file.
3. Native `.glassEffect(...)` can remain real native glass.
4. We avoid maintaining a fake glass renderer.
5. Webcam timing, keystroke timing, shadows, blur, and shape are captured exactly as the user saw them.

Cost:

1. Overlays are not editable after capture.
2. Overlay Pro gating must happen before recording/export, not by removing overlays after recording.
3. A mistake in overlay placement during recording is baked into the file.

### 4.2 Overlay-Only Filter Exception

The capture filter should still exclude VivyShot as an app, but should except only dedicated content overlay windows.

Conceptual flow:

1. Create/show the recording overlay window.
2. Resolve the `SCWindow` matching that `NSWindow.windowNumber`.
3. Build `SCContentFilter(display:excludingApplications:exceptingWindows:)`.
4. Pass VivyShot's `SCRunningApplication` in `excludingApplications`.
5. Pass only content overlay `SCWindow`s in `exceptingWindows`.
6. Do not pass stop controls, capture UI, settings, paywall, or other app windows.

Result:

1. Screen content is captured.
2. Webcam/keystroke overlay panel is captured.
3. Other VivyShot windows remain invisible to the recording.

### 4.3 Separate Content Overlay From Control Overlay

Do not put recording controls inside the same window that is excepted into capture.

Required split:

1. `RecordingContentOverlayController`
   - Captured.
   - Contains webcam, keystrokes, and future visual click overlays only.
   - Has no stop/pause/export/debug controls.

2. `RecordingControlOverlayController`
   - Excluded.
   - Contains stop/pause/status controls.
   - Can stay in the normal VivyShot app exclusion.

If we keep one panel for both, we cannot include overlays without also burning stop controls. V1 should split them before enabling burn-in.

### 4.4 Review Tools

The post-recording review window keeps review actions in the preview surface, not the toolbar:

1. Toolbar owns final actions only: `Export...` and `Save`.
2. The bottom playback bar owns playback, trim, and final-output sound.
3. `Trim` is an inline timeline mode with draggable left/right handles, similar to QuickTime and iOS Photos.
4. `Sound` is a speaker toggle in the playback bar.

The review must not show overlay visibility toggles, because webcam/keystrokes are already part of the recorded pixels and cannot be removed honestly.

`Sound` controls whether the final saved video includes audio.

Rules:

1. Show the speaker toggle only when the recording has an audio track.
2. The default is on when audio exists.
3. Turning it off mutes preview playback and exports video without audio tracks.
4. Turning it off does not modify the temporary raw recording file.
5. GIF export is unaffected because GIF has no audio.
6. If microphone audio is the only Pro reason, turning sound off removes that Pro reason from video export.

### 4.5 Pro Gate Behavior

The paywall/trial rule stays simple:

1. Free users can preview/configure Pro overlays before recording.
2. Starting a recording with Pro overlays is allowed under the existing preview/trial direction.
3. Saving/exporting a recording that contains burned Pro overlays is a Pro export.
4. The one free Pro export is consumed only after a successful save/export.
5. Canceling or failing export does not consume the trial.

Since overlays are baked, the review window cannot remove Pro reasons by hiding overlays. If the recording contains burned webcam/keystroke overlays, those reasons remain attached to the export.

## 5. UX Specification

### 5.1 Recording Setup

Before recording starts:

1. Webcam and keystroke toggles remain the place to enable/disable overlays.
2. The user can place and resize overlays in the capture region before/during recording.
3. The app should make it clear that overlays will be included in the final recording.

Recommended helper copy in settings or tooltip, not a blocking prompt:

`Overlays are recorded exactly as shown.`

### 5.2 During Recording

During recording:

1. Webcam and keystroke overlays appear as real native app overlays.
2. They can keep using native Liquid Glass.
3. Dragging/resizing changes what is burned into the video from that moment onward.
4. Stop/pause controls remain visible to the user but are not recorded.

### 5.3 Review Window

The review window:

1. Plays the raw recorded file.
2. Does not draw webcam/keystroke overlays on top of playback.
3. Shows the same overlays because they are already in the video pixels.
4. Keeps native title/subtitle/toolbar behavior.

Toolbar order:

1. flexible space
2. `Export...`
3. `Save` format menu

`Save` menu:

1. `Save as MP4`
2. `Save as MOV`
3. `Save as GIF`

`Export...` opens the detailed export sheet for codec, quality, frame rate, scale, bitrate, and GIF export.

### 5.4 Trim Timeline

`Trim` is a bottom playback-bar mode, not a toolbar item or settings-style tray.

Trim timeline behavior:

1. Shows full duration.
2. Shows selected range.
3. Uses two handles for start/end.
4. Shades excluded ranges.
5. Shows current playhead.
6. Clicking inside the selected range seeks.
7. Dragging handles updates playback immediately.
8. Playhead stays constrained to the selected range.

Secondary action:

1. `Reset Trim`

No overlay toggles in v1.

### 5.5 Sound Tool

`Sound` is a speaker toggle in the playback bar, not a toolbar item or tray.

Behavior:

1. On by default when the recording has audio.
2. Click once to turn final-output sound off.
3. Click again to restore final-output sound.
4. While off, preview playback is muted so preview matches output intent.
5. The raw temporary recording file is not changed.
6. The export path omits all audio tracks when off.

### 5.6 Playback Behavior

Playback respects trim:

1. Play starts at `trimStartMS` if current time is outside the selected range.
2. Play pauses or loops to trim start at `trimEndMS`.
3. Normal seeking stays within the selected range.
4. Time labels show current time and selected duration.
5. Preview playback is muted when `Sound` is off.

Recommended labels:

1. Current source time: `00:03`
2. Selected duration: `00:06 selected`

### 5.7 Export Behavior

All save paths use the current trim and sound state:

1. `Save as MP4`
2. `Save as MOV`
3. `Save as GIF`
4. `Export...` to video
5. `Export...` to GIF

Video export:

1. Use `AVAssetExportSession.timeRange` with the trim range when possible.
2. If a custom export path is needed for codec/scale/quality, still treat overlays as normal source pixels.
3. If `Sound` is on, audio is trimmed from the same source range and placed at output time zero.
4. If `Sound` is off, no audio tracks are inserted into the final video.

GIF export:

1. Use the trimmed duration for the 120 second GIF limit.
2. Build GIF plan with `startMS: trimStartMS` and `endMS: trimEndMS`.
3. Frames are generated from the source video, which already contains overlays.

## 6. Technical Design

### 6.1 Window Capture Eligibility

Add an explicit capture role for recording-related windows.

Recommended shape:

```swift
enum RecordingWindowCaptureRole {
  case capturedContentOverlay
  case excludedControlOverlay
}
```

The screen recorder should receive only the `NSWindow.windowNumber` values for `.capturedContentOverlay` windows.

### 6.2 Resolving Overlay Windows

`SCContentFilter` requires `SCWindow` objects in `exceptingWindows`.

Resolution flow:

1. Show the content overlay panel.
2. Read `panel.windowNumber`.
3. Load `SCShareableContent`.
4. Find `SCWindow` where `window.windowID == CGWindowID(panel.windowNumber)`.
5. Build the filter with that `SCWindow` as an exception.

If the overlay window cannot be resolved:

1. Do not silently record without overlays.
2. Show a clear error or fallback prompt.
3. Recommended v1 behavior: fail recording start with `Unable to include recording overlays.`

This is better than creating a file that looks different from what the user saw.

### 6.3 Screen Recorder Inputs

`ScreenRegionRecorder.start(...)` should accept a list of captured overlay window IDs:

```swift
struct VideoRecordingConfig {
  ...
  var capturedOverlayWindowIDs: [CGWindowID]
}
```

or:

```swift
func start(
  selectionRectInScreen: CGRect,
  outputURL: URL,
  config: VideoRecordingConfig,
  capturedOverlayWindows: [NSWindow]
) async throws
```

The recorder owns mapping those IDs to `SCWindow`s because it already loads `SCShareableContent`.

### 6.4 Capture Startup Order

Startup order matters:

1. Create webcam recorder/session if needed.
2. Create and show content overlay panel.
3. Resolve content overlay panel as `SCWindow`.
4. Start ScreenCaptureKit stream with the overlay exception.
5. Start webcam recording only if we still need a separate webcam asset for fallback/debug.
6. Start input monitor for keystroke text.

For burn-in v1, separate webcam asset export is optional. Keeping it temporarily for diagnostics is acceptable, but the final preview/export should use the burned video as source of truth.

### 6.5 Review State

Post-recording edit state stores trim and output audio:

```swift
struct PostRecordingReviewEditState: Equatable {
  var trimStartMS: UInt32
  var trimEndMS: UInt32
  var isTrimModeActive: Bool
  var isOutputAudioEnabled: Bool
}
```

No overlay visibility booleans in v1.

Initialize `isOutputAudioEnabled` from `PostRecordingDetails` or asset track inspection. If the recording has no audio, force it to `false` and hide the speaker toggle.

### 6.6 Rust Core Role

Rust remains useful for:

1. Trim range normalization.
2. GIF frame timing.
3. Export policy/pro requirement calculation, including audio visibility.
4. Future non-burned editor features.

Rust does not need to render webcam/keystroke overlays for v1 burn-in output.

## 7. Implementation Plan

### Slice 1: Split Overlay Windows

1. Rename/refactor current `RecordingOverlayController` into content overlay responsibilities.
2. Ensure captured content overlay contains only webcam/keystroke visual content.
3. Ensure stop/pause/status controls are in a separate excluded controller.
4. Expose captured content overlay `windowNumber`.

### Slice 2: ScreenCaptureKit Overlay Exception

1. Pass captured content overlay window IDs into `ScreenRegionRecorder`.
2. Resolve matching `SCWindow`s from `SCShareableContent`.
3. Build filter with VivyShot app excluded and overlay windows excepted.
4. Fail recording start if an enabled overlay window cannot be resolved.

### Slice 3: Review Uses Burned Source

1. Remove webcam/keystroke `PostRecordingOverlayPreviewLayer` from the review path for burn-in recordings.
2. Keep the raw player as the visual truth.
3. Keep metadata only for Pro requirement and diagnostics.

### Slice 4: Bottom Trim Timeline

1. Add `Trim` as a bottom playback-bar toggle.
2. Replace settings-style sliders with one timeline and draggable start/end handles.
3. Use `RustCoreBridge.normalizeTrimRange(...)`.
4. Clamp playback to trim range.

### Slice 5: Bottom Sound Tool

1. Add a speaker toggle to the bottom playback bar.
2. Initialize from the recording's audio presence.
3. Mute preview playback while off.
4. Pass `isOutputAudioEnabled` into video save/export.
5. Exclude audio tracks from video output while off.
6. Ensure microphone Pro reasons are not reported when output audio is off.

### Slice 6: Trimmed Export

1. Apply trim to video save/export.
2. Apply trim to GIF export.
3. Apply trim to audio.
4. Keep overlays as recorded pixels.

### Slice 7: Cleanup Old Overlay Compositor

1. Remove or gate the old custom webcam/keystroke compositor for new burn-in recordings.
2. Keep only if needed for old/debug paths.
3. Remove review overlay preview paths that can drift from recorded pixels.

## 8. Acceptance Criteria

### 8.1 Capture

1. Webcam overlay is visible during recording and appears in the raw recorded file.
2. Keystroke overlay is visible during recording and appears in the raw recorded file.
3. Stop/pause controls are visible during recording but do not appear in the raw recorded file.
4. Settings/paywall/menu windows do not appear in the raw recorded file.
5. Native Liquid Glass appearance is preserved in the recorded file.

### 8.2 Review

1. Review preview plays the raw recorded overlay pixels.
2. No duplicate webcam/keystroke overlays are drawn on top of preview.
3. Preview matches exported output at the same timestamp.
4. `Trim` toggles a direct-manipulation timeline with left/right handles.
5. Speaker toggle controls preview and final-output audio when audio exists.
6. Toolbar contains only final actions: `Export...` and `Save`.

### 8.3 Export

1. Saving full duration preserves burned overlays.
2. Trimmed video export preserves burned overlays.
3. Trimmed GIF export preserves burned overlays.
4. Exported audio matches the trimmed source range.
5. Turning `Sound` off exports a silent video with no audio track.
6. Turning `Sound` off does not affect GIF export behavior.

### 8.4 Pro Gate

1. Previewing and recording overlays does not consume the free Pro export.
2. Successful export with burned Pro overlays consumes the free Pro export for free users.
3. Canceling the save panel does not consume the trial.
4. Failed export does not consume the trial.
5. Microphone audio is not listed as a Pro reason when `Sound` is off.

## 9. Test Plan

Automated:

1. `cargo test -p vivyshot-core`
2. `cargo test -p vivyshot-ffi`
3. `plutil -lint macos/Resources/*.lproj/Localizable.strings`
4. `./scripts/install-macos-release.sh`

Manual:

1. Record with webcam and keystrokes enabled.
2. Confirm raw review preview contains webcam and keystrokes without extra preview overlay.
3. Confirm stop controls are absent from the preview.
4. Save as MP4/MOV and compare with preview.
5. Save as GIF and compare with preview.
6. Trim start/end and verify output duration.
7. Toggle `Sound` off and verify exported video has no audio.
8. Toggle `Sound` on and verify exported video keeps trimmed audio.
9. Repeat on a bright background and a dark background to verify real glass remains readable.

Optional validation helper:

1. Capture a frame from the raw recording.
2. Capture a frame from exported video at the same source timestamp.
3. Compare pixels outside expected compression tolerance.

## 10. Risks

### 10.1 Overlay Window Resolution

The overlay panel may not appear in `SCShareableContent` immediately.

Mitigation:

1. Show panel before resolving content.
2. Wait/retry briefly.
3. Fail start with a clear message if resolution still fails.

### 10.2 Burning UI Mistakes

If a control is accidentally placed in the captured content overlay, it will be recorded.

Mitigation:

1. Keep captured content overlay and control overlay as separate controllers.
2. Add assertions/logging around captured window IDs.
3. Manual QA must verify stop controls are absent.

### 10.3 Loss Of Post-Recording Overlay Editing

Burn-in prevents disabling overlays after recording.

Mitigation:

1. Make pre-recording overlay toggles obvious.
2. Consider a future advanced mode for clean recording plus composited editable overlays.
3. Do not pretend burned overlays can be removed in v1.

## 11. Recommended V1 Scope

Ship v1 as:

1. Overlay-only burn-in capture.
2. Stop/control UI excluded from capture.
3. Review preview uses raw recorded video only.
4. Bottom trim timeline with direct left/right handles.
5. Bottom speaker toggle for final video audio on/off.
6. Save menu for MP4/MOV/GIF.
7. Detailed `Export...` sheet.
8. Trimmed video/GIF export.

Do not ship post-recording overlay disabling in the same v1. It conflicts with the burn-in requirement and would force us back to fake compositing.
