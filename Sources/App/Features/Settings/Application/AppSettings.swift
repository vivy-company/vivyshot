import AppKit
import Carbon
import Foundation

extension Notification.Name {
  static let vivyShotSettingsDidChange = Notification.Name("com.vivyshot.settingsDidChange")
}

/// Animated transition used after a screenshot selection is confirmed.
enum CaptureTransitionStyle: Int, CaseIterable, Identifiable {
  case none = 0
  case fade = 1
  case ripple = 2
  case liquidDrop = 3
  case zoomBlur = 4
  case waterWave = 5

  var id: Int { rawValue }

  var title: String {
    switch self {
    case .none:
      return String(localized: "None", bundle: AppLocalizer.shared.bundle)
    case .fade:
      return String(localized: "Fade", bundle: AppLocalizer.shared.bundle)
    case .ripple:
      return String(localized: "Wave Drop", bundle: AppLocalizer.shared.bundle)
    case .liquidDrop:
      return String(localized: "Liquid Drop", bundle: AppLocalizer.shared.bundle)
    case .zoomBlur:
      return String(localized: "Zoom Blur", bundle: AppLocalizer.shared.bundle)
    case .waterWave:
      return String(localized: "Water Wave", bundle: AppLocalizer.shared.bundle)
    }
  }
}

/// Single source of truth for user preferences that affect capture, editing, export, and store UX.
@MainActor
final class AppSettings: ObservableObject {
  static let shared = AppSettings()

  static let systemFontFamilyName = "System"

  @Published private(set) var captureKeyCode: UInt32
  @Published private(set) var captureUseCommand: Bool
  @Published private(set) var captureUseShift: Bool
  @Published private(set) var captureUseOption: Bool
  @Published private(set) var captureUseControl: Bool
  @Published private(set) var captureShowHelper: Bool
  @Published private(set) var captureSmartWindowSelectionEnabled: Bool
  @Published private(set) var hasSeenWelcome: Bool
  @Published private(set) var defaultCaptureType: CaptureContentType
  @Published private(set) var appLanguage: AppLanguage

  @Published private(set) var toolOrder: [AnnotationTool]
  @Published private(set) var hiddenTools: Set<AnnotationTool>
  @Published private(set) var recordingToolOrder: [RecordingTool]
  @Published private(set) var hiddenRecordingTools: Set<RecordingTool>

  @Published private(set) var textFontSize: Double
  @Published private(set) var textFontName: String

  @Published private(set) var defaultSaveDirectoryPath: String
  @Published private(set) var alwaysSaveToDefaultDirectory: Bool
  @Published private(set) var saveCopiedScreenshotsToDefaultDirectory: Bool

  @Published private(set) var captureTransitionStyle: CaptureTransitionStyle
  @Published private(set) var captureTransitionSpeed: Double
  @Published private(set) var captureTransitionIntensity: Double
  @Published private(set) var toolbarAccentRed: Double
  @Published private(set) var toolbarAccentGreen: Double
  @Published private(set) var toolbarAccentBlue: Double
  @Published private(set) var toolbarAccentAlpha: Double
  @Published private(set) var screenshotMainAction: ScreenshotMainAction

  @Published private(set) var recordingEncoder: RecordingEncoder
  @Published private(set) var recordingFrameRate: RecordingFrameRate
  @Published private(set) var recordingCountdown: RecordingCountdown
  @Published private(set) var exportCodec: PostRecordingExportCodec
  @Published private(set) var exportFrameRate: PostRecordingExportFrameRate
  @Published private(set) var exportQuality: PostRecordingExportQuality
  @Published private(set) var exportScale: PostRecordingExportScale
  @Published private(set) var exportBitrate: PostRecordingExportBitratePreset
  @Published private(set) var recordSystemAudio: Bool
  @Published private(set) var recordMicrophone: Bool
  @Published private(set) var microphoneDeviceID: String
  @Published private(set) var showWebcam: Bool
  @Published private(set) var webcamDeviceID: String
  @Published private(set) var webcamOverlaySize: WebcamOverlaySize
  @Published private(set) var webcamOverlayShape: WebcamShape
  @Published private(set) var webcamOverlayAspectRatio: WebcamAspectRatio
  @Published private(set) var webcamOverlayNormalizedX: Double
  @Published private(set) var webcamOverlayNormalizedY: Double
  @Published private(set) var webcamOverlayNormalizedWidth: Double
  @Published private(set) var webcamOverlayNormalizedHeight: Double
  @Published private(set) var highlightMouseClicks: Bool
  @Published private(set) var mouseClickHighlightStyle: MouseClickHighlightStyle
  @Published private(set) var highlightKeystrokes: Bool
  @Published private(set) var keystrokeOverlayStyle: KeystrokeStyle
  @Published private(set) var keystrokeOverlaySize: KeystrokeSize
  @Published private(set) var keystrokeOverlayNormalizedX: Double
  @Published private(set) var keystrokeOverlayNormalizedY: Double
  @Published private(set) var keystrokeOverlayNormalizedWidth: Double
  @Published private(set) var keystrokeOverlayNormalizedHeight: Double
  @Published private(set) var hideNotificationsBestEffort: Bool
  @Published private(set) var proExportTrialConsumedAt: Date?

  var toolbarAccentColor: NSColor {
    NSColor(
      calibratedRed: CGFloat(Self.clampedUnit(toolbarAccentRed)),
      green: CGFloat(Self.clampedUnit(toolbarAccentGreen)),
      blue: CGFloat(Self.clampedUnit(toolbarAccentBlue)),
      alpha: CGFloat(Self.clampedUnit(toolbarAccentAlpha))
    )
  }

