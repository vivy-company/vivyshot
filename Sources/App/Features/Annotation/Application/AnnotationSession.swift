import AppKit
import CoreGraphics
import CoreText
import Foundation

/// Command-based annotation renderer with undo and redo for one screenshot image.
final class AnnotationSession {
  private let baseImage: CGImage
  private var commands: [Command] = []
  private var undone: [Command] = []
  private var renderedImage: CGImage

  init?(image: CGImage) {
    baseImage = image
    renderedImage = image
  }

  func currentImage() -> CGImage? {
    renderedImage
  }

  func addRect(imageRect: CGRect, color: NSColor = .systemOrange, strokeWidth: UInt32 = 4) -> CGImage? {
    append(.rect(imageRect.standardized, color, CGFloat(strokeWidth), false))
  }

  func addFilledRect(imageRect: CGRect, color: NSColor = .systemOrange) -> CGImage? {
    append(.rect(imageRect.standardized, color, 1, true))
  }

  func addCircle(imageRect: CGRect, color: NSColor = .systemOrange, strokeWidth: UInt32 = 4) -> CGImage? {
    append(.ellipse(imageRect.standardized, color, CGFloat(strokeWidth), false))
  }

  func addFilledCircle(imageRect: CGRect, color: NSColor = .systemOrange) -> CGImage? {
    append(.ellipse(imageRect.standardized, color, 1, true))
  }

  func addLine(from start: CGPoint, to end: CGPoint, color: NSColor = .systemOrange, strokeWidth: UInt32 = 4) -> CGImage? {
    append(.line(start, end, color, CGFloat(strokeWidth)))
  }

  func addPath(_ points: [CGPoint], color: NSColor = .systemOrange, strokeWidth: UInt32 = 6) -> CGImage? {
    guard !points.isEmpty else {
      return currentImage()
    }
    return append(.path(points, color, CGFloat(strokeWidth)))
  }

  func addArrow(from start: CGPoint, to end: CGPoint, color: NSColor = .systemOrange, strokeWidth: UInt32 = 5) -> CGImage? {
    append(.arrow(start, end, color, CGFloat(strokeWidth)))
  }

  func addText(_ text: String, at point: CGPoint, style: TextAnnotationStyle) -> CGImage? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return currentImage()
    }
    return append(.text(trimmed, point, style))
  }

  func addPixelate(imageRect: CGRect) -> CGImage? {
    append(.effect(imageRect.standardized, NSColor.black.withAlphaComponent(0.18)))
  }

  func addBlur(imageRect: CGRect) -> CGImage? {
    append(.effect(imageRect.standardized, NSColor.white.withAlphaComponent(0.14)))
  }

  func undo() -> CGImage? {
    guard let command = commands.popLast() else {
      return currentImage()
    }
    undone.append(command)
    return render()
  }

  func redo() -> CGImage? {
    guard let command = undone.popLast() else {
      return currentImage()
    }
    commands.append(command)
    return render()
  }

  func listAnnotations() -> [AnnotationInfo] {
    commands.enumerated().map { index, command in
      AnnotationInfo(index: index, kind: command.kind, bounds: command.bounds)
    }
  }

  func hitTestAnnotation(at point: CGPoint) -> AnnotationInfo? {
    listAnnotations().reversed().first { $0.contains(point) }
  }

  func annotationInfo(index: Int) -> AnnotationInfo? {
    guard commands.indices.contains(index) else {
      return nil
    }
    return AnnotationInfo(index: index, kind: commands[index].kind, bounds: commands[index].bounds)
  }

  func moveAnnotation(index: Int, delta: CGPoint) -> CGImage? {
    guard commands.indices.contains(index) else {
      return nil
    }
    commands[index].move(by: delta)
    return render()
  }

  func removeAnnotation(index: Int) -> CGImage? {
    guard commands.indices.contains(index) else {
      return nil
    }
    commands.remove(at: index)
    undone.removeAll()
    return render()
  }

  func resizeAnnotation(index: Int, imageRect: CGRect) -> CGImage? {
    guard commands.indices.contains(index) else {
      return nil
    }
    commands[index].resize(to: imageRect.standardized)
    return render()
  }

  private func append(_ command: Command) -> CGImage? {
    commands.append(command)
    undone.removeAll()
    return render()
  }

  private func render() -> CGImage? {
    guard
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil,
        width: baseImage.width,
        height: baseImage.height,
        bitsPerComponent: 8,
        bytesPerRow: baseImage.width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else {
      return nil
    }
    context.interpolationQuality = .high
    context.draw(baseImage, in: CGRect(x: 0, y: 0, width: baseImage.width, height: baseImage.height))
    for command in commands {
      command.draw(in: context)
    }
    guard let image = context.makeImage() else {
      return nil
    }
    renderedImage = image
    return image
  }
}

