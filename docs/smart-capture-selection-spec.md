# VivyShot Smart Capture Selection Spec

- Status: Proposed
- Date: 2026-05-15
- Owner: VivyShot
- Related:
  - `AGENTS.md`
  - `macos/Sources/App/Features/Capture/CaptureCoordinator.swift`
  - `macos/Sources/App/Features/RegionSelection/RegionSelectionOverlay.swift`
  - `macos/Sources/App/Features/RegionSelection/RegionSelectionOverlayController.swift`
  - `macos/Sources/App/Features/RegionSelection/RegionSelectionOverlay+EditingTargetPicking.swift`
  - `macos/Sources/App/Features/RegionSelection/RegionSelectionOverlay+EditingSelection.swift`
  - `macos/Sources/App/Shared/UI/CaptureGlassViews.swift`
  - `macos/Sources/App/Shared/UI/CaptureOverlayToolbars.swift`
  - `vivyshot-rs/crates/vivyshot-core/`
  - `vivyshot-rs/crates/vivyshot-ffi/`

## 1. Problem Statement

The current capture flow makes window capture feel like a second step instead of a first-class target.

Today the user enters capture and must first select an area. Only after an area exists does the editing toolbar appear, and only then can the user switch to window mode and click a window.

That means the path for "capture this window" is:

1. Enter capture.
2. Draw an arbitrary area first.
3. Switch capture mode to window.
4. Click the real target window.

This is backwards from the user's intent. When a user enters capture and points at a window, VivyShot should understand that the window is a valid target immediately. When the user drags instead, VivyShot should understand that the user wants a custom area.

## 2. Product Goal

Make the initial capture overlay a smart target picker:

1. Hover a window -> show the same selected-window highlight behavior we already use in window mode.
2. Click a highlighted window -> select that window as the capture target.
3. Drag anywhere -> select a custom area.
4. Do not require the user to draw an area before selecting a window.
5. Keep the existing post-target editor and toolbar behavior.

The short rule:

```text
Enter capture once. Click a window or drag an area.
```

This is not a drag-and-drop interaction. It is normal pointer selection with intent inferred from click vs drag.

## 3. User Experience Specification

### 3.1 Initial Overlay State

When the user enters capture, the overlay starts in a neutral smart selection state.

The user sees:

1. The frozen screen image.
2. The existing dimmed overlay.
3. The capture type selector for screenshot vs video.
4. A short hint.
5. No forced area selection.
6. No visible "smart mode" control.

Recommended hint copy:

1. Screenshot: `Click a window or drag an area`
2. Video: `Click a window or drag an area for video`

If these strings are added to the app, update every supported macOS localization file in the same change.

### 3.2 Hovering A Window

When the pointer is over a capturable window:

1. Highlight the window bounds.
2. Use the same visual language as current selected-window mode.
3. Prefer the existing window highlight rectangle, dimming, and stroke style.
4. Change the cursor to the capture camera cursor if that does not fight the area-selection feel.
5. Keep the screenshot/video selector interactive.

The highlight must not appear for:

1. VivyShot's own overlay and toolbars.
2. Dock and Window Server surfaces.
3. Desktop elements.
4. Invisible, tiny, transparent, or offscreen windows.
5. Windows outside the active capture screen frame.

### 3.3 Clicking A Window

If the user presses and releases without crossing the drag threshold while a window is highlighted:

1. Select that window's bounds as the capture target.
2. Enter the existing post-target editing state.
3. Mark the selected capture mode as `.window`.
4. Do not leave `windowCapturePickPending` active.
5. Do not require a second window-mode click.
6. Do not forward the click to the underlying app.

The selected window should behave as if the user had switched to window mode after area selection and picked that window, except it happens immediately from the initial overlay.

For video, initial window selection should not auto-start recording unless area selection also auto-starts recording. The initial target selection step should only resolve the target and show the existing video toolbar.

### 3.4 Dragging An Area

If the user moves beyond the drag threshold after mouse down:

1. Area selection wins, even if the pointer started over a highlighted window.
2. Hide the window hover highlight.
3. Show the normal area-selection rectangle.
4. On mouse up, select that area as the capture target.
5. Enter the existing post-target editing state.
6. Mark the selected capture mode as `.selection`.

This preserves the muscle memory of the current area-selection flow.

