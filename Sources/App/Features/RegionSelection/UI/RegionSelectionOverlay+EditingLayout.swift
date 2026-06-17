import AppKit
import QuartzCore

@MainActor
extension RegionSelectionView {
  func layoutSelectingHint() {
    selectingHintHost.layoutSubtreeIfNeeded()
    let targetSize = selectingHintHost.fittingSize
    guard targetSize.width > 0, targetSize.height > 0 else {
      return
    }

    let maxWidth = max(240, bounds.width - 40)
    let width = min(targetSize.width, maxWidth)
    let x = floor((bounds.width - width) * 0.5)
    let y = floor((bounds.height - targetSize.height) * 0.5)
    selectingHintHost.frame = CGRect(x: x, y: y, width: width, height: targetSize.height).integral
  }

  func updateSelectingHintVisibility(animated: Bool) {
    let shouldShow = settings.captureShowHelper
      && glassChromeReadyForBackdrop
      && mode == .selecting
      && interactionState.isIdle

    if shouldShow {
      layoutSelectingHint()
      if selectingHintHost.isHidden {
        selectingHintHost.isHidden = false
      }
    }

    selectingHintHost.alphaValue = 1
    selectingHintHost.isHidden = !shouldShow
  }

  func layoutCaptureTypePanel() {
    let activeSelection: CGRect?
    if mode == .editing, selectedCaptureMode == .window, windowCapturePickPending {
      activeSelection = windowCaptureHoverRect?.standardized
    } else {
      activeSelection = (selectionRect() ?? committedSelectionRect)?.standardized
    }
    let hasSelection = {
      guard let activeSelection else {
        return false
      }
      return activeSelection.width >= 2 && activeSelection.height >= 2
    }()
    let shouldShow = mode == .selecting || (mode == .editing && hasSelection && !recordingActive)

    guard shouldShow, glassChromeReadyForBackdrop else {
      captureTypeHost.isHidden = true
      return
    }

    captureTypeHost.layoutSubtreeIfNeeded()
    let fit = captureTypeHost.fittingSize
    let panelWidth = max(56, fit.width)
    let panelHeight = max(104, fit.height)

    let padding: CGFloat = 10
    let minX = padding
    let maxX = max(minX, bounds.width - panelWidth - padding)

    let x: CGFloat
    let centeredY: CGFloat
    if let activeSelection {
      let selectionGap: CGFloat = 14
      var candidateX = activeSelection.minX - panelWidth - selectionGap
      if candidateX < minX {
        candidateX = min(maxX, activeSelection.maxX + selectionGap)
      }
      x = candidateX
      centeredY = activeSelection.midY - panelHeight * 0.5
    } else {
      x = minX
      centeredY = bounds.midY - panelHeight * 0.5
    }

    let y = min(max(padding, centeredY), max(padding, bounds.height - panelHeight - padding))

    captureTypeHost.frame = CGRect(x: x, y: y, width: panelWidth, height: panelHeight).integral
    captureTypeHost.alphaValue = 1
    captureTypeHost.isHidden = false
  }

