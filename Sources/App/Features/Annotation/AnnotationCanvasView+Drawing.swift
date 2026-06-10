import AppKit
import CoreGraphics

@MainActor
extension AnnotationCanvasView {
  func drawMoveSelectionPreview(context: CGContext) {
    guard let selectedAnnotationBoundsInView else {
      return
    }

    context.setStrokeColor(accentColor.withAlphaComponent(0.95).cgColor)
    context.setLineWidth(1.6)
    context.setLineDash(phase: 0, lengths: [6, 4])
    context.stroke(selectedAnnotationBoundsInView.insetBy(dx: -0.5, dy: -0.5))
    context.setLineDash(phase: 0, lengths: [])

    drawResizeHandles(context: context, selection: selectedAnnotationBoundsInView)
  }

  func drawResizeHandles(context: CGContext, selection: CGRect) {
    let radius: CGFloat = 5.5
    for center in resizeHandleCenters(for: selection).values {
      let handleRect = CGRect(
        x: center.x - radius,
        y: center.y - radius,
        width: radius * 2,
        height: radius * 2
      )
      context.setFillColor(NSColor.black.withAlphaComponent(0.85).cgColor)
      context.fillEllipse(in: handleRect)
      context.setStrokeColor(NSColor.white.withAlphaComponent(0.95).cgColor)
      context.setLineWidth(1.4)
      context.strokeEllipse(in: handleRect.insetBy(dx: 0.5, dy: 0.5))
    }
  }

  func drawPaintPathPreview(context: CGContext) {
    guard !paintPathPointsInView.isEmpty else {
      return
    }

    context.setStrokeColor(accentColor.cgColor)
    context.setLineWidth(max(1.8, previewStrokeWidth))
    context.setLineCap(.round)
    context.setLineJoin(.round)

    if paintPathPointsInView.count == 1 {
      let p = paintPathPointsInView[0]
      let radius = max(1.2, previewStrokeWidth * 0.5)
      let dot = CGRect(
        x: p.x - radius,
        y: p.y - radius,
        width: radius * 2,
        height: radius * 2
      )
      context.fillEllipse(in: dot)
      return
    }

    context.beginPath()
    context.move(to: paintPathPointsInView[0])
    for point in paintPathPointsInView.dropFirst() {
      context.addLine(to: point)
    }
    context.strokePath()
  }

  func drawArrowPreview(context: CGContext, start: CGPoint, end: CGPoint, color: NSColor) {
    context.setStrokeColor(color.cgColor)
    context.setLineWidth(previewStrokeWidth)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.move(to: start)
    context.addLine(to: end)
    context.strokePath()

    guard let (p1, p2) = AnnotationArrowGeometry.headPoints(
      start: start,
      end: end,
      strokeWidth: previewStrokeWidth
    ) else {
      return
    }

    context.move(to: end)
    context.addLine(to: p1)
    context.move(to: end)
    context.addLine(to: p2)
    context.strokePath()
  }

  func drawTextCursorPreview(context: CGContext, point: CGPoint, color: NSColor) {
    context.setStrokeColor(color.cgColor)
    context.setLineWidth(2.0)

    let h: CGFloat = 10
    let v: CGFloat = 14
    context.move(to: CGPoint(x: point.x - h, y: point.y))
    context.addLine(to: CGPoint(x: point.x + h, y: point.y))
    context.move(to: CGPoint(x: point.x, y: point.y - v))
    context.addLine(to: CGPoint(x: point.x, y: point.y + v))
    context.strokePath()
  }
}
