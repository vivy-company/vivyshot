import CoreGraphics

enum ResizeEdge {
  case topLeft
  case top
  case topRight
  case right
  case bottom
  case left
  case bottomLeft
  case bottomRight
}

/// Shared rectangle-resize primitive used by selection and annotation handles.
enum ResizableRect {
  /// Applies a drag delta from a resize edge, then clamps the result inside bounds and minimum size.
  static func resizeRect(start: CGRect, bounds: CGRect, edge: ResizeEdge, delta: CGPoint, minWidth: CGFloat, minHeight: CGFloat) -> CGRect? {
    guard delta.x.isFinite, delta.y.isFinite, minWidth.isFinite, minHeight.isFinite, minWidth > 0, minHeight > 0 else {
      return nil
    }
    let start = start.standardized
    let bounds = bounds.standardized
    var minX = start.minX
    var maxX = start.maxX
    var minY = start.minY
    var maxY = start.maxY

    switch edge {
    case .topLeft:
      minX += delta.x; maxY += delta.y
    case .top:
      maxY += delta.y
    case .topRight:
      maxX += delta.x; maxY += delta.y
    case .right:
      maxX += delta.x
    case .bottom:
      minY += delta.y
    case .left:
      minX += delta.x
    case .bottomLeft:
      minX += delta.x; minY += delta.y
    case .bottomRight:
      maxX += delta.x; minY += delta.y
    }

    switch edge {
    case .topLeft:
      minX = min(minX, maxX - minWidth); maxY = max(maxY, minY + minHeight)
    case .top:
      maxY = max(maxY, minY + minHeight)
    case .topRight:
      maxX = max(maxX, minX + minWidth); maxY = max(maxY, minY + minHeight)
    case .right:
      maxX = max(maxX, minX + minWidth)
    case .bottom:
      minY = min(minY, maxY - minHeight)
    case .left:
      minX = min(minX, maxX - minWidth)
    case .bottomLeft:
      minX = min(minX, maxX - minWidth); minY = min(minY, maxY - minHeight)
    case .bottomRight:
      maxX = max(maxX, minX + minWidth); minY = min(minY, maxY - minHeight)
    }

    minX = max(minX, bounds.minX)
    maxX = min(maxX, bounds.maxX)
    minY = max(minY, bounds.minY)
    maxY = min(maxY, bounds.maxY)

    let width = maxX - minX
    let height = maxY - minY
    guard width >= minWidth, height >= minHeight else {
      return nil
    }
    return CGRect(x: minX, y: minY, width: width, height: height)
  }
}