  func layoutEditorChrome() {
    guard mode == .editing else {
      canvasView.isHidden = true
      toolbarHost.isHidden = true
      editingMaskView.isHidden = true
      hideVideoOverlayPlacementViews()
      setResizeHandlesHidden(true)
      return
    }

    if stitchState.passThroughOverlayActive {
      canvasView.isHidden = true
      editingMaskView.isHidden = true
      toolbarHost.isHidden = true
      hideVideoOverlayPlacementViews()
      setResizeHandlesHidden(true)
      return
    }

    let selection = committedSelectionRect?.standardized.integral
    let hidesSelectionFrame = selectedCaptureMode != .selection
    let liveTargetPickActive = windowCapturePickPending || screenCapturePickPending
    let toolbarAnchorSelection = hidesSelectionFrame ? nil : selection
    let isPostStitchEditor = stitchState.postEditorMode && selection == nil
    let topChromeHeight: CGFloat = isPostStitchEditor ? 68 : 0
    let canvasFrame = CGRect(
      x: bounds.minX,
      y: bounds.minY,
      width: bounds.width,
      height: max(1, bounds.height - topChromeHeight)
    ).integral

    canvasView.frame = canvasFrame
    editingMaskView.frame = bounds

    canvasView.isHidden = liveTargetPickActive || recordingActive
    toolbarHost.alphaValue = 1
    updateCanvasPreviewStrokeWidth()

    let shouldShowSelectionMask = !recordingActive
      && !liveTargetPickActive
      && selection != nil
      && (selectedCaptureMode == .selection || selectedCaptureMode == .window)

    if shouldShowSelectionMask, let selection {
      editingMaskView.displayStyle = selectedCaptureMode == .window ? .windowHighlight : .selection
      editingMaskView.selectionRect = selection
      editingMaskView.isHidden = false
    } else {
      editingMaskView.selectionRect = .zero
      editingMaskView.isHidden = true
    }

    if recordingActive {
      setResizeHandlesHidden(true)
      layoutVideoOverlayPlacementViews(selection: selection)
    }

    toolbarHost.layoutSubtreeIfNeeded()
    var toolbarSize = toolbarHost.fittingSize
    if toolbarSize.width < 300 || toolbarSize.height < 30 {
      toolbarSize = CGSize(width: 430, height: 54)
    }

    let padding: CGFloat = 12
    let maxX = max(padding, bounds.width - toolbarSize.width - padding)

    let defaultX: CGFloat
    let defaultY: CGFloat
    let minY: CGFloat
    let maxY: CGFloat
    if let selection = toolbarAnchorSelection {
      minY = padding
      maxY = max(padding, bounds.height - toolbarSize.height - padding)
      defaultX = min(max(padding, selection.midX - toolbarSize.width * 0.5), maxX)
      let proposedBelow = selection.minY - toolbarSize.height - 14
      if proposedBelow >= padding {
        defaultY = proposedBelow
      } else {
        defaultY = min(maxY, selection.maxY + 14)
      }
    } else if hidesSelectionFrame {
      // Full-screen mode: keep controls centered near the bottom edge.
      let bottomInset = captureSurfaceBottomInset()
      minY = padding + bottomInset + 8
      maxY = max(padding, bounds.height - toolbarSize.height - padding)
      defaultX = min(max(padding, bounds.midX - toolbarSize.width * 0.5), maxX)
      defaultY = min(maxY, minY + 26)
    } else if isPostStitchEditor {
      // Default to top-right for long stitched screenshots.
      minY = padding
      maxY = max(padding, bounds.height - toolbarSize.height - padding)
      defaultX = maxX - 4
      defaultY = maxY
    } else {
      minY = padding
      maxY = max(padding, bounds.height - toolbarSize.height - padding)
      defaultX = min(max(padding, bounds.midX - toolbarSize.width * 0.5), maxX)
      defaultY = maxY
    }

    let unclampedX = defaultX + toolbarOffset.width
    let unclampedY = defaultY + toolbarOffset.height
    let x = min(max(padding, unclampedX), maxX)
    let y = min(max(minY, unclampedY), maxY)
    toolbarOffset = CGSize(width: x - defaultX, height: y - defaultY)

    let toolbarFrame = CGRect(
      x: x,
      y: y,
      width: toolbarSize.width,
      height: toolbarSize.height
    ).integral

    let shouldAnimateToolbarFrame = toolbarFrameAnimationPending
      && glassChromeReadyForBackdrop
      && !toolbarHost.isHidden
      && toolbarHost.frame.width > 0
      && toolbarHost.frame.height > 0
      && toolbarHost.frame != toolbarFrame
    toolbarFrameAnimationPending = false

    if shouldAnimateToolbarFrame {
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.26
        context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        toolbarHost.animator().frame = toolbarFrame
      }
    } else {
      toolbarHost.frame = toolbarFrame
    }
    toolbarHost.isHidden = !glassChromeReadyForBackdrop

    if recordingActive {
      updateRecordingToolbarPassthrough()
      return
    }

    if stitchState.modeEnabled || selection == nil || hidesSelectionFrame {
      setResizeHandlesHidden(true)
    } else if let selection {
      layoutResizeHandles(for: selection)
    }

