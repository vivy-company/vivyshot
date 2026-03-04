import AppKit
import CoreGraphics

@MainActor
extension AnnotationCanvasView {
  func dragLineInView() -> (CGPoint, CGPoint)? {
    guard let start = dragStart, let end = dragCurrent else {
      return nil
    }

    let distance = hypot(end.x - start.x, end.y - start.y)
    guard distance >= 2 else {
      return nil
    }

    return (start, end)
  }

  func dragRectInView() -> CGRect? {
    guard let dragStart, let dragCurrent else {
      return nil
    }

    let raw = CGRect(
      x: min(dragStart.x, dragCurrent.x),
      y: min(dragStart.y, dragCurrent.y),
      width: abs(dragCurrent.x - dragStart.x),
      height: abs(dragCurrent.y - dragStart.y)
    )

    guard raw.width >= 2, raw.height >= 2 else {
      return nil
    }

    guard let imageRect = imageDestinationRect() else {
      return nil
    }

    let clipped = raw.intersection(imageRect)
    guard !clipped.isNull, clipped.width >= 2, clipped.height >= 2 else {
      return nil
    }

    return clipped.integral
  }

  func imageRectFromViewRect(_ viewRect: CGRect) -> CGRect? {
    guard let image, let destination = imageDestinationRect() else {
      return nil
    }
    return RustCoreBridge.shared.viewRectToImageRect(
      viewRect: viewRect,
      destinationRect: destination,
      imageSize: CGSize(width: image.width, height: image.height)
    )
  }

  func exportImageRect(fromViewRect viewRect: CGRect) -> CGRect? {
    imageRectFromViewRect(viewRect)
  }

  func viewRectFromImageRect(_ imageRect: CGRect) -> CGRect? {
    guard let image, let destination = imageDestinationRect() else {
      return nil
    }
    return RustCoreBridge.shared.imageRectToViewRect(
      imageRect: imageRect,
      destinationRect: destination,
      imageSize: CGSize(width: image.width, height: image.height)
    )
  }

  func viewDeltaFromImageDelta(_ delta: CGPoint) -> CGPoint? {
    guard let image, let destination = imageDestinationRect() else {
      return nil
    }
    return RustCoreBridge.shared.imageDeltaToViewDelta(
      delta,
      destinationRect: destination,
      imageSize: CGSize(width: image.width, height: image.height)
    )
  }

  func imagePointsFromViewPoints(_ points: [CGPoint]) -> [CGPoint] {
    var output: [CGPoint] = []
    output.reserveCapacity(points.count)

    var last: CGPoint?
    for point in points {
      guard let imagePoint = imagePointFromViewPoint(point) else {
        continue
      }
      if let last, hypot(last.x - imagePoint.x, last.y - imagePoint.y) < 0.1 {
        continue
      }
      output.append(imagePoint)
      last = imagePoint
    }

    return output
  }

  func resizeHandleCenters(for selection: CGRect) -> [AnnotationResizeHandle: CGPoint] {
    [
      .topLeft: CGPoint(x: selection.minX, y: selection.maxY),
      .topRight: CGPoint(x: selection.maxX, y: selection.maxY),
      .bottomLeft: CGPoint(x: selection.minX, y: selection.minY),
      .bottomRight: CGPoint(x: selection.maxX, y: selection.minY),
    ]
  }

  func resizeHandle(at point: CGPoint, in selection: CGRect) -> AnnotationResizeHandle? {
    let hitRadius: CGFloat = 9
    for (handle, center) in resizeHandleCenters(for: selection) {
      if hypot(point.x - center.x, point.y - center.y) <= hitRadius {
        return handle
      }
    }
    return nil
  }

  func resizedAnnotationBounds(
    from start: CGRect,
    handle: AnnotationResizeHandle,
    delta: CGPoint
  ) -> CGRect? {
    guard let imageRect = imageDestinationRect() else {
      return nil
    }
    return RustCoreBridge.shared.resizeRect(
      start: start,
      bounds: imageRect,
      cornerCode: resizeCornerCode(for: handle),
      delta: delta,
      minWidth: 6,
      minHeight: 6
    )?.integral
  }

  func imageSize(of image: CGImage?) -> CGSize? {
    guard let image else {
      return nil
    }
    return CGSize(width: image.width, height: image.height)
  }

