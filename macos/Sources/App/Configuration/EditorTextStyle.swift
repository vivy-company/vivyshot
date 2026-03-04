import AppKit
import CoreGraphics

struct EditorTextStyle {
  static let defaultFontName = "System"

  var fontSize: CGFloat
  var color: NSColor
  var fontName: String

  init(
    fontSize: CGFloat,
    color: NSColor,
    fontName: String = Self.defaultFontName
  ) {
    self.fontSize = fontSize
    self.color = color
    self.fontName = fontName
  }
}