private enum Command {
  case rect(CGRect, NSColor, CGFloat, Bool)
  case ellipse(CGRect, NSColor, CGFloat, Bool)
  case line(CGPoint, CGPoint, NSColor, CGFloat)
  case path([CGPoint], NSColor, CGFloat)
  case arrow(CGPoint, CGPoint, NSColor, CGFloat)
  case text(String, CGPoint, TextAnnotationStyle)
  case effect(CGRect, NSColor)

  var kind: Int {
    switch self {
    case .rect: return 1
    case .ellipse: return 2
    case .line: return 3
    case .path: return 4
    case .arrow: return 5
    case .text: return 6
    case .effect: return 7
    }
  }

  var bounds: CGRect {
    switch self {
    case .rect(let rect, _, _, _), .ellipse(let rect, _, _, _), .effect(let rect, _):
      return rect.standardized
    case .line(let start, let end, _, let width), .arrow(let start, let end, _, let width):
      return CGRect(
        x: min(start.x, end.x) - width,
        y: min(start.y, end.y) - width,
        width: abs(end.x - start.x) + width * 2,
        height: abs(end.y - start.y) + width * 2
      )
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

  func draw(in context: CGContext) {
    switch self {
    case .rect(let rect, let color, let width, let filled):
      context.setStrokeColor(color.cgColor)
      context.setFillColor(color.cgColor)
      context.setLineWidth(max(1, width))
      filled ? context.fill(rect) : context.stroke(rect)
    case .ellipse(let rect, let color, let width, let filled):
      context.setStrokeColor(color.cgColor)
      context.setFillColor(color.cgColor)
      context.setLineWidth(max(1, width))
      filled ? context.fillEllipse(in: rect) : context.strokeEllipse(in: rect)
    case .line(let start, let end, let color, let width):
      context.setStrokeColor(color.cgColor)
      context.setLineCap(.round)
      context.setLineJoin(.round)
      context.setLineWidth(max(1, width))
      context.move(to: start)
      context.addLine(to: end)
      context.strokePath()
    case .path(let points, let color, let width):
      guard let first = points.first else { return }
      context.setStrokeColor(color.cgColor)
      context.setLineCap(.round)
      context.setLineJoin(.round)
      context.setLineWidth(max(1, width))
      context.move(to: first)
      for point in points.dropFirst() {
        context.addLine(to: point)
      }
      context.strokePath()
    case .arrow(let start, let end, let color, let width):
      Command.line(start, end, color, width).draw(in: context)
      let angle = atan2(end.y - start.y, end.x - start.x)
      let length = max(width * 4, 14)
      let left = CGPoint(x: end.x - cos(angle - .pi / 6) * length, y: end.y - sin(angle - .pi / 6) * length)
      let right = CGPoint(x: end.x - cos(angle + .pi / 6) * length, y: end.y - sin(angle + .pi / 6) * length)
      context.setFillColor(color.cgColor)
      context.beginPath()
      context.move(to: end)
      context.addLine(to: left)
      context.addLine(to: right)
      context.closePath()
      context.fillPath()
    case .text(let text, let point, let style):
      let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: style.fontSize, weight: .semibold),
        .foregroundColor: style.color
      ]
      let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
      context.saveGState()
      context.textPosition = point
      CTLineDraw(line, context)
      context.restoreGState()
    case .effect(let rect, let color):
      context.setFillColor(color.cgColor)
      context.fill(rect)
    }
  }

  mutating func move(by delta: CGPoint) {
    switch self {
    case .rect(let rect, let color, let width, let filled):
      self = .rect(rect.offsetBy(dx: delta.x, dy: delta.y), color, width, filled)
    case .ellipse(let rect, let color, let width, let filled):
      self = .ellipse(rect.offsetBy(dx: delta.x, dy: delta.y), color, width, filled)
    case .line(let start, let end, let color, let width):
      self = .line(start + delta, end + delta, color, width)
    case .path(let points, let color, let width):
      self = .path(points.map { $0 + delta }, color, width)
    case .arrow(let start, let end, let color, let width):
      self = .arrow(start + delta, end + delta, color, width)
    case .text(let text, let point, let style):
      self = .text(text, point + delta, style)
    case .effect(let rect, let color):
      self = .effect(rect.offsetBy(dx: delta.x, dy: delta.y), color)
    }
  }

  mutating func resize(to rect: CGRect) {
    switch self {
    case .rect(_, let color, let width, let filled):
      self = .rect(rect, color, width, filled)
    case .ellipse(_, let color, let width, let filled):
      self = .ellipse(rect, color, width, filled)
    case .effect(_, let color):
      self = .effect(rect, color)
    default:
      break
    }
  }
}

private func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
  CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
}
