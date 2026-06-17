import AppKit
import Carbon
import Combine
import Foundation

/// Single source of truth for user preferences that affect capture, editing, export, and store UX.
@MainActor
final class AppSettings: ObservableObject {
  static let systemFontFamilyName = "System"

  @Published var captureKeyCode: UInt32
  @Published var captureUseCommand: Bool
  @Published var captureUseShift: Bool
  @Published var captureUseOption: Bool
  @Published var captureUseControl: Bool
  @Published var captureShowHelper: Bool
  @Published var captureSmartWindowSelectionEnabled: Bool
  @Published var defaultCaptureType: CaptureContentType
  @Published var screenshotWindowCaptureStyle: ScreenshotWindowCaptureStyle
  @Published var appLanguage: AppLanguage

  @Published var toolOrder: [AnnotationTool]
  @Published var hiddenTools: Set<AnnotationTool>
  @Published var recordingToolOrder: [RecordingTool]
  @Published var hiddenRecordingTools: Set<RecordingTool>

  @Published var textFontSize: Double
  @Published var textFontName: String
  @Published var drawingStrokeWidth: Double

  @Published var defaultSaveDirectoryPath: String
  @Published var alwaysSaveToDefaultDirectory: Bool
  @Published var saveCopiedScreenshotsToDefaultDirectory: Bool
  @Published var videoSaveDirectoryPath: String
  @Published var videoSaveSkipsDialog: Bool
  @Published var saveCopiedVideosToDefaultDirectory: Bool

  @Published var captureTransitionStyle: CaptureTransitionStyle
  @Published var captureTransitionSpeed: Double
  @Published var captureTransitionIntensity: Double
  @Published var toolbarAccentRed: Double
  @Published var toolbarAccentGreen: Double
  @Published var toolbarAccentBlue: Double
  @Published var toolbarAccentAlpha: Double
  @Published var screenshotMainAction: ScreenshotMainAction

  @Published var recordingEncoder: RecordingEncoder
  @Published var recordingFrameRate: RecordingFrameRate
  @Published var recordingCountdown: RecordingCountdown
  @Published var recordingColorProfile: RecordingColorProfile
  @Published var recordingCaptureResolution: RecordingCaptureResolution
  @Published var recordingCaptureBuffering: RecordingCaptureBuffering
  @Published var recordingShowsPointer: Bool
  @Published var recordingShowsSystemClickRings: Bool
  @Published var recordingWindowCaptureStyle: RecordingWindowCaptureStyle
  @Published var recordingIncludesAppAudio: Bool
  @Published var exportCodec: PostRecordingExportCodec
  @Published var exportFrameRate: PostRecordingExportFrameRate
  @Published var exportQuality: PostRecordingExportQuality
  @Published var exportScale: PostRecordingExportScale
  @Published var exportBitrate: PostRecordingExportBitratePreset
  @Published var recordSystemAudio: Bool
  @Published var recordMicrophone: Bool
  @Published var microphoneDeviceID: String
  @Published var showWebcam: Bool
  @Published var webcamDeviceID: String
  @Published var webcamOverlayShape: WebcamShape
  @Published var webcamOverlayAspectRatio: WebcamAspectRatio
  @Published var webcamOverlayNormalizedX: Double
  @Published var webcamOverlayNormalizedY: Double
  @Published var webcamOverlayNormalizedWidth: Double
  @Published var webcamOverlayNormalizedHeight: Double
  @Published var highlightMouseClicks: Bool
  @Published var mouseClickHighlightStyle: MouseClickHighlightStyle
  @Published var highlightKeystrokes: Bool
  @Published var keystrokeOverlayStyle: KeystrokeStyle
  @Published var keystrokeOverlaySize: KeystrokeSize
  @Published var keystrokeOverlayNormalizedX: Double
  @Published var keystrokeOverlayNormalizedY: Double
  @Published var keystrokeOverlayNormalizedWidth: Double
  @Published var keystrokeOverlayNormalizedHeight: Double
  @Published var hideNotificationsBestEffort: Bool