  func imageDestinationRect() -> CGRect? {
    guard let image else {
      return nil
    }

    let imageWidth = CGFloat(image.width)
    let imageHeight = CGFloat(image.height)
    guard imageWidth > 0, imageHeight > 0 else {
      return nil
    }

    guard bounds.width > 0, bounds.height > 0 else {
      return nil
    }

    let fitScale = min(bounds.width / imageWidth, bounds.height / imageHeight)
    let drawScale = fitScale * zoomScale
    let drawWidth = imageWidth * drawScale
    let drawHeight = imageHeight * drawScale
    let clampedPan = clampedPanOffset(for: image, zoomScale: zoomScale, candidate: panOffset)

    return CGRect(
      x: bounds.midX - drawWidth * 0.5 + clampedPan.x,
      y: bounds.midY - drawHeight * 0.5 + clampedPan.y,
      width: drawWidth,
      height: drawHeight
    )
  }

  private func clampedPanOffset(for image: CGImage, zoomScale: CGFloat, candidate: CGPoint) -> CGPoint {
    guard bounds.width > 0, bounds.height > 0 else {
      return .zero
    }
    return RustCoreBridge.shared.clampPanOffset(
      boundsSize: bounds.size,
      imageSize: CGSize(width: image.width, height: image.height),
      zoomScale: zoomScale,
      overscroll: 24,
      candidate: candidate
    ) ?? CGPoint(
      x: min(max(candidate.x, -24), 24),
      y: min(max(candidate.y, -24), 24)
    )
  }

  private func resizeCornerCode(for handle: AnnotationResizeHandle) -> UInt8 {
    switch handle {
    case .topLeft:
      return 0
    case .topRight:
      return 2
    case .bottomLeft:
      return 6
    case .bottomRight:
      return 7
    }
  }

  func clampPanOffset() {
    guard let image else {
      if panOffset != .zero {
        panOffset = .zero
      }
      return
    }

    let clamped = clampedPanOffset(for: image, zoomScale: zoomScale, candidate: panOffset)
    if abs(clamped.x - panOffset.x) > 0.001 || abs(clamped.y - panOffset.y) > 0.001 {
      panOffset = clamped
      needsDisplay = true
    }
  }

  func setZoom(_ requestedScale: CGFloat, anchorViewPoint: CGPoint) {
    guard image != nil else {
      return
    }

    let boundedScale = min(max(requestedScale, minZoomScale), maxZoomScale)
    guard abs(boundedScale - zoomScale) > 0.0001 else {
      return
    }

    let anchorImagePoint = imagePointFromViewPoint(anchorViewPoint)
    zoomScale = boundedScale

    if let anchorImagePoint,
       let repositionedAnchor = viewPointFromImagePoint(anchorImagePoint) {
      panOffset.x += anchorViewPoint.x - repositionedAnchor.x
      panOffset.y += anchorViewPoint.y - repositionedAnchor.y
    }

    clampPanOffset()
    needsDisplay = true
    onViewportChanged?()
  }

  func clampedToImageRect(_ point: CGPoint) -> CGPoint {
    guard let imageRect = imageDestinationRect() else {
      return point
    }

    return CGPoint(
      x: min(max(point.x, imageRect.minX), imageRect.maxX),
      y: min(max(point.y, imageRect.minY), imageRect.maxY)
    )
  }

  func imagePointFromViewPoint(_ point: CGPoint) -> CGPoint? {
    guard let image, let destination = imageDestinationRect() else {
      return nil
    }

    let clamped = CGPoint(
      x: min(max(point.x, destination.minX), destination.maxX),
      y: min(max(point.y, destination.minY), destination.maxY)
    )

    let scaleX = CGFloat(image.width) / destination.width
    let scaleY = CGFloat(image.height) / destination.height
    let imageHeight = CGFloat(image.height)

    let x = (clamped.x - destination.minX) * scaleX
    let yFromBottom = (clamped.y - destination.minY) * scaleY
    let y = imageHeight - yFromBottom
    return CGPoint(x: x, y: y)
  }

  func viewPointFromImagePoint(_ imagePoint: CGPoint) -> CGPoint? {
    guard let image, let destination = imageDestinationRect() else {
      return nil
    }

    let scaleX = destination.width / CGFloat(image.width)
    let scaleY = destination.height / CGFloat(image.height)
    guard scaleX > 0, scaleY > 0 else {
      return nil
    }

    let x = destination.minX + imagePoint.x * scaleX
    let yFromBottom = CGFloat(image.height) - imagePoint.y
    let y = destination.minY + yFromBottom * scaleY
    return CGPoint(x: x, y: y)
  }
}
