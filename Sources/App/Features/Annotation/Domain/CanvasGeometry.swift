import CoreGraphics

enum CanvasGeometry {
  static func viewRectToImageRect(viewRect: CGRect, destinationRect: CGRect, imageSize: CGSize) -> CGRect? {
    guard imageSize.width >= 1, imageSize.height >= 1, destinationRect.width > 0, destinationRect.height > 0 else {
      return nil
    }
    let clipped = viewRect.standardized.intersection(destinationRect.standardized)
    guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else {
      return nil
    }
    let scaleX = imageSize.width / destinationRect.width
    let scaleY = imageSize.height / destinationRect.height
    let y0FromBottom = (clipped.minY - destinationRect.minY) * scaleY
    let y1FromBottom = (clipped.maxY - destinationRect.minY) * scaleY
    return CGRect(
      x: (clipped.minX - destinationRect.minX) * scaleX,
      y: imageSize.height - y1FromBottom,
      width: clipped.width * scaleX,
      height: y1FromBottom - y0FromBottom
    ).integral
  }

  static func imageRectToViewRect(imageRect: CGRect, destinationRect: CGRect, imageSize: CGSize) -> CGRect? {
    guard imageSize.width >= 1, imageSize.height >= 1 else {
      return nil
    }
    let imageRect = imageRect.standardized
    let scaleX = destinationRect.width / imageSize.width
    let scaleY = destinationRect.height / imageSize.height
    let yTop = destinationRect.minY + (imageSize.height - imageRect.minY) * scaleY
    let yBottom = destinationRect.minY + (imageSize.height - imageRect.maxY) * scaleY
    return CGRect(
      x: destinationRect.minX + imageRect.minX * scaleX,
      y: min(yBottom, yTop),
      width: imageRect.width * scaleX,
      height: abs(yTop - yBottom)
    ).integral
  }

  static func viewDeltaToImageDelta(_ delta: CGPoint, destinationRect: CGRect, imageSize: CGSize) -> CGPoint? {
    guard imageSize.width >= 1, imageSize.height >= 1, destinationRect.width > 0, destinationRect.height > 0 else {
      return nil
    }
    return CGPoint(
      x: delta.x / destinationRect.width * imageSize.width,
      y: -delta.y / destinationRect.height * imageSize.height
    )
  }

  static func imageDeltaToViewDelta(_ delta: CGPoint, destinationRect: CGRect, imageSize: CGSize) -> CGPoint? {
    guard imageSize.width >= 1, imageSize.height >= 1 else {
      return nil
    }
    return CGPoint(
      x: delta.x / imageSize.width * destinationRect.width,
      y: -delta.y / imageSize.height * destinationRect.height
    )
  }

  static func clampPanOffset(boundsSize: CGSize, imageSize: CGSize, zoomScale: CGFloat, overscroll: CGFloat, candidate: CGPoint) -> CGPoint? {
    guard imageSize.width >= 1, imageSize.height >= 1 else {
      return nil
    }
    guard boundsSize.width > 0, boundsSize.height > 0, zoomScale > 0 else {
      return nil
    }
    let fitScale = min(boundsSize.width / imageSize.width, boundsSize.height / imageSize.height)
    let drawScale = fitScale * zoomScale
    let drawWidth = imageSize.width * drawScale
    let drawHeight = imageSize.height * drawScale
    let maxX = max(0, (drawWidth - boundsSize.width) * 0.5 + overscroll)
    let maxY = max(0, (drawHeight - boundsSize.height) * 0.5 + overscroll)
    return CGPoint(x: min(max(-maxX, candidate.x), maxX), y: min(max(-maxY, candidate.y), maxY))
  }

  static func resizeRect(start: CGRect, bounds: CGRect, cornerCode: UInt8, delta: CGPoint, minWidth: CGFloat, minHeight: CGFloat) -> CGRect? {
    ResizableRect.resizeRect(
      start: start,
      bounds: bounds,
      cornerCode: cornerCode,
      delta: delta,
      minWidth: minWidth,
      minHeight: minHeight
    )
  }
}
