import CoreGraphics
import Foundation

@MainActor
struct VideoSettingsSnapshot {
  var defaultCaptureType: CaptureContentType
  var recordingEncoder: RecordingEncoder
  var recordingFrameRate: RecordingFrameRate
  var recordingCountdown: RecordingCountdown
  var recordingColorProfile: RecordingColorProfile
  var recordingCaptureResolution: RecordingCaptureResolution
  var recordingCaptureBuffering: RecordingCaptureBuffering
  var recordingShowsPointer: Bool
  var recordingShowsSystemClickRings: Bool
  var recordingWindowCaptureStyle: RecordingWindowCaptureStyle
  var recordingIncludesAppAudio: Bool
  var exportCodec: PostRecordingExportCodec
  var exportFrameRate: PostRecordingExportFrameRate
  var exportQuality: PostRecordingExportQuality
  var exportScale: PostRecordingExportScale
  var exportBitrate: PostRecordingExportBitratePreset
  var recordSystemAudio: Bool
  var recordMicrophone: Bool
  var microphoneDeviceID: String
  var showWebcam: Bool
  var webcamDeviceID: String
  var webcamOverlayShape: WebcamShape
  var webcamOverlayAspectRatio: WebcamAspectRatio
  var webcamOverlayFrame: CGRect
  var highlightMouseClicks: Bool
  var mouseClickHighlightStyle: MouseClickHighlightStyle
  var highlightKeystrokes: Bool
  var keystrokeOverlayStyle: KeystrokeStyle
  var keystrokeOverlaySize: KeystrokeSize
  var keystrokeOverlayFrame: CGRect
  var hideNotificationsBestEffort: Bool

  static var defaultValues: VideoSettingsSnapshot {
    VideoSettingsSnapshot(
      defaultCaptureType: .screenshot,
      recordingEncoder: AppSettings.Defaults.recordingEncoder,
      recordingFrameRate: AppSettings.Defaults.recordingFrameRate,
      recordingCountdown: AppSettings.Defaults.recordingCountdown,
      recordingColorProfile: AppSettings.Defaults.recordingColorProfile,
      recordingCaptureResolution: AppSettings.Defaults.recordingCaptureResolution,
      recordingCaptureBuffering: AppSettings.Defaults.recordingCaptureBuffering,
      recordingShowsPointer: AppSettings.Defaults.recordingShowsPointer,
      recordingShowsSystemClickRings: AppSettings.Defaults.recordingShowsSystemClickRings,
      recordingWindowCaptureStyle: AppSettings.Defaults.recordingWindowCaptureStyle,
      recordingIncludesAppAudio: AppSettings.Defaults.recordingIncludesAppAudio,
      exportCodec: AppSettings.Defaults.exportCodec,
      exportFrameRate: AppSettings.Defaults.exportFrameRate,
      exportQuality: AppSettings.Defaults.exportQuality,
      exportScale: AppSettings.Defaults.exportScale,
      exportBitrate: AppSettings.Defaults.exportBitrate,
      recordSystemAudio: AppSettings.Defaults.recordSystemAudio,
      recordMicrophone: false,
      microphoneDeviceID: "",
      showWebcam: false,
      webcamDeviceID: "",
      webcamOverlayShape: AppSettings.Defaults.webcamShape,
      webcamOverlayAspectRatio: AppSettings.Defaults.webcamAspectRatio,
      webcamOverlayFrame: AppSettings.defaultWebcamOverlayFrame,
      highlightMouseClicks: AppSettings.Defaults.highlightMouseClicks,
      mouseClickHighlightStyle: AppSettings.Defaults.mouseClickHighlightStyle,
      highlightKeystrokes: false,
      keystrokeOverlayStyle: AppSettings.Defaults.keystrokeStyle,
      keystrokeOverlaySize: AppSettings.Defaults.keystrokeSize,
      keystrokeOverlayFrame: AppSettings.defaultKeystrokeOverlayFrame,
      hideNotificationsBestEffort: AppSettings.Defaults.hideNotifications
    )
  }

