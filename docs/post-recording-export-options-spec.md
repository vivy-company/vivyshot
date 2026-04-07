# VivyShot Post-Recording Export Options Spec

- Status: Active Draft
- Date: 2026-04-06
- Owner: VivyShot
- Related: `SPEC.md`, `docs/video-editor-spec.md`, `macos/Sources/App/Features/Capture/VideoCaptureUI.swift`, `macos/Sources/App/Features/Capture/VideoCaptureComponents.swift`

## 1. Problem Statement

The current post-recording review window is too thin for a video workflow that is otherwise starting to look professional.

Today, after a recording stops, VivyShot opens `PostRecordingActionPanel` with:

1. A preview player.
2. `Discard`.
3. `Save GIF`.
4. `Save MP4`.

That is functional, but it does not feel like a complete recording review/export surface.

At the same time, VivyShot already has recording-level configuration for:

1. Codec via `VideoCodecOption`.
2. Frame rate via `VideoFrameRateOption`.

Those settings exist in app settings and capture configuration, but they are not surfaced in the review/export experience where users most expect professional controls.

## 2. Product Goal

Make the post-recording review window feel like a real export surface by adding compact export controls directly into the review toolbar area.

This surface must:

1. Keep the core workflow free and complete.
2. Provide a clear place for future paid value.
3. Reuse the existing recording/export architecture where possible.
4. Avoid introducing a large editor or inspector redesign.

## 3. Non-Goals

Initial implementation does not include:

1. A full video editor inside the review window.
2. Timeline editing in the review window.
3. GIF redesign or advanced GIF controls.
4. Full transcoding pipeline redesign in Rust.
5. Custom bitrate text fields.
6. Arbitrary output dimension editing.

Also:

1. Trim is not a paid feature.
2. Normal recording is not a paid feature.
3. Standard save/export is not a paid feature.

## 4. Locked Product Decisions

### 4.1 Placement

The export controls live in the post-recording review window, not in general settings.

They must appear in the review toolbar area so the window feels immediately more complete without adding a second configuration screen.

### 4.2 Free vs Paid Line

Free users must retain a complete workflow:

1. Record.
2. Review.
3. Trim later when trimming is added to this surface.
4. Save/export with default settings.

Paid value comes from advanced export control, not from blocking the core workflow.

### 4.3 First Paid Surface

The first paid surface in this window is advanced export settings, specifically:

1. Higher frame rates.
2. Higher-end codecs where supported.
3. Higher-quality export presets.

This is the preferred monetization surface because it feels professional, useful, and does not make the free product feel petty.

## 5. Current Code Reality

This spec is based on the current macOS code, not a hypothetical future architecture.

### 5.1 Current Review Window

`macos/Sources/App/Features/Capture/VideoCaptureUI.swift`

Relevant types:

1. `PostRecordingActionPanel`
2. `PostRecordingActionView`
3. `PostRecordingPlayerPreview`

Current behavior:

1. The panel is a native `NSWindow`.
2. It already uses a unified toolbar.
3. The toolbar currently contains only action buttons:
   - `Discard`
   - `Save GIF`
   - `Save MP4`
4. The content view is only a preview player or thumbnail fallback.

### 5.2 Current Recording Configuration

`macos/Sources/App/Configuration/CaptureMode.swift`

Current enums:

1. `VideoCodecOption`
   - `h264`
   - `hevc`
2. `VideoFrameRateOption`
   - `fps30`
   - `fps60`

`macos/Sources/App/Configuration/AppSettings.swift`

Current persisted settings already include:

1. `videoCodec`
2. `videoFrameRate`

### 5.3 Current Recording Output Path

`macos/Sources/App/Features/Capture/VideoCaptureComponents.swift`

Current facts:

1. Capture-time recording already respects `VideoRecordingConfig.codec`.
2. Capture-time recording already respects `VideoRecordingConfig.frameRate`.
3. The post-recording `quickSaveMP4` path currently exports with:
   - `AVAssetExportPresetHighestQuality`
   - `.mp4`
   - a full-duration trim range
