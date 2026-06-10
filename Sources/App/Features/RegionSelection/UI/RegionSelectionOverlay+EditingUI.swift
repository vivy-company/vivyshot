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

    webcamPlacementView.translatesAutoresizingMaskIntoConstraints = true
    webcamPlacementView.isHidden = true
    webcamPlacementView.onFrameChanged = { [weak self] frame in
      self?.persistVideoOverlayFrame(frame, kind: .webcam)
    }
    addSubview(webcamPlacementView)

    keystrokePlacementView.translatesAutoresizingMaskIntoConstraints = true
    keystrokePlacementView.isHidden = true
    keystrokePlacementView.onFrameChanged = { [weak self] frame in
      self?.persistVideoOverlayFrame(frame, kind: .keystroke)
    }
    addSubview(keystrokePlacementView)

    selectingHintHost.translatesAutoresizingMaskIntoConstraints = true
    selectingHintHost.alphaValue = 1
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
    toolbarHost.alphaValue = 1
    toolbarHost.isHidden = true
    addSubview(toolbarHost)
  }

  func configureCanvasCallbacks() {
    canvasView.delegate = self
  }

  func makeCaptureTypeSidebar() -> CaptureTypeSidebar {
    CaptureTypeSidebar(
      selectedType: selectedCaptureType,
      usesExternalGlassSurface: true,
      onSelectType: { [weak self] type in
        self?.setSelectedCaptureType(type)
      }
    )
  }

  func refreshSelectingHint() {
    selectingHintHost.rootView = CaptureHintGlassCard(selectedType: selectedCaptureType, usesExternalGlassSurface: true)
    needsLayout = true
  }

  func refreshCaptureTypeSidebar() {
    captureTypeHost.rootView = makeCaptureTypeSidebar()
    needsLayout = true
  }

  func observeSettingsChanges() {
    let cancellable = settings.regionSelectionSettingsChanges
      .sink { [weak self] in
        self?.applySettingsFromPreferences()
      }
    settingsCancellables.append(cancellable)
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

    if mode == .selecting, interactionState.isIdle {
      selectedCaptureType = settings.defaultCaptureType
      refreshCaptureTypeSidebar()
      refreshSelectingHint()
    }

    refreshToolbar()
    updateCanvasPreviewStrokeWidth()
    needsLayout = true
    if mode == .editing {
      layoutEditorChrome()
    }
    updateSelectingHintVisibility(animated: false)
  }

  func finishEditing(animatedClose: Bool = true) {
    canvasView.finishInlineTextEditing(commit: true)
    resetStitchRuntimeState()
    resetLiveCaptureTargetPickingState(sync: true, resetSmartSelection: false)
    window?.ignoresMouseEvents = false
    hideStitchControlPanel()
    delegate?.regionSelectionView(self, didFinishEditingAnimatedClose: animatedClose)
  }
}

extension RegionSelectionView: AnnotationCanvasViewDelegate {
  func annotationCanvasViewDidChangeViewport(_ canvasView: AnnotationCanvasView) {
    updateCanvasPreviewStrokeWidth()
  }

  func annotationCanvasView(_ canvasView: AnnotationCanvasView, didCommit commit: AnnotationCanvasCommit) {
    commitAnnotationCanvasChange(commit)
  }

  func annotationCanvasView(_ canvasView: AnnotationCanvasView, hitTestAnnotationAt point: CGPoint) -> AnnotationInfo? {
    annotationEditor.hitTestAnnotation(at: point, currentImage: canvasView.image)
  }

  func annotationCanvasView(
    _ canvasView: AnnotationCanvasView,
    moveAnnotationAt index: Int,
    by delta: CGPoint
  ) -> CGImage? {
    annotationEditor.moveAnnotation(index: index, delta: delta, currentImage: canvasView.image)
  }

  func annotationCanvasView(
    _ canvasView: AnnotationCanvasView,
    resizeAnnotationAt index: Int,
    to imageRect: CGRect
  ) -> CGImage? {
    annotationEditor.resizeAnnotation(index: index, imageRect: imageRect, currentImage: canvasView.image)
  }

  func annotationCanvasView(_ canvasView: AnnotationCanvasView, deleteAnnotationAt index: Int) -> CGImage? {
    annotationEditor.removeAnnotation(index: index, currentImage: canvasView.image)
  }

  func annotationCanvasViewWillMoveCaptureArea(_ canvasView: AnnotationCanvasView) {
    beginMovingCapturedSelectionPreview()
  }

  func annotationCanvasView(_ canvasView: AnnotationCanvasView, moveCaptureAreaBy delta: CGPoint) -> Bool {
    guard !stitchState.modeEnabled else {
      return false
    }
    return moveCapturedSelection(by: delta)
  }

  func annotationCanvasViewDidFinishMovingCaptureArea(_ canvasView: AnnotationCanvasView) {
    finishMovingCapturedSelection()
  }
}
