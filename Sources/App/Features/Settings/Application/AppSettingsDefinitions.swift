import Carbon
import Foundation

struct UserDefaultSetting<Value: Sendable>: Sendable {
  let key: String
  let defaultValue: Value
}

extension UserDefaultSetting where Value == Bool {
  func read(from defaults: UserDefaults) -> Bool {
    guard defaults.object(forKey: key) != nil else {
      return defaultValue
    }
    return defaults.bool(forKey: key)
  }

  func write(_ value: Bool, to defaults: UserDefaults) {
    defaults.set(value, forKey: key)
  }
}

extension UserDefaultSetting where Value == Int {
  func read(from defaults: UserDefaults) -> Int {
    defaults.object(forKey: key) as? Int ?? defaultValue
  }

  func write(_ value: Int, to defaults: UserDefaults) {
    defaults.set(value, forKey: key)
  }
}

extension UserDefaultSetting where Value == Double {
  func read(from defaults: UserDefaults) -> Double {
    defaults.object(forKey: key) as? Double ?? defaultValue
  }

  func write(_ value: Double, to defaults: UserDefaults) {
    defaults.set(value, forKey: key)
  }
}

extension UserDefaultSetting where Value == String {
  func read(from defaults: UserDefaults) -> String {
    defaults.string(forKey: key) ?? defaultValue
  }

  func write(_ value: String, to defaults: UserDefaults) {
    defaults.set(value, forKey: key)
  }
}

extension AppSettings {
  /// Registry entries for scalar persisted settings. Keep the key and default together when adding new scalar settings.
  enum Definitions {
    static let captureKeyCode = UserDefaultSetting(key: Keys.captureKeyCode, defaultValue: Defaults.captureKeyCode)
    static let captureUseCommand = UserDefaultSetting(key: Keys.captureUseCommand, defaultValue: Defaults.captureUseCommand)
    static let captureUseShift = UserDefaultSetting(key: Keys.captureUseShift, defaultValue: Defaults.captureUseShift)
    static let captureUseOption = UserDefaultSetting(key: Keys.captureUseOption, defaultValue: false)
    static let captureUseControl = UserDefaultSetting(key: Keys.captureUseControl, defaultValue: false)
    static let captureShowHelper = UserDefaultSetting(key: Keys.captureShowHelper, defaultValue: Defaults.captureShowHelper)
    static let captureSmartWindowSelectionEnabled = UserDefaultSetting(
      key: Keys.captureSmartWindowSelectionEnabled,
      defaultValue: Defaults.smartWindowSelection
    )
    static let appLanguage = UserDefaultSetting(key: Keys.appLanguage, defaultValue: AppLanguage.system.rawValue)
    static let textFontSize = UserDefaultSetting(key: Keys.textFontSize, defaultValue: Defaults.textFontSize)
    static let textFontName = UserDefaultSetting(key: Keys.textFontName, defaultValue: Defaults.textFontName)
    static let drawingStrokeWidth = UserDefaultSetting(key: Keys.drawingStrokeWidth, defaultValue: Defaults.drawingStrokeWidth)
    static let defaultSaveDirectoryPath = UserDefaultSetting(key: Keys.defaultSaveDirectoryPath, defaultValue: "")
    static let alwaysSaveToDefaultDirectory = UserDefaultSetting(key: Keys.alwaysSaveToDefaultDirectory, defaultValue: false)
    static let saveCopiedScreenshotsToDefaultDirectory = UserDefaultSetting(
      key: Keys.saveCopiedScreenshotsToDefaultDirectory,
      defaultValue: false
    )
    static let videoSaveDirectoryPath = UserDefaultSetting(key: Keys.videoSaveDirectoryPath, defaultValue: "")
    static let videoSaveSkipsDialog = UserDefaultSetting(key: Keys.videoSaveSkipsDialog, defaultValue: false)
    static let saveCopiedVideosToDefaultDirectory = UserDefaultSetting(
      key: Keys.saveCopiedVideosToDefaultDirectory,
      defaultValue: false
    )
    static let captureTransitionStyle = UserDefaultSetting(
      key: Keys.captureTransitionStyle,
      defaultValue: Defaults.transitionStyle.rawValue
    )
    static let captureTransitionSpeed = UserDefaultSetting(key: Keys.captureTransitionSpeed, defaultValue: Defaults.transitionSpeed)
    static let captureTransitionIntensity = UserDefaultSetting(
      key: Keys.captureTransitionIntensity,
      defaultValue: Defaults.transitionIntensity
    )
    static let toolbarAccentRed = UserDefaultSetting(key: Keys.toolbarAccentRed, defaultValue: 0.0)
    static let toolbarAccentGreen = UserDefaultSetting(key: Keys.toolbarAccentGreen, defaultValue: 0.0)
    static let toolbarAccentBlue = UserDefaultSetting(key: Keys.toolbarAccentBlue, defaultValue: 0.0)
    static let toolbarAccentAlpha = UserDefaultSetting(key: Keys.toolbarAccentAlpha, defaultValue: 1.0)
    static let screenshotMainAction = UserDefaultSetting(
      key: Keys.screenshotMainAction,
      defaultValue: Defaults.screenshotMainAction.rawValue
    )
  }