    layoutVideoOverlayPlacementViews(selection: selection)
  }

  func layoutVideoOverlayPlacementViews(selection: CGRect?) {
    guard mode == .editing,
          selectedCaptureType == .video,
          selectedCaptureMode == .selection,
          let selection,
          selection.width >= 2,
          selection.height >= 2,
          !windowCapturePickPending,
          !screenCapturePickPending,
          !stitchState.passThroughOverlayActive,
          !recordingActive
    else {
      hideVideoOverlayPlacementViews()
      return
    }

    if settings.showWebcam {
      webcamPlacementView.containerFrame = selection
      webcamPlacementView.webcamShape = settings.webcamOverlayShape
      webcamPlacementView.webcamAspectRatio = settings.webcamOverlayAspectRatio
      webcamPlacementView.frame = resolvedWebcamOverlayFrame(
        settings.webcamOverlayNormalizedFrame,
        in: selection
      )
      webcamPlacementView.updateWebcamPreview(preferredDeviceID: settings.webcamDeviceID)
      webcamPlacementView.isHidden = false
    } else {
      webcamPlacementView.stopWebcamPreview()
      webcamPlacementView.isHidden = true
    }

    if settings.highlightKeystrokes {
      keystrokePlacementView.containerFrame = selection
      keystrokePlacementView.keystrokeStyle = settings.keystrokeOverlayStyle
      keystrokePlacementView.keystrokeSize = settings.keystrokeOverlaySize
      keystrokePlacementView.frame = RecordingOverlayFrameGeometry.resolvedOverlayFrame(
        settings.keystrokeOverlayNormalizedFrame,
        in: selection
      )
      keystrokePlacementView.isHidden = false
    } else {
      keystrokePlacementView.isHidden = true
    }
  }

  func hideVideoOverlayPlacementViews() {
    webcamPlacementView.stopWebcamPreview()
    webcamPlacementView.isHidden = true
    keystrokePlacementView.isHidden = true
  }

  func resolvedOverlayFrame(_ normalized: CGRect, in container: CGRect) -> CGRect {
    RecordingOverlayFrameGeometry.resolvedOverlayFrame(normalized, in: container)
  }

  func resolvedWebcamOverlayFrame(_ normalized: CGRect, in container: CGRect) -> CGRect {
    RecordingOverlayFrameGeometry.resolvedWebcamOverlayFrame(
      normalized,
      in: container,
      shape: settings.webcamOverlayShape,
      aspectRatio: settings.webcamOverlayAspectRatio
    )
  }

  func normalizedOverlayFrame(_ frame: CGRect, in container: CGRect) -> CGRect {
    RecordingOverlayFrameGeometry.normalizedOverlayFrame(frame, in: container)
  }

  func persistVideoOverlayFrame(_ frame: CGRect, kind: CaptureOverlayPlacementKind) {
    guard let selection = committedSelectionRect?.standardized, selection.width > 0, selection.height > 0 else {
      return
    }
    let normalized = normalizedOverlayFrame(frame, in: selection)
    switch kind {
    case .webcam:
      settings.setWebcamOverlayFrame(normalized)
    case .keystroke:
      settings.setKeystrokeOverlayFrame(normalized)
    }
    needsLayout = true
  }

  func captureSurfaceBottomInset() -> CGFloat {
    guard let hostWindow = window,
          let screen = hostWindow.screen else {
      return 0
    }
    return max(0, screen.visibleFrame.minY - screen.frame.minY)
  }

  func setResizeHandlesHidden(_ hidden: Bool) {
    for handle in resizeHandles.values {
      handle.isHidden = hidden
    }
  }

  func layoutResizeHandles(for selection: CGRect) {
    let size: CGFloat = 20
    let half = size * 0.5

    let positions = selectionHandlePoints(for: selection)

    for (corner, handle) in resizeHandles {
      guard let point = positions[corner] else {
        continue
      }

      handle.frame = CGRect(x: point.x - half, y: point.y - half, width: size, height: size).integral
      handle.isHidden = false
      handle.alphaValue = 0.001
      handle.needsDisplay = false
    }
  }

  func selectionHandlePoints(for selection: CGRect) -> [ResizeCorner: CGPoint] {
    let minX = selection.minX
    let maxX = selection.maxX
    let minY = selection.minY
    let maxY = selection.maxY
    let midX = selection.midX
    let midY = selection.midY

    return [
      .topLeft: CGPoint(x: minX, y: maxY),
      .top: CGPoint(x: midX, y: maxY),
      .topRight: CGPoint(x: maxX, y: maxY),
      .right: CGPoint(x: maxX, y: midY),
      .bottomRight: CGPoint(x: maxX, y: minY),
      .bottom: CGPoint(x: midX, y: minY),
      .bottomLeft: CGPoint(x: minX, y: minY),
      .left: CGPoint(x: minX, y: midY),
    ]
  }
}
