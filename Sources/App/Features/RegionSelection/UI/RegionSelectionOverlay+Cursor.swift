import AppKit

@MainActor
extension RegionSelectionView {
  static let captureCameraCursor: NSCursor = {
    let size = NSSize(width: 28, height: 28)
    let image = NSImage(size: size)
    image.lockFocus()

    let circleRect = NSRect(x: 1, y: 1, width: 26, height: 26)
    NSColor.black.withAlphaComponent(0.68).setFill()
    NSBezierPath(ovalIn: circleRect).fill()

    NSColor.white.withAlphaComponent(0.18).setStroke()
    let strokePath = NSBezierPath(ovalIn: circleRect.insetBy(dx: 0.5, dy: 0.5))
    strokePath.lineWidth = 1
    strokePath.stroke()

    if let baseSymbol = NSImage(systemSymbolName: "camera.fill", accessibilityDescription: nil) {
      let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
      let symbol = baseSymbol.withSymbolConfiguration(config) ?? baseSymbol
      NSColor.white.set()
      symbol.draw(in: NSRect(x: 7.5, y: 7.5, width: 13, height: 13))
    }

    image.unlockFocus()
    return NSCursor(image: image, hotSpot: NSPoint(x: size.width * 0.5, y: size.height * 0.5))
  }()

  func applyEditingHoverCursor(at point: CGPoint?) {
    guard mode == .editing else {
      return
    }

    if let point,
       (toolbarHost.frame.contains(point) || captureTypeHost.frame.contains(point))
    {
      NSCursor.arrow.set()
      return
    }

    if selectedCaptureMode == .screen || selectedCaptureMode == .window {
      Self.captureCameraCursor.set()
    } else {
      NSCursor.arrow.set()
    }
  }

  func applySelectingHoverCursor(at point: CGPoint?) {
    guard mode == .selecting else {
      return
    }

    if let point, captureTypeHost.frame.contains(point) {
      NSCursor.arrow.set()
      return
    }

    if smartWindowHoverRect != nil, !smartDragActivated {
      Self.captureCameraCursor.set()
    } else {
      NSCursor.crosshair.set()
    }
  }
}