  /// Stable UserDefaults keys. These strings are persisted app data, so rename only with a deliberate migration plan.
  enum Keys {
    static let captureKeyCode = "settings.capture.keyCode"
    static let captureUseCommand = "settings.capture.useCommand"
    static let captureUseShift = "settings.capture.useShift"
    static let captureUseOption = "settings.capture.useOption"
    static let captureUseControl = "settings.capture.useControl"
    static let captureShowHelper = "settings.capture.showHelper"
    static let captureSmartWindowSelectionEnabled = "settings.capture.smartWindowSelectionEnabled"
    static let defaultCaptureType = "settings.capture.defaultType"
    static let appLanguage = "settings.app.language"

    static let toolOrder = "settings.toolbar.toolOrder"
    static let hiddenTools = "settings.toolbar.hiddenTools"
    static let recordingToolOrder = "settings.video.toolbar.toolOrder"
    static let hiddenRecordingTools = "settings.video.toolbar.hiddenTools"

    static let textFontSize = "settings.text.fontSize"
    static let textFontName = "settings.text.fontName"
    static let drawingStrokeWidth = "settings.drawing.strokeWidth"

    static let defaultSaveDirectoryPath = "settings.save.defaultDirectoryPath"
    static let alwaysSaveToDefaultDirectory = "settings.save.alwaysSaveToDefaultDirectory"
    static let saveCopiedScreenshotsToDefaultDirectory = "settings.save.saveCopiedScreenshotsToDefaultDirectory"
    static let videoSaveDirectoryPath = "settings.video.save.defaultDirectoryPath"
    static let videoSaveSkipsDialog = "settings.video.save.skipsDialog"
    static let saveCopiedVideosToDefaultDirectory = "settings.video.save.saveCopiedVideosToDefaultDirectory"

    static let captureTransitionStyle = "settings.capture.transition.style"
    static let captureTransitionSpeed = "settings.capture.transition.speed"
    static let captureTransitionIntensity = "settings.capture.transition.intensity"
    static let toolbarAccentRed = "settings.appearance.toolbarAccent.red"
    static let toolbarAccentGreen = "settings.appearance.toolbarAccent.green"
    static let toolbarAccentBlue = "settings.appearance.toolbarAccent.blue"
    static let toolbarAccentAlpha = "settings.appearance.toolbarAccent.alpha"
    static let screenshotMainAction = "settings.appearance.screenshotMainAction"

