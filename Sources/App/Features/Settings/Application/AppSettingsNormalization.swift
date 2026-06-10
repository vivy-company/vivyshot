import AppKit
import Carbon
import Foundation

extension AppSettings {
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

  static func normalizedTextFontName(_ raw: String?) -> String {
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

  static func clampedTextFontSize(_ value: Double) -> Double {
    max(Limits.textFontSize.lowerBound, min(Limits.textFontSize.upperBound, value))
  }

  static func clampedDrawingStrokeWidth(_ value: Double) -> Double {
    max(Limits.drawingStrokeWidth.lowerBound, min(Limits.drawingStrokeWidth.upperBound, value))
  }

  static func clampedCaptureTransitionSpeed(_ value: Double) -> Double {
    max(Limits.transitionSpeed.lowerBound, min(Limits.transitionSpeed.upperBound, value))
  }

  static func clampedCaptureTransitionIntensity(_ value: Double) -> Double {
    max(Limits.transitionIntensity.lowerBound, min(Limits.transitionIntensity.upperBound, value))
  }

  static var defaultWebcamOverlayFrame: CGRect {
    CGRect(x: 0.74, y: 0.68, width: 0.22, height: 0.22)
  }

  static var defaultKeystrokeOverlayFrame: CGRect {
    CGRect(x: 0.30, y: 0.08, width: 0.40, height: 0.12)
  }

  static func clampedNormalizedOrigin(_ value: Double) -> Double {
    max(Limits.normalized.lowerBound, min(Limits.normalized.upperBound, value))
  }

  static func clampedNormalizedDimension(_ value: Double) -> Double {
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

  static func normalizedOverlayFrame(_ frame: CGRect, fallback: CGRect) -> CGRect {
    RecordingOverlayFrameGeometry.normalizedUnitFrame(frame, fallback: fallback)
  }

  static func resizedNormalizedOverlayFrame(_ frame: CGRect, width: CGFloat, height: CGFloat) -> CGRect {
    RecordingOverlayFrameGeometry.resizedNormalizedUnitFrame(frame, width: width, height: height)
  }

  static func clampedUnit(_ value: Double) -> Double {
    max(Limits.normalized.lowerBound, min(Limits.normalized.upperBound, value))
  }

  static func normalizedAccentComponents(from color: NSColor) -> (red: Double, green: Double, blue: Double, alpha: Double) {
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

  static func normalizeToolOrder(rawValues: [Int]?) -> [AnnotationTool] {
    normalizeOrderedTools(rawValues: rawValues)
  }

  static func normalizeHiddenTools(rawValues: [Int]?, orderedTools: [AnnotationTool]) -> Set<AnnotationTool> {
    normalizeHiddenToolSet(rawValues: rawValues, orderedTools: orderedTools)
  }

  static func normalizeRecordingToolOrder(rawValues: [Int]?) -> [RecordingTool] {
    normalizeOrderedTools(rawValues: rawValues, legacyDefaultOrder: [0, 1, 2, 3, 4, 5])
  }

  static func normalizeHiddenRecordingTools(rawValues: [Int]?, orderedTools: [RecordingTool]) -> Set<RecordingTool> {
    normalizeHiddenToolSet(rawValues: rawValues, orderedTools: orderedTools)
  }

  private static func normalizeOrderedTools<T>(
    rawValues: [Int]?,
    legacyDefaultOrder: [Int]? = nil
  ) -> [T] where T: CaseIterable & Hashable & RawRepresentable, T.RawValue == Int {
    let allTools = Array(T.allCases)
    if rawValues == nil || rawValues == legacyDefaultOrder {
      return allTools
    }

    var seen = Set<T>()
    var ordered: [T] = []

    for raw in rawValues ?? [] {
      guard let tool = T(rawValue: raw), !seen.contains(tool) else {
        continue
      }
      ordered.append(tool)
      seen.insert(tool)
    }

    for tool in allTools where !seen.contains(tool) {
      ordered.append(tool)
      seen.insert(tool)
    }

    return ordered
  }

  private static func normalizeHiddenToolSet<T>(
    rawValues: [Int]?,
    orderedTools: [T]
  ) -> Set<T> where T: Hashable & RawRepresentable, T.RawValue == Int {
    guard let rawValues else {
      return []
    }

    var valid = Set<T>()
    for raw in rawValues {
      if let tool = T(rawValue: raw) {
        valid.insert(tool)
      }
    }
    let orderedSet = Set(orderedTools)
    return valid.intersection(orderedSet)
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
}