  static func load(from defaults: UserDefaults) -> VideoSettingsSnapshot {
    let storedDefaultCaptureType = defaults.object(forKey: AppSettings.Keys.defaultCaptureType) as? Int
    let storedRecordingEncoder = defaults.object(forKey: AppSettings.Keys.recordingEncoder) as? Int
    let storedRecordingFrameRate = defaults.object(forKey: AppSettings.Keys.recordingFrameRate) as? Int
    let storedRecordingCountdown = defaults.object(forKey: AppSettings.Keys.recordingCountdown) as? Int
    let storedRecordingColorProfile = defaults.object(forKey: AppSettings.Keys.recordingColorProfile) as? Int
    let storedRecordingCaptureResolution = defaults.object(forKey: AppSettings.Keys.recordingCaptureResolution) as? Int
    let storedRecordingCaptureBuffering = defaults.object(forKey: AppSettings.Keys.recordingCaptureBuffering) as? Int
    let storedRecordingWindowCaptureStyle = defaults.object(forKey: AppSettings.Keys.recordingWindowCaptureStyle) as? Int
    let storedExportFrameRate = defaults.object(forKey: AppSettings.Keys.exportFrameRate) as? Int
    let storedWebcamShape = defaults.object(forKey: AppSettings.Keys.webcamOverlayShape) as? Int
    let storedWebcamAspectRatio = defaults.object(forKey: AppSettings.Keys.webcamOverlayAspectRatio) as? Int
    let storedMouseClickStyle = defaults.object(forKey: AppSettings.Keys.mouseClickHighlightStyle) as? Int
    let storedKeystrokeStyle = defaults.object(forKey: AppSettings.Keys.keystrokeOverlayStyle) as? Int
    let storedKeystrokeSize = defaults.object(forKey: AppSettings.Keys.keystrokeOverlaySize) as? Int

    let webcamShape = WebcamShape(
      rawValue: storedWebcamShape ?? AppSettings.Defaults.webcamShape.rawValue
    ) ?? AppSettings.Defaults.webcamShape
    let storedAspectRatio = WebcamAspectRatio(
      rawValue: storedWebcamAspectRatio ?? AppSettings.Defaults.webcamAspectRatio.rawValue
    ) ?? AppSettings.Defaults.webcamAspectRatio
    let webcamAspectRatio = webcamShape == .circle ? WebcamAspectRatio.square : storedAspectRatio

    let defaultWebcamFrame = AppSettings.defaultWebcamOverlayFrame
    let defaultKeystrokeFrame = AppSettings.defaultKeystrokeOverlayFrame

    let recordSystemAudio: Bool
    if defaults.object(forKey: AppSettings.Keys.recordSystemAudio) == nil {
      recordSystemAudio = AppSettings.Defaults.recordSystemAudio
    } else {
      recordSystemAudio = defaults.bool(forKey: AppSettings.Keys.recordSystemAudio)
    }

    let highlightMouseClicks: Bool
    if defaults.object(forKey: AppSettings.Keys.highlightMouseClicks) == nil {
      highlightMouseClicks = AppSettings.Defaults.highlightMouseClicks
    } else {
      highlightMouseClicks = defaults.bool(forKey: AppSettings.Keys.highlightMouseClicks)
    }

    let hideNotifications: Bool
    if defaults.object(forKey: AppSettings.Keys.hideNotificationsBestEffort) == nil {
      hideNotifications = AppSettings.Defaults.hideNotifications
    } else {
      hideNotifications = defaults.bool(forKey: AppSettings.Keys.hideNotificationsBestEffort)
    }

    let recordingShowsPointer = boolValue(
      forKey: AppSettings.Keys.recordingShowsPointer,
      defaultValue: AppSettings.Defaults.recordingShowsPointer,
      defaults: defaults
    )
    let recordingShowsSystemClickRings = boolValue(
      forKey: AppSettings.Keys.recordingShowsSystemClickRings,
      defaultValue: AppSettings.Defaults.recordingShowsSystemClickRings,
      defaults: defaults
    )
    let recordingIncludesAppAudio = boolValue(
      forKey: AppSettings.Keys.recordingIncludesAppAudio,
      defaultValue: AppSettings.Defaults.recordingIncludesAppAudio,
      defaults: defaults
    )

    return VideoSettingsSnapshot(
      defaultCaptureType: CaptureContentType(
        rawValue: storedDefaultCaptureType ?? CaptureContentType.screenshot.rawValue
      ) ?? .screenshot,
      recordingEncoder: RecordingEncoder(
        rawValue: storedRecordingEncoder ?? AppSettings.Defaults.recordingEncoder.rawValue
      ) ?? AppSettings.Defaults.recordingEncoder,
      recordingFrameRate: RecordingFrameRate(
        rawValue: storedRecordingFrameRate ?? AppSettings.Defaults.recordingFrameRate.rawValue
      ) ?? AppSettings.Defaults.recordingFrameRate,
      recordingCountdown: RecordingCountdown(
        rawValue: storedRecordingCountdown ?? AppSettings.Defaults.recordingCountdown.rawValue
      ) ?? AppSettings.Defaults.recordingCountdown,
      recordingColorProfile: RecordingColorProfile(
        rawValue: storedRecordingColorProfile ?? AppSettings.Defaults.recordingColorProfile.rawValue
      ) ?? AppSettings.Defaults.recordingColorProfile,
      recordingCaptureResolution: RecordingCaptureResolution(
        rawValue: storedRecordingCaptureResolution ?? AppSettings.Defaults.recordingCaptureResolution.rawValue
      ) ?? AppSettings.Defaults.recordingCaptureResolution,
      recordingCaptureBuffering: RecordingCaptureBuffering(
        rawValue: storedRecordingCaptureBuffering ?? AppSettings.Defaults.recordingCaptureBuffering.rawValue
      ) ?? AppSettings.Defaults.recordingCaptureBuffering,
      recordingShowsPointer: recordingShowsPointer,
      recordingShowsSystemClickRings: recordingShowsSystemClickRings,
      recordingWindowCaptureStyle: RecordingWindowCaptureStyle(
        rawValue: storedRecordingWindowCaptureStyle ?? AppSettings.Defaults.recordingWindowCaptureStyle.rawValue
      ) ?? AppSettings.Defaults.recordingWindowCaptureStyle,
      recordingIncludesAppAudio: recordingIncludesAppAudio,
      exportCodec: PostRecordingExportCodec(
        rawValue: defaults.string(forKey: AppSettings.Keys.exportCodec) ?? AppSettings.Defaults.exportCodec.rawValue
      ) ?? AppSettings.Defaults.exportCodec,
      exportFrameRate: PostRecordingExportFrameRate(
        rawValue: storedExportFrameRate ?? AppSettings.Defaults.exportFrameRate.rawValue
      ) ?? AppSettings.Defaults.exportFrameRate,
      exportQuality: PostRecordingExportQuality(
        rawValue: defaults.string(forKey: AppSettings.Keys.exportQuality) ?? AppSettings.Defaults.exportQuality.rawValue
      ) ?? AppSettings.Defaults.exportQuality,
      exportScale: PostRecordingExportScale(
        rawValue: defaults.string(forKey: AppSettings.Keys.exportScale) ?? AppSettings.Defaults.exportScale.rawValue
      ) ?? AppSettings.Defaults.exportScale,
      exportBitrate: PostRecordingExportBitratePreset(
        rawValue: defaults.string(forKey: AppSettings.Keys.exportBitrate) ?? AppSettings.Defaults.exportBitrate.rawValue
      ) ?? AppSettings.Defaults.exportBitrate,
      recordSystemAudio: recordSystemAudio,
      recordMicrophone: defaults.bool(forKey: AppSettings.Keys.recordMicrophone),
      microphoneDeviceID: defaults.string(forKey: AppSettings.Keys.microphoneDeviceID) ?? "",
      showWebcam: defaults.bool(forKey: AppSettings.Keys.showWebcam),
      webcamDeviceID: defaults.string(forKey: AppSettings.Keys.webcamDeviceID) ?? "",
      webcamOverlayShape: webcamShape,
      webcamOverlayAspectRatio: webcamAspectRatio,
      webcamOverlayFrame: CGRect(
        x: AppSettings.clampedNormalizedOrigin(
          defaults.object(forKey: AppSettings.Keys.webcamOverlayNormalizedX) as? Double ?? defaultWebcamFrame.minX
        ),
        y: AppSettings.clampedNormalizedOrigin(
          defaults.object(forKey: AppSettings.Keys.webcamOverlayNormalizedY) as? Double ?? defaultWebcamFrame.minY
        ),
        width: AppSettings.clampedNormalizedDimension(
          defaults.object(forKey: AppSettings.Keys.webcamOverlayNormalizedWidth) as? Double ?? defaultWebcamFrame.width
        ),
        height: AppSettings.clampedNormalizedDimension(
          defaults.object(forKey: AppSettings.Keys.webcamOverlayNormalizedHeight) as? Double ?? defaultWebcamFrame.height
        )
      ),
      highlightMouseClicks: highlightMouseClicks,
      mouseClickHighlightStyle: storedMouseClickStyle
        .flatMap(MouseClickHighlightStyle.init(rawValue:))
        ?? AppSettings.Defaults.mouseClickHighlightStyle,
      highlightKeystrokes: defaults.bool(forKey: AppSettings.Keys.highlightKeystrokes),
      keystrokeOverlayStyle: KeystrokeStyle(
        rawValue: storedKeystrokeStyle ?? AppSettings.Defaults.keystrokeStyle.rawValue
      ) ?? AppSettings.Defaults.keystrokeStyle,
      keystrokeOverlaySize: KeystrokeSize(
        rawValue: storedKeystrokeSize ?? AppSettings.Defaults.keystrokeSize.rawValue
      ) ?? AppSettings.Defaults.keystrokeSize,
      keystrokeOverlayFrame: CGRect(
        x: AppSettings.clampedNormalizedOrigin(
          defaults.object(forKey: AppSettings.Keys.keystrokeOverlayNormalizedX) as? Double ?? defaultKeystrokeFrame.minX
        ),
        y: AppSettings.clampedNormalizedOrigin(
          defaults.object(forKey: AppSettings.Keys.keystrokeOverlayNormalizedY) as? Double ?? defaultKeystrokeFrame.minY
        ),
        width: AppSettings.clampedNormalizedDimension(
          defaults.object(forKey: AppSettings.Keys.keystrokeOverlayNormalizedWidth) as? Double ?? defaultKeystrokeFrame.width
        ),
        height: AppSettings.clampedNormalizedDimension(
          defaults.object(forKey: AppSettings.Keys.keystrokeOverlayNormalizedHeight) as? Double ?? defaultKeystrokeFrame.height
        )
      ),
      hideNotificationsBestEffort: hideNotifications
    )
  }

