import AppKit
import Carbon
import Foundation

extension AppSettings {
  var toolbarAccentColor: NSColor {
    NSColor(
      calibratedRed: CGFloat(Self.clampedUnit(toolbarAccentRed)),
      green: CGFloat(Self.clampedUnit(toolbarAccentGreen)),
      blue: CGFloat(Self.clampedUnit(toolbarAccentBlue)),
      alpha: CGFloat(Self.clampedUnit(toolbarAccentAlpha))
    )
  }

  var defaultSaveDirectoryURL: URL? {
    Self.validDirectoryURL(path: defaultSaveDirectoryPath)
  }

  var videoSaveDirectoryURL: URL? {
    Self.validDirectoryURL(path: videoSaveDirectoryPath)
  }

  private static func validDirectoryURL(path: String) -> URL? {
    guard !path.isEmpty else { return nil }
    let url = URL(fileURLWithPath: path, isDirectory: true)
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

  static var drawingStrokeWidthRange: ClosedRange<Double> {
    Limits.drawingStrokeWidth
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

  func shortcutKeyLabel(for keyCode: UInt32) -> String {
    Self.shortcutKeyLabel(for: keyCode)
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
}
