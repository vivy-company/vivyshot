import AppKit
import Carbon
import Foundation

extension Notification.Name {
  static let vivyShotSettingsDidChange = Notification.Name("com.vivyshot.settingsDidChange")
}

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
      return "None"
    case .fade:
      return "Fade"
    case .ripple:
      return "Wave Drop"
    case .liquidDrop:
      return "Liquid Drop"
    case .zoomBlur:
      return "Zoom Blur"
    case .waterWave:
      return "Water Wave"
    }
  }
}

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
  @Published private(set) var defaultCaptureType: CaptureContentType

  @Published private(set) var toolOrder: [AnnotationTool]
  @Published private(set) var hiddenTools: Set<AnnotationTool>
  @Published private(set) var videoToolOrder: [VideoToolbarTool]
  @Published private(set) var hiddenVideoTools: Set<VideoToolbarTool>

  @Published private(set) var textFontSize: Double
  @Published private(set) var textFontName: String

  @Published private(set) var defaultSaveDirectoryPath: String
  @Published private(set) var alwaysSaveToDefaultDirectory: Bool

  @Published private(set) var captureTransitionStyle: CaptureTransitionStyle
  @Published private(set) var captureTransitionSpeed: Double
  @Published private(set) var captureTransitionIntensity: Double
  @Published private(set) var toolbarAccentRed: Double
  @Published private(set) var toolbarAccentGreen: Double
  @Published private(set) var toolbarAccentBlue: Double
  @Published private(set) var toolbarAccentAlpha: Double
  @Published private(set) var screenshotMainAction: ScreenshotMainAction

  @Published private(set) var videoCodec: VideoCodecOption
  @Published private(set) var videoFrameRate: VideoFrameRateOption
  @Published private(set) var videoCountdown: VideoCountdownOption
  @Published private(set) var videoRecordSystemAudio: Bool
  @Published private(set) var videoRecordMicrophone: Bool
  @Published private(set) var videoShowWebcam: Bool
  @Published private(set) var videoWebcamDeviceID: String
  @Published private(set) var videoWebcamOverlaySize: VideoWebcamOverlaySizeOption
  @Published private(set) var videoWebcamOverlayShape: VideoWebcamOverlayShapeOption
  @Published private(set) var videoHighlightMouseClicks: Bool
  @Published private(set) var videoHighlightKeystrokes: Bool
  @Published private(set) var videoHideNotificationsBestEffort: Bool

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

  var visibleTools: [AnnotationTool] {
    let visible = toolOrder.filter { !hiddenTools.contains($0) }
    return visible.isEmpty ? [.move] : visible
  }

  var visibleVideoTools: [VideoToolbarTool] {
    videoToolOrder.filter { !hiddenVideoTools.contains($0) }
  }

  private let defaults: UserDefaults

  private enum Keys {
    static let captureKeyCode = "settings.capture.keyCode"
    static let captureUseCommand = "settings.capture.useCommand"
    static let captureUseShift = "settings.capture.useShift"
    static let captureUseOption = "settings.capture.useOption"
    static let captureUseControl = "settings.capture.useControl"
    static let captureShowHelper = "settings.capture.showHelper"
    static let defaultCaptureType = "settings.capture.defaultType"

    static let toolOrder = "settings.toolbar.toolOrder"
    static let hiddenTools = "settings.toolbar.hiddenTools"
    static let videoToolOrder = "settings.video.toolbar.toolOrder"
    static let videoHiddenTools = "settings.video.toolbar.hiddenTools"

    static let textFontSize = "settings.text.fontSize"
    static let textFontName = "settings.text.fontName"

    static let defaultSaveDirectoryPath = "settings.save.defaultDirectoryPath"
    static let alwaysSaveToDefaultDirectory = "settings.save.alwaysSaveToDefaultDirectory"

    static let captureTransitionStyle = "settings.capture.transition.style"
    static let captureTransitionSpeed = "settings.capture.transition.speed"
    static let captureTransitionIntensity = "settings.capture.transition.intensity"
    static let toolbarAccentRed = "settings.appearance.toolbarAccent.red"
    static let toolbarAccentGreen = "settings.appearance.toolbarAccent.green"
    static let toolbarAccentBlue = "settings.appearance.toolbarAccent.blue"
    static let toolbarAccentAlpha = "settings.appearance.toolbarAccent.alpha"
    static let screenshotMainAction = "settings.appearance.screenshotMainAction"

    static let videoCodec = "settings.video.codec"
    static let videoFrameRate = "settings.video.frameRate"
    static let videoCountdown = "settings.video.countdown"
    static let videoRecordSystemAudio = "settings.video.recordSystemAudio"
    static let videoRecordMicrophone = "settings.video.recordMicrophone"
    static let videoShowWebcam = "settings.video.showWebcam"
    static let videoWebcamDeviceID = "settings.video.webcam.deviceID"
    static let videoWebcamOverlaySize = "settings.video.webcam.overlaySize"
    static let videoWebcamOverlayShape = "settings.video.webcam.overlayShape"
    static let videoHighlightMouseClicks = "settings.video.highlightMouseClicks"
    static let videoHighlightKeystrokes = "settings.video.highlightKeystrokes"
    static let videoHideNotificationsBestEffort = "settings.video.hideNotificationsBestEffort"
  }

  private init(defaults: UserDefaults = .standard) {
    self.defaults = defaults

    let storedKeyCode = defaults.object(forKey: Keys.captureKeyCode) as? Int
    captureKeyCode = UInt32(storedKeyCode ?? Int(kVK_ANSI_2))

    if defaults.object(forKey: Keys.captureUseCommand) == nil {
      captureUseCommand = true
    } else {
      captureUseCommand = defaults.bool(forKey: Keys.captureUseCommand)
    }

    if defaults.object(forKey: Keys.captureUseShift) == nil {
      captureUseShift = true
    } else {
      captureUseShift = defaults.bool(forKey: Keys.captureUseShift)
    }

    captureUseOption = defaults.bool(forKey: Keys.captureUseOption)
    captureUseControl = defaults.bool(forKey: Keys.captureUseControl)
    if defaults.object(forKey: Keys.captureShowHelper) == nil {
      captureShowHelper = true
    } else {
      captureShowHelper = defaults.bool(forKey: Keys.captureShowHelper)
    }

    let storedDefaultCaptureType = defaults.object(forKey: Keys.defaultCaptureType) as? Int
    defaultCaptureType = CaptureContentType(rawValue: storedDefaultCaptureType ?? CaptureContentType.screenshot.rawValue) ?? .screenshot

    let normalizedToolOrder = Self.normalizeToolOrder(rawValues: defaults.array(forKey: Keys.toolOrder) as? [Int])
    toolOrder = normalizedToolOrder
    hiddenTools = Self.normalizeHiddenTools(
      rawValues: defaults.array(forKey: Keys.hiddenTools) as? [Int],
      orderedTools: normalizedToolOrder
    )
    let normalizedVideoToolOrder = Self.normalizeVideoToolOrder(rawValues: defaults.array(forKey: Keys.videoToolOrder) as? [Int])
    videoToolOrder = normalizedVideoToolOrder
    hiddenVideoTools = Self.normalizeHiddenVideoTools(
      rawValues: defaults.array(forKey: Keys.videoHiddenTools) as? [Int],
      orderedTools: normalizedVideoToolOrder
    )

    let storedTextSize = defaults.object(forKey: Keys.textFontSize) as? Double
    textFontSize = Self.clampedTextFontSize(storedTextSize ?? 16)

    let storedFontName = defaults.string(forKey: Keys.textFontName)
    textFontName = Self.normalizedTextFontName(storedFontName)

    defaultSaveDirectoryPath = defaults.string(forKey: Keys.defaultSaveDirectoryPath) ?? ""
    alwaysSaveToDefaultDirectory = defaults.bool(forKey: Keys.alwaysSaveToDefaultDirectory)

    let storedTransitionStyle = defaults.object(forKey: Keys.captureTransitionStyle) as? Int
    captureTransitionStyle = CaptureTransitionStyle(rawValue: storedTransitionStyle ?? CaptureTransitionStyle.ripple.rawValue) ?? .ripple

    let storedTransitionSpeed = defaults.object(forKey: Keys.captureTransitionSpeed) as? Double
    captureTransitionSpeed = Self.clampedCaptureTransitionSpeed(storedTransitionSpeed ?? 1.25)

    let storedTransitionIntensity = defaults.object(forKey: Keys.captureTransitionIntensity) as? Double
    captureTransitionIntensity = Self.clampedCaptureTransitionIntensity(storedTransitionIntensity ?? 0.72)

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
      rawValue: storedScreenshotMainAction ?? ScreenshotMainAction.copy.rawValue
    ) ?? .copy

    let storedVideoCodec = defaults.object(forKey: Keys.videoCodec) as? Int
    videoCodec = VideoCodecOption(rawValue: storedVideoCodec ?? VideoCodecOption.h264.rawValue) ?? .h264

    let storedVideoFrameRate = defaults.object(forKey: Keys.videoFrameRate) as? Int
    videoFrameRate = VideoFrameRateOption(rawValue: storedVideoFrameRate ?? VideoFrameRateOption.fps30.rawValue) ?? .fps30

    let storedVideoCountdown = defaults.object(forKey: Keys.videoCountdown) as? Int
    videoCountdown = VideoCountdownOption(rawValue: storedVideoCountdown ?? VideoCountdownOption.off.rawValue) ?? .off

    if defaults.object(forKey: Keys.videoRecordSystemAudio) == nil {
      videoRecordSystemAudio = true
    } else {
      videoRecordSystemAudio = defaults.bool(forKey: Keys.videoRecordSystemAudio)
    }

    videoRecordMicrophone = defaults.bool(forKey: Keys.videoRecordMicrophone)
    videoShowWebcam = defaults.bool(forKey: Keys.videoShowWebcam)
    videoWebcamDeviceID = defaults.string(forKey: Keys.videoWebcamDeviceID) ?? ""

    let storedWebcamSize = defaults.object(forKey: Keys.videoWebcamOverlaySize) as? Int
    videoWebcamOverlaySize = VideoWebcamOverlaySizeOption(rawValue: storedWebcamSize ?? VideoWebcamOverlaySizeOption.medium.rawValue) ?? .medium

    let storedWebcamShape = defaults.object(forKey: Keys.videoWebcamOverlayShape) as? Int
    videoWebcamOverlayShape = VideoWebcamOverlayShapeOption(rawValue: storedWebcamShape ?? VideoWebcamOverlayShapeOption.roundedRect.rawValue) ?? .roundedRect

    if defaults.object(forKey: Keys.videoHighlightMouseClicks) == nil {
      videoHighlightMouseClicks = true
    } else {
      videoHighlightMouseClicks = defaults.bool(forKey: Keys.videoHighlightMouseClicks)
    }

    videoHighlightKeystrokes = defaults.bool(forKey: Keys.videoHighlightKeystrokes)

    if defaults.object(forKey: Keys.videoHideNotificationsBestEffort) == nil {
      videoHideNotificationsBestEffort = true
    } else {
      videoHideNotificationsBestEffort = defaults.bool(forKey: Keys.videoHideNotificationsBestEffort)
    }

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
      keyCode: UInt32(kVK_ANSI_2),
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

  func setDefaultCaptureType(_ type: CaptureContentType) {
    guard defaultCaptureType != type else {
      return
    }
    defaultCaptureType = type
    persistVideoCaptureSettings()
  }

  func setVideoCodec(_ codec: VideoCodecOption) {
    guard videoCodec != codec else {
      return
    }
    videoCodec = codec
    persistVideoCaptureSettings()
  }

  func setVideoFrameRate(_ frameRate: VideoFrameRateOption) {
    guard videoFrameRate != frameRate else {
      return
    }
    videoFrameRate = frameRate
    persistVideoCaptureSettings()
  }

  func setVideoCountdown(_ countdown: VideoCountdownOption) {
    guard videoCountdown != countdown else {
      return
    }
    videoCountdown = countdown
    persistVideoCaptureSettings()
  }

  func setVideoRecordSystemAudio(_ enabled: Bool) {
    guard videoRecordSystemAudio != enabled else {
      return
    }
    videoRecordSystemAudio = enabled
    persistVideoCaptureSettings()
  }

  func setVideoRecordMicrophone(_ enabled: Bool) {
    guard videoRecordMicrophone != enabled else {
      return
    }
    videoRecordMicrophone = enabled
    persistVideoCaptureSettings()
  }

  func setVideoShowWebcam(_ enabled: Bool) {
    guard videoShowWebcam != enabled else {
      return
    }
    videoShowWebcam = enabled
    persistVideoCaptureSettings()
  }

  func setVideoWebcamDeviceID(_ deviceID: String) {
    let normalized = deviceID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard videoWebcamDeviceID != normalized else {
      return
    }
    videoWebcamDeviceID = normalized
    persistVideoCaptureSettings()
  }

  func setVideoWebcamOverlaySize(_ size: VideoWebcamOverlaySizeOption) {
    guard videoWebcamOverlaySize != size else {
      return
    }
    videoWebcamOverlaySize = size
    persistVideoCaptureSettings()
  }

  func setVideoWebcamOverlayShape(_ shape: VideoWebcamOverlayShapeOption) {
    guard videoWebcamOverlayShape != shape else {
      return
    }
    videoWebcamOverlayShape = shape
    persistVideoCaptureSettings()
  }

  func setVideoHighlightMouseClicks(_ enabled: Bool) {
    guard videoHighlightMouseClicks != enabled else {
      return
    }
    videoHighlightMouseClicks = enabled
    persistVideoCaptureSettings()
  }

  func setVideoHighlightKeystrokes(_ enabled: Bool) {
    guard videoHighlightKeystrokes != enabled else {
      return
    }
    videoHighlightKeystrokes = enabled
    persistVideoCaptureSettings()
  }

  func setVideoHideNotificationsBestEffort(_ enabled: Bool) {
    guard videoHideNotificationsBestEffort != enabled else {
      return
    }
    videoHideNotificationsBestEffort = enabled
    persistVideoCaptureSettings()
  }

  func resetVideoCaptureSettings() {
    defaultCaptureType = .screenshot
    videoCodec = .h264
    videoFrameRate = .fps30
    videoCountdown = .off
    videoRecordSystemAudio = true
    videoRecordMicrophone = false
    videoShowWebcam = false
    videoWebcamDeviceID = ""
    videoWebcamOverlaySize = .medium
    videoWebcamOverlayShape = .roundedRect
    videoHighlightMouseClicks = true
    videoHighlightKeystrokes = false
    videoHideNotificationsBestEffort = true
    persistVideoCaptureSettings()
  }

  func isVideoToolVisible(_ tool: VideoToolbarTool) -> Bool {
    !hiddenVideoTools.contains(tool)
  }

  func setVideoToolVisible(_ tool: VideoToolbarTool, isVisible: Bool) {
    var updated = hiddenVideoTools
    if isVisible {
      updated.remove(tool)
    } else {
      updated.insert(tool)
    }

    guard updated != hiddenVideoTools else {
      return
    }

    hiddenVideoTools = updated
    persistVideoToolbarConfiguration()
  }

  func moveVideoTools(from source: IndexSet, to destination: Int) {
    guard !source.isEmpty else {
      return
    }

    var updated = videoToolOrder
    let moving = source.sorted().map { updated[$0] }
    for index in source.sorted(by: >) {
      updated.remove(at: index)
    }

    let beforeDestinationCount = source.filter { $0 < destination }.count
    let adjustedDestination = max(0, min(updated.count, destination - beforeDestinationCount))
    updated.insert(contentsOf: moving, at: adjustedDestination)

    guard updated != videoToolOrder else {
      return
    }

    videoToolOrder = updated
    persistVideoToolbarConfiguration()
  }

  func resetVideoToolbarConfiguration() {
    videoToolOrder = VideoToolbarTool.allCases
    hiddenVideoTools = []
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
    max(10, min(72, value))
  }

  private static func clampedCaptureTransitionSpeed(_ value: Double) -> Double {
    max(0.8, min(2.4, value))
  }

  private static func clampedCaptureTransitionIntensity(_ value: Double) -> Double {
    max(0.2, min(1, value))
  }

  private static func clampedUnit(_ value: Double) -> Double {
    max(0, min(1, value))
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

  private static func normalizeVideoToolOrder(rawValues: [Int]?) -> [VideoToolbarTool] {
    var seen = Set<VideoToolbarTool>()
    var ordered: [VideoToolbarTool] = []

    if let rawValues {
      for raw in rawValues {
        guard let tool = VideoToolbarTool(rawValue: raw), !seen.contains(tool) else {
          continue
        }
        ordered.append(tool)
        seen.insert(tool)
      }
    }

    for tool in VideoToolbarTool.allCases where !seen.contains(tool) {
      ordered.append(tool)
      seen.insert(tool)
    }

    return ordered
  }

  private static func normalizeHiddenVideoTools(rawValues: [Int]?, orderedTools: [VideoToolbarTool]) -> Set<VideoToolbarTool> {
    guard let rawValues else {
      return []
    }

    let valid = Set(rawValues.compactMap(VideoToolbarTool.init(rawValue:)))
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

  private func persistToolbarConfiguration() {
    defaults.set(toolOrder.map(\.rawValue), forKey: Keys.toolOrder)
    defaults.set(Array(hiddenTools).map(\.rawValue), forKey: Keys.hiddenTools)
    notifySettingsChanged()
  }

  private func persistVideoToolbarConfiguration() {
    defaults.set(videoToolOrder.map(\.rawValue), forKey: Keys.videoToolOrder)
    defaults.set(Array(hiddenVideoTools).map(\.rawValue), forKey: Keys.videoHiddenTools)
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

  private func persistVideoCaptureSettings() {
    defaults.set(defaultCaptureType.rawValue, forKey: Keys.defaultCaptureType)
    defaults.set(videoCodec.rawValue, forKey: Keys.videoCodec)
    defaults.set(videoFrameRate.rawValue, forKey: Keys.videoFrameRate)
    defaults.set(videoCountdown.rawValue, forKey: Keys.videoCountdown)
    defaults.set(videoRecordSystemAudio, forKey: Keys.videoRecordSystemAudio)
    defaults.set(videoRecordMicrophone, forKey: Keys.videoRecordMicrophone)
    defaults.set(videoShowWebcam, forKey: Keys.videoShowWebcam)
    defaults.set(videoWebcamDeviceID, forKey: Keys.videoWebcamDeviceID)
    defaults.set(videoWebcamOverlaySize.rawValue, forKey: Keys.videoWebcamOverlaySize)
    defaults.set(videoWebcamOverlayShape.rawValue, forKey: Keys.videoWebcamOverlayShape)
    defaults.set(videoHighlightMouseClicks, forKey: Keys.videoHighlightMouseClicks)
    defaults.set(videoHighlightKeystrokes, forKey: Keys.videoHighlightKeystrokes)
    defaults.set(videoHideNotificationsBestEffort, forKey: Keys.videoHideNotificationsBestEffort)
    notifySettingsChanged()
  }

  private func persistAll(notify: Bool) {
    defaults.set(Int(captureKeyCode), forKey: Keys.captureKeyCode)
    defaults.set(captureUseCommand, forKey: Keys.captureUseCommand)
    defaults.set(captureUseShift, forKey: Keys.captureUseShift)
    defaults.set(captureUseOption, forKey: Keys.captureUseOption)
    defaults.set(captureUseControl, forKey: Keys.captureUseControl)
    defaults.set(captureShowHelper, forKey: Keys.captureShowHelper)
    defaults.set(defaultCaptureType.rawValue, forKey: Keys.defaultCaptureType)
    defaults.set(toolOrder.map(\.rawValue), forKey: Keys.toolOrder)
    defaults.set(Array(hiddenTools).map(\.rawValue), forKey: Keys.hiddenTools)
    defaults.set(videoToolOrder.map(\.rawValue), forKey: Keys.videoToolOrder)
    defaults.set(Array(hiddenVideoTools).map(\.rawValue), forKey: Keys.videoHiddenTools)
    defaults.set(textFontSize, forKey: Keys.textFontSize)
    defaults.set(textFontName, forKey: Keys.textFontName)
    defaults.set(defaultSaveDirectoryPath, forKey: Keys.defaultSaveDirectoryPath)
    defaults.set(alwaysSaveToDefaultDirectory, forKey: Keys.alwaysSaveToDefaultDirectory)
    defaults.set(toolbarAccentRed, forKey: Keys.toolbarAccentRed)
    defaults.set(toolbarAccentGreen, forKey: Keys.toolbarAccentGreen)
    defaults.set(toolbarAccentBlue, forKey: Keys.toolbarAccentBlue)
    defaults.set(toolbarAccentAlpha, forKey: Keys.toolbarAccentAlpha)
    defaults.set(screenshotMainAction.rawValue, forKey: Keys.screenshotMainAction)
    defaults.set(captureTransitionStyle.rawValue, forKey: Keys.captureTransitionStyle)
    defaults.set(captureTransitionSpeed, forKey: Keys.captureTransitionSpeed)
    defaults.set(captureTransitionIntensity, forKey: Keys.captureTransitionIntensity)
    defaults.set(videoCodec.rawValue, forKey: Keys.videoCodec)
    defaults.set(videoFrameRate.rawValue, forKey: Keys.videoFrameRate)
    defaults.set(videoCountdown.rawValue, forKey: Keys.videoCountdown)
    defaults.set(videoRecordSystemAudio, forKey: Keys.videoRecordSystemAudio)
    defaults.set(videoRecordMicrophone, forKey: Keys.videoRecordMicrophone)
    defaults.set(videoShowWebcam, forKey: Keys.videoShowWebcam)
    defaults.set(videoWebcamDeviceID, forKey: Keys.videoWebcamDeviceID)
    defaults.set(videoWebcamOverlaySize.rawValue, forKey: Keys.videoWebcamOverlaySize)
    defaults.set(videoWebcamOverlayShape.rawValue, forKey: Keys.videoWebcamOverlayShape)
    defaults.set(videoHighlightMouseClicks, forKey: Keys.videoHighlightMouseClicks)
    defaults.set(videoHighlightKeystrokes, forKey: Keys.videoHighlightKeystrokes)
    defaults.set(videoHideNotificationsBestEffort, forKey: Keys.videoHideNotificationsBestEffort)

    if notify {
      notifySettingsChanged()
    }
  }

  private func notifySettingsChanged() {
    NotificationCenter.default.post(name: .vivyShotSettingsDidChange, object: self)
  }
}
