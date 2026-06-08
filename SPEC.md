# VivyShot v1 Spec

## 1. Product

- Name: `VivyShot`
- Type: native macOS screenshot, annotation, and recording utility
- Positioning: fast, minimal alternative to heavy screenshot tools
- Initial release targets:
  - Mac App Store build
  - direct notarized build

## 2. Goals

- Capture and annotate screenshots with near-zero friction.
- Record short screen flows with clear review/export options.
- Keep memory usage stable across repeated captures.
- Ship a focused macOS product quickly.
- Keep implementation direct, native, and understandable in Swift.

## 3. Non-Goals

- No cloud sync.
- No collaborative editing.
- No plugin system.
- No advanced image editing suite.
- No non-macOS support.
- No cross-platform engine or interop bridge.

## 4. Platform Baseline

- Deployment target: `macOS 15.2+`
- Reason:
  - `SCScreenshotManager.captureImage(in:completionHandler:)` exists on macOS 15.2 and simplifies region capture significantly.
  - Legacy capture APIs in CoreGraphics are marked obsolete and should not be used for new builds.

## 5. Architecture

VivyShot is a Swift-owned macOS app.

The app owns:

- lifecycle, menu bar, and windows
- global hotkey registration
- region selection overlay
- permission checks and screen capture API calls
- screenshot annotation model and command history
- recording setup, review, and export
- clipboard, save panel, share sheet integration
- settings, store, entitlement, and paywall behavior
- App Sandbox, signing, notarization, and App Store packaging

## 6. Dependencies

Runtime dependencies should stay native by default.

Apple frameworks:

- `SwiftUI` and `AppKit` for UI and windowing
- `ScreenCaptureKit` for screenshot capture and recording
- `AVFoundation` for media playback, writing, and export
- `CoreGraphics` for permission checks, geometry, and image interop
- `ImageIO` for PNG/JPEG encoding
- `Carbon` (`RegisterEventHotKey`) for global hotkeys
- `UniformTypeIdentifiers` for export MIME/UTType mapping
- `OSLog` for structured logs and signposts

Tooling:

- Xcode
- Swift
- shell scripts for local packaging and release automation

## 7. Capture Pipeline

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
- Convert the resulting `CGImage` into app-owned image state for annotation and export.

### 7.3 Why This Path

- Single capture call for region mode.
- No stream queue management for one-shot screenshots.
- Lower memory overhead versus long-lived streaming capture for screenshot-only flows.

## 8. Editing Data and Rendering

The screenshot editor should keep:

- immutable base capture image
- mutable annotation commands
- undo/redo history
- dirty-region tracking where useful
- export helpers for clipboard, PNG, and JPEG output

Command variants:

- rectangle
- line
- arrow
- text
- paint
- pixelate rect
- blur rect

Rendering should prefer native image and drawing APIs unless profiling shows a clear bottleneck.

## 9. UX and Interaction Requirements

- Hotkey to capture-ready overlay: target `< 250 ms` on warm app.
- Tool switch response: target `< 16 ms`.
- Primary user flow target:
  - hotkey -> select region -> annotate -> copy/save in `< 10 s`.

## 10. Performance and Memory Budgets

- Idle RSS after launch: target `< 40 MB`.
- Single 4K active edit session: target `< 140 MB`.
- 100 sequential 4K edit sessions should avoid unbounded RSS growth.

## 11. Acceptance Criteria

- macOS app opens, captures a selected region, and displays the screenshot editor.
- User can add annotations, undo/redo, copy, and save.
- Recording flow can create a review window and export.
- Build passes through Xcode.
- App Store build metadata and entitlements are consistent with the shipped feature set.
