import AppKit
import CoreGraphics

enum DisplayCoordinateConversion {
  static func activeScreen(containing point: CGPoint) -> NSScreen? {
    NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main ?? NSScreen.screens.first
  }

  static func cocoaRectToCGDisplayRect(_ rect: CGRect) -> CGRect {
    guard let primaryHeight = NSScreen.screens.first?.frame.height else {
      return rect
    }
    return cocoaRectToCGDisplayRect(rect, primaryDisplayHeight: primaryHeight)
  }

  static func cocoaRectToCGDisplayRect(_ rect: CGRect, primaryDisplayHeight: CGFloat) -> CGRect {
    CGRect(x: rect.origin.x, y: primaryDisplayHeight - rect.maxY, width: rect.width, height: rect.height)
  }

  static func cgDisplayRectToCocoaRect(_ rect: CGRect) -> CGRect {
    cocoaRectToCGDisplayRect(rect)
  }

  static func cgDisplayRectToCocoaRect(_ rect: CGRect, primaryDisplayHeight: CGFloat) -> CGRect {
    cocoaRectToCGDisplayRect(rect, primaryDisplayHeight: primaryDisplayHeight)
  }
}