### 3.5 Clicking Empty Space

If the user clicks empty space without crossing the drag threshold:

1. Keep the overlay open.
2. Do not capture full screen.
3. Do not beep repeatedly.
4. Optionally pulse or show the initial hint again.

Single-clicking empty space is too ambiguous to mean full-screen capture. Full-screen capture should remain available through existing screen mode and shortcuts.

### 3.6 After A Target Is Selected

After the first target is selected, the current editing surface remains the source of truth:

1. Screenshot captures still open the annotation/export toolbar.
2. Video captures still open the recording toolbar.
3. The toolbar mode switcher still offers screen, window, and selection.
4. Switching to window mode after this point keeps the existing "click a window to retarget" behavior.
5. Switching back to area mode restores the last area target when available.

Smart selection is only the initial pre-target behavior. It is not a new persistent capture mode.

## 4. Current Code Reality

### 4.1 Current Initial Flow

`CaptureCoordinator.startRegionCapture()` captures a frozen screen image, creates the selection overlay, and waits for `beginSelection(...)` to return a `RegionSelectionResult`.

The result currently contains:

1. `selectionRectInScreen`
2. `captureType`

It does not contain the chosen capture mode.

After the result is returned, `enterEditing(...)` is called with the selected rect and capture type.

### 4.2 Current Initial Pointer Behavior

`RegionSelectionView` currently starts in `OverlayMode.selecting`.

In selecting mode:

1. `mouseDown` always starts an area drag.
2. `mouseDragged` updates the area drag.
3. `mouseUp` commits the area if it is at least 2x2 points.
4. Window hover is not active in this mode.

This is the behavior that forces area selection before window selection.

### 4.3 Current Window Picking

Window picking already exists in `RegionSelectionOverlay+EditingTargetPicking.swift`.

Current useful pieces:

1. `captureRectForWindowPick(at:)` queries `CGWindowListCopyWindowInfo`.
2. It filters out VivyShot, Dock, Window Server, invisible windows, transparent windows, tiny windows, and non-layer-0 windows.
3. It converts CG window bounds into overlay-local Cocoa rects.
4. `updateWindowCaptureHover(...)` tracks a hover rect.
5. `handleGlobalTargetPickClick(...)` applies the window rect.

The missing piece is availability during initial selection.

### 4.4 Current Editing Window Mode

After the user has an area and switches to window mode:

1. `selectedCaptureMode = .window`
2. `windowCapturePickPending = true`
3. Hover updates show a window highlight.
4. Clicking a window applies that rect and resolves the pending pick.

That behavior should remain available after a target is selected. The new smart initial selection should reuse the same target detection and drawing rules where possible.

## 5. Product Decisions

### 5.1 Smart Selection Is Not A Visible Mode

Do not add a fourth toolbar mode called Smart or Auto.

The user should not have to choose between:

1. Area mode.
2. Window mode.
3. Smart mode.

The initial overlay is simply smart by default. After the first target is selected, the existing explicit modes remain useful for retargeting.

### 5.2 Drag Has Priority Over Window Hover

Dragging must always mean area selection.

This matters because a user may start dragging on top of a window. That should not lock them into window capture. Once movement crosses the threshold, VivyShot should commit to area-selection feedback.

### 5.3 Window Clicks Must Be Non-Destructive

The initial overlay must intercept window clicks.

Clicking a highlighted window should select that target in VivyShot. It should not click buttons, links, table rows, text fields, or other UI inside the target app.

The current editing window-pick mode uses global monitors and can set the overlay window to ignore mouse events. That behavior should not be copied into initial smart selection unless we can still guarantee the underlying app does not receive the click.

### 5.4 Target Type Must Travel With The Result

The first selected target needs to preserve whether it came from:

1. `.selection`
2. `.window`
3. `.screen` if a future initial full-screen gesture is added

`RegionSelectionResult` should include the chosen `CaptureMode`.

Without this, `enterEditing(...)` has to assume `.selection`, which makes a clicked window look like an area crop in the toolbar and mode state.

### 5.5 Window Capture Means Existing Window-Bounds Capture

This spec does not introduce a new occlusion-independent `SCWindow` capture pipeline.

For v1, selected window means what current window mode means: use native window detection to choose the window bounds, then capture that rectangle through the existing image/video flow.

