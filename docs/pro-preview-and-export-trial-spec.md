# VivyShot Pro Preview And Export Trial Spec

- Status: Active Draft
- Date: 2026-05-05
- Owner: VivyShot
- Supersedes:
  - `docs/paid-capture-overlays-and-effects-spec.md`
- Related:
  - `docs/post-recording-export-options-spec.md`
  - `docs/video-editor-spec.md`
  - `docs/capture-statistics-spec.md`
  - `macos/Sources/App/Features/Capture/VideoCaptureComponents.swift`
  - `macos/Sources/App/Features/Capture/VideoCaptureUI.swift`
  - `macos/Sources/App/Features/RegionSelection/RegionSelectionOverlay.swift`
  - `macos/Sources/App/Features/Settings/SettingsWindowController.swift`
  - `macos/Sources/App/Features/Store/StoreDomain.swift`
  - `macos/Sources/App/Features/Store/StoreViews.swift`

## 1. Product Goal

VivyShot should let users understand Pro value before buying.

The app should feel like:

1. Free users can make useful screenshots and basic recordings without friction.
2. Free users can try Pro recording/export features and complete one successful Pro export.
3. Paid users get unlimited Pro exports and Pro runtime polish.
4. Supporter remains the same functional access as Lifetime, plus supporter identity.

This replaces the lock-first model where paid tools are disabled throughout the UI.

The new rule is:

**You can preview Pro. You can export one Pro result for free. Unlimited Pro output requires paid access.**

## 2. Non-Goals

This spec does not add:

1. Accounts, cloud sync, server-side trial tracking, or anti-abuse enforcement.
2. A full video editor.
3. Scrolling capture.
4. Watermark-only monetization.
5. A separate functional Supporter tier.
6. Complex per-feature trial counters.

## 3. Product Decisions

### 3.1 Paid Access Definition

Use the existing paid entitlement model:

1. Lifetime unlock gives unlimited Pro access.
2. Supporter gives the same unlimited Pro access.
3. Supporter adds badge/supporter identity only.

### 3.2 Trial Definition

Free users get one successful Pro export.

Trial behavior:

1. The trial is consumed only after a Pro export succeeds.
2. Canceling a save panel does not consume the trial.
3. Failed exports do not consume the trial.
4. Multiple Pro features in one export consume one trial.
5. Paid users never consume trial state.
6. Trial state is local, per device, and best effort.
7. Trial state is not a security boundary.

Initial storage:

1. `AppSettings` stores `proExportTrialConsumedAt: Date?`.
2. Optional debug setting can reset the local trial during development.
3. No server validation is required for v1.

### 3.3 Feature Classification

Pro features are split into three groups.

#### Export-Bearing Pro Features

These can be used by free users, but exporting the result requires paid access or the one free Pro export:

1. Webcam overlay in final video/GIF.
2. Keystroke overlay in final video/GIF.
3. Microphone audio in final video.
4. GIF export.
5. HEVC export.
6. 60 fps export.
7. High quality/high bitrate export.
8. Future intro/outro transitions baked into video/GIF output.

#### Runtime-Only Pro Polish

These are not meaningfully present in the saved artifact today:

1. Capture overlay enter transition.
2. Capture overlay exit transition.

Free users can preview these in Settings, but real capture uses them only for paid users.

If a future implementation bakes these transitions into video/GIF output, they move into the export-bearing group.

#### Preview/Demo Pro Features

These should have a preview path that does not consume the export trial:

1. Capture transition preview.
2. Webcam overlay shape/size preview.
3. Keystroke overlay style/size preview.
4. Statistics preview.

## 4. Free Product Boundary

Free users keep unlimited:

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

Free users can also configure and try Pro output features before export:

1. Turn on webcam overlay.
2. Turn on keystroke overlay.
3. Turn on microphone.
4. Choose GIF/HEVC/60 fps/high quality export.
5. Adjust overlay placement and customization.

The gate appears when a final saved artifact would contain Pro value.

## 5. UX Direction

### 5.1 Toolbar

Do not show locked toolbar buttons by default.

Toolbar behavior:

1. Microphone, webcam, and keystroke buttons are normal toggles.
2. Free users can toggle them.
3. Paid-only value is explained with subtle `Pro` markers or tooltips, not disabled controls.
4. If the free trial is already consumed, toggling a Pro output feature may show a non-blocking toast:
   - `Exports with Webcam require Pro. You can still preview it.`
5. Never interrupt recording setup with a paywall unless the user explicitly opens upgrade UI.

### 5.2 Settings

Settings should be useful for both users and debugging.

Rules:

