import AppKit
import ApplicationServices
import CoreGraphics
import ScreenCaptureKit
import SwiftUI

@MainActor
extension RegionSelectionView {
  func addStitchSegment() {
    if stitchRecordingActive {
      stopStitchRecording(applyResult: true)
      return
    }
    startStitchRecording()
  }

  func startStitchRecording() {
    canvasView.finishInlineTextEditing(commit: true)

    guard mode == .editing, !stitchRecordingActive else {
      return
    }
    guard let overlayWindow = window else {
      NSSound.beep()
      return
    }

    let screenFrame = overlayWindow.frame
    let captureRectInScreen: CGRect
    let baseImage: CGImage

    if stitchModeEnabled {
      guard let storedRect = stitchCaptureRectInScreen,
            let existingImage = canvasView.image
      else {
        NSSound.beep()
        return
      }
      captureRectInScreen = storedRect
      baseImage = existingImage
    } else {
      guard let currentSelection = committedSelectionRect?.standardized,
            currentSelection.width >= 2,
            currentSelection.height >= 2,
            let selectedImage = exportImageForCurrentSelection(),
            let currentCanvasImage = canvasView.image
      else {
        NSSound.beep()
        return
      }

      captureRectInScreen = currentSelection
        .offsetBy(dx: screenFrame.minX, dy: screenFrame.minY)
        .standardized
      stitchCaptureRectInScreen = captureRectInScreen
      preStitchImage = currentCanvasImage
      preStitchSelectionRect = committedSelectionRect
      stitchSegmentCount = 1
      stitchModeEnabled = true
      activeResizeCorner = nil
      resizeStartRect = nil
      toolbarOffset = .zero
      toolbarDragStartOffset = nil
      if let previousSelection = preStitchSelectionRect {
        committedSelectionRect = previousSelection.standardized.integral
      }
      baseImage = selectedImage
    }

    guard let rustStitchSession = RustCoreBridge.shared.makeStitchSession(),
          rustStitchSession.setBaseImage(baseImage, baseSegmentCount: stitchSegmentCount)
    else {
      NSSound.beep()
      return
    }

    stitchSession = rustStitchSession
    stitchWorkingImage = baseImage
    stitchDirectionLocked = false
    stitchCaptureInProgress = false
    resetStitchAutoScrollState()
    refreshAutoScrollTrust(promptIfNeeded: stitchAutoScrollEnabled)
    if stitchAutoScrollEnabled, !stitchAutoScrollTrusted {
      TransientToast.show("Auto-scroll requires Accessibility permission")
    }
    stitchTargetApp = resolveStitchTargetAppUnderCursor()
    stitchRecordingActive = true
    refreshToolbar()
    beginStitchPassThroughOverlay(on: overlayWindow, captureRectInScreen: captureRectInScreen)
    showStitchControlPanel()

    let captureRect = captureRectInScreen

    stitchCaptureTask?.cancel()
    stitchCaptureTask = Task { [weak self] in
      guard let self else {
        return
      }
      await self.runStitchRecordingLoop(
        screenFrame: screenFrame,
        captureRectInScreen: captureRect
      )
    }
  }

  func stopStitchRecording(applyResult: Bool) {
    guard stitchRecordingActive || stitchPassThroughOverlayActive else {
      return
    }

    stitchRecordingActive = false
    stitchCaptureTask?.cancel()
    stitchCaptureTask = nil
    stitchCaptureInProgress = false
    hideStitchControlPanel()
    restoreOverlayWindowAfterStitchCapture(window)

    if applyResult {
      finalizeStitchWorkingImage()
    } else {
      stitchWorkingImage = nil
      stitchDirectionLocked = false
      resetStitchAutoScrollState()
    }
    stitchSession = nil

    if applyResult {
      resetStitchAutoScrollState()
    }
    refreshToolbar()
  }

  func runStitchRecordingLoop(
    screenFrame: CGRect,
    captureRectInScreen: CGRect
  ) async {
    while stitchRecordingActive, mode == .editing {
      let didAutoScrollTick = performAutoScrollTickIfNeeded(captureRectInScreen: captureRectInScreen)
      if didAutoScrollTick {
        let settleDelay = UInt64(max(0.03, stitchAutoScrollSettleInterval) * 1_000_000_000)
        try? await Task.sleep(nanoseconds: settleDelay)
      }

      stitchCaptureInProgress = true
      refreshToolbar()

      let frame = await captureFrameForStitchRecording(
        screenFrame: screenFrame,
        captureRectInScreen: captureRectInScreen
      )

      stitchCaptureInProgress = false
      refreshToolbar()

      if !stitchRecordingActive || mode != .editing {
        break
      }

      var merged = false
      if let frame {
        merged = processStitchCapturedFrame(frame)
      }

      if didAutoScrollTick {
        updateAutoScrollFeedback(didMerge: merged)
      }

      let interval = didAutoScrollTick ? max(0.08, stitchCaptureInterval * 0.85) : max(0.08, stitchCaptureInterval)
      let delay = UInt64(interval * 1_000_000_000)
      try? await Task.sleep(nanoseconds: delay)
    }
  }

