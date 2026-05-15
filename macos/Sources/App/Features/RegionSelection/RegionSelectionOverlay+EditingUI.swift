import AppKit

@MainActor
extension RegionSelectionView {
  func configureEditorSubviews() {
    canvasView.translatesAutoresizingMaskIntoConstraints = true
    canvasView.isHidden = true
    canvasView.accentColor = annotationColor
    updateCanvasPreviewStrokeWidth()
    addSubview(canvasView)

    editingMaskView.translatesAutoresizingMaskIntoConstraints = true
    editingMaskView.isHidden = true
    addSubview(editingMaskView)

    videoWebcamPlacementView.translatesAutoresizingMaskIntoConstraints = true
    videoWebcamPlacementView.isHidden = true
    videoWebcamPlacementView.onFrameChanged = { [weak self] frame in
      self?.persistVideoOverlayFrame(frame, kind: .webcam)
    }
    addSubview(videoWebcamPlacementView)

    videoKeystrokePlacementView.translatesAutoresizingMaskIntoConstraints = true
    videoKeystrokePlacementView.isHidden = true
    videoKeystrokePlacementView.onFrameChanged = { [weak self] frame in
      self?.persistVideoOverlayFrame(frame, kind: .keystroke)
    }
    addSubview(videoKeystrokePlacementView)

    selectingHintHost.translatesAutoresizingMaskIntoConstraints = true
    selectingHintHost.alphaValue = 0
    selectingHintHost.isHidden = true
    addSubview(selectingHintHost)

    captureTypeHost.translatesAutoresizingMaskIntoConstraints = true
    captureTypeHost.alphaValue = 1
    captureTypeHost.isHidden = true
    addSubview(captureTypeHost)

    for corner in ResizeCorner.allCases {
      let handle = ResizeHandleView(corner: corner)
      handle.translatesAutoresizingMaskIntoConstraints = true
      handle.isHidden = true
      handle.onDragStart = { [weak self] corner in
        self?.startResizingSelection(corner: corner)
      }
      handle.onDragChanged = { [weak self] corner, delta in
        self?.updateResizingSelection(corner: corner, delta: delta)
      }
      handle.onDragEnd = { [weak self] corner, delta in
        self?.finishResizingSelection(corner: corner, delta: delta)
      }
      resizeHandles[corner] = handle
      addSubview(handle)
    }

    toolbarHost.translatesAutoresizingMaskIntoConstraints = true
    toolbarHost.isHidden = true
    addSubview(toolbarHost)
  }

  func configureCanvasCallbacks() {
    canvasView.onViewportChanged = { [weak self] in
      self?.updateCanvasPreviewStrokeWidth()
    }
    canvasView.onCommitRect = { [weak self] rect in
      self?.commitRect(rect)
    }
    canvasView.onCommitFilledRect = { [weak self] rect in
      self?.commitFilledRect(rect)
    }
    canvasView.onCommitCircle = { [weak self] rect in
      self?.commitCircle(rect)
    }
    canvasView.onCommitFilledCircle = { [weak self] rect in
      self?.commitFilledCircle(rect)
    }
    canvasView.onCommitLine = { [weak self] start, end in
      self?.commitLine(from: start, to: end)
    }
    canvasView.onCommitArrow = { [weak self] start, end in
      self?.commitArrow(from: start, to: end)
    }
    canvasView.onCommitPaintPath = { [weak self] points in
      self?.commitPaintPath(points)
    }
    canvasView.onCommitText = { [weak self] text, point in
      self?.commitText(text, at: point)
    }
    canvasView.onCommitPixelateRect = { [weak self] rect in
      self?.commitPixelate(rect)
    }
    canvasView.onCommitBlurRect = { [weak self] rect in
      self?.commitBlur(rect)
    }
    canvasView.onHitTestAnnotation = { [weak self] point in
      guard let self, let session = self.ensureEditingSession() else {
        return nil
      }
      return session.hitTestAnnotation(at: point)
    }
    canvasView.onMoveAnnotation = { [weak self] index, delta in
      guard let self, let session = self.ensureEditingSession() else {
        return nil
      }
      return session.moveAnnotation(index: index, delta: delta)
    }
    canvasView.onResizeAnnotation = { [weak self] index, imageRect in
      guard let self, let session = self.ensureEditingSession() else {
        return nil
      }
      return session.resizeAnnotation(index: index, imageRect: imageRect)
    }
    canvasView.onDeleteAnnotation = { [weak self] index in
      guard let self, let session = self.ensureEditingSession() else {
        return nil
      }
      return session.removeAnnotation(index: index)
    }
    canvasView.onBeginMovingCaptureArea = { [weak self] in
      self?.beginMovingCapturedSelectionPreview()
    }
    canvasView.onMoveCaptureArea = { [weak self] delta in
      guard let self, !self.stitchModeEnabled else {
        return false
      }
      return self.moveCapturedSelection(by: delta)
    }
    canvasView.onFinishMovingCaptureArea = { [weak self] in
      self?.finishMovingCapturedSelection()
    }
  }

  func makeCaptureTypeSidebar() -> CaptureTypeSidebar {
    CaptureTypeSidebar(
      selectedType: selectedCaptureType,
      onSelectType: { [weak self] type in
        self?.setSelectedCaptureType(type)
      }
    )
  }

  func refreshSelectingHint() {
    selectingHintHost.rootView = CaptureHintGlassCard(selectedType: selectedCaptureType)
    needsLayout = true
  }

  func refreshCaptureTypeSidebar() {
    captureTypeHost.rootView = makeCaptureTypeSidebar()
    needsLayout = true
  }

  func observeSettingsChanges() {
    settingsObserver = NotificationCenter.default.addObserver(
      forName: .vivyShotSettingsDidChange,
      object: settings,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.applySettingsFromPreferences()
      }
    }
  }

  func applySettingsFromPreferences() {
    let configuredFontSize = CGFloat(settings.textFontSize)
    let configuredFontName = settings.textFontName
    if abs(textStyle.fontSize - configuredFontSize) > .ulpOfOne || textStyle.fontName != configuredFontName {
      textStyle = EditorTextStyle(
        fontSize: configuredFontSize,
        color: textStyle.color,
        fontName: configuredFontName
      )
    }

    let visibleTools = settings.visibleTools
    if !visibleTools.contains(currentTool) {
      currentTool = visibleTools.first ?? .move
    }

    if mode == .selecting,
       smartMouseDownPoint == nil,
       dragStart == nil,
       dragCurrent == nil,
       committedSelectionRect == nil
    {
      selectedCaptureType = settings.defaultCaptureType
      refreshCaptureTypeSidebar()
      refreshSelectingHint()
    }

    refreshToolbar()
    needsLayout = true
    if mode == .editing {
      layoutEditorChrome()
    }
    updateSelectingHintVisibility(animated: false)
  }

  func finishEditing(animatedClose: Bool = true) {
    canvasView.finishInlineTextEditing(commit: true)
    stitchCaptureTask?.cancel()
    stitchCaptureTask = nil
    stitchRecordingActive = false
    stitchCaptureInProgress = false
    stitchPassThroughOverlayActive = false
    stitchSession = nil
    windowCapturePickPending = false
    screenCapturePickPending = false
    windowCaptureHoverRect = nil
    syncLiveCaptureTargetPickingState()
    stitchDirectionLocked = false
    resetStitchAutoScrollState()
    window?.ignoresMouseEvents = false
    hideStitchControlPanel()
    let callback = onEditingDone
    onEditingDone = nil
    callback?(animatedClose)
  }
}