  var defaultSaveDirectoryURL: URL? {
    guard !defaultSaveDirectoryPath.isEmpty else {
      return nil
    }
    let url = URL(fileURLWithPath: defaultSaveDirectoryPath, isDirectory: true)
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
      return nil
    }
    return url
  }

  var effectiveMouseClickHighlightStyle: MouseClickHighlightStyle? {
    highlightMouseClicks ? mouseClickHighlightStyle : nil
  }

  var captureModifierFlags: UInt32 {
    var flags: UInt32 = 0
    if captureUseCommand { flags |= UInt32(cmdKey) }
    if captureUseShift { flags |= UInt32(shiftKey) }
    if captureUseOption { flags |= UInt32(optionKey) }
    if captureUseControl { flags |= UInt32(controlKey) }
    return flags
  }

  var captureShortcutDisplay: String {
    Self.shortcutDisplay(
      keyCode: captureKeyCode,
      command: captureUseCommand,
      shift: captureUseShift,
      option: captureUseOption,
      control: captureUseControl
    )
  }

  static var webcamOverlaySizeRange: ClosedRange<Double> {
    Limits.webcamWidth
  }

  static var keystrokeOverlaySizeRange: ClosedRange<Double> {
    Limits.keystrokeWidth
  }

  var visibleTools: [AnnotationTool] {
    let visible = toolOrder.filter { !hiddenTools.contains($0) }
    return visible.isEmpty ? [.move] : visible
  }

  var visibleRecordingTools: [RecordingTool] {
    recordingToolOrder.filter { !hiddenRecordingTools.contains($0) }
  }

  var webcamOverlayNormalizedFrame: CGRect {
    CGRect(
      x: webcamOverlayNormalizedX,
      y: webcamOverlayNormalizedY,
      width: webcamOverlayNormalizedWidth,
      height: webcamOverlayNormalizedHeight
    )
  }

  var keystrokeOverlayNormalizedFrame: CGRect {
    CGRect(
      x: keystrokeOverlayNormalizedX,
      y: keystrokeOverlayNormalizedY,
      width: keystrokeOverlayNormalizedWidth,
      height: keystrokeOverlayNormalizedHeight
    )
  }

  private let defaults: UserDefaults

  /// Stable UserDefaults keys. These strings are persisted app data, so rename only with a deliberate migration plan.
  private enum Keys {
    static let captureKeyCode = "settings.capture.keyCode"
    static let captureUseCommand = "settings.capture.useCommand"
    static let captureUseShift = "settings.capture.useShift"
    static let captureUseOption = "settings.capture.useOption"
    static let captureUseControl = "settings.capture.useControl"
    static let captureShowHelper = "settings.capture.showHelper"
    static let captureSmartWindowSelectionEnabled = "settings.capture.smartWindowSelectionEnabled"
    static let hasSeenWelcome = "settings.welcome.hasSeenWelcome"
    static let defaultCaptureType = "settings.capture.defaultType"
    static let appLanguage = "settings.app.language"

    static let toolOrder = "settings.toolbar.toolOrder"
    static let hiddenTools = "settings.toolbar.hiddenTools"
    static let recordingToolOrder = "settings.video.toolbar.toolOrder"
    static let hiddenRecordingTools = "settings.video.toolbar.hiddenTools"

    static let textFontSize = "settings.text.fontSize"
    static let textFontName = "settings.text.fontName"

    static let defaultSaveDirectoryPath = "settings.save.defaultDirectoryPath"
    static let alwaysSaveToDefaultDirectory = "settings.save.alwaysSaveToDefaultDirectory"
    static let saveCopiedScreenshotsToDefaultDirectory = "settings.save.saveCopiedScreenshotsToDefaultDirectory"

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
    static let webcamOverlaySize = "settings.video.webcam.overlaySize"
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
    static let proExportTrialConsumedAt = "settings.proExportTrial.consumedAt"
  }

  /// Built-in preference values used when the user has not persisted a value yet.
  private enum Defaults {
    static let captureKeyCode = Int(kVK_ANSI_C)
    static let captureUseCommand = true
    static let captureUseShift = true
    static let captureShowHelper = true
    static let smartWindowSelection = true
    static let textFontSize = 16.0
    static let transitionStyle = CaptureTransitionStyle.ripple
    static let transitionSpeed = 1.25
    static let transitionIntensity = 0.72
    static let screenshotMainAction = ScreenshotMainAction.copy
    static let recordingEncoder = RecordingEncoder.standardH264
    static let recordingFrameRate = RecordingFrameRate.fps30
    static let recordingCountdown = RecordingCountdown.off
    static let exportCodec = PostRecordingExportCodec.h264
    static let exportFrameRate = PostRecordingExportFrameRate.fps30
    static let exportQuality = PostRecordingExportQuality.standard
    static let exportScale = PostRecordingExportScale.full
    static let exportBitrate = PostRecordingExportBitratePreset.standard
    static let recordSystemAudio = true
    static let webcamSize = WebcamOverlaySize.medium
    static let webcamShape = WebcamShape.roundedRect
    static let webcamAspectRatio = WebcamAspectRatio.square
    static let highlightMouseClicks = true
    static let mouseClickHighlightStyle = MouseClickHighlightStyle.system
    static let keystrokeStyle = KeystrokeStyle.glass
    static let keystrokeSize = KeystrokeSize.medium
    static let hideNotifications = true
  }

  /// Numeric guardrails for persisted settings and draggable overlay frames.
  private enum Limits {
    static let normalized = 0.0...1.0
    static let textFontSize = 10.0...72.0
    static let transitionSpeed = 0.5...2.4
    static let transitionIntensity = 0.2...1.0
    static let minimumOverlayDimension = 0.04
    static let webcamWidth = 0.12...0.50
    static let webcamHeight = 0.04...0.90
    static let keystrokeWidth = 0.20...0.72
    static let keystrokeHeight = 0.07...0.28
  }

  private init(defaults: UserDefaults = .standard) {
    self.defaults = defaults

    let storedKeyCode = defaults.object(forKey: Keys.captureKeyCode) as? Int
    captureKeyCode = UInt32(storedKeyCode ?? Defaults.captureKeyCode)

    if defaults.object(forKey: Keys.captureUseCommand) == nil {
      captureUseCommand = Defaults.captureUseCommand
    } else {
      captureUseCommand = defaults.bool(forKey: Keys.captureUseCommand)
    }

    if defaults.object(forKey: Keys.captureUseShift) == nil {
      captureUseShift = Defaults.captureUseShift
    } else {
      captureUseShift = defaults.bool(forKey: Keys.captureUseShift)
    }

    captureUseOption = defaults.bool(forKey: Keys.captureUseOption)
    captureUseControl = defaults.bool(forKey: Keys.captureUseControl)
    if defaults.object(forKey: Keys.captureShowHelper) == nil {
      captureShowHelper = Defaults.captureShowHelper
    } else {
      captureShowHelper = defaults.bool(forKey: Keys.captureShowHelper)
    }
    if defaults.object(forKey: Keys.captureSmartWindowSelectionEnabled) == nil {
      captureSmartWindowSelectionEnabled = Defaults.smartWindowSelection
    } else {
      captureSmartWindowSelectionEnabled = defaults.bool(forKey: Keys.captureSmartWindowSelectionEnabled)
    }

    hasSeenWelcome = defaults.bool(forKey: Keys.hasSeenWelcome)

    let storedDefaultCaptureType = defaults.object(forKey: Keys.defaultCaptureType) as? Int
    defaultCaptureType = CaptureContentType(rawValue: storedDefaultCaptureType ?? CaptureContentType.screenshot.rawValue) ?? .screenshot
    let storedAppLanguage = defaults.string(forKey: Keys.appLanguage)
    appLanguage = AppLanguage(rawValue: storedAppLanguage ?? AppLanguage.system.rawValue) ?? .system

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

    let storedTextSize = defaults.object(forKey: Keys.textFontSize) as? Double
    textFontSize = Self.clampedTextFontSize(storedTextSize ?? Defaults.textFontSize)

    let storedFontName = defaults.string(forKey: Keys.textFontName)
    textFontName = Self.normalizedTextFontName(storedFontName)

    defaultSaveDirectoryPath = defaults.string(forKey: Keys.defaultSaveDirectoryPath) ?? ""
    alwaysSaveToDefaultDirectory = defaults.bool(forKey: Keys.alwaysSaveToDefaultDirectory)
    saveCopiedScreenshotsToDefaultDirectory = defaults.bool(forKey: Keys.saveCopiedScreenshotsToDefaultDirectory)

    let storedTransitionStyle = defaults.object(forKey: Keys.captureTransitionStyle) as? Int
    captureTransitionStyle = CaptureTransitionStyle(rawValue: storedTransitionStyle ?? Defaults.transitionStyle.rawValue) ?? Defaults.transitionStyle

    let storedTransitionSpeed = defaults.object(forKey: Keys.captureTransitionSpeed) as? Double
    captureTransitionSpeed = Self.clampedCaptureTransitionSpeed(storedTransitionSpeed ?? Defaults.transitionSpeed)

    let storedTransitionIntensity = defaults.object(forKey: Keys.captureTransitionIntensity) as? Double
    captureTransitionIntensity = Self.clampedCaptureTransitionIntensity(storedTransitionIntensity ?? Defaults.transitionIntensity)

    let systemAccent = Self.normalizedAccentComponents(from: NSColor.controlAccentColor)
    let storedAccentRed = defaults.object(forKey: Keys.toolbarAccentRed) as? Double
    let storedAccentGreen = defaults.object(forKey: Keys.toolbarAccentGreen) as? Double
    let storedAccentBlue = defaults.object(forKey: Keys.toolbarAccentBlue) as? Double
    let storedAccentAlpha = defaults.object(forKey: Keys.toolbarAccentAlpha) as? Double
    toolbarAccentRed = Self.clampedUnit(storedAccentRed ?? systemAccent.red)
    toolbarAccentGreen = Self.clampedUnit(storedAccentGreen ?? systemAccent.green)
    toolbarAccentBlue = Self.clampedUnit(storedAccentBlue ?? systemAccent.blue)
    toolbarAccentAlpha = Self.clampedUnit(storedAccentAlpha ?? systemAccent.alpha)

    let storedScreenshotMainAction = defaults.object(forKey: Keys.screenshotMainAction) as? Int
    screenshotMainAction = ScreenshotMainAction(
      rawValue: storedScreenshotMainAction ?? Defaults.screenshotMainAction.rawValue
    ) ?? Defaults.screenshotMainAction

    let storedRecordingEncoder = defaults.object(forKey: Keys.recordingEncoder) as? Int
    recordingEncoder = RecordingEncoder(
      rawValue: storedRecordingEncoder ?? Defaults.recordingEncoder.rawValue
    ) ?? Defaults.recordingEncoder

    let storedRecordingFrameRate = defaults.object(forKey: Keys.recordingFrameRate) as? Int
    recordingFrameRate = RecordingFrameRate(rawValue: storedRecordingFrameRate ?? Defaults.recordingFrameRate.rawValue) ?? Defaults.recordingFrameRate

    let storedRecordingCountdown = defaults.object(forKey: Keys.recordingCountdown) as? Int
    recordingCountdown = RecordingCountdown(rawValue: storedRecordingCountdown ?? Defaults.recordingCountdown.rawValue) ?? Defaults.recordingCountdown

    let storedExportCodec = defaults.string(forKey: Keys.exportCodec)
    exportCodec = PostRecordingExportCodec(rawValue: storedExportCodec ?? Defaults.exportCodec.rawValue) ?? Defaults.exportCodec

    let storedExportFrameRate = defaults.object(forKey: Keys.exportFrameRate) as? Int
    exportFrameRate = PostRecordingExportFrameRate(rawValue: storedExportFrameRate ?? Defaults.exportFrameRate.rawValue) ?? Defaults.exportFrameRate

    let storedExportQuality = defaults.string(forKey: Keys.exportQuality)
    exportQuality = PostRecordingExportQuality(rawValue: storedExportQuality ?? Defaults.exportQuality.rawValue) ?? Defaults.exportQuality

    let storedExportScale = defaults.string(forKey: Keys.exportScale)
    exportScale = PostRecordingExportScale(rawValue: storedExportScale ?? Defaults.exportScale.rawValue) ?? Defaults.exportScale

    let storedExportBitrate = defaults.string(forKey: Keys.exportBitrate)
    exportBitrate = PostRecordingExportBitratePreset(rawValue: storedExportBitrate ?? Defaults.exportBitrate.rawValue) ?? Defaults.exportBitrate

    if defaults.object(forKey: Keys.recordSystemAudio) == nil {
      recordSystemAudio = Defaults.recordSystemAudio
    } else {
      recordSystemAudio = defaults.bool(forKey: Keys.recordSystemAudio)
    }

    recordMicrophone = defaults.bool(forKey: Keys.recordMicrophone)
    microphoneDeviceID = defaults.string(forKey: Keys.microphoneDeviceID) ?? ""
    showWebcam = defaults.bool(forKey: Keys.showWebcam)
    webcamDeviceID = defaults.string(forKey: Keys.webcamDeviceID) ?? ""

    let storedWebcamSize = defaults.object(forKey: Keys.webcamOverlaySize) as? Int
    webcamOverlaySize = WebcamOverlaySize(rawValue: storedWebcamSize ?? Defaults.webcamSize.rawValue) ?? Defaults.webcamSize

    let storedWebcamShape = defaults.object(forKey: Keys.webcamOverlayShape) as? Int
    let initialWebcamShape = WebcamShape(
      rawValue: storedWebcamShape ?? Defaults.webcamShape.rawValue
    ) ?? Defaults.webcamShape
    webcamOverlayShape = initialWebcamShape

    let storedWebcamAspectRatio = defaults.object(forKey: Keys.webcamOverlayAspectRatio) as? Int
    let storedAspectRatio = WebcamAspectRatio(
      rawValue: storedWebcamAspectRatio ?? Defaults.webcamAspectRatio.rawValue
    ) ?? Defaults.webcamAspectRatio
    webcamOverlayAspectRatio = initialWebcamShape == .circle ? .square : storedAspectRatio

    let defaultWebcamFrame = Self.defaultWebcamOverlayFrame
    webcamOverlayNormalizedX = Self.clampedNormalizedOrigin(defaults.object(forKey: Keys.webcamOverlayNormalizedX) as? Double ?? defaultWebcamFrame.minX)
    webcamOverlayNormalizedY = Self.clampedNormalizedOrigin(defaults.object(forKey: Keys.webcamOverlayNormalizedY) as? Double ?? defaultWebcamFrame.minY)
    webcamOverlayNormalizedWidth = Self.clampedNormalizedDimension(defaults.object(forKey: Keys.webcamOverlayNormalizedWidth) as? Double ?? defaultWebcamFrame.width)
    webcamOverlayNormalizedHeight = Self.clampedNormalizedDimension(defaults.object(forKey: Keys.webcamOverlayNormalizedHeight) as? Double ?? defaultWebcamFrame.height)

    let storedHighlightMouseClicks: Bool
    if defaults.object(forKey: Keys.highlightMouseClicks) == nil {
      storedHighlightMouseClicks = Defaults.highlightMouseClicks
    } else {
      storedHighlightMouseClicks = defaults.bool(forKey: Keys.highlightMouseClicks)
    }
    let storedMouseClickStyle = defaults.object(forKey: Keys.mouseClickHighlightStyle) as? Int
    let resolvedMouseClickStyle = storedMouseClickStyle
      .flatMap(MouseClickHighlightStyle.init(rawValue:))
      ?? Defaults.mouseClickHighlightStyle
    highlightMouseClicks = storedHighlightMouseClicks
    mouseClickHighlightStyle = resolvedMouseClickStyle

    highlightKeystrokes = defaults.bool(forKey: Keys.highlightKeystrokes)

    let storedKeystrokeStyle = defaults.object(forKey: Keys.keystrokeOverlayStyle) as? Int
    keystrokeOverlayStyle = KeystrokeStyle(rawValue: storedKeystrokeStyle ?? Defaults.keystrokeStyle.rawValue) ?? Defaults.keystrokeStyle

    let storedKeystrokeSize = defaults.object(forKey: Keys.keystrokeOverlaySize) as? Int
    keystrokeOverlaySize = KeystrokeSize(rawValue: storedKeystrokeSize ?? Defaults.keystrokeSize.rawValue) ?? Defaults.keystrokeSize

    let defaultKeystrokeFrame = Self.defaultKeystrokeOverlayFrame
    keystrokeOverlayNormalizedX = Self.clampedNormalizedOrigin(defaults.object(forKey: Keys.keystrokeOverlayNormalizedX) as? Double ?? defaultKeystrokeFrame.minX)
    keystrokeOverlayNormalizedY = Self.clampedNormalizedOrigin(defaults.object(forKey: Keys.keystrokeOverlayNormalizedY) as? Double ?? defaultKeystrokeFrame.minY)
    keystrokeOverlayNormalizedWidth = Self.clampedNormalizedDimension(defaults.object(forKey: Keys.keystrokeOverlayNormalizedWidth) as? Double ?? defaultKeystrokeFrame.width)
    keystrokeOverlayNormalizedHeight = Self.clampedNormalizedDimension(defaults.object(forKey: Keys.keystrokeOverlayNormalizedHeight) as? Double ?? defaultKeystrokeFrame.height)

    if defaults.object(forKey: Keys.hideNotificationsBestEffort) == nil {
      hideNotificationsBestEffort = Defaults.hideNotifications
    } else {
      hideNotificationsBestEffort = defaults.bool(forKey: Keys.hideNotificationsBestEffort)
    }

    proExportTrialConsumedAt = defaults.object(forKey: Keys.proExportTrialConsumedAt) as? Date

    AppLocalizer.shared.update(language: appLanguage)
    persistAll(notify: false)
  }

  func shortcutKeyLabel(for keyCode: UInt32) -> String {
    Self.shortcutKeyLabel(for: keyCode)
  }

  func setCaptureShortcut(
    keyCode: UInt32,
    command: Bool,
    shift: Bool,
    option: Bool,
    control: Bool
  ) {
    let changed = captureKeyCode != keyCode
      || captureUseCommand != command
      || captureUseShift != shift
      || captureUseOption != option
      || captureUseControl != control

    guard changed else {
      return
    }

    captureKeyCode = keyCode
    captureUseCommand = command
    captureUseShift = shift
    captureUseOption = option
    captureUseControl = control
    persistCaptureShortcut()
  }

  func setCaptureShortcut(keyCode: UInt32, modifierFlags: NSEvent.ModifierFlags) {
    let flags = modifierFlags.intersection(.deviceIndependentFlagsMask)
    setCaptureShortcut(
      keyCode: keyCode,
      command: flags.contains(.command),
      shift: flags.contains(.shift),
      option: flags.contains(.option),
      control: flags.contains(.control)
    )
  }

  func setCaptureKeyCode(_ keyCode: UInt32) {
    setCaptureShortcut(
      keyCode: keyCode,
      command: captureUseCommand,
      shift: captureUseShift,
      option: captureUseOption,
      control: captureUseControl
    )
  }

  func setCaptureModifierCommand(_ enabled: Bool) {
    setCaptureShortcut(
      keyCode: captureKeyCode,
      command: enabled,
      shift: captureUseShift,
      option: captureUseOption,
      control: captureUseControl
    )
  }

  func setCaptureModifierShift(_ enabled: Bool) {
    setCaptureShortcut(
      keyCode: captureKeyCode,
      command: captureUseCommand,
      shift: enabled,
      option: captureUseOption,
      control: captureUseControl
    )
  }

  func setCaptureModifierOption(_ enabled: Bool) {
    setCaptureShortcut(
      keyCode: captureKeyCode,
      command: captureUseCommand,
      shift: captureUseShift,
      option: enabled,
      control: captureUseControl
    )
  }

  func setCaptureModifierControl(_ enabled: Bool) {
    setCaptureShortcut(
      keyCode: captureKeyCode,
      command: captureUseCommand,
      shift: captureUseShift,
      option: captureUseOption,
      control: enabled
    )
  }

  func resetCaptureShortcut() {
    setCaptureShortcut(
      keyCode: UInt32(kVK_ANSI_C),
      command: true,
      shift: true,
      option: false,
      control: false
    )
  }

  func setCaptureShowHelper(_ enabled: Bool) {
    guard captureShowHelper != enabled else {
      return
    }
    captureShowHelper = enabled
    persistCaptureHelperSetting()
  }

  func setCaptureSmartWindowSelectionEnabled(_ enabled: Bool) {
    guard captureSmartWindowSelectionEnabled != enabled else {
      return
    }
    captureSmartWindowSelectionEnabled = enabled
    persistCaptureSmartWindowSelectionSetting()
  }

  func markWelcomeSeen() {
    guard !hasSeenWelcome else {
      return
    }
    hasSeenWelcome = true
    persistWelcomeState()
  }

  func setDefaultCaptureType(_ type: CaptureContentType) {
    guard defaultCaptureType != type else {
      return
    }
    defaultCaptureType = type
    persistVideoCaptureSettings()
  }

  func setAppLanguage(_ language: AppLanguage) {
    guard appLanguage != language else {
      return
    }
    appLanguage = language
    AppLocalizer.shared.update(language: language)
    persistAppLanguage()
  }

  func setRecordingEncoder(_ encoder: RecordingEncoder) {
    guard recordingEncoder != encoder else {
      return
    }
    recordingEncoder = encoder
    persistVideoCaptureSettings()
  }

  func setRecordingFrameRate(_ frameRate: RecordingFrameRate) {
    guard recordingFrameRate != frameRate else {
      return
    }
    recordingFrameRate = frameRate
    persistVideoCaptureSettings()
  }

  func setRecordingCountdown(_ countdown: RecordingCountdown) {
    guard recordingCountdown != countdown else {
      return
    }
    recordingCountdown = countdown
    persistVideoCaptureSettings()
  }

  func setVideoExportCodec(_ codec: PostRecordingExportCodec) {
    guard exportCodec != codec else {
      return
    }
    exportCodec = codec
    persistVideoCaptureSettings()
  }

  func setVideoExportFrameRate(_ frameRate: PostRecordingExportFrameRate) {
    guard exportFrameRate != frameRate else {
      return
    }
    exportFrameRate = frameRate
    persistVideoCaptureSettings()
  }

  func setVideoExportQuality(_ quality: PostRecordingExportQuality) {
    guard exportQuality != quality else {
      return
    }
    exportQuality = quality
    persistVideoCaptureSettings()
  }

  func setVideoExportScale(_ scale: PostRecordingExportScale) {
    guard exportScale != scale else {
      return
    }
    exportScale = scale
    persistVideoCaptureSettings()
  }

  func setVideoExportBitrate(_ bitrate: PostRecordingExportBitratePreset) {
    guard exportBitrate != bitrate else {
      return
    }
    exportBitrate = bitrate
    persistVideoCaptureSettings()
  }

  func setVideoRecordSystemAudio(_ enabled: Bool) {
    guard recordSystemAudio != enabled else {
      return
    }
    recordSystemAudio = enabled
    persistVideoCaptureSettings()
  }

  func setVideoRecordMicrophone(_ enabled: Bool) {
    guard recordMicrophone != enabled else {
      return
    }
    recordMicrophone = enabled
    persistVideoCaptureSettings()
  }

  func setVideoMicrophoneDeviceID(_ deviceID: String) {
    let normalized = deviceID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard microphoneDeviceID != normalized else {
      return
    }
    microphoneDeviceID = normalized
    persistVideoCaptureSettings()
  }

  func setVideoShowWebcam(_ enabled: Bool) {
    guard showWebcam != enabled else {
      return
    }
    showWebcam = enabled
    persistVideoCaptureSettings()
  }

  func setVideoWebcamDeviceID(_ deviceID: String) {
    let normalized = deviceID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard webcamDeviceID != normalized else {
      return
    }
    webcamDeviceID = normalized
    persistVideoCaptureSettings()
  }

  func setWebcamOverlaySize(_ size: WebcamOverlaySize) {
    guard webcamOverlaySize != size else {
      return
    }
    webcamOverlaySize = size
    let current = webcamOverlayNormalizedFrame
    let dimension = size.widthFraction
    let resized = Self.resizedNormalizedOverlayFrame(
      current,
      width: dimension,
      height: dimension
    )
    webcamOverlayNormalizedX = resized.minX
    webcamOverlayNormalizedY = resized.minY
    webcamOverlayNormalizedWidth = resized.width
    webcamOverlayNormalizedHeight = resized.height
    persistVideoCaptureSettings()
  }

  func setWebcamOverlayShape(_ shape: WebcamShape) {
    guard webcamOverlayShape != shape else {
      return
    }
    webcamOverlayShape = shape
    if shape == .circle {
      webcamOverlayAspectRatio = .square
    }
    persistVideoCaptureSettings()
  }

  func setWebcamOverlayAspectRatio(_ aspectRatio: WebcamAspectRatio) {
    let normalized = webcamOverlayShape == .circle ? .square : aspectRatio
    guard webcamOverlayAspectRatio != normalized else {
      return
    }
    webcamOverlayAspectRatio = normalized
    persistVideoCaptureSettings()
  }

  func setWebcamOverlayFrame(_ frame: CGRect) {
    let source = Self.normalizedOverlayFrame(frame, fallback: Self.defaultWebcamOverlayFrame)
    let width = Self.clampedWebcamOverlayWidth(Double(source.width))
    let height = Self.clampedWebcamOverlayHeight(Double(source.height))
    let normalized = Self.resizedNormalizedOverlayFrame(
      source,
      width: CGFloat(width),
      height: CGFloat(height)
    )
    let changed = abs(webcamOverlayNormalizedX - normalized.minX) > .ulpOfOne
      || abs(webcamOverlayNormalizedY - normalized.minY) > .ulpOfOne
      || abs(webcamOverlayNormalizedWidth - normalized.width) > .ulpOfOne
      || abs(webcamOverlayNormalizedHeight - normalized.height) > .ulpOfOne
    guard changed else {
      return
    }
    webcamOverlayNormalizedX = normalized.minX
    webcamOverlayNormalizedY = normalized.minY
    webcamOverlayNormalizedWidth = normalized.width
    webcamOverlayNormalizedHeight = normalized.height
    persistVideoCaptureSettings()
  }

  func setWebcamOverlayWidth(_ width: Double) {
    let current = webcamOverlayNormalizedFrame
    let normalizedWidth = Self.clampedWebcamOverlayWidth(width)
    setWebcamOverlayFrame(
      CGRect(
        x: current.midX - normalizedWidth * 0.5,
        y: current.minY,
        width: normalizedWidth,
        height: current.height
      )
    )
  }

  func setWebcamOverlayHeight(_ height: Double) {
    let current = webcamOverlayNormalizedFrame
    let normalizedHeight = Self.clampedWebcamOverlayHeight(height)
    setWebcamOverlayFrame(
      CGRect(
        x: current.minX,
        y: current.midY - normalizedHeight * 0.5,
        width: current.width,
        height: normalizedHeight
      )
    )
  }

  func resetWebcamOverlayPlacement() {
    setWebcamOverlayFrame(Self.defaultWebcamOverlayFrame)
  }

  func setVideoHighlightMouseClicks(_ enabled: Bool) {
    guard highlightMouseClicks != enabled else {
      return
    }
    highlightMouseClicks = enabled
    persistVideoCaptureSettings()
  }

  func setMouseClickHighlightStyle(_ style: MouseClickHighlightStyle) {
    guard mouseClickHighlightStyle != style else {
      return
    }
    mouseClickHighlightStyle = style
    persistVideoCaptureSettings()
  }

  func setVideoHighlightKeystrokes(_ enabled: Bool) {
    guard highlightKeystrokes != enabled else {
      return
    }
    highlightKeystrokes = enabled
    persistVideoCaptureSettings()
  }

  func setKeystrokeOverlayStyle(_ style: KeystrokeStyle) {
    guard keystrokeOverlayStyle != style else {
      return
    }
    keystrokeOverlayStyle = style
    persistVideoCaptureSettings()
  }

  func setKeystrokeOverlaySize(_ size: KeystrokeSize) {
    guard keystrokeOverlaySize != size else {
      return
    }
    keystrokeOverlaySize = size
    let current = keystrokeOverlayNormalizedFrame
    let resized = Self.resizedNormalizedOverlayFrame(
      current,
      width: size.normalizedSize.width,
      height: size.normalizedSize.height
    )
    keystrokeOverlayNormalizedX = resized.minX
    keystrokeOverlayNormalizedY = resized.minY
    keystrokeOverlayNormalizedWidth = resized.width
    keystrokeOverlayNormalizedHeight = resized.height
    persistVideoCaptureSettings()
  }

  func setKeystrokeOverlayFrame(_ frame: CGRect) {
    let source = Self.normalizedOverlayFrame(frame, fallback: Self.defaultKeystrokeOverlayFrame)
    let normalized = Self.resizedNormalizedOverlayFrame(
      source,
      width: CGFloat(Self.clampedKeystrokeOverlayWidth(Double(source.width))),
      height: CGFloat(Self.clampedKeystrokeOverlayHeight(Double(source.height)))
    )
    let changed = abs(keystrokeOverlayNormalizedX - normalized.minX) > .ulpOfOne
      || abs(keystrokeOverlayNormalizedY - normalized.minY) > .ulpOfOne
      || abs(keystrokeOverlayNormalizedWidth - normalized.width) > .ulpOfOne
      || abs(keystrokeOverlayNormalizedHeight - normalized.height) > .ulpOfOne
    guard changed else {
      return
    }
    keystrokeOverlayNormalizedX = normalized.minX
    keystrokeOverlayNormalizedY = normalized.minY
    keystrokeOverlayNormalizedWidth = normalized.width
    keystrokeOverlayNormalizedHeight = normalized.height
    persistVideoCaptureSettings()
  }

  func setKeystrokeOverlayWidth(_ width: Double) {
    let current = keystrokeOverlayNormalizedFrame
    let normalizedWidth = Self.clampedKeystrokeOverlayWidth(width)
    setKeystrokeOverlayFrame(
      CGRect(
        x: current.midX - normalizedWidth * 0.5,
        y: current.minY,
        width: normalizedWidth,
        height: current.height
      )
    )
  }

  func setKeystrokeOverlayScale(_ width: Double) {
    let current = keystrokeOverlayNormalizedFrame
    let normalizedWidth = Self.clampedKeystrokeOverlayWidth(width)
    let ratio = current.width > 0
      ? current.height / current.width
      : Self.defaultKeystrokeOverlayFrame.height / Self.defaultKeystrokeOverlayFrame.width
    let normalizedHeight = Self.clampedKeystrokeOverlayHeight(normalizedWidth * Double(ratio))
    setKeystrokeOverlayFrame(
      CGRect(
        x: current.midX - normalizedWidth * 0.5,
        y: current.midY - normalizedHeight * 0.5,
        width: normalizedWidth,
        height: normalizedHeight
      )
    )
  }

  func setKeystrokeOverlayHeight(_ height: Double) {
    let current = keystrokeOverlayNormalizedFrame
    let normalizedHeight = Self.clampedKeystrokeOverlayHeight(height)
    setKeystrokeOverlayFrame(
      CGRect(
        x: current.minX,
        y: current.midY - normalizedHeight * 0.5,
        width: current.width,
        height: normalizedHeight
      )
    )
  }

  func resetKeystrokeOverlayPlacement() {
    setKeystrokeOverlayFrame(Self.defaultKeystrokeOverlayFrame)
  }

  func setVideoHideNotificationsBestEffort(_ enabled: Bool) {
    guard hideNotificationsBestEffort != enabled else {
      return
    }
    hideNotificationsBestEffort = enabled
    persistVideoCaptureSettings()
  }

  func resetVideoCaptureSettings() {
    defaultCaptureType = .screenshot
    recordingEncoder = .standardH264
    recordingFrameRate = .fps30
    recordingCountdown = .off
    exportCodec = .h264
    exportFrameRate = .fps30
    exportQuality = .standard
    exportScale = .full
    exportBitrate = .standard
    recordSystemAudio = true
    recordMicrophone = false
    microphoneDeviceID = ""
    showWebcam = false
    webcamDeviceID = ""
    webcamOverlaySize = .medium
    webcamOverlayShape = .roundedRect
    webcamOverlayAspectRatio = .square
    let defaultWebcamFrame = Self.defaultWebcamOverlayFrame
    webcamOverlayNormalizedX = defaultWebcamFrame.minX
    webcamOverlayNormalizedY = defaultWebcamFrame.minY
    webcamOverlayNormalizedWidth = defaultWebcamFrame.width
    webcamOverlayNormalizedHeight = defaultWebcamFrame.height
    highlightMouseClicks = Defaults.highlightMouseClicks
    mouseClickHighlightStyle = Defaults.mouseClickHighlightStyle
    highlightKeystrokes = false
    keystrokeOverlayStyle = .glass
    keystrokeOverlaySize = .medium
    let defaultKeystrokeFrame = Self.defaultKeystrokeOverlayFrame
    keystrokeOverlayNormalizedX = defaultKeystrokeFrame.minX
    keystrokeOverlayNormalizedY = defaultKeystrokeFrame.minY
    keystrokeOverlayNormalizedWidth = defaultKeystrokeFrame.width
    keystrokeOverlayNormalizedHeight = defaultKeystrokeFrame.height
    hideNotificationsBestEffort = true
    persistVideoCaptureSettings()
  }

  func isRecordingToolVisible(_ tool: RecordingTool) -> Bool {
    !hiddenRecordingTools.contains(tool)
  }

  func setRecordingToolVisible(_ tool: RecordingTool, isVisible: Bool) {
    var updated = hiddenRecordingTools
    if isVisible {
      updated.remove(tool)
    } else {
      updated.insert(tool)
    }

    guard updated != hiddenRecordingTools else {
      return
    }

    hiddenRecordingTools = updated
    persistVideoToolbarConfiguration()
  }

  func moveVideoTools(from source: IndexSet, to destination: Int) {
    guard !source.isEmpty else {
      return
    }

    var updated = recordingToolOrder
    let moving = source.sorted().map { updated[$0] }
    for index in source.sorted(by: >) {
      updated.remove(at: index)
    }

    let beforeDestinationCount = source.filter { $0 < destination }.count
    let adjustedDestination = max(0, min(updated.count, destination - beforeDestinationCount))
    updated.insert(contentsOf: moving, at: adjustedDestination)

    guard updated != recordingToolOrder else {
      return
    }

    recordingToolOrder = updated
    persistVideoToolbarConfiguration()
  }

  func resetVideoToolbarConfiguration() {
    recordingToolOrder = RecordingTool.allCases
    hiddenRecordingTools = []
    persistVideoToolbarConfiguration()
  }

  func isToolVisible(_ tool: AnnotationTool) -> Bool {
    !hiddenTools.contains(tool)
  }

  func setToolVisible(_ tool: AnnotationTool, isVisible: Bool) {
    var updated = hiddenTools
    if isVisible {
      updated.remove(tool)
    } else {
      let currentlyVisible = toolOrder.filter { !updated.contains($0) }
      if currentlyVisible.count <= 1, currentlyVisible.contains(tool) {
        return
      }
      updated.insert(tool)
    }

    guard updated != hiddenTools else {
      return
    }

    hiddenTools = updated
    persistToolbarConfiguration()
  }

  func moveTool(_ tool: AnnotationTool, offset: Int) {
    guard let index = toolOrder.firstIndex(of: tool) else {
      return
    }

    let target = index + offset
    guard target >= 0, target < toolOrder.count else {
      return
    }

    var updated = toolOrder
    let moved = updated.remove(at: index)
    updated.insert(moved, at: target)
    toolOrder = updated
    persistToolbarConfiguration()
  }

  func moveTools(from source: IndexSet, to destination: Int) {
    guard !source.isEmpty else {
      return
    }

    var updated = toolOrder
    let moving = source.sorted().map { updated[$0] }
    for index in source.sorted(by: >) {
      updated.remove(at: index)
    }

    let beforeDestinationCount = source.filter { $0 < destination }.count
    let adjustedDestination = max(0, min(updated.count, destination - beforeDestinationCount))
    updated.insert(contentsOf: moving, at: adjustedDestination)

    guard updated != toolOrder else {
      return
    }

    toolOrder = updated
    persistToolbarConfiguration()
  }

  func resetToolbarConfiguration() {
    toolOrder = AnnotationTool.allCases
    hiddenTools = []
    persistToolbarConfiguration()
  }

  func setTextFontSize(_ size: Double) {
    let clamped = Self.clampedTextFontSize(size)
    guard abs(textFontSize - clamped) > .ulpOfOne else {
      return
    }
    textFontSize = clamped
    persistTextSettings()
  }

  func setTextFontName(_ name: String) {
    let normalized = Self.normalizedTextFontName(name)
    guard textFontName != normalized else {
      return
    }
    textFontName = normalized
    persistTextSettings()
  }

  func resetTextSettings() {
    textFontSize = 16
    textFontName = Self.systemFontFamilyName
    persistTextSettings()
  }

  func setDefaultSaveDirectory(_ url: URL?) {
    let normalizedPath = url?.standardizedFileURL.path ?? ""
    guard defaultSaveDirectoryPath != normalizedPath else {
      return
    }
    defaultSaveDirectoryPath = normalizedPath
    if normalizedPath.isEmpty {
      alwaysSaveToDefaultDirectory = false
      saveCopiedScreenshotsToDefaultDirectory = false
    }
    persistSaveSettings()
  }

  func setAlwaysSaveToDefaultDirectory(_ enabled: Bool) {
    let normalizedEnabled = enabled && !defaultSaveDirectoryPath.isEmpty
    guard alwaysSaveToDefaultDirectory != normalizedEnabled else {
      return
    }
    alwaysSaveToDefaultDirectory = normalizedEnabled
    persistSaveSettings()
  }

  func setSaveCopiedScreenshotsToDefaultDirectory(_ enabled: Bool) {
    let normalizedEnabled = enabled && !defaultSaveDirectoryPath.isEmpty
    guard saveCopiedScreenshotsToDefaultDirectory != normalizedEnabled else {
      return
    }
    saveCopiedScreenshotsToDefaultDirectory = normalizedEnabled
    persistSaveSettings()
  }

  func setToolbarAccentColor(_ color: NSColor) {
    let normalized = Self.normalizedAccentComponents(from: color)
    let nextRed = Self.clampedUnit(normalized.red)
    let nextGreen = Self.clampedUnit(normalized.green)
    let nextBlue = Self.clampedUnit(normalized.blue)
    let nextAlpha = Self.clampedUnit(normalized.alpha)
    let changed = abs(toolbarAccentRed - nextRed) > .ulpOfOne
      || abs(toolbarAccentGreen - nextGreen) > .ulpOfOne
      || abs(toolbarAccentBlue - nextBlue) > .ulpOfOne
      || abs(toolbarAccentAlpha - nextAlpha) > .ulpOfOne
    guard changed else {
      return
    }
    toolbarAccentRed = nextRed
    toolbarAccentGreen = nextGreen
    toolbarAccentBlue = nextBlue
    toolbarAccentAlpha = nextAlpha
    persistAppearanceSettings()
  }

  func setScreenshotMainAction(_ action: ScreenshotMainAction) {
    guard screenshotMainAction != action else {
      return
    }
    screenshotMainAction = action
    persistAppearanceSettings()
  }

  func setCaptureTransitionStyle(_ style: CaptureTransitionStyle) {
    guard captureTransitionStyle != style else {
      return
    }
    captureTransitionStyle = style
    persistCaptureTransitionSettings()
  }

  func setCaptureTransitionSpeed(_ speed: Double) {
    let clamped = Self.clampedCaptureTransitionSpeed(speed)
    guard abs(captureTransitionSpeed - clamped) > .ulpOfOne else {
      return
    }
    captureTransitionSpeed = clamped
    persistCaptureTransitionSettings()
  }

  func setCaptureTransitionIntensity(_ intensity: Double) {
    let clamped = Self.clampedCaptureTransitionIntensity(intensity)
    guard abs(captureTransitionIntensity - clamped) > .ulpOfOne else {
      return
    }
    captureTransitionIntensity = clamped
    persistCaptureTransitionSettings()
  }

  func resetCaptureTransitionSettings() {
    captureTransitionStyle = .ripple
    captureTransitionSpeed = 1.25
    captureTransitionIntensity = 0.72
    persistCaptureTransitionSettings()
  }

  var isProExportTrialAvailable: Bool {
    proExportTrialConsumedAt == nil
  }

  func markProExportTrialConsumed(at date: Date = Date()) {
    guard proExportTrialConsumedAt == nil else {
      return
    }
    proExportTrialConsumedAt = date
    persistProExportTrial()
  }

  func resetProExportTrial() {
    guard proExportTrialConsumedAt != nil else {
      return
    }
    proExportTrialConsumedAt = nil
    persistProExportTrial()
  }

  static func availableTextFontFamilyNames() -> [String] {
    let families = NSFontManager.shared.availableFontFamilies
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    return [systemFontFamilyName] + families
  }

  func resolvedTextFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
    let clampedSize = max(8, size)
    if textFontName == Self.systemFontFamilyName {
      return .systemFont(ofSize: clampedSize, weight: weight)
    }

    if let familyFont = NSFontManager.shared.font(withFamily: textFontName, traits: [], weight: 5, size: clampedSize) {
      return familyFont
    }

    if let namedFont = NSFont(name: textFontName, size: clampedSize) {
      return namedFont
    }

    return .systemFont(ofSize: clampedSize, weight: weight)
  }

  static func shortcutDisplay(
    keyCode: UInt32,
    command: Bool,
    shift: Bool,
    option: Bool,
    control: Bool
  ) -> String {
    var parts: [String] = []
    if command { parts.append("⌘") }
    if shift { parts.append("⇧") }
    if option { parts.append("⌥") }
    if control { parts.append("⌃") }
    parts.append(shortcutKeyLabel(for: keyCode))
    return parts.joined()
  }

  static func shortcutKeyLabel(for keyCode: UInt32) -> String {
    let ascii = keyCodeToAscii(keyCode)
    if ascii != UInt8(ascii: "?") {
      return String(format: "%c", ascii)
    }

    switch Int(keyCode) {
    case kVK_F1: return "F1"
    case kVK_F2: return "F2"
    case kVK_F3: return "F3"
    case kVK_F4: return "F4"
    case kVK_F5: return "F5"
    case kVK_F6: return "F6"
    case kVK_F7: return "F7"
    case kVK_F8: return "F8"
    case kVK_F9: return "F9"
    case kVK_F10: return "F10"
    case kVK_F11: return "F11"
    case kVK_F12: return "F12"
    case kVK_Space: return "Space"
    case kVK_Return: return "Return"
    case kVK_Tab: return "Tab"
    case kVK_Delete: return "Delete"
    case kVK_ForwardDelete: return "Del"
    case kVK_Escape: return "Esc"
    case kVK_LeftArrow: return "←"
    case kVK_RightArrow: return "→"
    case kVK_UpArrow: return "↑"
    case kVK_DownArrow: return "↓"
    case kVK_Home: return "Home"
    case kVK_End: return "End"
    case kVK_PageUp: return "PgUp"
    case kVK_PageDown: return "PgDn"
    case kVK_ANSI_Minus: return "-"
    case kVK_ANSI_Equal: return "="
    case kVK_ANSI_LeftBracket: return "["
    case kVK_ANSI_RightBracket: return "]"
    case kVK_ANSI_Semicolon: return ";"
    case kVK_ANSI_Quote: return "'"
    case kVK_ANSI_Comma: return ","
    case kVK_ANSI_Period: return "."
    case kVK_ANSI_Slash: return "/"
    case kVK_ANSI_Backslash: return "\\"
    case kVK_ANSI_Grave: return "`"
    default:
      return "Key \(keyCode)"
    }
  }

  private static func keyCodeToAscii(_ keyCode: UInt32) -> UInt8 {
    switch Int(keyCode) {
    case kVK_ANSI_A: return UInt8(ascii: "A")
    case kVK_ANSI_B: return UInt8(ascii: "B")
    case kVK_ANSI_C: return UInt8(ascii: "C")
    case kVK_ANSI_D: return UInt8(ascii: "D")
    case kVK_ANSI_E: return UInt8(ascii: "E")
    case kVK_ANSI_F: return UInt8(ascii: "F")
    case kVK_ANSI_G: return UInt8(ascii: "G")
    case kVK_ANSI_H: return UInt8(ascii: "H")
    case kVK_ANSI_I: return UInt8(ascii: "I")
    case kVK_ANSI_J: return UInt8(ascii: "J")
    case kVK_ANSI_K: return UInt8(ascii: "K")
    case kVK_ANSI_L: return UInt8(ascii: "L")
    case kVK_ANSI_M: return UInt8(ascii: "M")
    case kVK_ANSI_N: return UInt8(ascii: "N")
    case kVK_ANSI_O: return UInt8(ascii: "O")
    case kVK_ANSI_P: return UInt8(ascii: "P")
    case kVK_ANSI_Q: return UInt8(ascii: "Q")
    case kVK_ANSI_R: return UInt8(ascii: "R")
    case kVK_ANSI_S: return UInt8(ascii: "S")
    case kVK_ANSI_T: return UInt8(ascii: "T")
    case kVK_ANSI_U: return UInt8(ascii: "U")
    case kVK_ANSI_V: return UInt8(ascii: "V")
    case kVK_ANSI_W: return UInt8(ascii: "W")
    case kVK_ANSI_X: return UInt8(ascii: "X")
    case kVK_ANSI_Y: return UInt8(ascii: "Y")
    case kVK_ANSI_Z: return UInt8(ascii: "Z")
    case kVK_ANSI_0: return UInt8(ascii: "0")
    case kVK_ANSI_1: return UInt8(ascii: "1")
    case kVK_ANSI_2: return UInt8(ascii: "2")
    case kVK_ANSI_3: return UInt8(ascii: "3")
    case kVK_ANSI_4: return UInt8(ascii: "4")
    case kVK_ANSI_5: return UInt8(ascii: "5")
    case kVK_ANSI_6: return UInt8(ascii: "6")
    case kVK_ANSI_7: return UInt8(ascii: "7")
    case kVK_ANSI_8: return UInt8(ascii: "8")
    case kVK_ANSI_9: return UInt8(ascii: "9")
    default: return UInt8(ascii: "?")
    }
  }

  private static func normalizedTextFontName(_ raw: String?) -> String {
    guard let raw else {
      return systemFontFamilyName
    }

    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return systemFontFamilyName
    }

    if trimmed == systemFontFamilyName {
      return systemFontFamilyName
    }

    if NSFontManager.shared.availableFontFamilies.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
      return trimmed
    }

    if NSFont(name: trimmed, size: 14) != nil {
      return trimmed
    }

    return systemFontFamilyName
  }

  private static func clampedTextFontSize(_ value: Double) -> Double {
    max(Limits.textFontSize.lowerBound, min(Limits.textFontSize.upperBound, value))
  }

  private static func clampedCaptureTransitionSpeed(_ value: Double) -> Double {
    max(Limits.transitionSpeed.lowerBound, min(Limits.transitionSpeed.upperBound, value))
  }

  private static func clampedCaptureTransitionIntensity(_ value: Double) -> Double {
    max(Limits.transitionIntensity.lowerBound, min(Limits.transitionIntensity.upperBound, value))
  }

  private static var defaultWebcamOverlayFrame: CGRect {
    CGRect(x: 0.74, y: 0.68, width: 0.22, height: 0.22)
  }

  private static var defaultKeystrokeOverlayFrame: CGRect {
    CGRect(x: 0.30, y: 0.08, width: 0.40, height: 0.12)
  }

  private static func clampedNormalizedOrigin(_ value: Double) -> Double {
    max(Limits.normalized.lowerBound, min(Limits.normalized.upperBound, value))
  }

  private static func clampedNormalizedDimension(_ value: Double) -> Double {
    max(Limits.minimumOverlayDimension, min(Limits.normalized.upperBound, value))
  }

  static func clampedWebcamOverlayWidth(_ value: Double) -> Double {
    max(Limits.webcamWidth.lowerBound, min(Limits.webcamWidth.upperBound, value))
  }

  static func clampedWebcamOverlayHeight(_ value: Double) -> Double {
    max(Limits.webcamHeight.lowerBound, min(Limits.webcamHeight.upperBound, value))
  }

  static func clampedKeystrokeOverlayWidth(_ value: Double) -> Double {
    max(Limits.keystrokeWidth.lowerBound, min(Limits.keystrokeWidth.upperBound, value))
  }

  static func clampedKeystrokeOverlayHeight(_ value: Double) -> Double {
    max(Limits.keystrokeHeight.lowerBound, min(Limits.keystrokeHeight.upperBound, value))
  }

  private static func normalizedOverlayFrame(_ frame: CGRect, fallback: CGRect) -> CGRect {
    let source = frame.isNull || frame.isEmpty ? fallback : frame.standardized
    let width = clampedNormalizedDimension(source.width)
    let height = clampedNormalizedDimension(source.height)
    let x = max(0, min(1 - width, source.minX))
    let y = max(0, min(1 - height, source.minY))
    return CGRect(x: x, y: y, width: width, height: height)
  }

  private static func resizedNormalizedOverlayFrame(_ frame: CGRect, width: CGFloat, height: CGFloat) -> CGRect {
    let source = normalizedOverlayFrame(frame, fallback: CGRect(x: 0, y: 0, width: width, height: height))
    let normalizedWidth = clampedNormalizedDimension(width)
    let normalizedHeight = clampedNormalizedDimension(height)
    let x = max(0, min(1 - normalizedWidth, source.midX - normalizedWidth * 0.5))
    let y = max(0, min(1 - normalizedHeight, source.midY - normalizedHeight * 0.5))
    return CGRect(x: x, y: y, width: normalizedWidth, height: normalizedHeight)
  }

  private static func clampedUnit(_ value: Double) -> Double {
    max(Limits.normalized.lowerBound, min(Limits.normalized.upperBound, value))
  }

  private static func normalizedAccentComponents(from color: NSColor) -> (red: Double, green: Double, blue: Double, alpha: Double) {
    let fallback = NSColor.systemBlue
    let rgb = color.usingColorSpace(.deviceRGB)
      ?? NSColor.controlAccentColor.usingColorSpace(.deviceRGB)
      ?? fallback.usingColorSpace(.deviceRGB)
      ?? fallback
    return (
      red: Double(rgb.redComponent),
      green: Double(rgb.greenComponent),
      blue: Double(rgb.blueComponent),
      alpha: Double(rgb.alphaComponent)
    )
  }

  private static func normalizeToolOrder(rawValues: [Int]?) -> [AnnotationTool] {
    var seen = Set<AnnotationTool>()
    var ordered: [AnnotationTool] = []

    if let rawValues {
      for raw in rawValues {
        guard let tool = AnnotationTool(rawValue: raw), !seen.contains(tool) else {
          continue
        }
        ordered.append(tool)
        seen.insert(tool)
      }
    }

    for tool in AnnotationTool.allCases where !seen.contains(tool) {
      ordered.append(tool)
      seen.insert(tool)
    }

    return ordered
  }

  private static func normalizeHiddenTools(rawValues: [Int]?, orderedTools: [AnnotationTool]) -> Set<AnnotationTool> {
    guard let rawValues else {
      return []
    }

    let valid = Set(rawValues.compactMap(AnnotationTool.init(rawValue:)))
    let orderedSet = Set(orderedTools)
    return valid.intersection(orderedSet)
  }

  private static func normalizeRecordingToolOrder(rawValues: [Int]?) -> [RecordingTool] {
    let legacyDefaultOrder = [0, 1, 2, 3, 4, 5]
    if rawValues == nil || rawValues == legacyDefaultOrder {
      return RecordingTool.allCases
    }

    var seen = Set<RecordingTool>()
    var ordered: [RecordingTool] = []

    if let rawValues {
      for raw in rawValues {
        guard let tool = RecordingTool(rawValue: raw), !seen.contains(tool) else {
          continue
        }
        ordered.append(tool)
        seen.insert(tool)
      }
    }

    for tool in RecordingTool.allCases where !seen.contains(tool) {
      ordered.append(tool)
      seen.insert(tool)
    }

    return ordered
  }

  private static func normalizeHiddenRecordingTools(rawValues: [Int]?, orderedTools: [RecordingTool]) -> Set<RecordingTool> {
    guard let rawValues else {
      return []
    }

    let valid = Set(rawValues.compactMap(RecordingTool.init(rawValue:)))
    let orderedSet = Set(orderedTools)
    return valid.intersection(orderedSet)
  }

  private func persistCaptureShortcut() {
    defaults.set(Int(captureKeyCode), forKey: Keys.captureKeyCode)
    defaults.set(captureUseCommand, forKey: Keys.captureUseCommand)
    defaults.set(captureUseShift, forKey: Keys.captureUseShift)
    defaults.set(captureUseOption, forKey: Keys.captureUseOption)
    defaults.set(captureUseControl, forKey: Keys.captureUseControl)
    notifySettingsChanged()
  }

  private func persistCaptureHelperSetting() {
    defaults.set(captureShowHelper, forKey: Keys.captureShowHelper)
    notifySettingsChanged()
  }

  private func persistCaptureSmartWindowSelectionSetting() {
    defaults.set(captureSmartWindowSelectionEnabled, forKey: Keys.captureSmartWindowSelectionEnabled)
    notifySettingsChanged()
  }

  private func persistWelcomeState() {
    defaults.set(hasSeenWelcome, forKey: Keys.hasSeenWelcome)
  }

  private func persistAppLanguage() {
    defaults.set(appLanguage.rawValue, forKey: Keys.appLanguage)
    notifySettingsChanged()
  }

  private func persistToolbarConfiguration() {
    defaults.set(toolOrder.map(\.rawValue), forKey: Keys.toolOrder)
    defaults.set(Array(hiddenTools).map(\.rawValue), forKey: Keys.hiddenTools)
    notifySettingsChanged()
  }

  private func persistVideoToolbarConfiguration() {
    defaults.set(recordingToolOrder.map(\.rawValue), forKey: Keys.recordingToolOrder)
    defaults.set(Array(hiddenRecordingTools).map(\.rawValue), forKey: Keys.hiddenRecordingTools)
    notifySettingsChanged()
  }

  private func persistTextSettings() {
    defaults.set(textFontSize, forKey: Keys.textFontSize)
    defaults.set(textFontName, forKey: Keys.textFontName)
    notifySettingsChanged()
  }

  private func persistSaveSettings() {
    defaults.set(defaultSaveDirectoryPath, forKey: Keys.defaultSaveDirectoryPath)
    defaults.set(alwaysSaveToDefaultDirectory, forKey: Keys.alwaysSaveToDefaultDirectory)
    defaults.set(saveCopiedScreenshotsToDefaultDirectory, forKey: Keys.saveCopiedScreenshotsToDefaultDirectory)
    notifySettingsChanged()
  }

  private func persistAppearanceSettings() {
    defaults.set(toolbarAccentRed, forKey: Keys.toolbarAccentRed)
    defaults.set(toolbarAccentGreen, forKey: Keys.toolbarAccentGreen)
    defaults.set(toolbarAccentBlue, forKey: Keys.toolbarAccentBlue)
    defaults.set(toolbarAccentAlpha, forKey: Keys.toolbarAccentAlpha)
    defaults.set(screenshotMainAction.rawValue, forKey: Keys.screenshotMainAction)
    notifySettingsChanged()
  }

  private func persistCaptureTransitionSettings() {
    defaults.set(captureTransitionStyle.rawValue, forKey: Keys.captureTransitionStyle)
    defaults.set(captureTransitionSpeed, forKey: Keys.captureTransitionSpeed)
    defaults.set(captureTransitionIntensity, forKey: Keys.captureTransitionIntensity)
    notifySettingsChanged()
  }

  private func persistProExportTrial() {
    if let proExportTrialConsumedAt {
      defaults.set(proExportTrialConsumedAt, forKey: Keys.proExportTrialConsumedAt)
    } else {
      defaults.removeObject(forKey: Keys.proExportTrialConsumedAt)
    }
    notifySettingsChanged()
  }

  private func persistVideoCaptureSettings() {
    defaults.set(defaultCaptureType.rawValue, forKey: Keys.defaultCaptureType)
    defaults.set(recordingEncoder.rawValue, forKey: Keys.recordingEncoder)
    defaults.set(recordingFrameRate.rawValue, forKey: Keys.recordingFrameRate)
    defaults.set(recordingCountdown.rawValue, forKey: Keys.recordingCountdown)
    defaults.set(exportCodec.rawValue, forKey: Keys.exportCodec)
    defaults.set(exportFrameRate.rawValue, forKey: Keys.exportFrameRate)
    defaults.set(exportQuality.rawValue, forKey: Keys.exportQuality)
    defaults.set(exportScale.rawValue, forKey: Keys.exportScale)
    defaults.set(exportBitrate.rawValue, forKey: Keys.exportBitrate)
    defaults.set(recordSystemAudio, forKey: Keys.recordSystemAudio)
    defaults.set(recordMicrophone, forKey: Keys.recordMicrophone)
    defaults.set(microphoneDeviceID, forKey: Keys.microphoneDeviceID)
    defaults.set(showWebcam, forKey: Keys.showWebcam)
    defaults.set(webcamDeviceID, forKey: Keys.webcamDeviceID)
    defaults.set(webcamOverlaySize.rawValue, forKey: Keys.webcamOverlaySize)
    defaults.set(webcamOverlayShape.rawValue, forKey: Keys.webcamOverlayShape)
    defaults.set(webcamOverlayAspectRatio.rawValue, forKey: Keys.webcamOverlayAspectRatio)
    defaults.set(webcamOverlayNormalizedX, forKey: Keys.webcamOverlayNormalizedX)
    defaults.set(webcamOverlayNormalizedY, forKey: Keys.webcamOverlayNormalizedY)
    defaults.set(webcamOverlayNormalizedWidth, forKey: Keys.webcamOverlayNormalizedWidth)
    defaults.set(webcamOverlayNormalizedHeight, forKey: Keys.webcamOverlayNormalizedHeight)
    defaults.set(highlightMouseClicks, forKey: Keys.highlightMouseClicks)
    defaults.set(mouseClickHighlightStyle.rawValue, forKey: Keys.mouseClickHighlightStyle)
    defaults.set(highlightKeystrokes, forKey: Keys.highlightKeystrokes)
    defaults.set(keystrokeOverlayStyle.rawValue, forKey: Keys.keystrokeOverlayStyle)
    defaults.set(keystrokeOverlaySize.rawValue, forKey: Keys.keystrokeOverlaySize)
    defaults.set(keystrokeOverlayNormalizedX, forKey: Keys.keystrokeOverlayNormalizedX)
    defaults.set(keystrokeOverlayNormalizedY, forKey: Keys.keystrokeOverlayNormalizedY)
    defaults.set(keystrokeOverlayNormalizedWidth, forKey: Keys.keystrokeOverlayNormalizedWidth)
    defaults.set(keystrokeOverlayNormalizedHeight, forKey: Keys.keystrokeOverlayNormalizedHeight)
    defaults.set(hideNotificationsBestEffort, forKey: Keys.hideNotificationsBestEffort)
    notifySettingsChanged()
  }

  private func persistAll(notify: Bool) {
    defaults.set(Int(captureKeyCode), forKey: Keys.captureKeyCode)
    defaults.set(captureUseCommand, forKey: Keys.captureUseCommand)
    defaults.set(captureUseShift, forKey: Keys.captureUseShift)
    defaults.set(captureUseOption, forKey: Keys.captureUseOption)
    defaults.set(captureUseControl, forKey: Keys.captureUseControl)
    defaults.set(captureShowHelper, forKey: Keys.captureShowHelper)
    defaults.set(captureSmartWindowSelectionEnabled, forKey: Keys.captureSmartWindowSelectionEnabled)
    defaults.set(hasSeenWelcome, forKey: Keys.hasSeenWelcome)
    defaults.set(defaultCaptureType.rawValue, forKey: Keys.defaultCaptureType)
    defaults.set(appLanguage.rawValue, forKey: Keys.appLanguage)
    defaults.set(toolOrder.map(\.rawValue), forKey: Keys.toolOrder)
    defaults.set(Array(hiddenTools).map(\.rawValue), forKey: Keys.hiddenTools)
    defaults.set(recordingToolOrder.map(\.rawValue), forKey: Keys.recordingToolOrder)
    defaults.set(Array(hiddenRecordingTools).map(\.rawValue), forKey: Keys.hiddenRecordingTools)
    defaults.set(textFontSize, forKey: Keys.textFontSize)
    defaults.set(textFontName, forKey: Keys.textFontName)
    defaults.set(defaultSaveDirectoryPath, forKey: Keys.defaultSaveDirectoryPath)
    defaults.set(alwaysSaveToDefaultDirectory, forKey: Keys.alwaysSaveToDefaultDirectory)
    defaults.set(saveCopiedScreenshotsToDefaultDirectory, forKey: Keys.saveCopiedScreenshotsToDefaultDirectory)
    defaults.set(toolbarAccentRed, forKey: Keys.toolbarAccentRed)
    defaults.set(toolbarAccentGreen, forKey: Keys.toolbarAccentGreen)
    defaults.set(toolbarAccentBlue, forKey: Keys.toolbarAccentBlue)
    defaults.set(toolbarAccentAlpha, forKey: Keys.toolbarAccentAlpha)
    defaults.set(screenshotMainAction.rawValue, forKey: Keys.screenshotMainAction)
    defaults.set(captureTransitionStyle.rawValue, forKey: Keys.captureTransitionStyle)
    defaults.set(captureTransitionSpeed, forKey: Keys.captureTransitionSpeed)
    defaults.set(captureTransitionIntensity, forKey: Keys.captureTransitionIntensity)
    defaults.set(recordingEncoder.rawValue, forKey: Keys.recordingEncoder)
    defaults.set(recordingFrameRate.rawValue, forKey: Keys.recordingFrameRate)
    defaults.set(recordingCountdown.rawValue, forKey: Keys.recordingCountdown)
    defaults.set(exportCodec.rawValue, forKey: Keys.exportCodec)
    defaults.set(exportFrameRate.rawValue, forKey: Keys.exportFrameRate)
    defaults.set(exportQuality.rawValue, forKey: Keys.exportQuality)
    defaults.set(exportScale.rawValue, forKey: Keys.exportScale)
    defaults.set(exportBitrate.rawValue, forKey: Keys.exportBitrate)
    defaults.set(recordSystemAudio, forKey: Keys.recordSystemAudio)
    defaults.set(recordMicrophone, forKey: Keys.recordMicrophone)
    defaults.set(microphoneDeviceID, forKey: Keys.microphoneDeviceID)
    defaults.set(showWebcam, forKey: Keys.showWebcam)
    defaults.set(webcamDeviceID, forKey: Keys.webcamDeviceID)
    defaults.set(webcamOverlaySize.rawValue, forKey: Keys.webcamOverlaySize)
    defaults.set(webcamOverlayShape.rawValue, forKey: Keys.webcamOverlayShape)
    defaults.set(webcamOverlayAspectRatio.rawValue, forKey: Keys.webcamOverlayAspectRatio)
    defaults.set(webcamOverlayNormalizedX, forKey: Keys.webcamOverlayNormalizedX)
    defaults.set(webcamOverlayNormalizedY, forKey: Keys.webcamOverlayNormalizedY)
    defaults.set(webcamOverlayNormalizedWidth, forKey: Keys.webcamOverlayNormalizedWidth)
    defaults.set(webcamOverlayNormalizedHeight, forKey: Keys.webcamOverlayNormalizedHeight)
    defaults.set(highlightMouseClicks, forKey: Keys.highlightMouseClicks)
    defaults.set(mouseClickHighlightStyle.rawValue, forKey: Keys.mouseClickHighlightStyle)
    defaults.set(highlightKeystrokes, forKey: Keys.highlightKeystrokes)
    defaults.set(keystrokeOverlayStyle.rawValue, forKey: Keys.keystrokeOverlayStyle)
    defaults.set(keystrokeOverlaySize.rawValue, forKey: Keys.keystrokeOverlaySize)
    defaults.set(keystrokeOverlayNormalizedX, forKey: Keys.keystrokeOverlayNormalizedX)
    defaults.set(keystrokeOverlayNormalizedY, forKey: Keys.keystrokeOverlayNormalizedY)
    defaults.set(keystrokeOverlayNormalizedWidth, forKey: Keys.keystrokeOverlayNormalizedWidth)
    defaults.set(keystrokeOverlayNormalizedHeight, forKey: Keys.keystrokeOverlayNormalizedHeight)
    defaults.set(hideNotificationsBestEffort, forKey: Keys.hideNotificationsBestEffort)
    if let proExportTrialConsumedAt {
      defaults.set(proExportTrialConsumedAt, forKey: Keys.proExportTrialConsumedAt)
    } else {
      defaults.removeObject(forKey: Keys.proExportTrialConsumedAt)
    }

    if notify {
      notifySettingsChanged()
    }
  }

  private func notifySettingsChanged() {
    NotificationCenter.default.post(name: .vivyShotSettingsDidChange, object: self)
  }
}