    static let recordingEncoder = "settings.video.recordingEncoder"
    static let recordingFrameRate = "settings.video.frameRate"
    static let recordingCountdown = "settings.video.countdown"
    static let recordingColorProfile = "settings.video.colorProfile"
    static let recordingCaptureResolution = "settings.video.captureResolution"
    static let recordingCaptureBuffering = "settings.video.captureBuffering"
    static let recordingShowsPointer = "settings.video.showsPointer"
    static let recordingShowsSystemClickRings = "settings.video.showsSystemClickRings"
    static let recordingIncludesAppAudio = "settings.video.includesAppAudio"
    static let exportCodec = "settings.video.export.codec"
    static let exportFrameRate = "settings.video.export.frameRate"
    static let exportQuality = "settings.video.export.quality"
    static let exportScale = "settings.video.export.scale"
    static let exportBitrate = "settings.video.export.bitrate"
    static let recordSystemAudio = "settings.video.recordSystemAudio"
    static let recordMicrophone = "settings.video.recordMicrophone"
    static let microphoneDeviceID = "settings.video.microphone.deviceID"
    static let showWebcam = "settings.video.showWebcam"
    static let webcamDeviceID = "settings.video.webcam.deviceID"
    static let webcamOverlayShape = "settings.video.webcam.overlayShape"
    static let webcamOverlayAspectRatio = "settings.video.webcam.overlayAspectRatio"
    static let webcamOverlayNormalizedX = "settings.video.webcam.overlay.normalizedX"
    static let webcamOverlayNormalizedY = "settings.video.webcam.overlay.normalizedY"
    static let webcamOverlayNormalizedWidth = "settings.video.webcam.overlay.normalizedWidth"
    static let webcamOverlayNormalizedHeight = "settings.video.webcam.overlay.normalizedHeight"
    static let highlightMouseClicks = "settings.video.highlightMouseClicks"
    static let mouseClickHighlightStyle = "settings.video.mouseClick.highlightStyle"
    static let highlightKeystrokes = "settings.video.highlightKeystrokes"
    static let keystrokeOverlayStyle = "settings.video.keystroke.overlay.style"
    static let keystrokeOverlaySize = "settings.video.keystroke.overlay.size"
    static let keystrokeOverlayNormalizedX = "settings.video.keystroke.overlay.normalizedX"
    static let keystrokeOverlayNormalizedY = "settings.video.keystroke.overlay.normalizedY"
    static let keystrokeOverlayNormalizedWidth = "settings.video.keystroke.overlay.normalizedWidth"
    static let keystrokeOverlayNormalizedHeight = "settings.video.keystroke.overlay.normalizedHeight"
    static let hideNotificationsBestEffort = "settings.video.hideNotificationsBestEffort"
  }

  /// Built-in preference values used when the user has not persisted a value yet.
  enum Defaults {
    static let captureKeyCode = Int(kVK_ANSI_C)
    static let captureUseCommand = true
    static let captureUseShift = true
    static let captureShowHelper = true
    static let smartWindowSelection = true
    static let textFontSize = 16.0
    static let textFontName = "System"
    static let drawingStrokeWidth = 4.0
    static let transitionStyle = CaptureTransitionStyle.ripple
    static let transitionSpeed = 1.25
    static let transitionIntensity = 0.72
    static let screenshotMainAction = ScreenshotMainAction.copy
    static let recordingEncoder = RecordingEncoder.standardH264
    static let recordingFrameRate = RecordingFrameRate.fps30
    static let recordingCountdown = RecordingCountdown.off
    static let recordingColorProfile = RecordingColorProfile.automatic
    static let recordingCaptureResolution = RecordingCaptureResolution.native
    static let recordingCaptureBuffering = RecordingCaptureBuffering.balanced
    static let recordingShowsPointer = true
    static let recordingShowsSystemClickRings = false
    static let recordingIncludesAppAudio = true
    static let exportCodec = PostRecordingExportCodec.h264
    static let exportFrameRate = PostRecordingExportFrameRate.fps30
    static let exportQuality = PostRecordingExportQuality.standard
    static let exportScale = PostRecordingExportScale.full
    static let exportBitrate = PostRecordingExportBitratePreset.standard
    static let recordSystemAudio = true
    static let webcamShape = WebcamShape.roundedRect
    static let webcamAspectRatio = WebcamAspectRatio.square
    static let highlightMouseClicks = true
    static let mouseClickHighlightStyle = MouseClickHighlightStyle.system
    static let keystrokeStyle = KeystrokeStyle.glass
    static let keystrokeSize = KeystrokeSize.medium
    static let hideNotifications = true
  }

  /// Numeric guardrails for persisted settings and draggable overlay frames.
  enum Limits {
    static let normalized = 0.0...1.0
    static let textFontSize = 10.0...72.0
    static let drawingStrokeWidth = 1.0...12.0
    static let transitionSpeed = 0.5...2.4
    static let transitionIntensity = 0.2...1.0
    static let minimumOverlayDimension = 0.04
    static let webcamWidth = 0.12...0.50
    static let webcamHeight = 0.04...0.90
    static let keystrokeWidth = 0.20...0.72
    static let keystrokeHeight = 0.07...0.28
  }
}
