import CoreGraphics

enum SelectionGeometry {
  static func moveRect(current: CGRect, bounds: CGRect, delta: CGPoint) -> CGRect? {
    let rect = current.standardized
    let x = min(max(bounds.minX, rect.minX + delta.x), bounds.maxX - rect.width)
    let y = min(max(bounds.minY, rect.minY + delta.y), bounds.maxY - rect.height)
    return CGRect(x: x, y: y, width: rect.width, height: rect.height).standardized
  }

  static func resizeRect(
    start: CGRect,
    bounds: CGRect,
    corner: ResizeCorner,
    delta: CGPoint,
    minWidth: CGFloat = 80,
    minHeight: CGFloat = 60
  ) -> CGRect? {
    ResizableRect.resizeRect(
      start: start,
      bounds: bounds,
      edge: resizeEdge(corner),
      delta: delta,
      minWidth: minWidth,
      minHeight: minHeight
    )
  }

  private static func resizeEdge(_ corner: ResizeCorner) -> ResizeEdge {
    switch corner {
    case .topLeft:
      return .topLeft
    case .top:
      return .top
    case .topRight:
      return .topRight
    case .right:
      return .right
    case .bottom:
      return .bottom
    case .left:
      return .left
    case .bottomLeft:
      return .bottomLeft
    case .bottomRight:
      return .bottomRight
    }
  }
}
