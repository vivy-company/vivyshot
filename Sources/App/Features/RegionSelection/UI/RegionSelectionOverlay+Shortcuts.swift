import AppKit
import AVFoundation
import Carbon

@MainActor
extension RegionSelectionView {
  func isPlainReturnKeyEvent(_ event: NSEvent) -> Bool {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    let disallowedFlags: NSEvent.ModifierFlags = [.shift, .control, .option, .command]
    guard flags.intersection(disallowedFlags).isEmpty else {
      return false
    }

    switch event.keyCode {
    case UInt16(kVK_Return), UInt16(kVK_ANSI_KeypadEnter):
      return true
    default:
      return false
    }
  }

  func handleCancelShortcut() {
    switch mode {
    case .selecting:
      delegate?.regionSelectionViewDidRequestCancel(self)
    case .editing:
      if recordingActive {
        stopVideoRecordingFromEditor()
        return
      }
      finishEditing()
    }
  }

  func performUndoShortcut() {
    guard mode == .editing else { return }
    performUndo()
  }

  func performRedoShortcut() {
    guard mode == .editing else { return }
    performRedo()
  }

  func performCopyShortcut() {
    switch mode {
    case .editing:
      performCopy()
    case .selecting:
      guard canUseHelperQuickScreenshotShortcuts else {
        NSSound.beep()
        return
      }
      quickCopyFullScreenFromSelectingOverlay()
    }
  }

  func performSaveShortcut() {
    switch mode {
    case .editing:
      performSave()
    case .selecting:
      guard canUseHelperQuickScreenshotShortcuts else {
        NSSound.beep()
        return
      }
      quickSaveFullScreenFromSelectingOverlay()
    }
  }

  func performDefaultCaptureActionShortcut() -> Bool {
    guard mode == .editing else {
      return false
    }

    switch selectedCaptureType {
    case .screenshot:
      switch settings.screenshotMainAction {
      case .copy:
        performCopy()
      case .save:
        performSave()
      }
      return true
    case .video:
      guard !recordingActive else {
        return false
      }
      guard !recordingStartPending else {
        return true
      }
      guard resolvePendingVideoCaptureTargetForDefaultAction() else {
        return true
      }
      startVideoRecordingFromEditor()
      return true
    }
  }

  func performAddStitchSegmentShortcut() {
    guard RegionSelectionFeatureFlags.stitchCaptureEnabled else { return }
    guard mode == .editing else { return }
    addStitchSegment()
  }

  func performResetStitchShortcut() {
    guard RegionSelectionFeatureFlags.stitchCaptureEnabled else { return }
    guard mode == .editing else { return }
    resetStitch()
  }

  func performZoomInShortcut() {
    guard mode == .editing else { return }
    canvasView.zoomIn()
    updateCanvasPreviewStrokeWidth()
  }

  func performZoomOutShortcut() {
    guard mode == .editing else { return }
    canvasView.zoomOut()
    updateCanvasPreviewStrokeWidth()
  }

  func performZoomResetShortcut() {
    guard mode == .editing else { return }
    canvasView.resetZoomAndPan()
    updateCanvasPreviewStrokeWidth()
  }

  func performSelectToolShortcut(index: Int) -> Bool {
    guard mode == .editing, selectedCaptureType == .screenshot else {
      return false
    }
    let tools = settings.visibleTools
    guard !tools.isEmpty, index >= 1, index <= tools.count else {
      return false
    }
    let targetTool = tools[index - 1]
    if currentTool != targetTool {
      currentTool = targetTool
    }
    return true
  }

