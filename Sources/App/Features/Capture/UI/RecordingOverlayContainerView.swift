import AppKit

@MainActor
final class RecordingOverlayContainerView: NSView {
  override var isOpaque: Bool { false }

  override func hitTest(_ point: NSPoint) -> NSView? {
    guard bounds.contains(point) else {
      return nil
    }
    return hitInteractiveOverlay(at: point)
  }

  func containsInteractiveOverlay(at point: NSPoint) -> Bool {
    hitInteractiveOverlay(at: point) != nil
  }

  private func hitInteractiveOverlay(at point: NSPoint) -> NSView? {
    for subview in subviews.reversed() where !subview.isHidden {
      let pointInSubview = subview.convert(point, from: self)
      if let hitView = subview.hitTest(pointInSubview) {
        return hitView
      }
    }
    return nil
  }
}