Future work can decide whether true per-window ScreenCaptureKit capture is needed.

## 6. Target Interaction Model

Use this conceptual state machine for initial selection:

```text
idle
  move over window -> idle with hoveredWindowRect
  mouse down -> pressed(startPoint, startHoveredWindowRect)

pressed
  move distance < threshold -> pressed, update hover if desired
  move distance >= threshold -> draggingArea(startPoint, currentPoint)
  mouse up with hovered window -> commitWindow(rect)
  mouse up without hovered window -> idle

draggingArea
  move -> update area rect
  mouse up with valid rect -> commitArea(rect)
  mouse up with invalid rect -> idle
```

Recommended thresholds:

1. Drag activation threshold: 5 points.
2. Minimum committed area: keep the existing 2x2 point lower bound unless testing shows accidental tiny captures.

The threshold should be based on squared distance from mouse-down to avoid jitter and touchpad micro-movement.

## 7. Architecture And Ownership

### 7.1 Swift macOS Surface Owns

Swift remains responsible for:

1. Receiving AppKit mouse and keyboard events.
2. Querying macOS window information.
3. Filtering platform-specific window candidates.
4. Drawing native hover and selection feedback.
5. Managing AppKit windows, cursors, and first responder state.
6. Preserving existing screenshot and video toolbar behavior.

### 7.2 Rust Core Should Own Portable Intent Rules

The smart selection decision rules are portable product behavior:

1. Click vs drag threshold.
2. Drag priority over hover.
3. Empty click behavior.
4. Final target kind.
5. Area rectangle normalization and clipping.

Preferred long-term implementation:

1. Add a small pure Rust capture-intent helper in `vivyshot-core`.
2. Expose it through `vivyshot-ffi` only if the macOS surface needs stateful interop.
3. Unit-test click, drag, empty click, and window-hover cases in Rust.
4. Keep macOS window enumeration outside Rust.

The native surface should supply `hoveredWindowRect` as input. Rust should not know about `CGWindowListCopyWindowInfo`, process IDs, window layers, AppKit cursors, or ScreenCaptureKit.

If v1 ships with a Swift-only state machine, it should still follow this spec exactly and keep the logic isolated enough to move into Rust later. Do not scatter the smart-selection rules across unrelated view methods.

## 8. Implementation Plan

### 8.1 Result Model

Update `RegionSelectionResult`:

```swift
struct RegionSelectionResult {
  let selectionRectInScreen: CGRect
  let captureType: CaptureContentType
  let captureMode: CaptureMode
}
```

Update call sites so `CaptureCoordinator` passes `captureMode` into `enterEditing(...)`.

Update `RegionSelectionView.enterEditing(...)` to accept an initial capture mode:

1. `.selection` sets `selectedCaptureMode = .selection` and stores `areaCaptureRect`.
2. `.window` sets `selectedCaptureMode = .window`, applies the rect, and does not leave a pending window pick.
3. `.screen` sets `selectedCaptureMode = .screen`, applies bounds, and does not leave a pending screen pick.

### 8.2 Initial Smart State

Add initial-selection state to `RegionSelectionView`.

Suggested Swift-local fields if the Rust helper is not added in the first patch:

```swift
private var smartMouseDownPoint: CGPoint?
private var smartDragActivated = false
private var smartWindowHoverRect: CGRect?
```

Use names that make it clear this state belongs to pre-target smart selection, not editing window retargeting.

Avoid overloading `windowCapturePickPending` for initial smart selection. Pending pick is an editing-mode concept.

### 8.3 Window Candidate Lookup

Refactor `captureRectForWindowPick(at:)` so it can be used by both:

1. Initial smart selection.
2. Editing-mode window retargeting.

Keep platform filtering in one place.

Add a way to suppress hover when the pointer is over VivyShot controls:

1. Capture type selector.
2. Any future initial overlay controls.
3. Toolbars after editing starts.

### 8.4 Pointer Handling

In selecting mode:

1. `mouseMoved` updates `smartWindowHoverRect`.
2. `mouseDown` records the down point and possible hover candidate.
3. `mouseDragged` checks the drag threshold.
4. Once drag activates, clear the window hover and update the area selection rect.
5. `mouseUp` commits either window or area.

Do not call `beginScreenshotStatisticsSessionIfNeeded()` for every mouse down on empty space. Start statistics only when:

