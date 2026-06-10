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

enum AnnotationCommand {
  case rect(CGRect, NSColor, CGFloat, Bool)
  case ellipse(CGRect, NSColor, CGFloat, Bool)
  case line(CGPoint, CGPoint, NSColor, CGFloat)
  case path([CGPoint], NSColor, CGFloat)
  case arrow(CGPoint, CGPoint, NSColor, CGFloat, CGFloat)
  case text(String, CGPoint, TextAnnotationStyle)
  case pixelate(CGRect)
  case blur(CGRect)

  var bounds: CGRect {
    switch self {
    case .rect(let rect, _, _, _), .ellipse(let rect, _, _, _), .pixelate(let rect), .blur(let rect):
      return rect.standardized
    case .line(let start, let end, _, let width):
      return CGRect(
        x: min(start.x, end.x) - width,
        y: min(start.y, end.y) - width,
        width: abs(end.x - start.x) + width * 2,
        height: abs(end.y - start.y) + width * 2
      )
    case .arrow(let start, let end, _, let width, let minimumHeadLength):
      let points = [start, end] + {
        guard let (left, right) = AnnotationArrowGeometry.headPoints(
          start: start,
          end: end,
          strokeWidth: width,
          minimumHeadLength: minimumHeadLength
        ) else {
          return []
        }
        return [left, right]
      }()
      let xs = points.map(\.x)
      let ys = points.map(\.y)
      guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else {
        return .zero
      }
      return CGRect(x: minX - width, y: minY - width, width: maxX - minX + width * 2, height: maxY - minY + width * 2)
    case .path(let points, _, let width):
      let xs = points.map(\.x)
      let ys = points.map(\.y)
      guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else {
        return .zero
      }
      return CGRect(x: minX - width, y: minY - width, width: maxX - minX + width * 2, height: maxY - minY + width * 2)
    case .text(let text, let point, let style):
      let width = max(24, CGFloat(text.count) * style.fontSize * 0.58)
      return CGRect(x: point.x, y: point.y, width: width, height: style.fontSize * 1.35)
    }
  }

  mutating func move(by delta: CGPoint) {
    switch self {
    case .rect(let rect, let color, let width, let filled):
      self = .rect(rect.offsetBy(dx: delta.x, dy: delta.y), color, width, filled)
    case .ellipse(let rect, let color, let width, let filled):
      self = .ellipse(rect.offsetBy(dx: delta.x, dy: delta.y), color, width, filled)
    case .line(let start, let end, let color, let width):
      self = .line(start.offset(by: delta), end.offset(by: delta), color, width)
    case .path(let points, let color, let width):
      self = .path(points.map { $0.offset(by: delta) }, color, width)
    case .arrow(let start, let end, let color, let width, let minimumHeadLength):
      self = .arrow(start.offset(by: delta), end.offset(by: delta), color, width, minimumHeadLength)
    case .text(let text, let point, let style):
      self = .text(text, point.offset(by: delta), style)
    case .pixelate(let rect):
      self = .pixelate(rect.offsetBy(dx: delta.x, dy: delta.y))
    case .blur(let rect):
      self = .blur(rect.offsetBy(dx: delta.x, dy: delta.y))
    }
  }

  mutating func resize(to rect: CGRect) {
    switch self {
    case .rect(_, let color, let width, let filled):
      self = .rect(rect, color, width, filled)
    case .ellipse(_, let color, let width, let filled):
      self = .ellipse(rect, color, width, filled)
    case .pixelate:
      self = .pixelate(rect)
    case .blur:
      self = .blur(rect)
    default:
      break
    }
  }
}

private extension CGPoint {
  func offset(by delta: CGPoint) -> CGPoint {
    CGPoint(x: x + delta.x, y: y + delta.y)
  }
}
