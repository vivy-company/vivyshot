import AppKit
import ApplicationServices
import CoreGraphics
import QuartzCore
import SwiftUI

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
      self?.session?.hitTestAnnotation(at: point)
    }
    canvasView.onMoveAnnotation = { [weak self] index, delta in
      self?.session?.moveAnnotation(index: index, delta: delta)
    }
    canvasView.onResizeAnnotation = { [weak self] index, imageRect in
      self?.session?.resizeAnnotation(index: index, imageRect: imageRect)
    }
    canvasView.onDeleteAnnotation = { [weak self] index in
      self?.session?.removeAnnotation(index: index)
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

  func layoutEditorChrome() {
    guard mode == .editing else {
      canvasView.isHidden = true
      toolbarHost.isHidden = true
      editingMaskView.isHidden = true
      setResizeHandlesHidden(true)
      return
    }

    if stitchPassThroughOverlayActive {
      canvasView.isHidden = true
      editingMaskView.isHidden = true
      toolbarHost.isHidden = true
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

    let width = current.width
    let height = current.height
    guard width >= 2, height >= 2 else {
      return false
    }

    let minX = bounds.minX
    let maxX = max(minX, bounds.maxX - width)
    let minY = bounds.minY
    let maxY = max(minY, bounds.maxY - height)

    let candidateX = min(max(minX, current.minX + delta.x), maxX)
    let candidateY = min(max(minY, current.minY + delta.y), maxY)
    let candidate = CGRect(x: candidateX, y: candidateY, width: width, height: height).standardized

    guard abs(candidate.minX - current.minX) > 0.01 || abs(candidate.minY - current.minY) > 0.01 else {
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
    var minX = start.minX
    var maxX = start.maxX
    var minY = start.minY
    var maxY = start.maxY

    switch corner {
    case .topLeft:
      minX += delta.x
      maxY += delta.y
    case .top:
      maxY += delta.y
    case .topRight:
      maxX += delta.x
      maxY += delta.y
    case .right:
      maxX += delta.x
    case .bottom:
      minY += delta.y
    case .left:
      minX += delta.x
    case .bottomLeft:
      minX += delta.x
      minY += delta.y
    case .bottomRight:
      maxX += delta.x
      minY += delta.y
    }

    let minWidth: CGFloat = 80
    let minHeight: CGFloat = 60

    switch corner {
    case .topLeft:
      minX = min(minX, maxX - minWidth)
      maxY = max(maxY, minY + minHeight)
    case .top:
      maxY = max(maxY, minY + minHeight)
    case .topRight:
      maxX = max(maxX, minX + minWidth)
      maxY = max(maxY, minY + minHeight)
    case .right:
      maxX = max(maxX, minX + minWidth)
    case .bottom:
      minY = min(minY, maxY - minHeight)
    case .left:
      minX = min(minX, maxX - minWidth)
    case .bottomLeft:
      minX = min(minX, maxX - minWidth)
      minY = min(minY, maxY - minHeight)
    case .bottomRight:
      maxX = max(maxX, minX + minWidth)
      minY = min(minY, maxY - minHeight)
    }

    minX = max(bounds.minX, minX)
    maxX = min(bounds.maxX, maxX)
    minY = max(bounds.minY, minY)
    maxY = min(bounds.maxY, maxY)

    let width = maxX - minX
    let height = maxY - minY
    guard width >= minWidth, height >= minHeight else {
      return nil
    }

    return CGRect(x: minX, y: minY, width: width, height: height).integral
  }

  func makeToolbarView() -> AnyView {
    if mode == .editing, selectedCaptureType == .video {
      return AnyView(makeVideoToolbar())
    }
    return AnyView(makeScreenshotToolbar())
  }

  func makeScreenshotToolbar() -> EditorGlassToolbar {
    EditorGlassToolbar(
      selectedCaptureMode: selectedCaptureMode,
      onSelectCaptureMode: { [weak self] captureMode in
        self?.setCaptureModeFromToolbar(captureMode)
      },
      onCloseCapture: { [weak self] in
        self?.finishEditing()
      },
      selectedTool: currentTool,
      toolOrder: settings.visibleTools,
      selectedColor: Color(annotationColor),
      onSelectTool: { [weak self] tool in
        self?.currentTool = tool
      },
      onColorChange: { [weak self] color in
        self?.setAnnotationColor(color)
      },
      onUndo: { [weak self] in
        self?.performUndo()
      },
      onRedo: { [weak self] in
        self?.performRedo()
      },
      onCopy: { [weak self] in
        self?.performCopy()
      },
      onSave: { [weak self] in
        self?.performSave()
      },
      onAddStitchSegment: { [weak self] in
        self?.addStitchSegment()
      },
      onResetStitch: stitchModeEnabled ? { [weak self] in
        self?.resetStitch()
      } : nil,
      isStitchRecordingActive: stitchRecordingActive,
      isStitchCaptureInProgress: stitchCaptureInProgress,
      onDone: { [weak self] in
        self?.finishEditing()
      },
      onToolbarDrag: { [weak self] translation in
        self?.updateToolbarDrag(translation)
      },
      onToolbarDragEnd: { [weak self] in
        self?.finishToolbarDrag()
      }
    )
  }

  func makeVideoToolbar() -> VideoEditorGlassToolbar {
    VideoEditorGlassToolbar(
      selectedCaptureMode: selectedCaptureMode,
      onSelectCaptureMode: { [weak self] captureMode in
        self?.setCaptureModeFromToolbar(captureMode)
      },
      onCloseCapture: { [weak self] in
        guard let self else { return }
        guard !self.videoRecordingStartPending else { return }
        self.finishEditing()
      },
      recordSystemAudio: settings.videoRecordSystemAudio,
      recordMicrophone: settings.videoRecordMicrophone,
      showWebcam: settings.videoShowWebcam,
      highlightMouseClicks: settings.videoHighlightMouseClicks,
      highlightKeystrokes: settings.videoHighlightKeystrokes,
      toolOrder: settings.visibleVideoTools,
      isRecordingActive: videoRecordingActive,
      isRecordingPending: videoRecordingStartPending,
      countdown: settings.videoCountdown,
      onToggleSystemAudio: { [weak self] in
        _ = self?.performToggleVideoSystemAudioShortcut()
      },
      onToggleMicrophone: { [weak self] in
        _ = self?.performToggleVideoMicrophoneShortcut()
      },
      onToggleWebcam: { [weak self] in
        _ = self?.performToggleVideoWebcamShortcut()
      },
      onToggleMouseClicks: { [weak self] in
        _ = self?.performToggleVideoMouseClicksShortcut()
      },
      onToggleKeystrokes: { [weak self] in
        _ = self?.performToggleVideoKeystrokesShortcut()
      },
      onSelectCountdown: { [weak self] countdown in
        guard let self else { return }
        guard !self.videoRecordingActive, !self.videoRecordingStartPending else { return }
        self.settings.setVideoCountdown(countdown)
        self.refreshToolbar()
      },
      onToggleRecording: { [weak self] in
        self?.toggleVideoRecordingFromEditor()
      },
      onToolbarDrag: { [weak self] translation in
        self?.updateToolbarDrag(translation)
      },
      onToolbarDragEnd: { [weak self] in
        self?.finishToolbarDrag()
      }
    )
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

  func captureRectForWindowPick(at localPoint: CGPoint) -> CGRect? {
    guard let hostWindow = window else {
      return nil
    }
    let screenPoint = CGPoint(
      x: hostWindow.frame.minX + localPoint.x,
      y: hostWindow.frame.minY + localPoint.y
    )

    let selfPID = ProcessInfo.processInfo.processIdentifier
    guard let windowInfo = CGWindowListCopyWindowInfo(
      [.optionOnScreenOnly, .excludeDesktopElements],
      kCGNullWindowID
    ) as? [[String: Any]]
    else {
      return nil
    }

    struct WindowPickCandidate {
      let rect: CGRect
      let layer: Int
      let order: Int
      let area: CGFloat
      let isFrontmostOwner: Bool
    }

    let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
    var candidates: [WindowPickCandidate] = []

    for (order, info) in windowInfo.enumerated() {
      guard let ownerPIDNumber = info[kCGWindowOwnerPID as String] as? NSNumber else {
        continue
      }
      let ownerPID = ownerPIDNumber.int32Value
      if ownerPIDNumber.int32Value == selfPID {
        continue
      }

      let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
      if layer != 0 {
        continue
      }

      if let ownerName = info[kCGWindowOwnerName as String] as? String,
         ownerName == "Dock" || ownerName == "Window Server"
      {
        continue
      }

      if let onscreen = info[kCGWindowIsOnscreen as String] as? NSNumber, !onscreen.boolValue {
        continue
      }

      if let alpha = info[kCGWindowAlpha as String] as? NSNumber, alpha.doubleValue < 0.05 {
        continue
      }

      guard let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
            let cgBounds = CGRect(dictionaryRepresentation: boundsDict),
            cgBounds.width >= 40,
            cgBounds.height >= 30
      else {
        continue
      }

      let screenBounds = overlayCGDisplayRectToCocoaRect(cgBounds)
      guard screenBounds.contains(screenPoint) else {
        continue
      }

      let rect = screenBounds
        .offsetBy(dx: -hostWindow.frame.minX, dy: -hostWindow.frame.minY)
        .integral
      let area = max(1, rect.width * rect.height)
      let isFrontmostOwner = frontmostPID.map { Int32($0) == ownerPID } ?? false

      candidates.append(
        WindowPickCandidate(
          rect: rect,
          layer: layer,
          order: order,
          area: area,
          isFrontmostOwner: isFrontmostOwner
        )
      )
    }

    guard !candidates.isEmpty else {
      return nil
    }

    candidates.sort { lhs, rhs in
      if lhs.isFrontmostOwner != rhs.isFrontmostOwner {
        return lhs.isFrontmostOwner && !rhs.isFrontmostOwner
      }
      if lhs.layer != rhs.layer {
        return lhs.layer < rhs.layer
      }
      if lhs.order != rhs.order {
        return lhs.order < rhs.order
      }
      return lhs.area < rhs.area
    }

    return candidates.first?.rect
  }

  func currentMousePointInView() -> CGPoint? {
    guard let window else {
      return nil
    }
    return convert(window.mouseLocationOutsideOfEventStream, from: nil)
  }

  func localPoint(fromScreenPoint screenPoint: CGPoint) -> CGPoint? {
    guard let hostWindow = window else {
      return nil
    }
    return CGPoint(
      x: screenPoint.x - hostWindow.frame.minX,
      y: screenPoint.y - hostWindow.frame.minY
    )
  }

  func updateWindowCaptureHover(at point: CGPoint?) {
    guard mode == .editing, selectedCaptureMode == .window, windowCapturePickPending, let point else {
      if windowCaptureHoverRect != nil {
        windowCaptureHoverRect = nil
        needsDisplay = true
      }
      return
    }

    let nextHover = captureRectForWindowPick(at: point)?.standardized.integral
    if nextHover != windowCaptureHoverRect {
      windowCaptureHoverRect = nextHover
      needsDisplay = true
    }
  }

  func updateWindowCaptureHover(atScreenPoint screenPoint: CGPoint?) {
    guard let screenPoint else {
      updateWindowCaptureHover(at: nil)
      return
    }
    updateWindowCaptureHover(at: localPoint(fromScreenPoint: screenPoint))
  }

  func captureRectForWindowPick(atScreenPoint screenPoint: CGPoint) -> CGRect? {
    guard let localPoint = localPoint(fromScreenPoint: screenPoint) else {
      return nil
    }
    return captureRectForWindowPick(at: localPoint)
  }

  func syncLiveCaptureTargetPickingState() {
    let shouldPassThrough = mode == .editing && (windowCapturePickPending || screenCapturePickPending)

    guard let hostWindow = window else {
      teardownGlobalTargetPickMonitors()
      return
    }

    hostWindow.ignoresMouseEvents = shouldPassThrough

    if shouldPassThrough {
      installGlobalTargetPickMonitors()
      if windowCapturePickPending {
        updateWindowCaptureHover(atScreenPoint: NSEvent.mouseLocation)
      } else {
        updateWindowCaptureHover(at: nil)
      }
      if selectedCaptureMode == .screen || selectedCaptureMode == .window {
        Self.captureCameraCursor.set()
      }
      needsLayout = true
      needsDisplay = true
    } else {
      teardownGlobalTargetPickMonitors()
      updateWindowCaptureHover(at: nil)
      window?.invalidateCursorRects(for: self)
    }
  }

  func installGlobalTargetPickMonitors() {
    if globalMouseMovedMonitor == nil {
      globalMouseMovedMonitor = NSEvent.addGlobalMonitorForEvents(
        matching: [.mouseMoved, .leftMouseDragged]
      ) { [weak self] event in
        let screenPoint = event.locationInWindow
        Task { @MainActor [weak self, screenPoint] in
          self?.handleGlobalTargetPickMouseMove(screenPoint: screenPoint)
        }
      }
    }

    if globalMouseDownMonitor == nil {
      globalMouseDownMonitor = NSEvent.addGlobalMonitorForEvents(
        matching: [.leftMouseDown]
      ) { [weak self] event in
        let screenPoint = event.locationInWindow
        Task { @MainActor [weak self, screenPoint] in
          self?.handleGlobalTargetPickClick(screenPoint: screenPoint)
        }
      }
    }
  }

  func teardownGlobalTargetPickMonitors() {
    if let globalMouseMovedMonitor {
      NSEvent.removeMonitor(globalMouseMovedMonitor)
      self.globalMouseMovedMonitor = nil
    }

    if let globalMouseDownMonitor {
      NSEvent.removeMonitor(globalMouseDownMonitor)
      self.globalMouseDownMonitor = nil
    }
  }

  func handleGlobalTargetPickMouseMove(screenPoint: CGPoint) {
    guard mode == .editing else {
      return
    }
    guard windowCapturePickPending || screenCapturePickPending else {
      return
    }

    if windowCapturePickPending {
      updateWindowCaptureHover(atScreenPoint: screenPoint)
    }

    if selectedCaptureMode == .screen || selectedCaptureMode == .window {
      Self.captureCameraCursor.set()
    }
  }

  func handleGlobalTargetPickClick(screenPoint: CGPoint) {
    guard mode == .editing else {
      return
    }

    if windowCapturePickPending {
      guard let windowRect = captureRectForWindowPick(atScreenPoint: screenPoint) else {
        NSSound.beep()
        return
      }
      if applyCaptureRect(windowRect, as: .window, rememberAsArea: false),
         selectedCaptureType == .video
      {
        startVideoRecordingFromEditor()
      }
      return
    }

    if screenCapturePickPending {
      if applyCaptureRect(bounds, as: .screen, rememberAsArea: false),
         selectedCaptureType == .video
      {
        startVideoRecordingFromEditor()
      }
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

  func setSelectedCaptureType(_ type: CaptureContentType) {
    guard !videoRecordingActive, !videoRecordingStartPending else {
      return
    }
    guard selectedCaptureType != type else {
      return
    }
    selectedCaptureType = type
    if mode == .editing, type == .video {
      currentTool = .move
      canvasView.finishInlineTextEditing(commit: true)
    }
    settings.setDefaultCaptureType(type)
    refreshCaptureTypeSidebar()
    refreshSelectingHint()
    refreshToolbar()
  }

  func toggleVideoRecordingFromEditor() {
    if videoRecordingStartPending {
      return
    }
    if videoRecordingActive {
      stopVideoRecordingFromEditor()
    } else {
      if !ensureCaptureTargetIsResolved(forRecording: true) {
        return
      }
      startVideoRecordingFromEditor()
    }
  }

  func startVideoRecordingFromEditor() {
    guard mode == .editing else {
      return
    }
    guard !videoRecordingActive, !videoRecordingStartPending else {
      return
    }
    guard ensureCaptureTargetIsResolved(forRecording: true) else {
      return
    }
    guard let selection = committedSelectionRect?.standardized.integral,
          selection.width >= 2,
          selection.height >= 2
    else {
      NSSound.beep()
      return
    }
    videoRecordingStartPending = true
    refreshToolbar()
    settings.setDefaultCaptureType(.video)
    onStartVideoRequested?(selection) { [weak self] started in
      guard let self else {
        return
      }
      self.videoRecordingStartPending = false
      self.videoRecordingActive = started
      self.refreshToolbar()
    }
  }

  func stopVideoRecordingFromEditor() {
    guard videoRecordingActive else {
      return
    }
    videoRecordingActive = false
    videoRecordingStartPending = false
    refreshToolbar()
    onStopVideoRequested?()
  }

  func setAnnotationColor(_ color: Color) {
    let nsColor = NSColor(color)
    guard let rgb = nsColor.usingColorSpace(.deviceRGB) else {
      return
    }
    annotationColor = rgb
  }

  func refreshToolbar() {
    toolbarHost.rootView = makeToolbarView()
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

    if mode == .selecting, dragStart == nil, dragCurrent == nil, committedSelectionRect == nil {
      selectedCaptureType = settings.defaultCaptureType
      refreshCaptureTypeSidebar()
      refreshSelectingHint()
    }

    refreshToolbar()
    updateSelectingHintVisibility(animated: false)
  }

  func updateToolbarDrag(_ translation: CGSize) {
    guard mode == .editing else {
      return
    }

    if toolbarDragStartOffset == nil {
      toolbarDragStartOffset = toolbarOffset
    }

    let start = toolbarDragStartOffset ?? .zero
    toolbarOffset = CGSize(
      width: start.width + translation.width,
      height: start.height + translation.height
    )
    needsLayout = true
  }

  func finishToolbarDrag() {
    toolbarDragStartOffset = nil
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