4. The post-recording export path does not currently expose per-export option selection in the review window.

This means the review UI can be improved without inventing a new subsystem from zero.

## 6. UX Specification

### 6.1 Window Structure

The review window remains a normal native window:

1. Title bar and subtitle stay native.
2. Toolbar keeps the main actions.
3. Preview remains the dominant content area.

The change is the addition of a compact export-controls strip in the toolbar region.

### 6.2 Toolbar Layout

Target toolbar composition:

1. `Discard`
2. separator
3. `Codec`
4. `FPS`
5. `Quality`
6. flexible space
7. `Save GIF`
8. `Save MP4`

The controls must look native:

1. `NSMenuToolbarItem` or toolbar-hosted pop-up/segmented controls.
2. No custom gradient pills.
3. No oversized inspector cards.

### 6.3 Control Labels

Initial toolbar labels:

1. `Codec: H.264`
2. `FPS: 30`
3. `Quality: Standard`

If a value is locked, the locked state should be visible but not obnoxious:

1. Small lock indicator in the menu item list is preferred.
2. Selecting a locked option opens the paywall.
3. Do not silently ignore selection.

### 6.4 Preview Area

The preview area remains simple for v1:

1. No inspector pane.
2. No stacked settings sidebar.
3. No heavy overlay UI on top of the player.

The professional feel comes from the toolbar controls plus the stronger export path, not from adding a second panel to the window.

## 7. Scope of Export Options

### 7.1 Full Target Scope

This spec includes the following post-recording export controls as the intended feature set:

1. `Codec`
   - `H.264`
   - `HEVC`
2. `Frame Rate`
   - `30 fps`
   - `60 fps`
   - `120 fps`
3. `Quality`
   - `Standard`
   - `High`
4. `Scale`
   - `100%`
   - `75%`
   - `50%`
5. `Bitrate`
   - preset-based menu, not free-form text input

### 7.2 First Implementation Slice

The first implementation pass may ship a narrower subset if needed, but it must be designed as the first slice of the full scope above.

Minimum first slice:

1. `Codec`
2. `Frame Rate`
3. `Quality`

### 7.3 Free/Paid Split

Free:

1. `H.264`
2. `30 fps`
3. `Standard`
4. `100%` scale
5. default bitrate preset

Paid:

1. `HEVC`
2. `60 fps`
3. `120 fps`
4. `High`
5. downscale presets
6. higher bitrate presets

### 7.4 Platform-Specific Rule

More codec targets are valid only when the platform/export path supports them reliably.

Rules:

1. Do not show a codec that cannot actually be exported on the current machine.
2. `HEVC` may be shown conditionally when the export path confirms support.
3. Additional codecs such as `AV1` are future extensions, not mandatory for this spec.

## 8. Trim Positioning

Trim is explicitly not part of the paid feature set.

When trim is added to the post-recording review window, it must be available to all users.

For this spec:

1. Trim is a future core feature.
2. Export controls are the premium surface.

That product line must remain stable.

## 9. Domain Model Additions

Add a distinct post-recording export options model rather than overloading unrelated UI state.

Suggested shape:

```text
PostRecordingExportOptions {
  codec: PostRecordingExportCodec
  frameRate: PostRecordingExportFrameRate
  quality: PostRecordingExportQuality
  scale: PostRecordingExportScale
  bitrate: PostRecordingExportBitratePreset
}
```

Suggested enums:

```text
PostRecordingExportCodec = h264 | hevc
PostRecordingExportFrameRate = fps30 | fps60 | fps120
PostRecordingExportQuality = standard | high
PostRecordingExportScale = full | percent75 | percent50
PostRecordingExportBitratePreset = standard | high | veryHigh
```

Rationale:

1. This keeps review-window export state local and explicit.
2. It avoids tightly coupling review UI to app-wide settings persistence.
3. It leaves room for capture defaults and export-time overrides to diverge cleanly later.

## 10. Capability and Paywall Gating

Store gating must not live inside view layout logic.

