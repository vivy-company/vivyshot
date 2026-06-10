import AppKit
import CoreGraphics

@MainActor
class RecordingDraggableOverlayView: NSView {
  var normalizedFrame: CGRect
  var onNormalizedFrameChanged: ((CGRect) -> Void)?
  var onDragStateChanged: ((Bool) -> Void)?

  private var dragStartPoint: CGPoint?
  private var dragStartFrame: CGRect = .zero
  private var activeInteraction: OverlayFrameInteraction = .move

  var allowsResizing: Bool { false }
  var minimumFrameSize: CGSize { CGSize(width: 80, height: 80) }
  var fixedAspectRatio: WebcamAspectRatio? { nil }

  private enum OverlayFrameInteraction {
    case move
    case resize(ResizeCorner)
  }

  init(normalizedFrame: CGRect) {
    self.normalizedFrame = RecordingOverlayState.normalizedFrame(normalizedFrame)
    super.init(frame: .zero)
    wantsLayer = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  override func resetCursorRects() {
    addCursorRect(bounds, cursor: .openHand)
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    true
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    guard !isHidden, bounds.contains(point) else {
      return nil
    }
    return self
  }

  override func mouseDown(with event: NSEvent) {
    guard let superview else {
      return
    }
    onDragStateChanged?(true)
    dragStartPoint = superview.convert(event.locationInWindow, from: nil)
    dragStartFrame = frame
    let localPoint = convert(event.locationInWindow, from: nil)
    activeInteraction = resizeCorner(at: localPoint).map(OverlayFrameInteraction.resize) ?? .move
    NSCursor.closedHand.set()
  }

  override func mouseDragged(with event: NSEvent) {
    guard let superview, let dragStartPoint else {
      return
    }

    let point = superview.convert(event.locationInWindow, from: nil)
    let dx = point.x - dragStartPoint.x
    let dy = point.y - dragStartPoint.y
    let proposed: CGRect
    switch activeInteraction {
    case .move:
      proposed = dragStartFrame.offsetBy(dx: dx, dy: dy)
    case .resize(let corner):
      proposed = RecordingOverlayFrameGeometry.resizedOverlayFrame(
        from: dragStartFrame,
        corner: corner,
        delta: CGSize(width: dx, height: dy),
        minimumSize: minimumFrameSize
      )
    }
    frame = clampedFrame(proposed, in: superview.bounds).integral
    normalizedFrame = Self.normalizedFrame(for: frame, in: superview.bounds)
    onNormalizedFrameChanged?(normalizedFrame)
    needsDisplay = true
  }

  override func mouseUp(with event: NSEvent) {
    dragStartPoint = nil
    activeInteraction = .move
    NSCursor.openHand.set()
    onDragStateChanged?(false)
    guard let superview else {
      return
    }
    normalizedFrame = Self.normalizedFrame(for: frame, in: superview.bounds)
    onNormalizedFrameChanged?(normalizedFrame)
  }

  private func resizeCorner(at point: CGPoint) -> ResizeCorner? {
    guard allowsResizing else {
      return nil
    }
    return RecordingOverlayFrameGeometry.resizeCorner(at: point, in: bounds)
  }

  private func clampedFrame(_ proposed: CGRect, in superviewBounds: CGRect) -> CGRect {
    let bounds = superviewBounds.insetBy(dx: 8, dy: 8)
    let minWidth = min(minimumFrameSize.width, bounds.width)
    let minHeight = min(minimumFrameSize.height, bounds.height)
    if let fixedAspectRatio {
      return fixedAspectRatio.constrainedFrame(
        proposed,
        in: bounds,
        minimumSize: CGSize(width: minWidth, height: minHeight)
      )
    }

    return RecordingOverlayFrameGeometry.clampedOverlayFrame(
      proposed,
      in: bounds,
      minimumSize: CGSize(width: minWidth, height: minHeight)
    )
  }

  private static func normalizedFrame(for frame: CGRect, in bounds: CGRect) -> CGRect {
    guard bounds.width > 0, bounds.height > 0 else {
      return .zero
    }
    return RecordingOverlayState.normalizedFrame(
      RecordingOverlayFrameGeometry.normalizedOverlayFrame(frame, in: bounds)
    )
  }
}