  let settingsChangeSubject = PassthroughSubject<AppSettingsChange, Never>()
  let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults

    captureKeyCode = UInt32(Definitions.captureKeyCode.read(from: defaults))
    captureUseCommand = Definitions.captureUseCommand.read(from: defaults)
    captureUseShift = Definitions.captureUseShift.read(from: defaults)
    captureUseOption = Definitions.captureUseOption.read(from: defaults)
    captureUseControl = Definitions.captureUseControl.read(from: defaults)
    captureShowHelper = Definitions.captureShowHelper.read(from: defaults)
    captureSmartWindowSelectionEnabled = Definitions.captureSmartWindowSelectionEnabled.read(from: defaults)
    screenshotWindowCaptureStyle = ScreenshotWindowCaptureStyle(
      rawValue: Definitions.screenshotWindowCaptureStyle.read(from: defaults)
    ) ?? Defaults.screenshotWindowCaptureStyle
    appLanguage = AppLanguage(rawValue: Definitions.appLanguage.read(from: defaults)) ?? .system

    let normalizedToolOrder = Self.normalizeToolOrder(rawValues: defaults.array(forKey: Keys.toolOrder) as? [Int])
    toolOrder = normalizedToolOrder
    hiddenTools = Self.normalizeHiddenTools(
      rawValues: defaults.array(forKey: Keys.hiddenTools) as? [Int],
      orderedTools: normalizedToolOrder
    )
    let normalizedRecordingToolOrder = Self.normalizeRecordingToolOrder(rawValues: defaults.array(forKey: Keys.recordingToolOrder) as? [Int])
    recordingToolOrder = normalizedRecordingToolOrder
    hiddenRecordingTools = Self.normalizeHiddenRecordingTools(
      rawValues: defaults.array(forKey: Keys.hiddenRecordingTools) as? [Int],
      orderedTools: normalizedRecordingToolOrder
    )

    textFontSize = Self.clampedTextFontSize(Definitions.textFontSize.read(from: defaults))
    textFontName = Self.normalizedTextFontName(Definitions.textFontName.read(from: defaults))
    drawingStrokeWidth = Self.clampedDrawingStrokeWidth(Definitions.drawingStrokeWidth.read(from: defaults))

    defaultSaveDirectoryPath = Definitions.defaultSaveDirectoryPath.read(from: defaults)
    alwaysSaveToDefaultDirectory = Definitions.alwaysSaveToDefaultDirectory.read(from: defaults)
    saveCopiedScreenshotsToDefaultDirectory = Definitions.saveCopiedScreenshotsToDefaultDirectory.read(from: defaults)
    videoSaveDirectoryPath = Definitions.videoSaveDirectoryPath.read(from: defaults)
    videoSaveSkipsDialog = Definitions.videoSaveSkipsDialog.read(from: defaults)
    saveCopiedVideosToDefaultDirectory = Definitions.saveCopiedVideosToDefaultDirectory.read(from: defaults)

    captureTransitionStyle = CaptureTransitionStyle(
      rawValue: Definitions.captureTransitionStyle.read(from: defaults)
    ) ?? Defaults.transitionStyle
    captureTransitionSpeed = Self.clampedCaptureTransitionSpeed(Definitions.captureTransitionSpeed.read(from: defaults))
    captureTransitionIntensity = Self.clampedCaptureTransitionIntensity(Definitions.captureTransitionIntensity.read(from: defaults))

    let systemAccent = Self.normalizedAccentComponents(from: NSColor.controlAccentColor)
    toolbarAccentRed = Self.clampedUnit(
      defaults.object(forKey: Definitions.toolbarAccentRed.key) as? Double ?? systemAccent.red
    )
    toolbarAccentGreen = Self.clampedUnit(
      defaults.object(forKey: Definitions.toolbarAccentGreen.key) as? Double ?? systemAccent.green
    )
    toolbarAccentBlue = Self.clampedUnit(
      defaults.object(forKey: Definitions.toolbarAccentBlue.key) as? Double ?? systemAccent.blue
    )
    toolbarAccentAlpha = Self.clampedUnit(
      defaults.object(forKey: Definitions.toolbarAccentAlpha.key) as? Double ?? systemAccent.alpha
    )

