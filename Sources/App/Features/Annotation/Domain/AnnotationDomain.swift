import AppKit
import CoreGraphics

/// Text styling captured when the user places an annotation label.
struct TextAnnotationStyle {
  let fontSize: CGFloat
  let color: NSColor

  static let `default` = TextAnnotationStyle(
    fontSize: 16,
    color: .white
  )
}

/// Lightweight metadata for selecting, moving, resizing, or deleting an annotation.
struct AnnotationInfo {
  let index: Int
  let kind: Int
  let bounds: CGRect

  func contains(_ point: CGPoint) -> Bool {
    let x = point.x
    let y = point.y
    return x >= bounds.minX && x <= bounds.maxX && y >= bounds.minY && y <= bounds.maxY
  }
}

enum AnnotationArrowGeometry {
  static let minimumHeadLength: CGFloat = 16.0

  static func headPoints(
    start: CGPoint,
    end: CGPoint,
    strokeWidth: CGFloat,
    minimumHeadLength: CGFloat = Self.minimumHeadLength
  ) -> (CGPoint, CGPoint)? {
    let dx = end.x - start.x
    let dy = end.y - start.y
    let length = hypot(dx, dy)
    guard length > 0.5 else {
      return nil
    }

    let ux = dx / length
    let uy = dy / length
    let headLength = max(minimumHeadLength, strokeWidth * 6.0)
    let angle: CGFloat = .pi / 6.0
    let cosA = cos(angle)
    let sinA = sin(angle)

    let rx1 = ux * cosA - uy * sinA
    let ry1 = ux * sinA + uy * cosA
    let rx2 = ux * cosA + uy * sinA
    let ry2 = -ux * sinA + uy * cosA

    return (
      CGPoint(x: end.x - rx1 * headLength, y: end.y - ry1 * headLength),
      CGPoint(x: end.x - rx2 * headLength, y: end.y - ry2 * headLength)
    )
  }
}