  func persist(to defaults: UserDefaults) {
    defaults.set(defaultCaptureType.rawValue, forKey: AppSettings.Keys.defaultCaptureType)
    defaults.set(recordingEncoder.rawValue, forKey: AppSettings.Keys.recordingEncoder)
    defaults.set(recordingFrameRate.rawValue, forKey: AppSettings.Keys.recordingFrameRate)
    defaults.set(recordingCountdown.rawValue, forKey: AppSettings.Keys.recordingCountdown)
    defaults.set(recordingColorProfile.rawValue, forKey: AppSettings.Keys.recordingColorProfile)
    defaults.set(recordingCaptureResolution.rawValue, forKey: AppSettings.Keys.recordingCaptureResolution)
    defaults.set(recordingCaptureBuffering.rawValue, forKey: AppSettings.Keys.recordingCaptureBuffering)
    defaults.set(recordingShowsPointer, forKey: AppSettings.Keys.recordingShowsPointer)
    defaults.set(recordingShowsSystemClickRings, forKey: AppSettings.Keys.recordingShowsSystemClickRings)
    defaults.set(recordingWindowCaptureStyle.rawValue, forKey: AppSettings.Keys.recordingWindowCaptureStyle)
    defaults.set(recordingIncludesAppAudio, forKey: AppSettings.Keys.recordingIncludesAppAudio)
    defaults.set(exportCodec.rawValue, forKey: AppSettings.Keys.exportCodec)
    defaults.set(exportFrameRate.rawValue, forKey: AppSettings.Keys.exportFrameRate)
    defaults.set(exportQuality.rawValue, forKey: AppSettings.Keys.exportQuality)
    defaults.set(exportScale.rawValue, forKey: AppSettings.Keys.exportScale)
    defaults.set(exportBitrate.rawValue, forKey: AppSettings.Keys.exportBitrate)
    defaults.set(recordSystemAudio, forKey: AppSettings.Keys.recordSystemAudio)
    defaults.set(recordMicrophone, forKey: AppSettings.Keys.recordMicrophone)
    defaults.set(microphoneDeviceID, forKey: AppSettings.Keys.microphoneDeviceID)
    defaults.set(showWebcam, forKey: AppSettings.Keys.showWebcam)
    defaults.set(webcamDeviceID, forKey: AppSettings.Keys.webcamDeviceID)
    defaults.set(webcamOverlayShape.rawValue, forKey: AppSettings.Keys.webcamOverlayShape)
    defaults.set(webcamOverlayAspectRatio.rawValue, forKey: AppSettings.Keys.webcamOverlayAspectRatio)
    defaults.set(webcamOverlayFrame.minX, forKey: AppSettings.Keys.webcamOverlayNormalizedX)
    defaults.set(webcamOverlayFrame.minY, forKey: AppSettings.Keys.webcamOverlayNormalizedY)
    defaults.set(webcamOverlayFrame.width, forKey: AppSettings.Keys.webcamOverlayNormalizedWidth)
    defaults.set(webcamOverlayFrame.height, forKey: AppSettings.Keys.webcamOverlayNormalizedHeight)
    defaults.set(highlightMouseClicks, forKey: AppSettings.Keys.highlightMouseClicks)
    defaults.set(mouseClickHighlightStyle.rawValue, forKey: AppSettings.Keys.mouseClickHighlightStyle)
    defaults.set(highlightKeystrokes, forKey: AppSettings.Keys.highlightKeystrokes)
    defaults.set(keystrokeOverlayStyle.rawValue, forKey: AppSettings.Keys.keystrokeOverlayStyle)
    defaults.set(keystrokeOverlaySize.rawValue, forKey: AppSettings.Keys.keystrokeOverlaySize)
    defaults.set(keystrokeOverlayFrame.minX, forKey: AppSettings.Keys.keystrokeOverlayNormalizedX)
    defaults.set(keystrokeOverlayFrame.minY, forKey: AppSettings.Keys.keystrokeOverlayNormalizedY)
    defaults.set(keystrokeOverlayFrame.width, forKey: AppSettings.Keys.keystrokeOverlayNormalizedWidth)
    defaults.set(keystrokeOverlayFrame.height, forKey: AppSettings.Keys.keystrokeOverlayNormalizedHeight)
    defaults.set(hideNotificationsBestEffort, forKey: AppSettings.Keys.hideNotificationsBestEffort)
  }

  private static func boolValue(forKey key: String, defaultValue: Bool, defaults: UserDefaults) -> Bool {
    guard defaults.object(forKey: key) != nil else {
      return defaultValue
    }
    return defaults.bool(forKey: key)
  }
}
