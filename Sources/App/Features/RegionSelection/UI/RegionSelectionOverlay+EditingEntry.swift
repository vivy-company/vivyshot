import AppKit

@MainActor
extension RegionSelectionView {
  func enterEditing(
    session: AnnotationSession?,
    selectionRect: CGRect,
    initialCaptureType: CaptureContentType,
    initialCaptureMode: CaptureMode,
    onDone: @escaping (Bool) -> Void
  ) {
    let clipped = selectionRect.standardized.intersection(bounds).integral
    guard !clipped.isNull, clipped.width >= 2, clipped.height >= 2 else {
      onDone(true)
      return
    }

    let image: CGImage
    if let session {
      guard let sessionImage = session.currentImage() else {
        onDone(true)
        return
      }
      image = sessionImage
    } else if let frozenImage {
      image = frozenImage
    } else {
      onDone(true)
      return
    }

    clearSelectionStateCallbacks()
    annotationEditor.setSession(session)
    selectedCaptureType = initialCaptureType
    selectedCaptureMode = initialCaptureMode
    captureModeSelectionState.setSelectedMode(initialCaptureMode, animated: false)
    resetRecordingState(closePanel: false)
    resetLiveCaptureTargetPickingState(sync: true, resetSmartSelection: true)
    if selectedCaptureType == .video {
      currentTool = .move
    }
    committedSelectionRect = clipped
    areaCaptureRect = initialCaptureMode == .selection ? clipped : nil
    activeResizeCorner = nil
    resizeStartRect = nil
    resetFloatingChromeOffsets()
    resetStitchSessionState(hidePanel: true)

    mode = .editing
    // Editing uses the session-backed canvas image; release the initial frozen frame early.
    frozenImage = nil
    canvasView.image = image
    canvasView.tool = currentTool
    canvasView.accentColor = annotationColor
    updateCanvasPreviewStrokeWidth()
    canvasView.textStyle = textStyle
    canvasView.isHidden = false

    editingMaskView.selectionRect = clipped
    editingMaskView.isHidden = false
    refreshCaptureTypeSidebar()
    refreshToolbar()
    layoutEditorChrome()
    needsLayout = true
    needsDisplay = true
  }
}