1. A valid window target is committed, or
2. An area drag has actually activated.

### 8.5 Drawing

Update `drawSelectingOverlay(in:)`:

1. If area drag is active, draw the current area selection exactly as today.
2. Else if `smartWindowHoverRect` exists, draw the window highlight.
3. Else draw only the normal dimmed overlay and hint.

Reuse current window highlight drawing where possible so pre-target and post-target window selection feel identical.

### 8.6 Cursor Behavior

Recommended behavior:

1. No hovered window: crosshair.
2. Hovered window: capture camera cursor.
3. Active area drag: crosshair.
4. Over capture type selector: arrow.

The cursor should reinforce the current action without introducing a new visible mode.

### 8.7 Copy And Save Shortcuts

Do not change `Command-C` and `Command-S` semantics in the first pass unless explicitly requested.

Current quick full-screen screenshot shortcuts can remain full-screen helpers. A future follow-up can decide whether a hovered window should become the shortcut target.

### 8.8 Localization

If hint copy changes, update all macOS `.lproj/Localizable.strings` files in the same commit.

Do not leave English-only capture hints.

## 9. Acceptance Criteria

### 9.1 Window Target

1. Enter capture.
2. Move the pointer over a normal app window.
3. VivyShot highlights the window immediately.
4. Click without dragging.
5. VivyShot selects that window as the target.
6. The editor opens with window mode selected.
7. No area selection was required first.
8. The underlying app does not receive the click.

### 9.2 Area Target

1. Enter capture.
2. Press down anywhere, including over a highlighted window.
3. Drag beyond the threshold.
4. VivyShot switches to area-selection feedback.
5. Release the pointer.
6. The editor opens with selection mode selected.

### 9.3 Empty Click

1. Enter capture.
2. Click empty desktop or non-capturable space without dragging.
3. The overlay remains open.
4. No capture is committed.
5. No repeated disruptive beep occurs.

### 9.4 Capture Type

1. Enter capture.
2. Switch between screenshot and video using the capture type selector or shortcuts.
3. Click a window or drag an area.
4. The chosen capture type is preserved in the editing toolbar.

### 9.5 Retargeting After First Selection

1. Select an area or window from initial smart selection.
2. Use the toolbar mode switcher.
3. Window, screen, and area retargeting still work as before.

### 9.6 Multi-Display

1. Start capture while the pointer is on an external display.
2. The overlay appears on that display.
3. Window hover only considers windows on that overlay display.
4. Window and area rects are converted correctly into screen coordinates.

## 10. Validation Plan

Run automated checks:

1. Rust tests if capture-intent logic or FFI changes are added:
   - `cargo test -p vivyshot-core`
   - `cargo test -p vivyshot-ffi`
2. Swift build:
   - `xcodebuild -project macos/VivyShot.xcodeproj -scheme VivyShot -configuration Debug build`
3. If ABI changes are made:
   - `./scripts/gen-ffi.sh`
   - Confirm `ffi/vivyshot_core.h` and `VivyShotKit.xcframework/.../vivyshot_core.h` are consistent.

Manual QA:

1. Screenshot, click window.
2. Screenshot, drag area.
3. Screenshot, empty click.
4. Video, click window.
5. Video, drag area.
6. Switch screenshot/video before selecting.
7. Retarget from editor toolbar to window.
8. Retarget from editor toolbar back to area.
9. External display.
10. Full-screen Space if available.
11. Target windows with overlapping windows.
12. Target windows near menu bar and screen edges.

## 11. Non-Goals

This spec does not include:

1. True `SCWindow`-based occlusion-independent capture.
2. Full-screen capture by empty single click.
3. A new visible Smart capture mode.
4. A new capture landing screen.
5. A redesign of the screenshot editor.
6. A redesign of the video recording toolbar.
7. New paywall behavior.
8. New onboarding.

## 12. Open Follow-Ups

These are intentionally left out of the first implementation:

1. Should hovering a window plus `Command-C` copy that window instead of full screen?
2. Should the initial overlay support keyboard cycling between window candidates under the pointer?
3. Should future Windows/Linux surfaces use the same Rust intent helper through FFI from day one?
4. Should selected-window video capture eventually use true per-window ScreenCaptureKit capture rather than a window-bounds region?
