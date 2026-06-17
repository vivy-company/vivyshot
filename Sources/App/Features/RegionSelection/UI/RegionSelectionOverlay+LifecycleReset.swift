import AppKit

extension RegionSelectionView {
  func prepareForClose() {
    glassChromeRevealTask?.cancel()
    glassChromeReadyForBackdrop = false
    canvasView.finishInlineTextEditing(commit: true)
    canvasView.image = nil
    frozenImage = nil
    canvasView.isHidden = false
    editingMaskView.isHidden = true
    editingMaskView.selectionRect = .zero
    setResizeHandlesHidden(true)
    clearSelectionStateCallbacks()
    annotationEditor.reset()
    currentScreenshotCaptureID = nil
    screenshotEditorEnteredAt = nil
    webcamPlacementView.stopWebcamPreview()
    recordingController = nil
    selectedCaptureMode = .selection
    captureModeSelectionState.setSelectedMode(.selection, animated: false)
    areaCaptureRect = nil
    clearNativeWindowCaptureState()
    resetLiveCaptureTargetPickingState(sync: true, resetSmartSelection: true)
    resetRecordingState(stopPassthrough: true)
    resetStitchSessionState(hidePanel: true)
    window?.ignoresMouseEvents = false
  }

  func clearSelectionStateCallbacks() {
    delegate = nil
  }

  func resetLiveCaptureTargetPickingState(sync: Bool, resetSmartSelection: Bool) {
    windowCapturePickPending = false
    screenCapturePickPending = false
    windowCaptureHoverRect = nil
    if resetSmartSelection {
      resetSmartSelectionState()
    }
    if sync {
      syncLiveCaptureTargetPickingState()
    }
  }

  func resetRecordingState(stopPassthrough: Bool) {
    let wasActive = recordingState.active
    recordingState = RegionSelectionRecordingState()
    if wasActive {
      updateRecordingFocusPresentation()
    } else if stopPassthrough {
      stopRecordingToolbarPassthrough()
    }
  }

  func resetFloatingChromeOffsets() {
    floatingChromeState = RegionSelectionFloatingChromeState()
  }

  func resetStitchRuntimeState() {
    stitchState.captureInProgress = false
    stitchState.passThroughOverlayActive = false
    stitchState.recordingActive = false
    stitchState.captureTask?.cancel()
    stitchState.captureTask = nil
    stitchState.session = nil
    stitchState.workingImage = nil
    stitchState.directionLocked = false
    resetStitchAutoScrollState()
  }

  func resetStitchSessionState(hidePanel: Bool) {
    stitchState.modeEnabled = false
    stitchState.segmentCount = 1
    resetStitchRuntimeState()
    stitchState.captureRectInScreen = nil
    stitchState.preImage = nil
    stitchState.preSelectionRect = nil
    stitchState.postEditorMode = false
    if hidePanel {
      hideStitchControlPanel()
    }
  }
}