  func resetStitchAutoScrollState() {
    let state = RustCoreBridge.shared.resetStitchAutoScrollState()
    applyRustStitchAutoScrollState(state)
    stitchAutoScrollTrusted = false
    stitchTargetApp = nil
  }

  func currentRustStitchAutoScrollState() -> RustStitchAutoScrollState {
    RustStitchAutoScrollState(
      directionSign: stitchAutoScrollDirectionSign,
      noMotionTicks: UInt32(max(0, stitchAutoScrollNoMotionTicks)),
      didFlipDirection: stitchAutoScrollDidFlipDirection
    )
  }

  func applyRustStitchAutoScrollState(_ state: RustStitchAutoScrollState) {
    stitchAutoScrollDirectionSign = state.directionSign == 0 ? -1 : state.directionSign
    stitchAutoScrollNoMotionTicks = Int(state.noMotionTicks)
    stitchAutoScrollDidFlipDirection = state.didFlipDirection
  }

  func refreshAutoScrollTrust(promptIfNeeded: Bool) {
    guard stitchAutoScrollEnabled else {
      stitchAutoScrollTrusted = false
      return
    }

    if promptIfNeeded, !stitchAutoScrollPromptAttempted {
      stitchAutoScrollPromptAttempted = true
      let options = ["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary
      stitchAutoScrollTrusted = AXIsProcessTrustedWithOptions(options)
    } else {
      stitchAutoScrollTrusted = AXIsProcessTrusted()
    }
  }

  func resolveStitchTargetAppUnderCursor() -> NSRunningApplication? {
    resolveStitchTargetApp(at: NSEvent.mouseLocation)
  }

  func resolveStitchTargetApp(at point: CGPoint) -> NSRunningApplication? {
    guard let windowInfo = CGWindowListCopyWindowInfo(
      [.optionOnScreenOnly, .excludeDesktopElements],
      kCGNullWindowID
    ) as? [[String: Any]]
    else {
      return nil
    }

    let selfPID = ProcessInfo.processInfo.processIdentifier
    for info in windowInfo {
      guard let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
            let bounds = CGRect(dictionaryRepresentation: boundsDict),
            bounds.contains(point),
            let ownerPIDNumber = info[kCGWindowOwnerPID as String] as? NSNumber
      else {
        continue
      }

      let ownerPID = ownerPIDNumber.int32Value
      if ownerPID == selfPID {
        continue
      }
      if let app = NSRunningApplication(processIdentifier: ownerPID), !app.isTerminated {
        return app
      }
    }
    return nil
  }

  func performAutoScrollTickIfNeeded(captureRectInScreen: CGRect) -> Bool {
    guard stitchAutoScrollEnabled else {
      return false
    }

    guard stitchAutoScrollTrusted else {
      return false
    }

    if stitchTargetApp == nil || stitchTargetApp?.isTerminated == true {
      let targetPoint = CGPoint(x: captureRectInScreen.midX, y: captureRectInScreen.midY)
      stitchTargetApp = resolveStitchTargetApp(at: targetPoint)
    }

    let delta = max(1, stitchAutoScrollStepLines) * stitchAutoScrollDirectionSign
    guard let scrollEvent = CGEvent(
      scrollWheelEvent2Source: nil,
      units: .line,
      wheelCount: 1,
      wheel1: delta,
      wheel2: 0,
      wheel3: 0
      ) else {
      return false
    }

    if let targetApp = stitchTargetApp, !targetApp.isTerminated {
      if !targetApp.isActive {
        targetApp.activate(options: [])
      }
      scrollEvent.postToPid(targetApp.processIdentifier)
    } else {
      scrollEvent.post(tap: .cghidEventTap)
    }

    return true
  }

  func updateAutoScrollFeedback(didMerge: Bool) {
    let next = RustCoreBridge.shared.updateStitchAutoScrollState(
      enabled: stitchAutoScrollEnabled,
      directionLocked: stitchDirectionLocked,
      didMerge: didMerge,
      thresholdTicks: 4,
      state: currentRustStitchAutoScrollState()
    )
    applyRustStitchAutoScrollState(next)
  }

  func processStitchCapturedFrame(_ frame: CGImage) -> Bool {
    guard stitchRecordingActive,
          let stitchSession
    else {
      return false
    }
    guard let pushResult = stitchSession.pushFrameAndMerge(frame) else {
      return false
    }

    let wasDirectionLocked = stitchDirectionLocked
    let (result, mergedImage) = pushResult
    stitchDirectionLocked = result.directionLocked
    stitchSegmentCount = max(stitchSegmentCount, result.segmentCount)

    if stitchAutoScrollEnabled, !wasDirectionLocked, result.directionLocked {
      stitchAutoScrollDirectionSign = Int32(result.scrollDirectionSign)
    }

    guard result.accepted, let mergedImage else {
      return false
    }

    stitchWorkingImage = mergedImage
    return true
  }

  func finalizeStitchWorkingImage() {
    defer {
      stitchSession = nil
      stitchWorkingImage = nil
      stitchDirectionLocked = false
      resetStitchAutoScrollState()
      needsLayout = true
      needsDisplay = true
    }

    guard let stitched = stitchWorkingImage else {
      return
    }

    guard let stitchedSession = RustCoreBridge.shared.makeSession(image: stitched) else {
      NSSound.beep()
      TransientToast.show("Failed to finalize stitched capture")
      return
    }

    session = stitchedSession
    canvasView.image = stitched
    postStitchEditorMode = isLikelyLongScrollImage(stitched)
    if postStitchEditorMode {
      canvasView.configureForScrollingCaptureEditing()
    }
    updateCanvasPreviewStrokeWidth()
    stitchModeEnabled = false
    stitchCaptureRectInScreen = nil
    preStitchImage = nil
    preStitchSelectionRect = nil
    committedSelectionRect = nil
    activeResizeCorner = nil
    resizeStartRect = nil
    toolbarOffset = .zero
    toolbarDragStartOffset = nil

    if stitchSegmentCount > 1 {
      TransientToast.show("Captured \(stitchSegmentCount) segments")
    } else {
      TransientToast.show("No scrolling movement captured")
    }
  }

  func isLikelyLongScrollImage(_ image: CGImage) -> Bool {
    let width = CGFloat(image.width)
    let height = CGFloat(image.height)
    guard width > 0, height > 0 else {
      return false
    }
    return height >= width * 1.6
  }

  func resetStitch() {
    guard mode == .editing, stitchModeEnabled else {
      NSSound.beep()
      return
    }

    if stitchRecordingActive || stitchPassThroughOverlayActive {
      stopStitchRecording(applyResult: false)
    }

    canvasView.finishInlineTextEditing(commit: true)

    guard let preStitchImage,
          let preStitchSelectionRect,
          let restoredSession = RustCoreBridge.shared.makeSession(image: preStitchImage)
    else {
      NSSound.beep()
      return
    }

    session = restoredSession
    canvasView.image = preStitchImage
    committedSelectionRect = preStitchSelectionRect.standardized.integral
    stitchModeEnabled = false
    stitchCaptureRectInScreen = nil
    stitchSegmentCount = 1
    stitchCaptureTask?.cancel()
    stitchCaptureTask = nil
    stitchRecordingActive = false
    stitchCaptureInProgress = false
    stitchSession = nil
    stitchWorkingImage = nil
    stitchDirectionLocked = false
    resetStitchAutoScrollState()
    stitchPassThroughOverlayActive = false
    postStitchEditorMode = false
    window?.ignoresMouseEvents = false
    hideStitchControlPanel()
    activeResizeCorner = nil
    resizeStartRect = nil
    updateCanvasPreviewStrokeWidth()
    refreshToolbar()
    needsLayout = true
    needsDisplay = true
    TransientToast.show("Stitch reset")
  }

  func captureFrameForStitchRecording(
    screenFrame: CGRect,
    captureRectInScreen: CGRect
  ) async -> CGImage? {
    guard let capturedImage = await captureScreenImage(frame: screenFrame) else {
      return nil
    }

    return cropSegment(
      from: capturedImage,
      captureRectInScreen: captureRectInScreen,
      screenFrame: screenFrame
    )
  }

  func restoreOverlayWindowAfterStitchCapture(_ overlayWindow: NSWindow?) {
    stitchPassThroughOverlayActive = false
    guard let overlayWindow else {
      needsLayout = true
      needsDisplay = true
      return
    }
    overlayWindow.ignoresMouseEvents = false
    NSApp.activate(ignoringOtherApps: true)
    overlayWindow.makeKeyAndOrderFront(nil)
    overlayWindow.makeFirstResponder(self)
    overlayWindow.invalidateCursorRects(for: self)
    needsLayout = true
    needsDisplay = true
  }

  func beginStitchPassThroughOverlay(on overlayWindow: NSWindow, captureRectInScreen: CGRect) {
    stitchPassThroughOverlayActive = true
    overlayWindow.ignoresMouseEvents = true
    canvasView.finishInlineTextEditing(commit: true)
    setResizeHandlesHidden(true)
    needsLayout = true
    needsDisplay = true
    overlayWindow.invalidateCursorRects(for: self)

    if stitchAutoScrollEnabled, stitchAutoScrollTrusted {
      if stitchTargetApp == nil || stitchTargetApp?.isTerminated == true {
        let targetPoint = CGPoint(x: captureRectInScreen.midX, y: captureRectInScreen.midY)
        stitchTargetApp = resolveStitchTargetApp(at: targetPoint)
      }
      stitchTargetApp?.activate(options: [])
    }
  }

  func showStitchControlPanel() {
    guard stitchRecordingActive, let overlayWindow = window else {
      return
    }

    let host = NSHostingView(
      rootView: StitchRecordingFloatingBar(
        onStop: { [weak self] in
          self?.stopStitchRecording(applyResult: true)
        }
      )
    )
    host.layoutSubtreeIfNeeded()
    var panelSize = host.fittingSize
    if panelSize.width < 150 || panelSize.height < 40 {
      panelSize = CGSize(width: 164, height: 44)
    }
    host.frame = CGRect(origin: .zero, size: panelSize)

    let panel: NSPanel
    if let existing = stitchControlPanel {
      panel = existing
      panel.setContentSize(panelSize)
    } else {
      panel = NSPanel(
        contentRect: CGRect(origin: .zero, size: panelSize),
        styleMask: [.nonactivatingPanel, .borderless],
        backing: .buffered,
        defer: false
      )
      panel.isReleasedWhenClosed = false
      panel.isOpaque = false
      panel.backgroundColor = .clear
      panel.hasShadow = true
      panel.level = NSWindow.Level(rawValue: max(NSWindow.Level.statusBar.rawValue, overlayWindow.level.rawValue + 2))
      panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
      panel.hidesOnDeactivate = false
      panel.ignoresMouseEvents = false
      panel.isMovable = false
      panel.isMovableByWindowBackground = false
      stitchControlPanel = panel
    }

    panel.contentView = host
    positionStitchControlPanel(panel, relativeTo: overlayWindow)
    panel.orderFrontRegardless()
  }

  func positionStitchControlPanel(_ panel: NSPanel, relativeTo overlayWindow: NSWindow) {
    let panelSize = panel.frame.size
    let anchor = committedSelectionRect ?? CGRect(
      x: bounds.midX - 140,
      y: bounds.midY - 80,
      width: 280,
      height: 160
    )

    let margin: CGFloat = 14
    let maxX = max(margin, bounds.width - panelSize.width - margin)
    var localX = anchor.midX - panelSize.width * 0.5
    localX = min(max(margin, localX), maxX)

    var localY = anchor.minY - panelSize.height - 12
    if localY < margin {
      let maxY = max(margin, bounds.height - panelSize.height - margin)
      localY = min(max(margin, anchor.maxY + 12), maxY)
    }

    panel.setFrame(
      CGRect(
        x: overlayWindow.frame.minX + localX,
        y: overlayWindow.frame.minY + localY,
        width: panelSize.width,
        height: panelSize.height
      ).integral,
      display: false
    )
  }

  func hideStitchControlPanel() {
    stitchControlPanel?.orderOut(nil)
    stitchControlPanel = nil
  }

  func captureScreenImage(frame: CGRect) async -> CGImage? {
    guard #available(macOS 15.2, *) else {
      return nil
    }

    return await withCheckedContinuation { continuation in
      SCScreenshotManager.captureImage(in: overlayCocoaRectToCGDisplayRect(frame)) { image, _ in
        continuation.resume(returning: image)
      }
    }
  }

  func cropSegment(
    from image: CGImage,
    captureRectInScreen: CGRect,
    screenFrame: CGRect
  ) -> CGImage? {
    let clippedSelection = captureRectInScreen.standardized.intersection(screenFrame)
    guard !clippedSelection.isNull, clippedSelection.width >= 2, clippedSelection.height >= 2 else {
      return nil
    }

    let localRect = clippedSelection.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
    let scaleX = CGFloat(image.width) / screenFrame.width
    let scaleY = CGFloat(image.height) / screenFrame.height

    let x = localRect.minX * scaleX
    let yTop = CGFloat(image.height) - (localRect.maxY * scaleY)
    let width = localRect.width * scaleX
    let height = localRect.height * scaleY

    var cropRect = CGRect(
      x: floor(x),
      y: floor(yTop),
      width: ceil(width),
      height: ceil(height)
    )

    let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    cropRect = cropRect.intersection(imageBounds)

    guard !cropRect.isNull, cropRect.width >= 2, cropRect.height >= 2 else {
      return nil
    }

    let integral = cropRect.integral
    return RustCoreBridge.shared.cropImage(image, imageRect: integral) ?? image.cropping(to: integral)
  }
}
