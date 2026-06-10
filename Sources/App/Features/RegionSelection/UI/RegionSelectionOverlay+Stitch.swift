import AppKit
import CoreGraphics

@MainActor
extension RegionSelectionView {
  func addStitchSegment() {
    if stitchState.recordingActive {
      stopStitchRecording(applyResult: true)
      return
    }
    startStitchRecording()
  }

  func startStitchRecording() {
    canvasView.finishInlineTextEditing(commit: true)

    guard mode == .editing, !stitchState.recordingActive else {
      return
    }
    guard let overlayWindow = window else {
      NSSound.beep()
      return
    }

    let screenFrame = overlayWindow.frame
    let captureRectInScreen: CGRect
    let baseImage: CGImage

    if stitchState.modeEnabled {
      guard let storedRect = stitchState.captureRectInScreen,
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
      stitchState.captureRectInScreen = captureRectInScreen
      stitchState.preImage = currentCanvasImage
      stitchState.preSelectionRect = committedSelectionRect
      stitchState.segmentCount = 1
      stitchState.modeEnabled = true
      activeResizeCorner = nil
      resizeStartRect = nil
      toolbarOffset = .zero
      toolbarDragStartOffset = nil
      if let previousSelection = stitchState.preSelectionRect {
        committedSelectionRect = previousSelection.standardized.integral
      }
      baseImage = selectedImage
    }

    guard let newStitchSession = StitchSession(),
          newStitchSession.setBaseImage(baseImage, baseSegmentCount: stitchState.segmentCount)
    else {
      NSSound.beep()
      return
    }

    stitchState.session = newStitchSession
    stitchState.workingImage = baseImage
    stitchState.directionLocked = false
    stitchState.captureInProgress = false
    resetStitchAutoScrollState()
    refreshAutoScrollTrust(promptIfNeeded: stitchState.autoScrollEnabled)
    if stitchState.autoScrollEnabled, !stitchState.autoScrollTrusted {
      toastPresenter.show("Auto-scroll requires Accessibility permission")
    }
    stitchState.targetApp = resolveStitchTargetAppUnderCursor()
    stitchState.recordingActive = true
    refreshToolbar()
    beginStitchPassThroughOverlay(on: overlayWindow, captureRectInScreen: captureRectInScreen)
    showStitchControlPanel()

    let captureRect = captureRectInScreen

    stitchState.captureTask?.cancel()
    stitchState.captureTask = Task { [weak self] in
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
    guard stitchState.recordingActive || stitchState.passThroughOverlayActive else {
      return
    }

    stitchState.recordingActive = false
    stitchState.captureTask?.cancel()
    stitchState.captureTask = nil
    stitchState.captureInProgress = false
    hideStitchControlPanel()
    restoreOverlayWindowAfterStitchCapture(window)

    if applyResult {
      finalizeStitchWorkingImage()
    } else {
      stitchState.workingImage = nil
      stitchState.directionLocked = false
      resetStitchAutoScrollState()
    }
    stitchState.session = nil

    if applyResult {
      resetStitchAutoScrollState()
    }
    refreshToolbar()
  }

  func runStitchRecordingLoop(
    screenFrame: CGRect,
    captureRectInScreen: CGRect
  ) async {
    while stitchState.recordingActive, mode == .editing {
      let didAutoScrollTick = performAutoScrollTickIfNeeded(captureRectInScreen: captureRectInScreen)
      if didAutoScrollTick {
        let settleDelay = UInt64(max(0.03, stitchAutoScrollSettleInterval) * 1_000_000_000)
        try? await Task.sleep(nanoseconds: settleDelay)
      }

      stitchState.captureInProgress = true
      refreshToolbar()

      let frame = await captureFrameForStitchRecording(
        screenFrame: screenFrame,
        captureRectInScreen: captureRectInScreen
      )

      stitchState.captureInProgress = false
      refreshToolbar()

      if !stitchState.recordingActive || mode != .editing {
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

  func processStitchCapturedFrame(_ frame: CGImage) -> Bool {
    guard stitchState.recordingActive,
          let session = stitchState.session
    else {
      return false
    }
    guard let pushResult = session.pushFrameAndMerge(frame) else {
      return false
    }

    let wasDirectionLocked = stitchState.directionLocked
    let (result, mergedImage) = pushResult
    stitchState.directionLocked = result.directionLocked
    stitchState.segmentCount = max(stitchState.segmentCount, result.segmentCount)

    if stitchState.autoScrollEnabled, !wasDirectionLocked, result.directionLocked {
      stitchState.autoScrollDirectionSign = Int32(result.scrollDirectionSign)
    }

    guard result.accepted, let mergedImage else {
      return false
    }

    stitchState.workingImage = mergedImage
    return true
  }

  func finalizeStitchWorkingImage() {
    defer {
      stitchState.session = nil
      stitchState.workingImage = nil
      stitchState.directionLocked = false
      resetStitchAutoScrollState()
      needsLayout = true
      needsDisplay = true
    }

    guard let stitched = stitchState.workingImage else {
      return
    }

    guard let stitchedSession = AnnotationSession(image: stitched) else {
      NSSound.beep()
      toastPresenter.show("Failed to finalize stitched capture")
      return
    }

    annotationEditor.setSession(stitchedSession)
    canvasView.image = stitched
    stitchState.postEditorMode = isLikelyLongScrollImage(stitched)
    if stitchState.postEditorMode {
      canvasView.configureForScrollingCaptureEditing()
    }
    updateCanvasPreviewStrokeWidth()
    stitchState.modeEnabled = false
    stitchState.captureRectInScreen = nil
    stitchState.preImage = nil
    stitchState.preSelectionRect = nil
    committedSelectionRect = nil
    activeResizeCorner = nil
    resizeStartRect = nil
    toolbarOffset = .zero
    toolbarDragStartOffset = nil

    if stitchState.segmentCount > 1 {
      toastPresenter.show("Captured \(stitchState.segmentCount) segments")
    } else {
      toastPresenter.show("No scrolling movement captured")
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
    guard mode == .editing, stitchState.modeEnabled else {
      NSSound.beep()
      return
    }

    if stitchState.recordingActive || stitchState.passThroughOverlayActive {
      stopStitchRecording(applyResult: false)
    }

    canvasView.finishInlineTextEditing(commit: true)

    guard let preImage = stitchState.preImage,
          let preSelectionRect = stitchState.preSelectionRect,
          let restoredSession = AnnotationSession(image: preImage)
    else {
      NSSound.beep()
      return
    }

    annotationEditor.setSession(restoredSession)
    canvasView.image = preImage
    committedSelectionRect = preSelectionRect.standardized.integral
    stitchState.modeEnabled = false
    stitchState.captureRectInScreen = nil
    stitchState.segmentCount = 1
    stitchState.captureTask?.cancel()
    stitchState.captureTask = nil
    stitchState.recordingActive = false
    stitchState.captureInProgress = false
    stitchState.session = nil
    stitchState.workingImage = nil
    stitchState.directionLocked = false
    resetStitchAutoScrollState()
    stitchState.passThroughOverlayActive = false
    stitchState.postEditorMode = false
    window?.ignoresMouseEvents = false
    hideStitchControlPanel()
    activeResizeCorner = nil
    resizeStartRect = nil
    updateCanvasPreviewStrokeWidth()
    refreshToolbar()
    needsLayout = true
    needsDisplay = true
    toastPresenter.show("Stitch reset")
  }

}
