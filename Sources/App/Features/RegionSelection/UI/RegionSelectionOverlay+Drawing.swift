import AppKit
import CoreGraphics

@MainActor
extension RegionSelectionView {
  func drawScreenCaptureOverlay(in context: CGContext) {
    guard selectedCaptureMode == .screen else {
      return
    }

    context.saveGState()
    context.setFillColor(NSColor.black.withAlphaComponent(0.08).cgColor)
    context.fill(bounds)
    context.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
    context.setLineWidth(1.6)
    context.stroke(bounds.insetBy(dx: 0.5, dy: 0.5))
    context.restoreGState()
  }

  func drawWindowCaptureOverlay(in context: CGContext) {
    guard selectedCaptureMode == .window else {
      return
    }

    let targetRect = (windowCapturePickPending ? windowCaptureHoverRect : committedSelectionRect)?
      .standardized
      .integral
    guard let targetRect, targetRect.width >= 2, targetRect.height >= 2 else {
      return
    }

    drawWindowCaptureHighlight(in: context, targetRect: targetRect, active: windowCapturePickPending)
  }

  func drawWindowCaptureHighlight(in context: CGContext, targetRect: CGRect, active: Bool) {
    let dimPath = CGMutablePath()
    dimPath.addRect(bounds)
    dimPath.addRect(targetRect)

    context.saveGState()
    context.addPath(dimPath)
    context.setFillColor(NSColor.black.withAlphaComponent(active ? 0.34 : 0.26).cgColor)
    context.drawPath(using: .eoFill)
    context.restoreGState()

    context.saveGState()
    context.setStrokeColor(NSColor.white.withAlphaComponent(active ? 0.94 : 0.8).cgColor)
    context.setLineWidth(active ? 2.0 : 1.4)
    context.stroke(targetRect.insetBy(dx: -0.5, dy: -0.5))
    context.restoreGState()
  }

  func drawStitchPassThroughFocus(in context: CGContext) {
    guard let selection = committedSelectionRect?.standardized.integral else {
      return
    }

    let dimPath = CGMutablePath()
    dimPath.addRect(bounds)
    dimPath.addRect(selection)

    context.saveGState()
    context.addPath(dimPath)
    context.setFillColor(NSColor.black.withAlphaComponent(0.34).cgColor)
    context.drawPath(using: .eoFill)
    context.restoreGState()
  }

  func drawRecordingFocusOverlay(in context: CGContext) {
    guard let selection = committedSelectionRect?.standardized.integral,
          !selection.isNull,
          selection.width >= 2,
          selection.height >= 2
    else {
      return
    }

    let dimPath = CGMutablePath()
    dimPath.addRect(bounds)
    dimPath.addRect(selection)

    context.saveGState()
    context.addPath(dimPath)
    context.setFillColor(NSColor.black.withAlphaComponent(0.42).cgColor)
    context.drawPath(using: .eoFill)
    context.restoreGState()

    context.saveGState()
    context.setStrokeColor(NSColor.systemRed.withAlphaComponent(0.96).cgColor)
    context.setLineWidth(2.2)
    context.setLineDash(phase: 0, lengths: [8, 5])
    context.stroke(selection.insetBy(dx: -0.5, dy: -0.5))
    context.setLineDash(phase: 0, lengths: [])
    context.restoreGState()
  }

  func drawSelectingOverlay(in context: CGContext) {
    let activeSelection = selectionRect() ?? committedSelectionRect
    if activeSelection == nil, let smartWindowHoverRect {
      drawWindowCaptureHighlight(
        in: context,
        targetRect: smartWindowHoverRect.standardized.integral,
        active: true
      )
      return
    }

    let dimPath = CGMutablePath()
    dimPath.addRect(bounds)
    if let activeSelection {
      dimPath.addRect(activeSelection)
    }

    context.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor)
    context.addPath(dimPath)
    context.drawPath(using: .eoFill)

    guard let selection = activeSelection else {
      return
    }

    context.setStrokeColor(NSColor.white.withAlphaComponent(0.92).cgColor)
    context.setLineWidth(1.6)
    context.setLineDash(phase: 0, lengths: [6, 4])
    context.stroke(selection)
    context.setLineDash(phase: 0, lengths: [])

    drawSelectionSize(selection)
    drawSelectionCornerGuides(in: context, selection: selection, alpha: 0.96)
  }

  func selectionRect() -> CGRect? {
    guard let dragStart, let dragCurrent else {
      return nil
    }

    let raw = CGRect(
      x: min(dragStart.x, dragCurrent.x),
      y: min(dragStart.y, dragCurrent.y),
      width: abs(dragCurrent.x - dragStart.x),
      height: abs(dragCurrent.y - dragStart.y)
    )

    if raw.width < 2 || raw.height < 2 {
      return nil
    }

    return raw.intersection(bounds).integral
  }

  func drawSelectionSize(_ selection: CGRect) {
    let sizeText = "\(Int(selection.width)) × \(Int(selection.height))"
    let textAttributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
      .foregroundColor: NSColor.white,
    ]
    let attributedSizeText = NSAttributedString(string: sizeText, attributes: textAttributes)
    let textSize = attributedSizeText.size()
    let backgroundPadding: CGFloat = 6
    var originX = selection.minX
    var originY = selection.maxY + 8
    if originY + textSize.height + backgroundPadding * 2 > bounds.maxY {
      originY = selection.minY - textSize.height - backgroundPadding * 2 - 8
    }
    originX = min(max(8, originX), bounds.maxX - textSize.width - backgroundPadding * 2 - 8)

    let backgroundRect = CGRect(
      x: originX,
      y: originY,
      width: textSize.width + backgroundPadding * 2,
      height: textSize.height + backgroundPadding * 2
    )

    NSColor.black.withAlphaComponent(0.62).setFill()
    NSBezierPath(roundedRect: backgroundRect, xRadius: 6, yRadius: 6).fill()

    attributedSizeText.draw(
      at: CGPoint(x: backgroundRect.minX + backgroundPadding, y: backgroundRect.minY + backgroundPadding),
    )
  }

  func drawSelectionCornerGuides(
    in context: CGContext,
    selection: CGRect,
    alpha: CGFloat
  ) {
    let displayScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    let pixel = 1.0 / max(displayScale, 1)
    func snapped(_ value: CGFloat) -> CGFloat {
      (value * displayScale).rounded() / displayScale
    }

    let snappedSelection = CGRect(
      x: snapped(selection.minX),
      y: snapped(selection.minY),
      width: snapped(selection.width),
      height: snapped(selection.height)
    )
    let points = selectionHandlePoints(for: snappedSelection)
    let cornerRadius: CGFloat = 4.9
    let edgeRadius: CGFloat = 4.3

    context.saveGState()
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)

    func drawHandle(at point: CGPoint, radius: CGFloat) {
      let diameter = radius * 2
      let rect = CGRect(
        x: snapped(point.x - radius),
        y: snapped(point.y - radius),
        width: diameter,
        height: diameter
      )

      context.setFillColor(NSColor.black.withAlphaComponent(0.76 * alpha).cgColor)
      context.fillEllipse(in: rect)
      context.setStrokeColor(NSColor.white.withAlphaComponent(alpha).cgColor)
      context.setLineWidth(max(1.0, pixel + 0.45))
      context.strokeEllipse(in: rect.insetBy(dx: pixel * 0.35, dy: pixel * 0.35))
    }

    for (corner, point) in points {
      drawHandle(at: point, radius: corner.isCorner ? cornerRadius : edgeRadius)
    }

    context.restoreGState()
  }
}
