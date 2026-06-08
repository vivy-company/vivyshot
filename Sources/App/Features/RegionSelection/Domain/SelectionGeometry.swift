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
      cornerCode: resizeCornerCode(corner),
      delta: delta,
      minWidth: minWidth,
      minHeight: minHeight
    )
  }

  private static func resizeCornerCode(_ corner: ResizeCorner) -> UInt8 {
    switch corner {
    case .topLeft:
      return 0
    case .top:
      return 1
    case .topRight:
      return 2
    case .right:
      return 3
    case .bottom:
      return 4
    case .left:
      return 5
    case .bottomLeft:
      return 6
    case .bottomRight:
      return 7
    }
  }
}
