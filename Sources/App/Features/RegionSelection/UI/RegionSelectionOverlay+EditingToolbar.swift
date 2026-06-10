import AppKit
import SwiftUI

@MainActor
extension RegionSelectionView {
  func makeToolbarView(glassNamespace: Namespace.ID) -> AnyView {
    if mode == .editing, selectedCaptureType == .video {
      if recordingActive {
        return AnyView(makeRecordingControlBar())
      }
      return AnyView(makeCaptureVideoToolbar(glassNamespace: glassNamespace))
    }
    return AnyView(makeScreenshotToolbar(glassNamespace: glassNamespace))
  }

  func makeScreenshotToolbar(glassNamespace: Namespace.ID? = nil) -> CaptureAnnotationToolbar {
    CaptureAnnotationToolbar(
      modeSelectionState: captureModeSelectionState,
      glassNamespace: glassNamespace,
      usesExternalGlassSurface: true,
      selectedTool: currentTool,
      toolOrder: settings.visibleTools,
      selectedColor: Color(annotationColor),
      stitchState: stitchToolbarState(),
      mainAction: settings.screenshotMainAction,
      accentColor: Color(settings.toolbarAccentColor),
      onAction: { [weak self] action in
        self?.handleAnnotationToolbarAction(action)
      }
    )
  }

  func stitchToolbarState() -> StitchToolbarState? {
    guard RegionSelectionFeatureFlags.stitchCaptureEnabled else {
      return nil
    }
    return StitchToolbarState(
      canReset: stitchState.modeEnabled,
      isRecordingActive: stitchState.recordingActive,
      isCaptureInProgress: stitchState.captureInProgress
    )
  }

  func handleAnnotationToolbarAction(_ action: CaptureAnnotationToolbarAction) {
    switch action {
    case .selectCaptureMode(let captureMode):
      setCaptureModeFromToolbar(captureMode)
    case .closeCapture:
      finishEditing()
    case .selectTool(let tool):
      currentTool = tool
    case .changeColor(let color):
      setAnnotationColor(color)
    case .undo:
      performUndo()
    case .redo:
      performRedo()
    case .copy:
      performCopy()
    case .save:
      performSave()
    case .addStitchSegment:
      guard RegionSelectionFeatureFlags.stitchCaptureEnabled else { return }
      addStitchSegment()
    case .resetStitch:
      guard RegionSelectionFeatureFlags.stitchCaptureEnabled else { return }
      resetStitch()
    case .mainAction:
      switch settings.screenshotMainAction {
      case .copy:
        performCopy()
      case .save:
        performSave()
      }
    case .drag(let translation):
      updateToolbarDrag(translation)
    case .dragEnded:
      finishToolbarDrag()
    }
  }

  func setSelectedCaptureType(_ type: CaptureContentType) {
    guard !recordingActive, !recordingStartPending else {
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
    refreshToolbar(animated: true)
  }

  func setAnnotationColor(_ color: Color) {
    let nsColor = NSColor(color)
    guard let rgb = nsColor.usingColorSpace(.deviceRGB) else {
      return
    }
    annotationColor = rgb
  }

  func refreshToolbar(animated: Bool = false) {
    captureModeSelectionState.setSelectedMode(selectedCaptureMode, animated: animated)
    if animated, mode == .editing {
      toolbarFrameAnimationPending = true
    }
    toolbarRefresh.refresh(animated: animated)
    needsLayout = true
    refreshGlassHosts()
  }

  func refreshToolbarSelection(animated: Bool = true) {
    captureModeSelectionState.setSelectedMode(selectedCaptureMode, animated: animated)
    needsLayout = true
    refreshGlassHosts()
  }

  func prepareGlassChromeForFirstDisplay() {
    glassChromeRevealTask?.cancel()
    closeRecordingControlPanel()
    glassBackdropRefreshScheduled = false
    glassChromeReadyForBackdrop = false
    selectingHintHost.alphaValue = 1
    selectingHintHost.isHidden = true
    captureTypeHost.alphaValue = 1
    captureTypeHost.isHidden = true
    toolbarHost.alphaValue = 1
    toolbarHost.isHidden = true
  }

  func primeGlassChromeAfterFirstDisplay(revealDelay: TimeInterval = 0.032) {
    glassChromeRevealTask?.cancel()
    layoutSubtreeIfNeeded()
    displayIfNeeded()
    refreshGlassHosts()

    glassChromeRevealTask = Task { @MainActor [weak self] in
      await Task.yield()
      guard let self, !Task.isCancelled else {
        return
      }

      self.layoutSubtreeIfNeeded()
      self.displayIfNeeded()
      self.window?.contentView?.displayIfNeeded()
      self.refreshGlassHosts()

      let delay = max(0.016, revealDelay)
      try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
      guard !Task.isCancelled else {
        return
      }

      self.glassChromeReadyForBackdrop = true
      self.rebuildGlassChromeForStableBackdrop()
      self.updateSelectingHintVisibility(animated: false)
      self.layoutCaptureTypePanel()
      self.layoutEditorChrome()
      self.refreshGlassHosts(redrawBackdrop: true)

      await Task.yield()
      guard !Task.isCancelled else {
        return
      }
      self.forceGlassBackdropResample()
    }
  }

  func refreshGlassHosts(redrawBackdrop: Bool = false) {
    for host in glassHostsForRefresh() {
      host.needsLayout = true
      host.layoutSubtreeIfNeeded()
      host.needsDisplay = true
      host.layer?.setNeedsDisplay()
      if let superview = host.superview {
        superview.setNeedsDisplay(host.frame.insetBy(dx: -2, dy: -2))
      }
    }
    if redrawBackdrop {
      window?.contentView?.needsDisplay = true
    }
  }

  func rebuildGlassChromeForStableBackdrop() {
    refreshSelectingHint()
    refreshCaptureTypeSidebar()
    refreshToolbar(animated: false)
  }

  func forceGlassBackdropResample() {
    for host in glassHostsForRefresh() where !host.isHidden {
      let frame = host.frame
      guard frame.width > 0, frame.height > 0 else {
        continue
      }

      host.frame = frame.offsetBy(dx: 0.5, dy: 0)
      host.layoutSubtreeIfNeeded()
      host.displayIfNeeded()
      host.frame = frame
      host.layoutSubtreeIfNeeded()
      host.displayIfNeeded()
    }
  }

  func scheduleGlassBackdropRefreshIfNeeded() {
    guard glassChromeReadyForBackdrop,
          !glassBackdropRefreshScheduled,
          glassHostsForRefresh().contains(where: { !$0.isHidden })
    else {
      return
    }

    glassBackdropRefreshScheduled = true
    DispatchQueue.main.async { [weak self] in
      guard let self else {
        return
      }
      self.glassBackdropRefreshScheduled = false
      self.refreshGlassHosts()
    }
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
    layoutEditorChrome()
  }

  func finishToolbarDrag() {
    toolbarDragStartOffset = nil
    recordingControlDragStartOffset = nil
    recordingControlDragStartMouseLocation = nil
    layoutRecordingControlPanel()
  }

  private func glassHostsForRefresh() -> [NSView] {
    var hosts: [NSView] = [selectingHintHost, captureTypeHost, toolbarHost]
    if let recordingControlHost {
      hosts.append(recordingControlHost)
    }
    return hosts
  }
}
