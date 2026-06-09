import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class RegionSelectionToolbarRefresh: ObservableObject {
  @Published private(set) var revision = 0
  private(set) var lastRefreshAnimated = false

  func refresh(animated: Bool) {
    lastRefreshAnimated = animated
    if animated {
      withAnimation(.smooth(duration: 0.28)) {
        revision += 1
      }
    } else {
      revision += 1
    }
  }
}

@MainActor
struct RegionSelectionToolbarHost: View {
  @ObservedObject var refresh: RegionSelectionToolbarRefresh
  let content: (Namespace.ID) -> AnyView

  @Namespace private var glassNamespace

  var body: some View {
    let revision = refresh.revision
    let animated = refresh.lastRefreshAnimated
    ZStack {
      content(glassNamespace)
        .id(revision)
        .transition(toolbarTransition(animated: animated))
    }
    .animation(animated ? .smooth(duration: 0.26) : nil, value: revision)
  }

  private func toolbarTransition(animated: Bool) -> AnyTransition {
    guard animated else {
      return .identity
    }

    return .asymmetric(
      insertion: .opacity
        .combined(with: .scale(scale: 0.985, anchor: .center))
        .combined(with: .offset(y: 3)),
      removal: .opacity
        .combined(with: .scale(scale: 1.015, anchor: .center))
        .combined(with: .offset(y: -3))
    )
  }
}

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
      selectedCaptureMode: selectedCaptureMode,
      modeSelectionState: captureModeSelectionState,
      glassNamespace: glassNamespace,
      usesExternalGlassSurface: true,
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
      onAddStitchSegment: stitchCaptureFeatureVisible ? { [weak self] in
        self?.addStitchSegment()
      } : nil,
      onResetStitch: stitchCaptureFeatureVisible && stitchModeEnabled ? { [weak self] in
        self?.resetStitch()
      } : nil,
      isStitchRecordingActive: stitchCaptureFeatureVisible && stitchRecordingActive,
      isStitchCaptureInProgress: stitchCaptureFeatureVisible && stitchCaptureInProgress,
      mainAction: settings.screenshotMainAction,
      onMainAction: { [weak self] in
        guard let self else { return }
        switch self.settings.screenshotMainAction {
        case .copy:
          self.performCopy()
        case .save:
          self.performSave()
        }
      },
      accentColor: Color(settings.toolbarAccentColor),
      onToolbarDrag: { [weak self] translation in
        self?.updateToolbarDrag(translation)
      },
      onToolbarDragEnd: { [weak self] in
        self?.finishToolbarDrag()
      }
    )
  }

  func makeCaptureVideoToolbar(glassNamespace: Namespace.ID? = nil) -> CaptureVideoToolbar {
    CaptureVideoToolbar(
      selectedCaptureMode: selectedCaptureMode,
      modeSelectionState: captureModeSelectionState,
      glassNamespace: glassNamespace,
      usesExternalGlassSurface: true,
      onSelectCaptureMode: { [weak self] captureMode in
        self?.setCaptureModeFromToolbar(captureMode)
      },
      onCloseCapture: { [weak self] in
        guard let self else { return }
        guard !self.recordingStartPending else { return }
        self.finishEditing()
      },
      recordSystemAudio: settings.recordSystemAudio,
      recordMicrophone: microphoneFeatureVisible && settings.recordMicrophone,
      showWebcam: webcamFeatureVisible && settings.showWebcam,
      highlightMouseClicks: settings.highlightMouseClicks,
      highlightKeystrokes: keystrokesFeatureVisible && settings.highlightKeystrokes,
      selectedMicrophoneID: settings.microphoneDeviceID,
      selectedWebcamID: settings.webcamDeviceID,
      microphoneSources: microphoneSourceOptions,
      webcamSources: webcamSourceOptions,
      toolOrder: availableRecordingTools,
      lockedTools: lockedRecordingTools,
      accentColor: Color(settings.toolbarAccentColor),
      isRecordingActive: recordingActive,
      isRecordingPending: recordingStartPending,
      countdown: settings.recordingCountdown,
      onToggleSystemAudio: { [weak self] in
        _ = self?.performToggleVideoSystemAudioShortcut()
      },
      onToggleMicrophone: { [weak self] in
        guard let self, self.microphoneFeatureVisible else { return }
        _ = self.performToggleVideoMicrophoneShortcut()
      },
      onToggleWebcam: { [weak self] in
        guard let self, self.webcamFeatureVisible else { return }
        _ = self.performToggleVideoWebcamShortcut()
      },
      onSelectMicrophoneSource: { [weak self] deviceID in
        self?.selectMicrophoneSource(deviceID)
      },
      onSelectWebcamSource: { [weak self] deviceID in
        self?.selectWebcamSource(deviceID)
      },
      onToggleMouseClicks: { [weak self] in
        _ = self?.performToggleVideoMouseClicksShortcut()
      },
      onToggleKeystrokes: { [weak self] in
        guard let self, self.keystrokesFeatureVisible else { return }
        _ = self.performToggleVideoKeystrokesShortcut()
      },
      onSelectCountdown: { [weak self] countdown in
        guard let self else { return }
        guard !self.recordingActive, !self.recordingStartPending else { return }
        self.settings.setRecordingCountdown(countdown)
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

  func makeRecordingControlBar() -> RecordingControlBar {
    let liveState = currentRecordingLiveControlState
    return RecordingControlBar(
      startedAt: recordingStartedAt ?? Date(),
      recordSystemAudio: liveState.recordSystemAudio,
      recordMicrophone: liveState.recordMicrophone,
      showWebcam: liveState.showWebcam,
      highlightMouseClicks: liveState.highlightMouseClicks,
      highlightKeystrokes: liveState.highlightKeystrokes,
      selectedMicrophoneID: settings.microphoneDeviceID,
      selectedWebcamID: settings.webcamDeviceID,
      microphoneSources: microphoneSourceOptions,
      webcamSources: webcamSourceOptions,
      toolOrder: availableRecordingTools.filter { $0 != .countdown },
      disabledTools: liveState.disabledTools,
      accentColor: Color(settings.toolbarAccentColor),
      usesExternalGlassSurface: true,
      onToggleSystemAudio: { [weak self] in
        self?.toggleLiveRecordingTool(.systemAudio)
      },
      onToggleMicrophone: { [weak self] in
        guard let self, self.microphoneFeatureVisible else { return }
        self.toggleLiveRecordingTool(.microphone)
      },
      onToggleWebcam: { [weak self] in
        guard let self, self.webcamFeatureVisible else { return }
        self.toggleLiveRecordingTool(.webcam)
      },
      onSelectMicrophoneSource: { [weak self] deviceID in
        self?.selectMicrophoneSource(deviceID)
      },
      onSelectWebcamSource: { [weak self] deviceID in
        self?.selectWebcamSource(deviceID)
      },
      onToggleMouseClicks: { [weak self] in
        self?.toggleLiveRecordingTool(.mouseClicks)
      },
      onToggleKeystrokes: { [weak self] in
        guard let self, self.keystrokesFeatureVisible else { return }
        self.toggleLiveRecordingTool(.keystrokes)
      },
      onStop: { [weak self] in
        self?.stopVideoRecordingFromEditor()
      },
      onDrag: { [weak self] mouseLocation in
        self?.updateRecordingControlDrag(mouseLocation: mouseLocation)
      },
      onDragEnd: { [weak self] in
        self?.finishRecordingControlDrag()
      }
    )
  }

  func toggleLiveRecordingTool(_ tool: RecordingTool) {
    guard recordingActive else {
      return
    }
    let currentState = currentRecordingLiveControlState
    guard !currentState.disabledTools.contains(tool) else {
      return
    }
    let requestedEnabled = !currentState.isEnabled(tool)
    onRecordingToolToggleRequested?(tool, requestedEnabled) { [weak self] updatedState in
      guard let self else {
        return
      }
      self.recordingLiveControlState = updatedState
      self.recordingControlPanelSize = nil
      self.recordingControlHost?.rootView = self.makeRecordingControlBar()
      self.layoutRecordingControlPanel()
    }
  }

  func selectMicrophoneSource(_ deviceID: String) {
    settings.setVideoMicrophoneDeviceID(deviceID)
    onRecordingMicrophoneSourceSelected?(deviceID)
    refreshToolbar()
    if recordingActive {
      recordingControlPanelSize = nil
      recordingControlHost?.rootView = makeRecordingControlBar()
      layoutRecordingControlPanel()
    }
  }

  func selectWebcamSource(_ deviceID: String) {
    settings.setVideoWebcamDeviceID(deviceID)
    onRecordingWebcamSourceSelected?(deviceID)
    if !recordingActive {
      layoutVideoOverlayPlacementViews(selection: committedSelectionRect?.standardized)
    }
    refreshToolbar()
    if recordingActive {
      recordingControlPanelSize = nil
      recordingControlHost?.rootView = makeRecordingControlBar()
      layoutRecordingControlPanel()
    }
  }

  private var currentRecordingLiveControlState: RecordingLiveControlState {
    recordingLiveControlState ?? RecordingLiveControlState(
      recordSystemAudio: settings.recordSystemAudio,
      recordMicrophone: microphoneFeatureVisible && settings.recordMicrophone,
      showWebcam: webcamFeatureVisible && settings.showWebcam,
      highlightMouseClicks: settings.highlightMouseClicks,
      highlightKeystrokes: keystrokesFeatureVisible && settings.highlightKeystrokes
    )
  }

  func showRecordingControlPanel() {
    guard recordingActive, let parentWindow = window else {
      closeRecordingControlPanel()
      return
    }

    let host: RegionSelectionGlassHostingView<RecordingControlBar>
    if let recordingControlHost {
      host = recordingControlHost
    } else {
      host = RegionSelectionGlassHostingView(rootView: makeRecordingControlBar(), cornerRadius: 28)
      host.translatesAutoresizingMaskIntoConstraints = true
      host.autoresizingMask = [.width, .height]
      host.alphaValue = 1
      recordingControlHost = host
    }

    let panel: NSPanel
    if let recordingControlPanel {
      panel = recordingControlPanel
    } else {
      panel = NSPanel(
        contentRect: .zero,
        styleMask: [.nonactivatingPanel, .borderless],
        backing: .buffered,
        defer: false
      )
      panel.isReleasedWhenClosed = false
      panel.level = NSWindow.Level(rawValue: max(NSWindow.Level.statusBar.rawValue, parentWindow.level.rawValue + 2))
      panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
      panel.backgroundColor = .clear
      panel.isOpaque = false
      panel.hasShadow = false
      panel.ignoresMouseEvents = false
      panel.acceptsMouseMovedEvents = true
      panel.animationBehavior = .none
      panel.appearance = parentWindow.appearance
      panel.contentView = host
      recordingControlPanel = panel
    }

    layoutRecordingControlPanel()
    panel.orderFrontRegardless()
  }

  func closeRecordingControlPanel() {
    recordingControlPanel?.close()
    recordingControlPanel = nil
    recordingControlHost = nil
    recordingControlPanelSize = nil
    recordingControlDragStartOffset = nil
    recordingControlDragStartMouseLocation = nil
  }

  func layoutRecordingControlPanel() {
    guard recordingActive,
          let parentWindow = window,
          let panel = recordingControlPanel,
          let host = recordingControlHost
    else {
      return
    }

    host.layoutSubtreeIfNeeded()
    let panelSize = recordingControlPanelSize ?? resolvedRecordingControlPanelSize(host.fittingSize)
    recordingControlPanelSize = panelSize

    let padding: CGFloat = 12
    let maxX = max(padding, bounds.width - panelSize.width - padding)
    let minY = padding
    let maxY = max(padding, bounds.height - panelSize.height - padding)

    let selection = committedSelectionRect?.standardized.integral
    let defaultX: CGFloat
    let defaultY: CGFloat
    if selectedCaptureMode == .selection, let selection {
      defaultX = min(max(padding, selection.midX - panelSize.width * 0.5), maxX)
      let proposedBelow = selection.minY - panelSize.height - 14
      defaultY = proposedBelow >= padding ? proposedBelow : min(maxY, selection.maxY + 14)
    } else {
      let bottomInset = captureSurfaceBottomInset()
      let bottomY = padding + bottomInset + 8
      defaultX = min(max(padding, bounds.midX - panelSize.width * 0.5), maxX)
      defaultY = min(maxY, bottomY + 26)
    }

    let x = min(max(padding, defaultX + recordingControlOffset.width), maxX)
    let y = min(max(minY, defaultY + recordingControlOffset.height), maxY)
    recordingControlOffset = CGSize(width: x - defaultX, height: y - defaultY)

    let localFrame = CGRect(
      x: x,
      y: y,
      width: panelSize.width,
      height: panelSize.height
    ).integral
    let windowFrame = convert(localFrame, to: nil)
    let screenFrame = parentWindow.convertToScreen(windowFrame)

    panel.setFrame(screenFrame, display: true)
    host.frame = CGRect(origin: .zero, size: panelSize)
    host.needsLayout = true
    host.layoutSubtreeIfNeeded()
  }

  func updateRecordingControlDrag(mouseLocation: CGPoint) {
    guard mode == .editing else {
      return
    }

    if recordingControlDragStartOffset == nil {
      recordingControlDragStartOffset = recordingControlOffset
      recordingControlDragStartMouseLocation = mouseLocation
    }

    let start = recordingControlDragStartOffset ?? .zero
    let startMouseLocation = recordingControlDragStartMouseLocation ?? mouseLocation
    let delta = CGSize(
      width: mouseLocation.x - startMouseLocation.x,
      height: mouseLocation.y - startMouseLocation.y
    )
    recordingControlOffset = CGSize(
      width: start.width + delta.width,
      height: start.height + delta.height
    )
    layoutRecordingControlPanel()
  }

  func finishRecordingControlDrag() {
    recordingControlDragStartOffset = nil
    recordingControlDragStartMouseLocation = nil
    layoutRecordingControlPanel()
  }

  private func resolvedRecordingControlPanelSize(_ fittingSize: CGSize) -> CGSize {
    let fallback = CGSize(width: 230, height: 52)
    guard fittingSize.width.isFinite,
          fittingSize.height.isFinite,
          fittingSize.width >= 120,
          fittingSize.height >= 36
    else {
      return fallback
    }
    return CGSize(
      width: max(fallback.width, fittingSize.width),
      height: max(fallback.height, fittingSize.height)
    )
  }

  var availableRecordingTools: [RecordingTool] {
    settings.visibleRecordingTools.filter { tool in
      switch tool {
      case .microphone:
        return microphoneFeatureVisible
      case .webcam:
        return webcamFeatureVisible
      case .keystrokes:
        return keystrokesFeatureVisible
      default:
        return true
      }
    }
  }

  var lockedRecordingTools: Set<RecordingTool> {
    []
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

  func toggleVideoRecordingFromEditor() {
    if recordingStartPending {
      return
    }
    if recordingActive {
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
    guard !recordingActive, !recordingStartPending else {
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
    recordingStartPending = true
    refreshToolbar()
    settings.setDefaultCaptureType(.video)
    onStartVideoRequested?(selection, currentRecordingOverlayState()) { [weak self] started, liveState in
      guard let self else {
        return
      }
      self.recordingStartPending = false
      self.recordingStartedAt = started ? Date() : nil
      self.recordingLiveControlState = started ? liveState : nil
      self.recordingActive = started
      if !started {
        self.layoutVideoOverlayPlacementViews(selection: self.committedSelectionRect?.standardized)
      }
      self.refreshToolbar()
    }
  }

  func stopVideoWebcamPreviewForRecordingStart() async {
    await webcamPlacementView.stopWebcamPreviewForRecordingStart()
  }

  func currentRecordingOverlayState() -> RecordingOverlayState {
    guard let selection = committedSelectionRect?.standardized,
          selection.width > 0,
          selection.height > 0
    else {
      return RecordingOverlayState(
        webcamFrame: settings.webcamOverlayNormalizedFrame,
        keystrokeFrame: settings.keystrokeOverlayNormalizedFrame
      )
    }

    return RecordingOverlayState(
      webcamFrame: webcamPlacementView.isHidden
        ? settings.webcamOverlayNormalizedFrame
        : normalizedOverlayFrame(webcamPlacementView.frame, in: selection),
      keystrokeFrame: keystrokePlacementView.isHidden
        ? settings.keystrokeOverlayNormalizedFrame
        : normalizedOverlayFrame(keystrokePlacementView.frame, in: selection)
    )
  }

  func stopVideoRecordingFromEditor() {
    guard recordingActive else {
      return
    }
    recordingActive = false
    recordingStartPending = false
    recordingStartedAt = nil
    recordingLiveControlState = nil
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