    screenshotMainAction = ScreenshotMainAction(
      rawValue: Definitions.screenshotMainAction.read(from: defaults)
    ) ?? Defaults.screenshotMainAction

    let videoSettings = VideoSettingsSnapshot.load(from: defaults)
    defaultCaptureType = videoSettings.defaultCaptureType
    recordingEncoder = videoSettings.recordingEncoder
    recordingFrameRate = videoSettings.recordingFrameRate
    recordingCountdown = videoSettings.recordingCountdown
    recordingColorProfile = videoSettings.recordingColorProfile
    recordingCaptureResolution = videoSettings.recordingCaptureResolution
    recordingCaptureBuffering = videoSettings.recordingCaptureBuffering
    recordingShowsPointer = videoSettings.recordingShowsPointer
    recordingShowsSystemClickRings = videoSettings.recordingShowsSystemClickRings
    recordingWindowCaptureStyle = videoSettings.recordingWindowCaptureStyle
    recordingIncludesAppAudio = videoSettings.recordingIncludesAppAudio
    exportCodec = videoSettings.exportCodec
    exportFrameRate = videoSettings.exportFrameRate
    exportQuality = videoSettings.exportQuality
    exportScale = videoSettings.exportScale
    exportBitrate = videoSettings.exportBitrate
    recordSystemAudio = videoSettings.recordSystemAudio
    recordMicrophone = videoSettings.recordMicrophone
    microphoneDeviceID = videoSettings.microphoneDeviceID
    showWebcam = videoSettings.showWebcam
    webcamDeviceID = videoSettings.webcamDeviceID
    webcamOverlayShape = videoSettings.webcamOverlayShape
    webcamOverlayAspectRatio = videoSettings.webcamOverlayAspectRatio
    webcamOverlayNormalizedX = videoSettings.webcamOverlayFrame.minX
    webcamOverlayNormalizedY = videoSettings.webcamOverlayFrame.minY
    webcamOverlayNormalizedWidth = videoSettings.webcamOverlayFrame.width
    webcamOverlayNormalizedHeight = videoSettings.webcamOverlayFrame.height
    highlightMouseClicks = videoSettings.highlightMouseClicks
    mouseClickHighlightStyle = videoSettings.mouseClickHighlightStyle
    highlightKeystrokes = videoSettings.highlightKeystrokes
    keystrokeOverlayStyle = videoSettings.keystrokeOverlayStyle
    keystrokeOverlaySize = videoSettings.keystrokeOverlaySize
    keystrokeOverlayNormalizedX = videoSettings.keystrokeOverlayFrame.minX
    keystrokeOverlayNormalizedY = videoSettings.keystrokeOverlayFrame.minY
    keystrokeOverlayNormalizedWidth = videoSettings.keystrokeOverlayFrame.width
    keystrokeOverlayNormalizedHeight = videoSettings.keystrokeOverlayFrame.height
    hideNotificationsBestEffort = videoSettings.hideNotificationsBestEffort

  }
  static func reordered<T>(_ values: [T], moving source: IndexSet, to destination: Int) -> [T]? {
    guard !source.isEmpty else {
      return nil
    }

    var updated = values
    let moving = source.sorted().map { updated[$0] }
    for index in source.sorted(by: >) {
      updated.remove(at: index)
    }

    let beforeDestinationCount = source.filter { $0 < destination }.count
    let adjustedDestination = max(0, min(updated.count, destination - beforeDestinationCount))
    updated.insert(contentsOf: moving, at: adjustedDestination)
    return updated
  }

}
