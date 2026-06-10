import AppKit
import CoreGraphics

enum ResizeCorner: CaseIterable {
  case topLeft
  case top
  case topRight
  case right
  case bottom
  case left
  case bottomLeft
  case bottomRight

  var cursor: NSCursor {
    .openHand
  }

  var isCorner: Bool {
    switch self {
    case .topLeft, .topRight, .bottomLeft, .bottomRight:
      return true
    case .top, .right, .bottom, .left:
      return false
    }
  }
}

@MainActor
final class ResizeHandleView: NSView {
  let corner: ResizeCorner

  var onDragStart: ((ResizeCorner) -> Void)?
  var onDragChanged: ((ResizeCorner, CGPoint) -> Void)?
  var onDragEnd: ((ResizeCorner, CGPoint) -> Void)?

  private var startPointInWindow: CGPoint?
  private var pushedClosedHandCursor = false

  init(corner: ResizeCorner) {
    self.corner = corner
    super.init(frame: .zero)
    wantsLayer = false
    isHidden = true
    alphaValue = 1
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  override var acceptsFirstResponder: Bool {
    false
  }

  override var isOpaque: Bool {
    false
  }

  override func resetCursorRects() {
    addCursorRect(bounds, cursor: corner.cursor)
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    let diameter: CGFloat = corner.isCorner ? 9.8 : 8.6
    let rect = CGRect(
      x: (bounds.width - diameter) * 0.5,
      y: (bounds.height - diameter) * 0.5,
      width: diameter,
      height: diameter
    )

    NSColor.black.withAlphaComponent(0.76).setFill()
    NSBezierPath(ovalIn: rect).fill()

    NSColor.white.withAlphaComponent(0.96).setStroke()
    let stroke = NSBezierPath(ovalIn: rect.insetBy(dx: 0.35, dy: 0.35))
    stroke.lineWidth = 1.1
    stroke.stroke()
  }

  override func mouseDown(with event: NSEvent) {
    startPointInWindow = event.locationInWindow
    NSCursor.closedHand.push()
    pushedClosedHandCursor = true
    onDragStart?(corner)
  }

  override func mouseDragged(with event: NSEvent) {
    guard let startPointInWindow else {
      return
    }
    let current = event.locationInWindow
    let delta = CGPoint(x: current.x - startPointInWindow.x, y: current.y - startPointInWindow.y)
    onDragChanged?(corner, delta)
  }

  override func mouseUp(with event: NSEvent) {
    defer {
      if pushedClosedHandCursor {
        NSCursor.pop()
        pushedClosedHandCursor = false
      }
      startPointInWindow = nil
    }
    guard let startPointInWindow else {
      return
    }
    let current = event.locationInWindow
    let delta = CGPoint(x: current.x - startPointInWindow.x, y: current.y - startPointInWindow.y)
    onDragEnd?(corner, delta)
  }
}

@MainActor
final class SelectionMaskOverlayView: NSView {
  enum DisplayStyle: Equatable {
    case selection
    case windowHighlight
  }

  var selectionRect: CGRect = .zero {
    didSet {
      if oldValue != selectionRect {
        needsDisplay = true
      }
    }
  }
  var displayStyle: DisplayStyle = .selection {
    didSet {
      if oldValue != displayStyle {
        needsDisplay = true
      }
    }
  }

  override var isOpaque: Bool {
    false
  }

  override func hitTest(_: NSPoint) -> NSView? {
    nil
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    guard let context = NSGraphicsContext.current?.cgContext else {
      return
    }

    guard !selectionRect.isNull, !selectionRect.isEmpty else {
      return
    }

    let selection = selectionRect.standardized.integral

    let dimPath = CGMutablePath()
    dimPath.addRect(bounds)
    dimPath.addRect(selection)

    context.setFillColor(NSColor.black.withAlphaComponent(displayStyle == .windowHighlight ? 0.46 : 0.5).cgColor)
    context.addPath(dimPath)
    context.drawPath(using: .eoFill)

    if displayStyle == .windowHighlight {
      context.setStrokeColor(NSColor.white.withAlphaComponent(0.94).cgColor)
      context.setLineWidth(2.1)
      context.stroke(selection.insetBy(dx: -0.5, dy: -0.5))
    } else {
      context.setStrokeColor(NSColor.white.withAlphaComponent(0.86).cgColor)
      context.setLineWidth(1.4)
      context.setLineDash(phase: 0, lengths: [6, 4])
      context.stroke(selection.insetBy(dx: -0.5, dy: -0.5))
      context.setLineDash(phase: 0, lengths: [])
      drawHandleDots(in: context, selection: selection)
    }
  }

  private func drawHandleDots(in context: CGContext, selection: CGRect) {
    let minX = selection.minX
    let midX = selection.midX
    let maxX = selection.maxX
    let minY = selection.minY
    let midY = selection.midY
    let maxY = selection.maxY

    let points: [(CGPoint, Bool)] = [
      (CGPoint(x: minX, y: maxY), true),
      (CGPoint(x: midX, y: maxY), false),
      (CGPoint(x: maxX, y: maxY), true),
      (CGPoint(x: maxX, y: midY), false),
      (CGPoint(x: maxX, y: minY), true),
      (CGPoint(x: midX, y: minY), false),
      (CGPoint(x: minX, y: minY), true),
      (CGPoint(x: minX, y: midY), false),
    ]

    for (point, isCorner) in points {
      let radius: CGFloat = isCorner ? 5.2 : 4.7
      let rect = CGRect(
        x: point.x - radius,
        y: point.y - radius,
        width: radius * 2,
        height: radius * 2
      )
      context.setFillColor(NSColor.black.withAlphaComponent(0.76).cgColor)
      context.fillEllipse(in: rect)
      context.setStrokeColor(NSColor.white.withAlphaComponent(0.96).cgColor)
      context.setLineWidth(1.1)
      context.strokeEllipse(in: rect.insetBy(dx: 0.35, dy: 0.35))
    }
  }
}
