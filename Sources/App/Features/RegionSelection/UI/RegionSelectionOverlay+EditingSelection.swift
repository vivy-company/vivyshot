import AppKit

@MainActor
extension RegionSelectionView {
  func startResizingSelection(corner: ResizeCorner) {
    guard mode == .editing, !stitchState.modeEnabled else {
      return
    }
    guard let committedSelectionRect else {
      return
    }

    activeResizeCorner = corner
    resizeStartRect = committedSelectionRect
  }

  func updateResizingSelection(corner: ResizeCorner, delta: CGPoint) {
    guard mode == .editing, !stitchState.modeEnabled else {
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
    clearNativeWindowCaptureState()
    if selectedCaptureMode != .selection {
      selectedCaptureMode = .selection
      refreshToolbarSelection(animated: true)
    }
    needsLayout = true
    needsDisplay = true
  }

  func finishResizingSelection(corner: ResizeCorner, delta: CGPoint) {
    defer {
      activeResizeCorner = nil
      resizeStartRect = nil
    }

    guard mode == .editing, !stitchState.modeEnabled else {
      return
    }

    guard activeResizeCorner == corner else {
      return
    }

    updateResizingSelection(corner: corner, delta: delta)
  }

  func beginMovingCapturedSelectionPreview() {
    guard mode == .editing, !stitchState.modeEnabled else {
      return
    }
  }

  func moveCapturedSelection(by delta: CGPoint) -> Bool {
    guard mode == .editing, !stitchState.modeEnabled, activeResizeCorner == nil, selectedCaptureMode == .selection else {
      return false
    }
    guard let current = committedSelectionRect?.standardized else {
      return false
    }

    guard let candidate = SelectionGeometry.moveRect(
      current: current,
      bounds: bounds,
      delta: delta
    ) else {
      return false
    }

    committedSelectionRect = candidate
    areaCaptureRect = candidate.integral
    clearNativeWindowCaptureState()
    if selectedCaptureMode != .selection {
      selectedCaptureMode = .selection
      refreshToolbarSelection(animated: true)
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
    SelectionGeometry.resizeRect(
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
    guard !recordingActive, !recordingStartPending else {
      return
    }

    switch captureMode {
    case .screen:
      selectedCaptureMode = .screen
      screenCapturePickPending = true
      windowCapturePickPending = false
      windowCaptureHoverRect = nil
      clearNativeWindowCaptureState()
      committedSelectionRect = bounds.integral
      activeResizeCorner = nil
      resizeStartRect = nil
      refreshToolbarSelection(animated: true)
      syncLiveCaptureTargetPickingState()
      needsLayout = true
      needsDisplay = true
      if selectedCaptureType == .video {
        toastPresenter.show("Click anywhere to start full-screen recording")
      } else {
        toastPresenter.show("Click anywhere to capture full screen")
      }
    case .window:
      selectedCaptureMode = .window
      windowCapturePickPending = true
      screenCapturePickPending = false
      updateWindowCaptureHover(at: currentMousePointInView())
      refreshToolbarSelection(animated: true)
      syncLiveCaptureTargetPickingState()
      window?.invalidateCursorRects(for: self)
      if selectedCaptureType == .video {
        toastPresenter.show("Click a window to start recording")
      } else {
        toastPresenter.show("Click a window to capture")
      }
    case .selection:
      windowCapturePickPending = false
      screenCapturePickPending = false
      windowCaptureHoverRect = nil
      clearNativeWindowCaptureState()
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
    rememberAsArea: Bool,
    windowID: CGWindowID? = nil
  ) -> Bool {
    let clipped = rect.standardized.intersection(bounds).integral
    guard !clipped.isNull, clipped.width >= 2, clipped.height >= 2 else {
      return false
    }

    committedSelectionRect = clipped
    selectedCaptureMode = captureMode
    selectedWindowID = captureMode == .window ? windowID : nil
    editsWholeImageCapture = false
    windowCapturePickPending = false
    screenCapturePickPending = false
    windowCaptureHoverRect = nil
    syncLiveCaptureTargetPickingState()
    window?.invalidateCursorRects(for: self)
    if rememberAsArea {
      areaCaptureRect = clipped
    }
    refreshNativeWindowScreenshotIfNeeded(windowID: windowID)
    activeResizeCorner = nil
    resizeStartRect = nil
    refreshToolbarSelection(animated: true)
    needsLayout = true
    needsDisplay = true
    return true
  }

  func clearNativeWindowCaptureState() {
    selectedWindowID = nil
    editsWholeImageCapture = false
  }

  private func refreshNativeWindowScreenshotIfNeeded(windowID: CGWindowID?) {
    guard selectedCaptureType == .screenshot,
          selectedCaptureMode == .window,
          settings.screenshotWindowCaptureStyle != .visibleAreaRectangle,
          let windowID
    else {
      return
    }

    let includesShadow = settings.screenshotWindowCaptureStyle == .nativeWithShadow
    Task { @MainActor [weak self] in
      do {
        let image = try await ScreenCaptureSnapshot.captureWindowImage(windowID: windowID, includesShadow: includesShadow)
        guard let self, self.selectedWindowID == windowID else {
          return
        }
        self.annotationEditor.setSession(AnnotationSession(image: image))
        self.canvasView.image = image
        self.editsWholeImageCapture = true
        self.needsLayout = true
        self.needsDisplay = true
      } catch {
        NSLog("[VivyShot] Native window screenshot refresh failed, keeping rectangle capture: \(error.localizedDescription)")
      }
    }
  }
}