  func performCycleToolShortcut(reverse: Bool) -> Bool {
    guard mode == .editing else {
      return false
    }
    guard !recordingActive, !recordingStartPending else {
      return false
    }

    if selectedCaptureType == .screenshot {
      let tools = settings.visibleTools
      guard !tools.isEmpty else {
        return false
      }
      let currentIndex = tools.firstIndex(of: currentTool) ?? 0
      let nextIndex: Int
      if reverse {
        nextIndex = (currentIndex - 1 + tools.count) % tools.count
      } else {
        nextIndex = (currentIndex + 1) % tools.count
      }
      currentTool = tools[nextIndex]
      return true
    }

    let modes = CaptureMode.allCases
    guard let currentIndex = modes.firstIndex(of: selectedCaptureMode) else {
      return false
    }
    let nextIndex: Int
    if reverse {
      nextIndex = (currentIndex - 1 + modes.count) % modes.count
    } else {
      nextIndex = (currentIndex + 1) % modes.count
    }
    setCaptureModeFromToolbar(modes[nextIndex])
    return true
  }

  func performCycleCaptureTypeShortcut() -> Bool {
    guard !recordingActive, !recordingStartPending else {
      return false
    }

    let types = CaptureContentType.allCases
    guard !types.isEmpty,
          let currentIndex = types.firstIndex(of: selectedCaptureType)
    else {
      return false
    }

    let nextIndex = (currentIndex + 1) % types.count
    setSelectedCaptureType(types[nextIndex])
    return true
  }

  func performCycleCaptureModeShortcut(reverse: Bool) -> Bool {
    guard mode == .editing else {
      return false
    }
    guard !recordingActive, !recordingStartPending else {
      return false
    }

    let modes = CaptureMode.allCases
    guard !modes.isEmpty,
          let currentIndex = modes.firstIndex(of: selectedCaptureMode)
    else {
      return false
    }

    let nextIndex: Int
    if reverse {
      nextIndex = (currentIndex - 1 + modes.count) % modes.count
    } else {
      nextIndex = (currentIndex + 1) % modes.count
    }
    setCaptureModeFromToolbar(modes[nextIndex])
    return true
  }

  func performCaptureModeShortcut(_ mode: CaptureMode) -> Bool {
    guard self.mode == .editing else {
      return false
    }
    guard !recordingActive, !recordingStartPending else {
      return false
    }
    setCaptureModeFromToolbar(mode)
    return true
  }

  func performToggleVideoSystemAudioShortcut() -> Bool {
    guard canUseVideoToolbarSettingsShortcut else {
      return false
    }
    settings.setVideoRecordSystemAudio(!settings.recordSystemAudio)
    refreshToolbar()
    return true
  }

  func performToggleVideoMicrophoneShortcut() -> Bool {
    guard canUseVideoToolbarSettingsShortcut else {
      return false
    }
    guard microphoneFeatureVisible else {
      return false
    }
    toggleRecordingMediaSetting(
      isEnabled: settings.recordMicrophone,
      setEnabled: settings.setVideoRecordMicrophone,
      mediaType: .audio,
      deniedMessage: "Microphone permission is required to enable microphone recording."
    )
    return true
  }

  func performToggleVideoWebcamShortcut() -> Bool {
    guard canUseVideoToolbarSettingsShortcut else {
      return false
    }
    guard webcamFeatureVisible else {
      return false
    }
    toggleRecordingMediaSetting(
      isEnabled: settings.showWebcam,
      setEnabled: settings.setVideoShowWebcam,
      mediaType: .video,
      deniedMessage: "Camera permission is required to enable the webcam overlay."
    )
    return true
  }

  private func toggleRecordingMediaSetting(
    isEnabled: Bool,
    setEnabled: @escaping @MainActor (Bool) -> Void,
    mediaType: AVMediaType,
    deniedMessage: String
  ) {
    if isEnabled {
      setEnabled(false)
      refreshToolbar()
      return
    }

    requestRecordingMediaAccess(for: mediaType, deniedMessage: deniedMessage) {
      setEnabled(true)
      self.refreshToolbar()
    }
  }

