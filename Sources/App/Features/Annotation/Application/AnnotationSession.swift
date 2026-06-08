import AppKit
import CoreGraphics
import CoreImage
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

private enum Command {
  case rect(CGRect, NSColor, CGFloat, Bool)
  case ellipse(CGRect, NSColor, CGFloat, Bool)
  case line(CGPoint, CGPoint, NSColor, CGFloat)
  case path([CGPoint], NSColor, CGFloat)
  case arrow(CGPoint, CGPoint, NSColor, CGFloat)
  case text(String, CGPoint, TextAnnotationStyle)
  case pixelate(CGRect)
  case blur(CGRect)

  var kind: Int {
    switch self {
    case .rect(_, _, _, let filled): return filled ? 2 : 1
    case .ellipse(_, _, _, let filled): return filled ? 4 : 3
    case .line: return 5
    case .arrow: return 6
    case .path: return 7
    case .text: return 8
    case .pixelate: return 9
    case .blur: return 10
    }
  }

  var bounds: CGRect {
    switch self {
    case .rect(let rect, _, _, _), .ellipse(let rect, _, _, _), .pixelate(let rect), .blur(let rect):
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
    case .pixelate, .blur:
      break
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

private enum ImageRegionEffect {
  private static let pixelateBlockSize = 12
  private static let blurRadius = 4
  private static let context = CIContext()

  static func pixelate(_ image: CGImage, rect: CGRect) -> CGImage? {
    apply(to: image, rect: rect) { input, region in
      input
        .cropped(to: region)
        .applyingFilter("CIPixellate", parameters: [
          kCIInputScaleKey: pixelateBlockSize,
          kCIInputCenterKey: CIVector(x: region.midX, y: region.midY)
        ])
        .cropped(to: region)
    }
  }

  static func blur(_ image: CGImage, rect: CGRect) -> CGImage? {
    apply(to: image, rect: rect) { input, region in
      let sample = region
        .insetBy(dx: -CGFloat(blurRadius), dy: -CGFloat(blurRadius))
        .intersection(input.extent)

      return input
        .cropped(to: sample)
        .clampedToExtent()
        .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: blurRadius])
        .cropped(to: region)
    }
  }

  private static func apply(
    to image: CGImage,
    rect: CGRect,
    effect: (CIImage, CGRect) -> CIImage?
  ) -> CGImage? {
    let input = CIImage(cgImage: image)
    let region = coreImageRect(fromTopLeftImageRect: rect, imageHeight: image.height).intersection(input.extent)
    guard !region.isNull, !region.isEmpty, let filteredRegion = effect(input, region) else {
      return nil
    }

    let output = filteredRegion.composited(over: input)
    return context.createCGImage(output, from: input.extent)
  }

  private static func coreImageRect(fromTopLeftImageRect rect: CGRect, imageHeight: Int) -> CGRect {
    let standardized = rect.standardized
    return CGRect(
      x: standardized.minX.rounded(.down),
      y: CGFloat(imageHeight) - standardized.maxY.rounded(.up),
      width: standardized.width.rounded(.up),
      height: standardized.height.rounded(.up)
    )
  }
}

private func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
  CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
}