Add capability helpers such as:

1. `canUsePostRecordingExportCodec(_:)`
2. `canUsePostRecordingFrameRate(_:)`
3. `canUsePostRecordingExportQuality(_:)`
4. `canUsePostRecordingExportScale(_:)`
5. `canUsePostRecordingExportBitrate(_:)`

These should derive from the existing store entitlements:

1. `hasPaidAccess`
2. `hasLifetimeUnlock`
3. `hasSupporterBadge`

Behavior:

1. Free-safe options always apply normally.
2. Locked selections open the paywall.
3. If purchase succeeds while the review window is open, the user can select the advanced option immediately.

## 11. Technical Design

### 11.1 Files Likely To Change

Primary files:

1. `macos/Sources/App/Features/Capture/VideoCaptureUI.swift`
2. `macos/Sources/App/Features/Capture/VideoCaptureComponents.swift`
3. `macos/Sources/App/Features/Store/StoreManager.swift`

Supporting files:

1. `macos/Sources/App/Configuration/CaptureMode.swift`
2. `macos/Sources/App/Configuration/AppSettings.swift`

### 11.2 Review Panel Changes

`PostRecordingActionPanel` should gain:

1. Toolbar items for export options.
2. A small local source of truth for selected export options.
3. A way to present paywall when a locked value is chosen.

The existing action buttons remain.

### 11.3 Export Path Changes

`quickSaveMP4(inputURL:)` is currently too hard-coded for this spec.

It must evolve to accept explicit export options, for example:

```text
quickSaveMP4(inputURL: URL, options: PostRecordingExportOptions)
```

Phase 1 implementation may still use AVFoundation on the Swift side.

That is acceptable because:

1. The current export path is already Swift-side AVFoundation.
2. This change is scoped to review/export UX rather than core timeline logic.

### 11.4 Persistence

For v1, selected export options in the review window do not need to persist globally.

Acceptable behavior:

1. The review window starts with free-safe defaults.
2. Optionally seed defaults from `AppSettings.videoCodec` and `AppSettings.videoFrameRate` where it improves continuity.
3. The export selection only needs to live for the lifetime of the review window.

This is deliberately smaller and less risky than immediately creating a broad persistent export-preferences system.

## 12. Implementation Phases

### Phase 1: UI and Gating

Deliver:

1. Toolbar controls for `Codec`, `FPS`, and `Quality`.
2. Domain model that already includes `Scale` and `Bitrate`, even if the first visible UI slice does not expose both immediately.
2. Review-window-local export options state.
3. Locked-option paywall presentation.
4. Free-safe defaults and selection logic.

This phase is mostly UI + entitlement behavior.

### Phase 2: Export Application

Deliver:

1. Pass selected options into the actual MP4 export path.
2. Ensure saved output reflects chosen free or paid values.
3. Handle unsupported platform combinations safely.
4. Apply frame rate, codec, scale, and bitrate presets where the export path supports them.

Rules:

1. If `HEVC` is not supported, show it disabled or fall back safely.
2. Export must not claim to apply a setting it cannot actually honor.

### Phase 3: Trim Integration

Deliver later:

1. Add trim UI to the review window.
2. Keep trim free.
3. Make trim and export options coexist in the same review surface cleanly.

## 13. Acceptance Criteria

This spec is considered implemented when:

1. The review window is designed around native-looking export controls for `Codec`, `FPS`, `Quality`, `Scale`, and `Bitrate`, even if shipped in slices.
2. Free users can always export successfully with default values.
3. Locked values clearly indicate upgrade behavior.
4. Selecting a locked value opens the existing paywall.
5. Paid users can select advanced values immediately.
6. The review window feels more complete and professional without becoming a full editor.

## 14. Explicit Product Rules

These rules are non-negotiable for this feature:

1. Do not paywall trim.
2. Do not paywall normal recording.
3. Do not paywall default save/export.
4. Do not hide advanced options entirely from free users.
5. Do not build a large inspector panel for v1.
6. Do not move this functionality into deep settings.
