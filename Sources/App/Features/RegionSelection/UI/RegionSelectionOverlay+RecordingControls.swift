import AppKit
import SwiftUI

@MainActor
extension RegionSelectionView {
  func refreshRecordingSourceOptions() {
    webcamSourceOptions = RecordingSourceProvider.webcamSources()
    microphoneSourceOptions = RecordingSourceProvider.microphoneSources()
  }

  func updateRecordingFocusPresentation() {
    if let window = window as? RegionSelectionWindow {
      window.passesEventsThrough = false
    } else {
      window?.ignoresMouseEvents = false
    }
    if recordingActive {
      window?.invalidateCursorRects(for: self)
      layoutEditorChrome()
      startRecordingToolbarPassthrough()
    } else {
      stopRecordingToolbarPassthrough()
      layoutEditorChrome()
    }
    needsDisplay = true
  }

  func makeRecordingControlBar(glassNamespace: Namespace.ID? = nil) -> RecordingControlBar {
    return RecordingControlBar(
      state: recordingControlBarState,
      glassNamespace: glassNamespace,
      usesExternalGlassSurface: true,
      onAction: { [weak self] action in
        self?.handleRecordingControlBarAction(action)
      }
    )
  }

  var recordingControlBarState: RecordingControlBarState {
    RecordingControlBarState(
      startedAt: recordingStartedAt ?? Date(),
      liveControls: currentRecordingLiveControlState,
      selectedMicrophoneID: settings.microphoneDeviceID,
      selectedWebcamID: settings.webcamDeviceID,
      microphoneSources: microphoneSourceOptions,
      webcamSources: webcamSourceOptions,
      toolOrder: availableRecordingTools.filter { $0 != .countdown },
      accentColor: Color(settings.toolbarAccentColor)
    )
  }

  func handleRecordingControlBarAction(_ action: RecordingControlBarAction) {
    switch action {
    case .toggleTool(let tool):
      switch tool {
      case .microphone where !microphoneFeatureVisible:
        return
      case .webcam where !webcamFeatureVisible:
        return
      case .keystrokes where !keystrokesFeatureVisible:
        return
      case .systemAudio, .mouseClicks, .countdown, .microphone, .webcam, .keystrokes:
        break
      }
      toggleLiveRecordingTool(tool)
    case .selectMicrophoneSource(let deviceID):
      selectMicrophoneSource(deviceID)
    case .selectWebcamSource(let deviceID):
      selectWebcamSource(deviceID)
    case .stop:
      stopVideoRecordingFromEditor()
    case .drag(let translation):
      updateToolbarDrag(translation)
    case .dragEnded:
      finishToolbarDrag()
    }
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
    Task { @MainActor [weak self] in
      guard let self else {
        return
      }
      guard let recordingController else {
        return
      }
      let updatedState = await recordingController.setLiveRecordingTool(tool, enabled: requestedEnabled)
      self.recordingLiveControlState = updatedState
      self.refreshToolbar()
      self.layoutEditorChrome()
    }
  }

  var currentRecordingLiveControlState: RecordingLiveControlState {
    recordingLiveControlState ?? RecordingLiveControlState(
      recordSystemAudio: settings.recordSystemAudio,
      recordMicrophone: microphoneFeatureVisible && settings.recordMicrophone,
      showWebcam: webcamFeatureVisible && settings.showWebcam,
      highlightMouseClicks: settings.highlightMouseClicks,
      highlightKeystrokes: keystrokesFeatureVisible && settings.highlightKeystrokes
    )
  }

  func startRecordingToolbarPassthrough() {
    recordingPointerPassthroughTimer?.invalidate()
    let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.updateRecordingToolbarPassthrough()
      }
    }
    RunLoop.main.add(timer, forMode: .common)
    recordingPointerPassthroughTimer = timer
    (window as? RegionSelectionWindow)?.passthroughActivationApp?.activate(options: [])
    updateRecordingToolbarPassthrough()
  }

  func stopRecordingToolbarPassthrough() {
    recordingPointerPassthroughTimer?.invalidate()
    recordingPointerPassthroughTimer = nil
    window?.ignoresMouseEvents = false
  }

  func updateRecordingToolbarPassthrough() {
    guard recordingActive, mode == .editing, let window else {
      window?.ignoresMouseEvents = false
      return
    }

    let pointInWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
    let point = convert(pointInWindow, from: nil)
    let acceptsToolbarEvents = !toolbarHost.isHidden && toolbarHost.frame.insetBy(dx: -6, dy: -6).contains(point)
    window.ignoresMouseEvents = !acceptsToolbarEvents
  }
}
