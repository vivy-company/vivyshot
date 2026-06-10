import Foundation

extension AppSettings {
  func persistCaptureShortcut() {
    Definitions.captureKeyCode.write(Int(captureKeyCode), to: defaults)
    Definitions.captureUseCommand.write(captureUseCommand, to: defaults)
    Definitions.captureUseShift.write(captureUseShift, to: defaults)
    Definitions.captureUseOption.write(captureUseOption, to: defaults)
    Definitions.captureUseControl.write(captureUseControl, to: defaults)
    notifySettingsChanged(.captureShortcut)
  }

  func persistCaptureHelperSetting() {
    Definitions.captureShowHelper.write(captureShowHelper, to: defaults)
    notifySettingsChanged(.regionSelection)
  }

  func persistCaptureSmartWindowSelectionSetting() {
    Definitions.captureSmartWindowSelectionEnabled.write(captureSmartWindowSelectionEnabled, to: defaults)
    notifySettingsChanged(.regionSelection)
  }

  func persistAppLanguage() {
    Definitions.appLanguage.write(appLanguage.rawValue, to: defaults)
    notifySettingsChanged(.appLanguage)
  }

  func persistToolbarConfiguration() {
    defaults.set(toolOrder.map(\.rawValue), forKey: Keys.toolOrder)
    defaults.set(Array(hiddenTools).map(\.rawValue), forKey: Keys.hiddenTools)
    notifySettingsChanged(.regionSelection)
  }

  func persistVideoToolbarConfiguration() {
    defaults.set(recordingToolOrder.map(\.rawValue), forKey: Keys.recordingToolOrder)
    defaults.set(Array(hiddenRecordingTools).map(\.rawValue), forKey: Keys.hiddenRecordingTools)
    notifySettingsChanged(.regionSelection)
  }

  func persistTextSettings() {
    Definitions.textFontSize.write(textFontSize, to: defaults)
    Definitions.textFontName.write(textFontName, to: defaults)
    notifySettingsChanged(.regionSelection)
  }

  func persistDrawingSettings() {
    Definitions.drawingStrokeWidth.write(drawingStrokeWidth, to: defaults)
    notifySettingsChanged(.regionSelection)
  }

  func persistSaveSettings() {
    Definitions.defaultSaveDirectoryPath.write(defaultSaveDirectoryPath, to: defaults)
    Definitions.alwaysSaveToDefaultDirectory.write(alwaysSaveToDefaultDirectory, to: defaults)
    Definitions.saveCopiedScreenshotsToDefaultDirectory.write(saveCopiedScreenshotsToDefaultDirectory, to: defaults)
  }

  func persistAppearanceSettings() {
    Definitions.toolbarAccentRed.write(toolbarAccentRed, to: defaults)
    Definitions.toolbarAccentGreen.write(toolbarAccentGreen, to: defaults)
    Definitions.toolbarAccentBlue.write(toolbarAccentBlue, to: defaults)
    Definitions.toolbarAccentAlpha.write(toolbarAccentAlpha, to: defaults)
    Definitions.screenshotMainAction.write(screenshotMainAction.rawValue, to: defaults)
    notifySettingsChanged(.regionSelection)
  }

  func persistCaptureTransitionSettings() {
    Definitions.captureTransitionStyle.write(captureTransitionStyle.rawValue, to: defaults)
    Definitions.captureTransitionSpeed.write(captureTransitionSpeed, to: defaults)
    Definitions.captureTransitionIntensity.write(captureTransitionIntensity, to: defaults)
    notifySettingsChanged(.regionSelection)
  }

  func persistWebcamOverlayFrame() {
    defaults.set(webcamOverlayNormalizedX, forKey: Keys.webcamOverlayNormalizedX)
    defaults.set(webcamOverlayNormalizedY, forKey: Keys.webcamOverlayNormalizedY)
    defaults.set(webcamOverlayNormalizedWidth, forKey: Keys.webcamOverlayNormalizedWidth)
    defaults.set(webcamOverlayNormalizedHeight, forKey: Keys.webcamOverlayNormalizedHeight)
    notifySettingsChanged(.video)
  }

  func persistKeystrokeOverlayFrame() {
    defaults.set(keystrokeOverlayNormalizedX, forKey: Keys.keystrokeOverlayNormalizedX)
    defaults.set(keystrokeOverlayNormalizedY, forKey: Keys.keystrokeOverlayNormalizedY)
    defaults.set(keystrokeOverlayNormalizedWidth, forKey: Keys.keystrokeOverlayNormalizedWidth)
    defaults.set(keystrokeOverlayNormalizedHeight, forKey: Keys.keystrokeOverlayNormalizedHeight)
    notifySettingsChanged(.video)
  }

  func persistVideoCaptureSettings() {
    videoSettingsSnapshot.persist(to: defaults)
    notifySettingsChanged(.video)
  }

  var videoSettingsSnapshot: VideoSettingsSnapshot {
    VideoSettingsSnapshot(
      defaultCaptureType: defaultCaptureType,
      recordingEncoder: recordingEncoder,
      recordingFrameRate: recordingFrameRate,
      recordingCountdown: recordingCountdown,
      exportCodec: exportCodec,
      exportFrameRate: exportFrameRate,
      exportQuality: exportQuality,
      exportScale: exportScale,
      exportBitrate: exportBitrate,
      recordSystemAudio: recordSystemAudio,
      recordMicrophone: recordMicrophone,
      microphoneDeviceID: microphoneDeviceID,
      showWebcam: showWebcam,
      webcamDeviceID: webcamDeviceID,
      webcamOverlayShape: webcamOverlayShape,
      webcamOverlayAspectRatio: webcamOverlayAspectRatio,
      webcamOverlayFrame: webcamOverlayNormalizedFrame,
      highlightMouseClicks: highlightMouseClicks,
      mouseClickHighlightStyle: mouseClickHighlightStyle,
      highlightKeystrokes: highlightKeystrokes,
      keystrokeOverlayStyle: keystrokeOverlayStyle,
      keystrokeOverlaySize: keystrokeOverlaySize,
      keystrokeOverlayFrame: keystrokeOverlayNormalizedFrame,
      hideNotificationsBestEffort: hideNotificationsBestEffort
    )
  }
}
