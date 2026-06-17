import AppKit
import CoreGraphics
import CoreText
import Foundation

/// Command-based annotation renderer with undo and redo for one screenshot image.
final class AnnotationSession {
  private let baseImage: CGImage
  private var commands: [AnnotationCommand] = []
  private var undone: [AnnotationCommand] = []
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

  func addArrow(
    from start: CGPoint,
    to end: CGPoint,
    color: NSColor = .systemOrange,
    strokeWidth: UInt32 = 5,
    minimumHeadLength: CGFloat = AnnotationArrowGeometry.minimumHeadLength
  ) -> CGImage? {
    append(.arrow(start, end, color, CGFloat(strokeWidth), minimumHeadLength))
  }

  func addText(_ text: String, at point: CGPoint, style: TextAnnotationStyle) -> CGImage? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return currentImage()
    }
    return append(.text(trimmed, point, style))
  }

  func addPixelate(imageRect: CGRect) -> CGImage? {
    append(.pixelate(imageRect.standardized))
  }

  func addBlur(imageRect: CGRect) -> CGImage? {
    append(.blur(imageRect.standardized))
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
      AnnotationInfo(index: index, bounds: command.bounds)
    }
  }

  func hitTestAnnotation(at point: CGPoint) -> AnnotationInfo? {
    listAnnotations().reversed().first { $0.contains(point) }
  }

  func annotationInfo(index: Int) -> AnnotationInfo? {
    guard commands.indices.contains(index) else {
      return nil
    }
    return AnnotationInfo(index: index, bounds: commands[index].bounds)
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

  private func append(_ command: AnnotationCommand) -> CGImage? {
    commands.append(command)
    undone.removeAll()
    return render()
  }

  private func render() -> CGImage? {
    guard var context = makeContext(drawing: baseImage) else {
      return nil
    }

    for command in commands {
      switch command {
      case .pixelate(let rect):
        guard
          let image = context.makeImage(),
          let pixelated = ImageRegionEffect.pixelate(image, rect: rect)
        else {
          return nil
        }
        guard let nextContext = makeContext(drawing: pixelated) else {
          return nil
        }
        context = nextContext
      case .blur(let rect):
        guard
          let image = context.makeImage(),
          let blurred = ImageRegionEffect.blur(image, rect: rect)
        else {
          return nil
        }
        guard let nextContext = makeContext(drawing: blurred) else {
          return nil
        }
        context = nextContext
      default:
        command.draw(in: context)
      }
    }
    guard let image = context.makeImage() else {
      return nil
    }
    renderedImage = image
    return image
  }

  private func makeContext(drawing image: CGImage) -> CGContext? {
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
      data: nil,
      width: baseImage.width,
      height: baseImage.height,
      bitsPerComponent: 8,
      bytesPerRow: baseImage.width * 4,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
      return nil
    }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    context.translateBy(x: 0, y: CGFloat(image.height))
    context.scaleBy(x: 1, y: -1)
    return context
  }
}

private extension AnnotationCommand {
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
      Self.strokeLine(from: start, to: end, color: color, width: width, in: context)
    case .path(let points, let color, let width):
      guard let first = points.first else { return }
      Self.configureStroke(color: color, width: width, in: context)
      context.move(to: first)
      for point in points.dropFirst() {
        context.addLine(to: point)
      }
      context.strokePath()
    case .arrow(let start, let end, let color, let width, let minimumHeadLength):
      Self.strokeLine(from: start, to: end, color: color, width: width, in: context)
      guard let (left, right) = AnnotationArrowGeometry.headPoints(
        start: start,
        end: end,
        strokeWidth: width,
        minimumHeadLength: minimumHeadLength
      ) else {
        return
      }
      Self.configureStroke(color: color, width: width, in: context)
      context.move(to: end)
      context.addLine(to: left)
      context.move(to: end)
      context.addLine(to: right)
      context.strokePath()
    case .text(let text, let point, let style):
      let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: style.fontSize, weight: .semibold),
        .foregroundColor: style.color
      ]
      let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
      var ascent: CGFloat = 0
      CTLineGetTypographicBounds(line, &ascent, nil, nil)
      context.saveGState()
      context.translateBy(x: point.x, y: point.y + ascent)
      context.scaleBy(x: 1, y: -1)
      context.textMatrix = .identity
      context.textPosition = .zero
      CTLineDraw(line, context)
      context.restoreGState()
    case .pixelate, .blur:
      break
    }
  }

  private static func strokeLine(from start: CGPoint, to end: CGPoint, color: NSColor, width: CGFloat, in context: CGContext) {
    configureStroke(color: color, width: width, in: context)
    context.move(to: start)
    context.addLine(to: end)
    context.strokePath()
  }

  private static func configureStroke(color: NSColor, width: CGFloat, in context: CGContext) {
    context.setStrokeColor(color.cgColor)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.setLineWidth(max(1, width))
  }
}