  private func requestRecordingMediaAccess(
    for mediaType: AVMediaType,
    deniedMessage: String,
    enable: @escaping @MainActor () -> Void
  ) {
    switch AVCaptureDevice.authorizationStatus(for: mediaType) {
    case .authorized:
      enable()
    case .notDetermined:
      Task { @MainActor [weak self] in
        let granted = await AVCaptureDevice.requestAccess(for: mediaType)
        guard let self else {
          return
        }
        if granted {
          enable()
        } else {
          reportRecordingMediaAccessDenied(deniedMessage)
        }
      }
    case .denied, .restricted:
      reportRecordingMediaAccessDenied(deniedMessage)
    @unknown default:
      reportRecordingMediaAccessDenied(deniedMessage)
    }
  }

  private func reportRecordingMediaAccessDenied(_ message: String) {
    NSSound.beep()
    refreshToolbar()
    delegate?.regionSelectionView(self, didFailRecordingWithMessage: message)
  }

  func performToggleVideoMouseClicksShortcut() -> Bool {
    guard canUseVideoToolbarSettingsShortcut else {
      return false
    }
    settings.setVideoHighlightMouseClicks(!settings.highlightMouseClicks)
    refreshToolbar()
    return true
  }

  func performToggleVideoKeystrokesShortcut() -> Bool {
    guard canUseVideoToolbarSettingsShortcut else {
      return false
    }
    guard keystrokesFeatureVisible else {
      return false
    }
    settings.setVideoHighlightKeystrokes(!settings.highlightKeystrokes)
    refreshToolbar()
    return true
  }

  func performCycleVideoCountdownShortcut() -> Bool {
    guard canUseVideoToolbarSettingsShortcut else {
      return false
    }
    guard !recordingActive else {
      return false
    }

    let options = RecordingCountdown.allCases
    guard !options.isEmpty else {
      return false
    }

    let currentIndex = options.firstIndex(of: settings.recordingCountdown) ?? 0
    let nextIndex = (currentIndex + 1) % options.count
    settings.setRecordingCountdown(options[nextIndex])
    refreshToolbar()
    return true
  }

  func performToggleVideoRecordingShortcut() -> Bool {
    guard mode == .editing, selectedCaptureType == .video else {
      return false
    }
    toggleVideoRecordingFromEditor()
    return true
  }

  func quickCopyFullScreenFromSelectingOverlay() {
    guard let frozenImage else {
      NSSound.beep()
      return
    }

    let encodedPNG = ScreenshotImage.encode(
      frozenImage,
      format: .png,
      jpegQuality: 100
    )
    let copied = copyImageToPasteboard(frozenImage, encodedPNG: encodedPNG)

    guard copied else {
      NSSound.beep()
      return
    }

    let autoSaveResult = autoSaveCopiedScreenshot(frozenImage)
    recordStandaloneScreenshotCapture(frozenImage)
    delegate?.regionSelectionViewDidRequestImmediateCancel(self)
    showCopyResultToast(autoSaveResult: autoSaveResult)
  }

  func quickSaveFullScreenFromSelectingOverlay() {
    guard let frozenImage else {
      NSSound.beep()
      return
    }

    recordStandaloneScreenshotCapture(frozenImage)

    if settings.alwaysSaveToDefaultDirectory,
       let directory = settings.defaultSaveDirectoryURL
    {
      let destination = Self.makeAutoSaveURL(in: directory, ext: "png")
      _ = saveImageToDisk(frozenImage, to: destination)
      delegate?.regionSelectionViewDidRequestCancel(self)
      return
    }

    let suggestedDirectory = settings.defaultSaveDirectoryURL
    let image = frozenImage
    delegate?.regionSelectionViewDidRequestImmediateCancel(self)
    Task { @MainActor [image, suggestedDirectory] in
      await Task.yield()
      self.presentSavePanel(for: image, suggestedDirectory: suggestedDirectory)
    }
  }

  var canUseHelperQuickScreenshotShortcuts: Bool {
    guard selectedCaptureType == .screenshot else {
      return false
    }
    return mode == .selecting && interactionState.isIdle
  }

  var canUseVideoToolbarSettingsShortcut: Bool {
    mode == .editing
      && selectedCaptureType == .video
      && !recordingActive
      && !recordingStartPending
  }
}
