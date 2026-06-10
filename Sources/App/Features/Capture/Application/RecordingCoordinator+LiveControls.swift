import AVFoundation

@MainActor
extension RecordingCoordinator {
  @discardableResult
  func setLiveRecordingTool(_ tool: RecordingTool, enabled: Bool) async -> RecordingLiveControlState {
    guard isRecordingActive else {
      return liveControlState
    }
    guard !liveControlState.disabledTools.contains(tool) else {
      return liveControlState
    }

    switch tool {
    case .systemAudio:
      await setSystemAudioEnabledForActiveRecording(enabled)
    case .microphone:
      await setMicrophoneEnabledForActiveRecording(enabled)
    case .webcam:
      setWebcamEnabledForActiveRecording(enabled)
    case .mouseClicks:
      setMouseClicksEnabledForActiveRecording(enabled)
    case .keystrokes:
      setKeystrokesEnabledForActiveRecording(enabled)
    case .countdown:
      break
    }
    return liveControlState
  }

  private func setSystemAudioEnabledForActiveRecording(_ enabled: Bool) async {
    do {
      try await recorder?.setSystemAudioEnabled(enabled)
      liveControlState.recordSystemAudio = enabled
      if enabled {
        systemAudioEnabledInSession = true
      }
    } catch {
      reportRecordingError("Failed to update system audio: \(error.localizedDescription)")
    }
  }

  private func setMicrophoneEnabledForActiveRecording(_ enabled: Bool) async {
    guard !enabled || storeManager.canUse(.microphoneAudioExport) else {
      liveControlState.recordMicrophone = false
      liveControlState.disabledTools.insert(.microphone)
      return
    }
    if enabled {
      let granted = await AVCaptureDevice.requestAccess(for: .audio)
      guard granted else {
        liveControlState.recordMicrophone = false
        reportRecordingError("Microphone permission is required to enable microphone recording.")
        return
      }
    }
    do {
      try await recorder?.setMicrophoneEnabled(enabled)
      liveControlState.recordMicrophone = enabled
      if enabled {
        microphoneEnabledInSession = true
      }
    } catch {
      reportRecordingError("Failed to update microphone: \(error.localizedDescription)")
    }
  }

  func setMicrophoneDeviceIDForNextRecording(_ deviceID: String) {
    settings.setVideoMicrophoneDeviceID(deviceID)
    guard isRecordingActive else {
      return
    }
    Task { [weak self] in
      guard let self else {
        return
      }
      await self.setMicrophoneDeviceIDForActiveRecording(deviceID)
    }
  }

  private func setMicrophoneDeviceIDForActiveRecording(_ deviceID: String) async {
    do {
      try await recorder?.setMicrophoneDeviceID(deviceID)
    } catch {
      reportRecordingError("Failed to update microphone source: \(error.localizedDescription)")
    }
  }

  func setWebcamDeviceIDForNextRecording(_ deviceID: String) {
    settings.setVideoWebcamDeviceID(deviceID)
    guard isRecordingActive else {
      return
    }
    Task { [weak self] in
      guard let self else {
        return
      }
      await self.setWebcamDeviceIDForActiveRecording(deviceID)
    }
  }

  private func setWebcamDeviceIDForActiveRecording(_ deviceID: String) async {
    guard let webcamRecorder else {
      return
    }
    do {
      try await webcamRecorder.setDeviceID(deviceID)
      if liveControlState.showWebcam {
        webcamOverlayUsedInSession = true
      }
    } catch {
      reportRecordingError("Failed to update webcam source: \(error.localizedDescription)")
    }
  }

  private func setMouseClicksEnabledForActiveRecording(_ enabled: Bool) {
    settings.setVideoHighlightMouseClicks(enabled)
    let style = enabled ? settings.mouseClickHighlightStyle : nil
    liveControlState.highlightMouseClicks = enabled
    mouseClickHighlightStyleInSession = style
    inputMonitor?.setCaptureMouseClicks(enabled)
  }

  private func setKeystrokesEnabledForActiveRecording(_ enabled: Bool) {
    guard !enabled || storeManager.canUse(.keystrokeOverlay) else {
      liveControlState.highlightKeystrokes = false
      liveControlState.disabledTools.insert(.keystrokes)
      return
    }
    guard !enabled || runtimePermissions.isAccessibilityTrusted(promptIfNeeded: true) else {
      liveControlState.highlightKeystrokes = false
      return
    }
    liveControlState.highlightKeystrokes = enabled
    keystrokeOverlayEnabledInSession = enabled
    recordingOverlayController?.setKeystrokeOverlayVisible(enabled)
    inputMonitor?.setCaptureKeystrokes(enabled)
  }

  private func setWebcamEnabledForActiveRecording(_ enabled: Bool) {
    guard !enabled || storeManager.canUse(.webcamOverlay) else {
      liveControlState.showWebcam = false
      liveControlState.disabledTools.insert(.webcam)
      return
    }
    guard webcamRecorder != nil,
          recordingOverlayController?.setWebcamVisible(enabled) == true
    else {
      liveControlState.showWebcam = false
      liveControlState.disabledTools.insert(.webcam)
      return
    }
    liveControlState.showWebcam = enabled
    if enabled {
      webcamOverlayUsedInSession = true
    }
  }
}
