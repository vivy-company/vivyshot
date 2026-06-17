import AppKit
import SwiftUI

@MainActor
extension SettingsView {
  private func appSettingsBinding<Value>(
    get: @escaping (AppSettings) -> Value,
    set: @escaping (AppSettings, Value) -> Void
  ) -> Binding<Value> {
    Binding(
      get: { get(settings) },
      set: { set(settings, $0) }
    )
  }

  var textFontSizeBinding: Binding<Double> {
    appSettingsBinding(get: \.textFontSize, set: { $0.setTextFontSize($1) })
  }

  var textFontNameBinding: Binding<String> {
    appSettingsBinding(get: \.textFontName, set: { $0.setTextFontName($1) })
  }

  var drawingStrokeWidthBinding: Binding<Double> {
    appSettingsBinding(get: \.drawingStrokeWidth, set: { $0.setDrawingStrokeWidth($1) })
  }

  var captureTransitionStyleBinding: Binding<CaptureTransitionStyle> {
    appSettingsBinding(get: \.captureTransitionStyle, set: { $0.setCaptureTransitionStyle($1) })
  }

  var captureTransitionSpeedBinding: Binding<Double> {
    appSettingsBinding(get: \.captureTransitionSpeed, set: { $0.setCaptureTransitionSpeed($1) })
  }

  var captureTransitionIntensityBinding: Binding<Double> {
    appSettingsBinding(get: \.captureTransitionIntensity, set: { $0.setCaptureTransitionIntensity($1) })
  }

  var captureShowHelperBinding: Binding<Bool> {
    appSettingsBinding(get: \.captureShowHelper, set: { $0.setCaptureShowHelper($1) })
  }

  var captureSmartWindowSelectionBinding: Binding<Bool> {
    appSettingsBinding(get: \.captureSmartWindowSelectionEnabled, set: { $0.setCaptureSmartWindowSelectionEnabled($1) })
  }

  var launchAtLoginBinding: Binding<Bool> {
    Binding(
      get: { launchAtLoginController.isEnabled },
      set: { launchAtLoginController.setEnabled($0) }
    )
  }

  var appLanguageBinding: Binding<AppLanguage> {
    appSettingsBinding(get: \.appLanguage, set: { $0.setAppLanguage($1) })
  }

  var alwaysSaveToDefaultDirectoryBinding: Binding<Bool> {
    appSettingsBinding(get: \.alwaysSaveToDefaultDirectory, set: { $0.setAlwaysSaveToDefaultDirectory($1) })
  }

  var saveCopiedScreenshotsToDefaultDirectoryBinding: Binding<Bool> {
    appSettingsBinding(
      get: \.saveCopiedScreenshotsToDefaultDirectory,
      set: { $0.setSaveCopiedScreenshotsToDefaultDirectory($1) }
    )
  }

  var toolbarAccentColorBinding: Binding<Color> {
    Binding(
      get: { Color(settings.toolbarAccentColor) },
      set: { settings.setToolbarAccentColor(NSColor($0)) }
    )
  }

  var screenshotMainActionBinding: Binding<ScreenshotMainAction> {
    appSettingsBinding(get: \.screenshotMainAction, set: { $0.setScreenshotMainAction($1) })
  }

  var defaultCaptureTypeBinding: Binding<CaptureContentType> {
    appSettingsBinding(get: \.defaultCaptureType, set: { $0.setDefaultCaptureType($1) })
  }

  var recordingEncoderBinding: Binding<RecordingEncoder> {
    appSettingsBinding(get: \.recordingEncoder, set: { $0.setRecordingEncoder($1) })
  }

  var recordingFrameRateBinding: Binding<RecordingFrameRate> {
    appSettingsBinding(get: \.recordingFrameRate, set: { $0.setRecordingFrameRate($1) })
  }

  var recordingCountdownBinding: Binding<RecordingCountdown> {
    appSettingsBinding(get: \.recordingCountdown, set: { $0.setRecordingCountdown($1) })
  }

  var recordingColorProfileBinding: Binding<RecordingColorProfile> {
    appSettingsBinding(get: \.recordingColorProfile, set: { $0.setRecordingColorProfile($1) })
  }

  var recordingCaptureResolutionBinding: Binding<RecordingCaptureResolution> {
    appSettingsBinding(get: \.recordingCaptureResolution, set: { $0.setRecordingCaptureResolution($1) })
  }

  var recordingCaptureBufferingBinding: Binding<RecordingCaptureBuffering> {
    appSettingsBinding(get: \.recordingCaptureBuffering, set: { $0.setRecordingCaptureBuffering($1) })
  }

  var recordingShowsPointerBinding: Binding<Bool> {
    appSettingsBinding(get: \.recordingShowsPointer, set: { $0.setRecordingShowsPointer($1) })
  }

  var recordingShowsSystemClickRingsBinding: Binding<Bool> {
    appSettingsBinding(get: \.recordingShowsSystemClickRings, set: { $0.setRecordingShowsSystemClickRings($1) })
  }

  var recordingIncludesAppAudioBinding: Binding<Bool> {
    appSettingsBinding(get: \.recordingIncludesAppAudio, set: { $0.setRecordingIncludesAppAudio($1) })
  }

  var recordSystemAudioBinding: Binding<Bool> {
    appSettingsBinding(get: \.recordSystemAudio, set: { $0.setVideoRecordSystemAudio($1) })
  }

  var recordMicrophoneBinding: Binding<Bool> {
    appSettingsBinding(get: \.recordMicrophone, set: { $0.setVideoRecordMicrophone($1) })
  }

  var showWebcamBinding: Binding<Bool> {
    appSettingsBinding(get: \.showWebcam, set: { $0.setVideoShowWebcam($1) })
  }

  var webcamOverlaySizeSliderBinding: Binding<Double> {
    appSettingsBinding(get: \.webcamOverlayNormalizedWidth, set: { $0.setWebcamOverlayWidth($1) })
  }

  var webcamOverlayShapeBinding: Binding<WebcamShape> {
    appSettingsBinding(get: \.webcamOverlayShape, set: { $0.setWebcamOverlayShape($1) })
  }

  var webcamOverlayAspectRatioBinding: Binding<WebcamAspectRatio> {
    appSettingsBinding(get: \.webcamOverlayAspectRatio, set: { $0.setWebcamOverlayAspectRatio($1) })
  }

  var mouseClickHighlightStyleBinding: Binding<MouseClickHighlightStyle> {
    appSettingsBinding(get: \.mouseClickHighlightStyle, set: { $0.setMouseClickHighlightStyle($1) })
  }

  var highlightMouseClicksBinding: Binding<Bool> {
    appSettingsBinding(get: \.highlightMouseClicks, set: { $0.setVideoHighlightMouseClicks($1) })
  }

  var highlightKeystrokesBinding: Binding<Bool> {
    appSettingsBinding(get: \.highlightKeystrokes, set: { $0.setVideoHighlightKeystrokes($1) })
  }

  var keystrokeOverlayStyleBinding: Binding<KeystrokeStyle> {
    appSettingsBinding(get: \.keystrokeOverlayStyle, set: { $0.setKeystrokeOverlayStyle($1) })
  }

  var keystrokeOverlaySizeSliderBinding: Binding<Double> {
    appSettingsBinding(get: \.keystrokeOverlayNormalizedWidth, set: { $0.setKeystrokeOverlayScale($1) })
  }

  var hideNotificationsBestEffortBinding: Binding<Bool> {
    appSettingsBinding(get: \.hideNotificationsBestEffort, set: { $0.setVideoHideNotificationsBestEffort($1) })
  }

}
