import CoreGraphics

/// Shared rectangle-resize primitive used by selection and annotation handles.
enum ResizableRect {
  private enum CornerCode {
    static let topLeft: UInt8 = 0
    static let top: UInt8 = 1
    static let topRight: UInt8 = 2
    static let right: UInt8 = 3
    static let bottom: UInt8 = 4
    static let left: UInt8 = 5
    static let bottomLeft: UInt8 = 6
    static let bottomRight: UInt8 = 7
  }

  /// Applies a drag delta from a handle code, then clamps the result inside bounds and minimum size.
  static func resizeRect(start: CGRect, bounds: CGRect, cornerCode: UInt8, delta: CGPoint, minWidth: CGFloat, minHeight: CGFloat) -> CGRect? {
    guard delta.x.isFinite, delta.y.isFinite, minWidth.isFinite, minHeight.isFinite, minWidth > 0, minHeight > 0 else {
      return nil
    }
    let start = start.standardized
    let bounds = bounds.standardized
    var minX = start.minX
    var maxX = start.maxX
    var minY = start.minY
    var maxY = start.maxY

    switch cornerCode {
    case CornerCode.topLeft:
      minX += delta.x; maxY += delta.y
    case CornerCode.top:
      maxY += delta.y
    case CornerCode.topRight:
      maxX += delta.x; maxY += delta.y
    case CornerCode.right:
      maxX += delta.x
    case CornerCode.bottom:
      minY += delta.y
    case CornerCode.left:
      minX += delta.x
    case CornerCode.bottomLeft:
      minX += delta.x; minY += delta.y
    case CornerCode.bottomRight:
      maxX += delta.x; minY += delta.y
    default:
      break
    }

    switch cornerCode {
    case CornerCode.topLeft:
      minX = min(minX, maxX - minWidth); maxY = max(maxY, minY + minHeight)
    case CornerCode.top:
      maxY = max(maxY, minY + minHeight)
    case CornerCode.topRight:
      maxX = max(maxX, minX + minWidth); maxY = max(maxY, minY + minHeight)
    case CornerCode.right:
      maxX = max(maxX, minX + minWidth)
    case CornerCode.bottom:
      minY = min(minY, maxY - minHeight)
    case CornerCode.left:
      minX = min(minX, maxX - minWidth)
    case CornerCode.bottomLeft:
      minX = min(minX, maxX - minWidth); minY = min(minY, maxY - minHeight)
    case CornerCode.bottomRight:
      maxX = max(maxX, minX + minWidth); minY = min(minY, maxY - minHeight)
    default:
      break
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