1. Do not hide Pro settings from free users.
2. Do not fill Settings with lock rows.
3. Use compact `Pro` badges or secondary copy where needed.
4. Store selected Pro settings for all users.
5. Runtime/export decides whether the setting can affect real output.

### 5.3 Preview Buttons In Settings

Add explicit preview actions for Pro visual features.

#### Capture Transition Preview

Add a `Preview` button near transition style/speed/strength.

Behavior:

1. Available to free and paid users.
2. Runs the selected transition through the real region overlay enter/exit path, using the normal opening state with no preselected region.
3. Does not start an actual capture or create an export.
4. Does not consume the Pro export trial.
5. Does not imply the transition will run in real capture for free users.
6. Useful in debug builds for verifying transition timing and shader state.

Free user helper copy:

`Preview is available. Real capture transitions require Pro.`

#### Webcam Overlay Preview

Add a `Preview Webcam Overlay` affordance or keep live preview when selecting a region.

Behavior:

1. Shows camera preview with selected shape/size.
2. Allows drag placement where capture context exists.
3. Requests camera permission only when preview or recording needs it.
4. Does not consume the Pro export trial.

#### Keystroke Overlay Preview

Add a preview sample near key style/size.

Behavior:

1. Shows a sample key label using selected style/size.
2. Does not require Accessibility permission unless capturing real key events.
3. Does not consume the Pro export trial.

#### Statistics Preview

Free users may see a limited preview of the statistics dashboard.

Behavior:

1. Prefer sample/teaser data or a compact real summary.
2. Full history/dashboard remains Pro.
3. Preview does not consume the Pro export trial.

### 5.4 Post-Recording Export Gate

Export is the primary paywall moment.

When a free user exports a recording, build a `ProExportRequirement` from:

1. `PostRecordingProject`.
2. `PostRecordingExportOptions`.
3. Requested target: video or GIF.

If the export does not require Pro:

1. Export immediately.
2. Do not show paywall.
3. Do not consume trial.

If the export requires Pro and the user has paid access:

1. Export immediately.
2. Do not consume trial.

If the export requires Pro and the free trial is unused:

1. Show a short confirmation sheet.
2. List the Pro features used.
3. Primary action: `Use Free Pro Export`.
4. Secondary action: `Upgrade`.
5. Tertiary action: `Cancel`.
6. Consume trial only after successful export.

If the export requires Pro and the free trial is already consumed:

1. Show the paywall.
2. Include the Pro features used in context.
3. Keep the recording/review window open if the user cancels.

### 5.5 Confirmation Copy

Trial sheet title:

`Use your free Pro export?`

Trial sheet body:

`This recording uses Pro features: Webcam overlay, Keystroke overlay, GIF export. Your first Pro export is free.`

Buttons:

1. `Use Free Pro Export`
2. `Upgrade`
3. `Cancel`

Consumed state copy:

`This export uses Pro features. Upgrade to export unlimited Pro recordings.`

## 6. Transition Policy

Capture transitions need special handling because today they are app experience, not output.

### 6.1 Settings Preview

All users can preview transition styles in Settings.

Preview should use:

1. Selected style.
2. Selected speed.
3. Selected strength.
4. Same renderer as the real capture overlay transition where practical.

### 6.2 Real Capture Runtime

For v1:

1. Paid users get selected capture enter/exit transitions in real capture.
2. Free users get `None` in real capture.
3. Free users can still save and preview transition settings.
4. A compact Settings note explains this.

Reasoning:

1. Runtime transitions are not part of a saved file today.
2. The one free Pro export cannot fairly apply to a pure app-experience feature.
3. The preview button gives users a concrete taste without adding toolbar/paywall complexity.

### 6.3 Future Baked Transitions

If video/GIF exports later include intro/outro transition effects:

1. They become export-bearing Pro features.
2. Free users can export them once via the Pro export trial.
3. The export gate lists them as `Capture transitions`.

## 7. Export Gate Model

Introduce a single export gate model.

Suggested Swift model:

```swift
struct ProExportRequirement: Equatable {
  let requiresPro: Bool
  let reasons: [ProExportReason]
}

enum ProExportReason: String, CaseIterable {
  case webcamOverlay
  case keystrokeOverlay
  case microphoneAudio
  case gifExport
  case hevcExport
  case sixtyFPS
  case highQuality
  case highBitrate
  case bakedTransition
}
```

Suggested helper:

```swift
func proExportRequirement(
  project: PostRecordingProject,
  options: PostRecordingExportOptions,
  target: PostRecordingExportTarget
) -> ProExportRequirement
```

Rules:

1. Webcam reason applies only if final output includes webcam.
2. Keystroke reason applies only if final output includes keystrokes.
3. Microphone reason applies if microphone audio is present in final output.
4. GIF reason applies to every GIF export.
5. HEVC reason applies to HEVC output.
6. 60 fps reason applies to non-30 fps output.
7. High quality/high bitrate reasons apply when non-standard export settings are used.
8. Baked transition reason applies only when transition pixels are present in final video/GIF.

## 8. Data Flow

The post-recording flow should be:

1. Record screen/webcam/input data.
2. Build `PostRecordingProject`.
3. User chooses export target/options.
4. Build `ProExportRequirement`.
5. Resolve access:
   - paid access
   - unused trial
   - no access
6. Export.
7. If a trial was used and export succeeds, persist trial consumed.
8. Clean up temporary assets after successful export or discard.

Trial consumption must happen after the export operation returns success.

## 9. Paywall Direction

The paywall should sell outcomes rather than locked controls.

Paywall table should still explain:

1. Screenshots: Free and Pro.
2. Annotation tools: Free and Pro.
3. Screen recording: Free and Pro.
4. System audio: Free and Pro.
5. Mouse click highlights: Free and Pro.
6. Webcam overlay export: Pro.
7. Keystroke overlay export: Pro.
8. Microphone audio export: Pro.
9. GIF export: Pro.
10. HEVC export: Pro.
11. 60 fps/high quality export: Pro.
12. Statistics dashboard: Pro.
13. Capture transitions: Pro, previewable.
14. Local-only data: Free and Pro.

Copy should include:

`Try Pro features before buying. Your first Pro export is free.`

## 10. Implementation Phases

### Phase 1: Spec Alignment And UI Simplification

1. Mark old lock-first spec as superseded.
2. Remove lock-first toolbar behavior.
3. Replace lock rows with subtle `Pro` markers.
4. Keep paid feature identifiers, but do not use them to disable most controls.

Acceptance:

1. Free users can toggle microphone/webcam/keystrokes.
2. Free users can select Pro export options.
3. Settings are not dominated by lock rows.

### Phase 2: Trial State

1. Add local trial-consumed setting.
2. Add debug reset if useful.
3. Add access helper:
   - paid access
   - free trial available
   - free trial consumed

Acceptance:

1. Trial starts available.
2. Trial is consumed only after successful Pro export.
3. Failed/canceled exports do not consume trial.

### Phase 3: Central Export Gate

1. Add `ProExportRequirement`.
2. Implement requirement detection for video and GIF exports.
3. Route all save/export actions through one gate.
4. Remove scattered export-option paywall checks where possible.

Acceptance:

1. Free standard export does not show paywall.
2. First Pro export shows trial confirmation.
3. Second Pro export shows paywall.
4. Paid export bypasses trial/paywall.

### Phase 4: Settings Preview

1. Add transition `Preview` button.
2. Add compact helper text for free users.
3. Add or preserve webcam overlay preview.
4. Add keystroke style preview.
5. Add statistics preview entry if not already present.

Acceptance:

1. Free users can preview transition styles.
2. Preview does not consume trial.
3. Real free capture still uses no runtime transition until paid.
4. Paid real capture uses selected transition.

### Phase 5: Paywall Copy

1. Update paywall value proposition.
2. Mention first Pro export is free.
3. Replace lock-oriented copy with outcome-oriented copy.

Acceptance:

1. Paywall makes clear what Pro output unlocks.
2. Supporter is framed as extra support, not a higher functional tier.

## 11. Validation Plan

Build validation:

1. `xcodebuild -project macos/VivyShot.xcodeproj -scheme VivyShot -configuration Release -derivedDataPath .build/DerivedData build`
2. `./scripts/install-macos-release.sh`

Manual validation:

1. Free fresh install:
   - Pro controls are selectable.
   - Transition preview works in Settings.
   - Real capture transition does not run.
   - Standard export succeeds without trial prompt.
   - Pro export shows free trial prompt.
   - Successful Pro export consumes trial.
2. Free trial consumed:
   - Pro controls remain selectable/previewable.
   - Pro export opens paywall.
   - Standard export still succeeds.
3. Paid user:
   - Pro controls work.
   - Real capture transition runs.
   - Pro exports do not show trial prompt.
4. Failure/cancel paths:
   - Cancel save panel does not consume trial.
   - Failed export does not consume trial.
   - Closing paywall keeps review window alive.

## 12. Decision Log

### 2026-05-05

The product direction changed from lock-first to preview-first:

1. Use one free successful Pro export instead of blocking Pro controls everywhere.
2. Keep the main UI simple and avoid lock-heavy settings/toolbars.
3. Put the primary paywall at export, when value is concrete.
4. Add Settings preview buttons for runtime-only Pro polish.
5. Capture transitions are previewable for everyone but run in real capture only for paid users until they become baked output features.
