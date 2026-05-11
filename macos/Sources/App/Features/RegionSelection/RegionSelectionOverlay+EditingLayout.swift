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
      && mode == .selecting
      && dragStart == nil
      && dragCurrent == nil
      && committedSelectionRect == nil

    if shouldShow {
      layoutSelectingHint()
      if selectingHintHost.isHidden {
        selectingHintHost.alphaValue = 0
        selectingHintHost.isHidden = false
      }
    }

    let targetAlpha: CGFloat = shouldShow ? 1 : 0

    if animated {
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.14
        context.timingFunction = CAMediaTimingFunction(name: .easeOut)
        selectingHintHost.animator().alphaValue = targetAlpha
      } completionHandler: { [weak self] in
        MainActor.assumeIsolated {
          guard let self else {
            return
          }
          if !shouldShow {
            self.selectingHintHost.isHidden = true
          }
        }
      }
      return
    }

    selectingHintHost.alphaValue = targetAlpha
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
    let shouldShow = (mode == .selecting || mode == .editing) && hasSelection

    guard shouldShow else {
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
    captureTypeHost.isHidden = false
  }

  func layoutEditorChrome() {
    guard mode == .editing else {
      canvasView.isHidden = true
      toolbarHost.isHidden = true
      editingMaskView.isHidden = true
      videoWebcamPlacementView.stopWebcamPreview()
      videoWebcamPlacementView.isHidden = true
      videoKeystrokePlacementView.isHidden = true
      setResizeHandlesHidden(true)
      return
    }

    if stitchPassThroughOverlayActive {
      canvasView.isHidden = true
      editingMaskView.isHidden = true
      toolbarHost.isHidden = true
      videoWebcamPlacementView.stopWebcamPreview()
      videoWebcamPlacementView.isHidden = true
      videoKeystrokePlacementView.isHidden = true
      setResizeHandlesHidden(true)
      return
    }

    let selection = committedSelectionRect?.standardized.integral
    let hidesSelectionFrame = selectedCaptureMode != .selection
    let liveTargetPickActive = windowCapturePickPending || screenCapturePickPending
    let toolbarAnchorSelection = hidesSelectionFrame ? nil : selection
    let isPostStitchEditor = postStitchEditorMode && selection == nil
    let topChromeHeight: CGFloat = isPostStitchEditor ? 68 : 0
    let canvasFrame = CGRect(
      x: bounds.minX,
      y: bounds.minY,
      width: bounds.width,
      height: max(1, bounds.height - topChromeHeight)
    ).integral

    canvasView.frame = canvasFrame
    editingMaskView.frame = bounds

    canvasView.isHidden = liveTargetPickActive
    toolbarHost.isHidden = false
    updateCanvasPreviewStrokeWidth()

    let shouldShowSelectionMask = !liveTargetPickActive
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

    toolbarHost.frame = CGRect(
      x: x,
      y: y,
      width: toolbarSize.width,
      height: toolbarSize.height
    ).integral

    if stitchModeEnabled || selection == nil || hidesSelectionFrame {
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
          !stitchPassThroughOverlayActive
    else {
      videoWebcamPlacementView.stopWebcamPreview()
      videoWebcamPlacementView.isHidden = true
      videoKeystrokePlacementView.isHidden = true
      return
    }

    if settings.videoShowWebcam {
      videoWebcamPlacementView.containerFrame = selection
      videoWebcamPlacementView.webcamShape = settings.videoWebcamOverlayShape
      videoWebcamPlacementView.webcamAspectRatio = settings.videoWebcamOverlayAspectRatio
      videoWebcamPlacementView.frame = resolvedWebcamOverlayFrame(settings.videoWebcamOverlayNormalizedFrame, in: selection)
      videoWebcamPlacementView.updateWebcamPreview(preferredDeviceID: settings.videoWebcamDeviceID)
      videoWebcamPlacementView.isHidden = false
    } else {
      videoWebcamPlacementView.stopWebcamPreview()
      videoWebcamPlacementView.isHidden = true
    }

    if settings.videoHighlightKeystrokes {
      videoKeystrokePlacementView.containerFrame = selection
      videoKeystrokePlacementView.keystrokeStyle = settings.videoKeystrokeOverlayStyle
      videoKeystrokePlacementView.keystrokeSize = settings.videoKeystrokeOverlaySize
      videoKeystrokePlacementView.frame = resolvedOverlayFrame(settings.videoKeystrokeOverlayNormalizedFrame, in: selection)
      videoKeystrokePlacementView.isHidden = false
    } else {
      videoKeystrokePlacementView.isHidden = true
    }
  }

  func resolvedOverlayFrame(_ normalized: CGRect, in container: CGRect) -> CGRect {
    let source = normalized.standardized
    let width = min(max(container.width * source.width, 36), container.width)
    let height = min(max(container.height * source.height, 28), container.height)
    let x = min(max(container.minX, container.minX + container.width * source.minX), container.maxX - width)
    let y = min(max(container.minY, container.minY + container.height * source.minY), container.maxY - height)
    return CGRect(x: x, y: y, width: width, height: height).integral
  }

  func resolvedWebcamOverlayFrame(_ normalized: CGRect, in container: CGRect) -> CGRect {
    let frame = resolvedOverlayFrame(normalized, in: container)
    let aspectRatio = settings.videoWebcamOverlayShape == .circle
      ? VideoWebcamOverlayAspectRatioOption.square
      : settings.videoWebcamOverlayAspectRatio
    return aspectRatio.constrainedFrame(frame, in: container, minimumSize: CGSize(width: 84, height: 84))
  }

  func normalizedOverlayFrame(_ frame: CGRect, in container: CGRect) -> CGRect {
    guard container.width > 0, container.height > 0 else {
      return .zero
    }
    let standardized = frame.standardized
    return CGRect(
      x: (standardized.minX - container.minX) / container.width,
      y: (standardized.minY - container.minY) / container.height,
      width: standardized.width / container.width,
      height: standardized.height / container.height
    )
  }

  func persistVideoOverlayFrame(_ frame: CGRect, kind: CaptureOverlayPlacementKind) {
    guard let selection = committedSelectionRect?.standardized, selection.width > 0, selection.height > 0 else {
      return
    }
    let normalized = normalizedOverlayFrame(frame, in: selection)
    switch kind {
    case .webcam:
      settings.setVideoWebcamOverlayNormalizedFrame(normalized)
    case .keystroke:
      settings.setVideoKeystrokeOverlayNormalizedFrame(normalized)
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
