import CoreGraphics
import Foundation

enum RecordedInputModifierMask {
  static let command: UInt32 = 1 << 0
  static let shift: UInt32 = 1 << 1
  static let option: UInt32 = 1 << 2
  static let control: UInt32 = 1 << 3
}

/// Normalizes keyboard and pointer events before they are stored as recording overlays.
enum InputEventNormalizer {
  /// Keystroke badges stay compact by showing at most two visible characters after modifiers.
  private static let maximumKeyCharacters = 2

  static func normalizeKeyToken(keyCode _: UInt16, modifiers: UInt32, characters: String?) -> String? {
    var parts: [String] = []
    if modifiers & RecordedInputModifierMask.command != 0 { parts.append("⌘") }
    if modifiers & RecordedInputModifierMask.shift != 0 { parts.append("⇧") }
    if modifiers & RecordedInputModifierMask.option != 0 { parts.append("⌥") }
    if modifiers & RecordedInputModifierMask.control != 0 { parts.append("⌃") }
    if let key = characters?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), !key.isEmpty {
      parts.append(String(key.prefix(maximumKeyCharacters)))
    } else {
      parts.append("K")
    }
    let token = parts.joined()
    return token.isEmpty ? nil : token
  }

  /// ScreenCaptureKit can report the same key event more than once; timestamp and token equality is enough to coalesce it.
  static func isDuplicateKeyEvent(lastTimestampNS: UInt64, lastToken: String, timestampNS: UInt64, token: String) -> Bool {
    lastTimestampNS == timestampNS && !lastToken.isEmpty && lastToken == token
  }

  /// Clamps a pointer location into normalized recording coordinates.
  static func normalizeClickPoint(x: CGFloat, y: CGFloat) -> CGPoint? {
    guard x.isFinite, y.isFinite else {
      return nil
    }
    return CGPoint(x: min(max(0, x), 1), y: min(max(0, y), 1))
  }

  /// Treats click events with the same timestamp/button and nearly identical point as duplicates.
  static func isDuplicateClickEvent(
    lastTimestampNS: UInt64,
    lastButton: UInt32,
    lastX: CGFloat,
    lastY: CGFloat,
    timestampNS: UInt64,
    button: UInt32,
    x: CGFloat,
    y: CGFloat,
    epsilon: CGFloat = 0.0001
  ) -> Bool {
    lastTimestampNS == timestampNS
      && lastButton == button
      && abs(lastX - x) <= max(epsilon, 0.000001)
      && abs(lastY - y) <= max(epsilon, 0.000001)
  }
}
