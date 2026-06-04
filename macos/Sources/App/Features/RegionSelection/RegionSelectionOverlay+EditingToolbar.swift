import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class RegionSelectionToolbarRefresh: ObservableObject {
  @Published private(set) var revision = 0

  func refresh(animated: Bool) {
    if animated {
      withAnimation(.smooth(duration: 0.18)) {
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
  let content: () -> AnyView

  var body: some View {
    let _ = refresh.revision
    content()
  }
}

@MainActor
extension RegionSelectionView {
  func makeToolbarView() -> AnyView {
    if mode == .editing, selectedCaptureType == .video {
      return AnyView(makeCaptureVideoToolbar())
    }
    return AnyView(makeScreenshotToolbar())
  }

  func makeScreenshotToolbar() -> CaptureAnnotationToolbar {
    CaptureAnnotationToolbar(
      selectedCaptureMode: selectedCaptureMode,
      modeSelectionState: captureModeSelectionState,
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

  func makeCaptureVideoToolbar() -> CaptureVideoToolbar {
    CaptureVideoToolbar(
      selectedCaptureMode: selectedCaptureMode,
      modeSelectionState: captureModeSelectionState,
      onSelectCaptureMode: { [weak self] captureMode in
        self?.setCaptureModeFromToolbar(captureMode)
      },
      onCloseCapture: { [weak self] in
        guard let self else { return }
        guard !self.videoRecordingStartPending else { return }
        self.finishEditing()
      },
      recordSystemAudio: settings.videoRecordSystemAudio,
      recordMicrophone: videoMicrophoneFeatureVisible && settings.videoRecordMicrophone,
      showWebcam: videoWebcamFeatureVisible && settings.videoShowWebcam,
      highlightMouseClicks: settings.videoHighlightMouseClicks,
      highlightKeystrokes: videoKeystrokesFeatureVisible && settings.videoHighlightKeystrokes,
      toolOrder: availableVideoToolbarTools,
      lockedTools: lockedVideoToolbarTools,
      accentColor: Color(settings.toolbarAccentColor),
      isRecordingActive: videoRecordingActive,
      isRecordingPending: videoRecordingStartPending,
      countdown: settings.videoCountdown,
      onToggleSystemAudio: { [weak self] in
        _ = self?.performToggleVideoSystemAudioShortcut()
      },
      onToggleMicrophone: { [weak self] in
        guard let self, self.videoMicrophoneFeatureVisible else { return }
        _ = self.performToggleVideoMicrophoneShortcut()
      },
      onToggleWebcam: { [weak self] in
        guard let self, self.videoWebcamFeatureVisible else { return }
        _ = self.performToggleVideoWebcamShortcut()
      },
      onToggleMouseClicks: { [weak self] in
        _ = self?.performToggleVideoMouseClicksShortcut()
      },
      onToggleKeystrokes: { [weak self] in
        guard let self, self.videoKeystrokesFeatureVisible else { return }
        _ = self.performToggleVideoKeystrokesShortcut()
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

  var availableVideoToolbarTools: [VideoToolbarTool] {
    settings.visibleVideoTools.filter { tool in
      switch tool {
      case .microphone:
        return videoMicrophoneFeatureVisible
      case .webcam:
        return videoWebcamFeatureVisible
      case .keystrokes:
        return videoKeystrokesFeatureVisible
      default:
        return true
      }
    }
  }

  var lockedVideoToolbarTools: Set<VideoToolbarTool> {
    []
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
    onStartVideoRequested?(selection, currentVideoCaptureOverlayState()) { [weak self] started in
      guard let self else {
        return
      }
      self.videoRecordingStartPending = false
      self.videoRecordingActive = started
      if !started {
        self.layoutVideoOverlayPlacementViews(selection: self.committedSelectionRect?.standardized)
      }
      self.refreshToolbar()
    }
  }

  func stopVideoWebcamPreviewForRecordingStart() async {
    await videoWebcamPlacementView.stopWebcamPreviewForRecordingStart()
  }

  func currentVideoCaptureOverlayState() -> VideoCaptureOverlayState {
    guard let selection = committedSelectionRect?.standardized,
          selection.width > 0,
          selection.height > 0
    else {
      return VideoCaptureOverlayState(
        webcamFrame: settings.videoWebcamOverlayNormalizedFrame,
        keystrokeFrame: settings.videoKeystrokeOverlayNormalizedFrame
      )
    }

    return VideoCaptureOverlayState(
      webcamFrame: videoWebcamPlacementView.isHidden
        ? settings.videoWebcamOverlayNormalizedFrame
        : normalizedOverlayFrame(videoWebcamPlacementView.frame, in: selection),
      keystrokeFrame: videoKeystrokePlacementView.isHidden
        ? settings.videoKeystrokeOverlayNormalizedFrame
        : normalizedOverlayFrame(videoKeystrokePlacementView.frame, in: selection)
    )
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

  func refreshToolbar(animated: Bool = false) {
    captureModeSelectionState.setSelectedMode(selectedCaptureMode, animated: animated)
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
    glassBackdropRefreshScheduled = false
  }

  func primeGlassChromeAfterFirstDisplay() {
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

      try? await Task.sleep(nanoseconds: 16_000_000)
      guard !Task.isCancelled else {
        return
      }

      self.updateSelectingHintVisibility(animated: false)
      self.layoutCaptureTypePanel()
      self.layoutEditorChrome()
      self.refreshGlassHosts()
    }
  }

  func refreshGlassHosts(redrawBackdrop: Bool = false) {
    toolbarHost.needsDisplay = true
    toolbarHost.layer?.setNeedsDisplay()
    toolbarHost.layoutSubtreeIfNeeded()
    captureTypeHost.needsDisplay = true
    captureTypeHost.layer?.setNeedsDisplay()
    selectingHintHost.needsDisplay = true
    selectingHintHost.layer?.setNeedsDisplay()
    if redrawBackdrop {
      window?.contentView?.needsDisplay = true
    }
  }

  func scheduleGlassBackdropRefreshIfNeeded() {
    guard !glassBackdropRefreshScheduled,
          !selectingHintHost.isHidden || !captureTypeHost.isHidden || !toolbarHost.isHidden
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
  }

  func finishToolbarDrag() {
    toolbarDragStartOffset = nil
  }
}
