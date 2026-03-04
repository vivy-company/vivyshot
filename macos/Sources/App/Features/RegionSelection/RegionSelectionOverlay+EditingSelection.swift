import AppKit

@MainActor
extension RegionSelectionView {
  func startResizingSelection(corner: ResizeCorner) {
    guard mode == .editing, !stitchModeEnabled else {
      return
    }
    guard let committedSelectionRect else {
      return
    }

    activeResizeCorner = corner
    resizeStartRect = committedSelectionRect
  }

  func updateResizingSelection(corner: ResizeCorner, delta: CGPoint) {
    guard mode == .editing, !stitchModeEnabled else {
      return
    }
    guard activeResizeCorner == corner, let startRect = resizeStartRect else {
      return
    }

    guard let resized = resizedSelectionRect(from: startRect, corner: corner, delta: delta) else {
      return
    }

    committedSelectionRect = resized
    areaCaptureRect = resized
    if selectedCaptureMode != .selection {
      selectedCaptureMode = .selection
      refreshToolbar()
    }
    needsLayout = true
    needsDisplay = true
  }

  func finishResizingSelection(corner: ResizeCorner, delta: CGPoint) {
    defer {
      activeResizeCorner = nil
      resizeStartRect = nil
    }

    guard mode == .editing, !stitchModeEnabled else {
      return
    }

    guard activeResizeCorner == corner else {
      return
    }

    updateResizingSelection(corner: corner, delta: delta)
  }

  func beginMovingCapturedSelectionPreview() {
    guard mode == .editing, !stitchModeEnabled else {
      return
    }
  }

  func moveCapturedSelection(by delta: CGPoint) -> Bool {
    guard mode == .editing, !stitchModeEnabled, activeResizeCorner == nil, selectedCaptureMode == .selection else {
      return false
    }
    guard let current = committedSelectionRect?.standardized else {
      return false
    }

    guard let candidate = RustCoreBridge.shared.moveSelectionRect(
      current: current,
      bounds: bounds,
      delta: delta
    ) else {
      return false
    }

    committedSelectionRect = candidate
    areaCaptureRect = candidate.integral
    if selectedCaptureMode != .selection {
      selectedCaptureMode = .selection
      refreshToolbar()
    }
    needsLayout = true
    needsDisplay = true
    return true
  }

  func finishMovingCapturedSelection() {
    guard mode == .editing else {
      return
    }
    needsLayout = true
    needsDisplay = true
  }

  func resizedSelectionRect(from start: CGRect, corner: ResizeCorner, delta: CGPoint) -> CGRect? {
    RustCoreBridge.shared.resizeSelectionRect(
      start: start,
      bounds: bounds,
      corner: corner,
      delta: delta,
      minWidth: 80,
      minHeight: 60
    )?.integral
  }

  func setCaptureModeFromToolbar(_ captureMode: CaptureMode) {
    guard mode == .editing else {
      return
    }
    guard !videoRecordingActive, !videoRecordingStartPending else {
      return
    }

    switch captureMode {
    case .screen:
      selectedCaptureMode = .screen
      screenCapturePickPending = true
      windowCapturePickPending = false
      windowCaptureHoverRect = nil
      committedSelectionRect = bounds.integral
      activeResizeCorner = nil
      resizeStartRect = nil
      refreshToolbar()
      syncLiveCaptureTargetPickingState()
      needsLayout = true
      needsDisplay = true
      if selectedCaptureType == .video {
        TransientToast.show("Click anywhere to start full-screen recording")
      } else {
        TransientToast.show("Click anywhere to capture full screen")
      }
    case .window:
      selectedCaptureMode = .window
      windowCapturePickPending = true
      screenCapturePickPending = false
      updateWindowCaptureHover(at: currentMousePointInView())
      refreshToolbar()
      syncLiveCaptureTargetPickingState()
      window?.invalidateCursorRects(for: self)
      if selectedCaptureType == .video {
        TransientToast.show("Click a window to start recording")
      } else {
        TransientToast.show("Click a window to capture")
      }
    case .selection:
      windowCapturePickPending = false
      screenCapturePickPending = false
      windowCaptureHoverRect = nil
      syncLiveCaptureTargetPickingState()
      if let areaCaptureRect {
        _ = applyCaptureRect(areaCaptureRect, as: .selection, rememberAsArea: true)
      } else if let committedSelectionRect {
        _ = applyCaptureRect(committedSelectionRect, as: .selection, rememberAsArea: true)
      }
    }
  }

  @discardableResult
  func applyCaptureRect(
    _ rect: CGRect,
    as captureMode: CaptureMode,
    rememberAsArea: Bool
  ) -> Bool {
    let clipped = rect.standardized.intersection(bounds).integral
    guard !clipped.isNull, clipped.width >= 2, clipped.height >= 2 else {
      return false
    }

    committedSelectionRect = clipped
    selectedCaptureMode = captureMode
    windowCapturePickPending = false
    screenCapturePickPending = false
    windowCaptureHoverRect = nil
    syncLiveCaptureTargetPickingState()
    window?.invalidateCursorRects(for: self)
    if rememberAsArea {
      areaCaptureRect = clipped
    }
    activeResizeCorner = nil
    resizeStartRect = nil
    refreshToolbar()
    needsLayout = true
    needsDisplay = true
    return true
  }
}
