import AppKit
import SwiftUI

@MainActor
extension RegionSelectionView {
  func makeCaptureVideoToolbar(glassNamespace: Namespace.ID? = nil) -> CaptureVideoToolbar {
    CaptureVideoToolbar(
      modeSelectionState: captureModeSelectionState,
      glassNamespace: glassNamespace,
      usesExternalGlassSurface: true,
      state: captureVideoToolbarState,
      onAction: { [weak self] action in
        self?.handleVideoToolbarAction(action)
      }
    )
  }

  var captureVideoToolbarState: CaptureVideoToolbarState {
    CaptureVideoToolbarState(
      recordingControls: RecordingLiveControlState(
        recordSystemAudio: settings.recordSystemAudio,
        recordMicrophone: microphoneFeatureVisible && settings.recordMicrophone,
        showWebcam: webcamFeatureVisible && settings.showWebcam,
        highlightMouseClicks: settings.highlightMouseClicks,
        highlightKeystrokes: keystrokesFeatureVisible && settings.highlightKeystrokes
      ),
      selectedMicrophoneID: settings.microphoneDeviceID,
      selectedWebcamID: settings.webcamDeviceID,
      microphoneSources: microphoneSourceOptions,
      webcamSources: webcamSourceOptions,
      toolOrder: availableRecordingTools,
      lockedTools: lockedRecordingTools,
      accentColor: Color(settings.toolbarAccentColor),
      isRecordingActive: recordingActive,
      isRecordingPending: recordingStartPending,
      countdown: settings.recordingCountdown
    )
  }

  func handleVideoToolbarAction(_ action: CaptureVideoToolbarAction) {
    switch action {
    case .selectCaptureMode(let captureMode):
      setCaptureModeFromToolbar(captureMode)
    case .closeCapture:
      guard !recordingStartPending else { return }
      finishEditing()
    case .toggleTool(let tool):
      toggleConfiguredRecordingTool(tool)
    case .selectMicrophoneSource(let deviceID):
      selectMicrophoneSource(deviceID)
    case .selectWebcamSource(let deviceID):
      selectWebcamSource(deviceID)
    case .selectCountdown(let countdown):
      guard !recordingActive, !recordingStartPending else { return }
      settings.setRecordingCountdown(countdown)
      refreshToolbar()
    case .toggleRecording:
      toggleVideoRecordingFromEditor()
    case .drag(let translation):
      updateToolbarDrag(translation)
    case .dragEnded:
      finishToolbarDrag()
    }
  }

  func toggleConfiguredRecordingTool(_ tool: RecordingTool) {
    switch tool {
    case .systemAudio:
      _ = performToggleVideoSystemAudioShortcut()
    case .microphone:
      guard microphoneFeatureVisible else { return }
      _ = performToggleVideoMicrophoneShortcut()
    case .webcam:
      guard webcamFeatureVisible else { return }
      _ = performToggleVideoWebcamShortcut()
    case .mouseClicks:
      _ = performToggleVideoMouseClicksShortcut()
    case .keystrokes:
      guard keystrokesFeatureVisible else { return }
      _ = performToggleVideoKeystrokesShortcut()
    case .countdown:
      break
    }
  }

  func selectMicrophoneSource(_ deviceID: String) {
    settings.setVideoMicrophoneDeviceID(deviceID)
    recordingController?.setMicrophoneDeviceIDForNextRecording(deviceID)
    refreshToolbar()
    if recordingActive {
      layoutEditorChrome()
    }
  }

  func selectWebcamSource(_ deviceID: String) {
    settings.setVideoWebcamDeviceID(deviceID)
    recordingController?.setWebcamDeviceIDForNextRecording(deviceID)
    if !recordingActive {
      layoutVideoOverlayPlacementViews(selection: committedSelectionRect?.standardized)
    }
    refreshToolbar()
    if recordingActive {
      layoutEditorChrome()
    }
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
    RecordingToolEntitlements.lockedTools(storeManager: storeManager)
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
    guard let recordingController, let window else {
      finishVideoRecordingStart(started: false, liveState: nil)
      return
    }

    let globalSelection = selection
      .offsetBy(dx: window.frame.origin.x, dy: window.frame.origin.y)
      .standardized
    recordingFlowHasStarted = false
    recordingController.startRecording(
      selectionRectInScreen: globalSelection,
      windowID: selectedCaptureMode == .window ? selectedWindowID : nil,
      overlayState: currentRecordingOverlayState(),
      showFloatingHUD: false,
      flowHandler: self
    )
  }

  func finishVideoRecordingStart(started: Bool, liveState: RecordingLiveControlState?) {
    recordingStartPending = false
    recordingStartedAt = started ? Date() : nil
    recordingLiveControlState = started ? liveState : nil
    recordingActive = started
    if !started {
      layoutVideoOverlayPlacementViews(selection: committedSelectionRect?.standardized)
    }
    refreshToolbar()
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
    let activeRecordingController = recordingController
    recordingActive = false
    recordingStartPending = false
    recordingStartedAt = nil
    recordingLiveControlState = nil
    refreshToolbar()
    activeRecordingController?.stopRecordingFromInlineToolbar()
    finishEditing()
  }
}

extension RegionSelectionView: RecordingFlowHandling {
  func recordingFlowWillStartWebcamCapture() async {
    await delegate?.regionSelectionViewWillStartRecordingWebcamCapture(self)
  }

  func recordingFlowDidStart(liveState: RecordingLiveControlState) {
    recordingFlowHasStarted = true
    finishVideoRecordingStart(started: true, liveState: liveState)
  }

  func recordingFlowDidFinish() {
    recordingFlowHasStarted = false
    delegate?.regionSelectionViewDidFinishRecordingFlow(self)
  }

  func recordingFlowDidFail(message: String) {
    if recordingFlowHasStarted {
      recordingFlowHasStarted = false
      delegate?.regionSelectionViewDidFinishRecordingFlow(self)
    } else {
      finishVideoRecordingStart(started: false, liveState: nil)
    }
    delegate?.regionSelectionView(self, didFailRecordingWithMessage: message)
  }
}
