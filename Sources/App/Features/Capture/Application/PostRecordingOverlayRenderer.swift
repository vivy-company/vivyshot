import AppKit
import CoreGraphics

extension PostRecordingCompositor {
  static func drawWebcamOverlay(
    image: CGImage,
    context: CGContext,
    renderSize: CGSize,
    item: RenderItem
  ) {
    let rect = coreGraphicsRect(fromBottomLeft: item.rect)
    guard rect.width > 0, rect.height > 0 else {
      return
    }
    let shape = WebcamShape(rawValue: Int(item.webcamShapeCode)) ?? .roundedRect
    context.saveGState()
    switch shape {
    case .circle:
      context.addEllipse(in: rect)
    case .roundedRect:
      context.addPath(CGPath(roundedRect: rect, cornerWidth: min(rect.height * 0.18, 18), cornerHeight: min(rect.height * 0.18, 18), transform: nil))
    }
    context.clip()
    context.draw(image, in: aspectFillRect(imageSize: CGSize(width: image.width, height: image.height), targetRect: rect))
    context.restoreGState()

    context.saveGState()
    context.setStrokeColor(NSColor.white.withAlphaComponent(0.55).cgColor)
    context.setLineWidth(max(1, min(renderSize.width, renderSize.height) * 0.0016))
    switch shape {
    case .circle:
      context.strokeEllipse(in: rect.insetBy(dx: 1, dy: 1))
    case .roundedRect:
      context.addPath(CGPath(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerWidth: min(rect.height * 0.18, 18), cornerHeight: min(rect.height * 0.18, 18), transform: nil))
      context.strokePath()
    }
    context.restoreGState()
  }

  static func drawKeystrokeOverlay(
    context: CGContext,
    renderSize: CGSize,
    item: RenderItem
  ) {
    let text = item.text.isEmpty ? "⌘K" : item.text
    var rect = coreGraphicsRect(fromBottomLeft: item.rect).integral
    guard rect.width > 0, rect.height > 0 else {
      return
    }
    let fallbackLayout = OverlayLayout.keyLabel(renderSize: renderSize, charCount: text.count)
    if rect.width <= 4 || rect.height <= 4, let fallbackLayout {
      rect = CGRect(
        x: (renderSize.width - fallbackLayout.width) * 0.5,
        y: fallbackLayout.y,
        width: fallbackLayout.width,
        height: fallbackLayout.height
      ).integral
    }

    let style = KeystrokeStyle(rawValue: Int(item.keystrokeStyleCode)) ?? .compact
    let size = KeystrokeSize(rawValue: Int(item.keystrokeSizeCode)) ?? .medium
    context.saveGState()
    let radius = min(rect.height * 0.5, 22)
    let backgroundPath = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    if style == .glass {
      context.saveGState()
      context.addPath(backgroundPath)
      context.clip()
      let colors = [
        NSColor.white.withAlphaComponent(0.30).cgColor,
        NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor,
        NSColor.black.withAlphaComponent(0.34).cgColor
      ] as CFArray
      let locations: [CGFloat] = [0, 0.45, 1]
      if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations) {
        context.drawLinearGradient(
          gradient,
          start: CGPoint(x: rect.midX, y: rect.maxY),
          end: CGPoint(x: rect.midX, y: rect.minY),
          options: []
        )
      } else {
        context.setFillColor(NSColor.black.withAlphaComponent(0.42).cgColor)
        context.fill(rect)
      }
      context.restoreGState()
    } else {
      context.setFillColor(NSColor.black.withAlphaComponent(0.78).cgColor)
      context.addPath(backgroundPath)
      context.fillPath()
    }

    context.setStrokeColor(NSColor.white.withAlphaComponent(style == .glass ? 0.42 : 0.16).cgColor)
    context.setLineWidth(1)
    context.addPath(CGPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.strokePath()

    let fontScale: CGFloat
    switch size {
    case .small:
      fontScale = 0.30
    case .medium:
      fontScale = 0.36
    case .large:
      fontScale = 0.42
    }
    let fontSize = max(13, min(rect.height * fontScale, rect.width / CGFloat(max(4, text.count)) * 1.8))
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold),
      .foregroundColor: NSColor.white
    ]
    let attributed = NSAttributedString(string: text, attributes: attributes)
    let textSize = attributed.size()
    let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphicsContext
    attributed.draw(
      at: CGPoint(
        x: rect.midX - textSize.width * 0.5,
        y: rect.midY - textSize.height * 0.5
      )
    )
    NSGraphicsContext.restoreGraphicsState()
    context.restoreGState()
  }

  static func drawMouseClickOverlay(
    context: CGContext,
    item: RenderItem
  ) {
    let rect = coreGraphicsRect(fromBottomLeft: item.rect).integral
    guard rect.width > 1, rect.height > 1, item.opacity > 0 else {
      return
    }

    let style = MouseClickHighlightStyle(rawValue: Int(item.mouseClickStyleCode)) ?? .ripple

    let color = mouseClickColor(button: item.mouseClickButtonCode)
    let alpha = max(0, min(1, item.opacity))
    let lineWidth = max(1.5, min(rect.width, rect.height) * 0.055)
    context.saveGState()
    context.setLineCap(.round)
    context.setLineJoin(.round)

    switch style {
    case .system:
      context.setFillColor(color.withAlphaComponent(0.26 * alpha).cgColor)
      context.fillEllipse(in: rect)
      context.setStrokeColor(NSColor.white.withAlphaComponent(0.78 * alpha).cgColor)
      context.setLineWidth(max(1.5, lineWidth * 0.65))
      context.strokeEllipse(in: rect.insetBy(dx: lineWidth, dy: lineWidth))
      let dotSide = max(4, min(rect.width, rect.height) * 0.18)
      let dotRect = CGRect(
        x: rect.midX - dotSide * 0.5,
        y: rect.midY - dotSide * 0.5,
        width: dotSide,
        height: dotSide
      )
      context.setFillColor(NSColor.white.withAlphaComponent(0.92 * alpha).cgColor)
      context.fillEllipse(in: dotRect)
    case .ripple:
      context.setStrokeColor(color.withAlphaComponent(0.90 * alpha).cgColor)
      context.setLineWidth(lineWidth)
      context.strokeEllipse(in: rect.insetBy(dx: lineWidth, dy: lineWidth))
      context.setStrokeColor(NSColor.white.withAlphaComponent(0.45 * alpha).cgColor)
      context.setLineWidth(max(1, lineWidth * 0.42))
      context.strokeEllipse(in: rect.insetBy(dx: lineWidth * 2.35, dy: lineWidth * 2.35))
    case .pulse:
      context.setFillColor(color.withAlphaComponent(0.44 * alpha).cgColor)
      context.fillEllipse(in: rect)
      context.setStrokeColor(NSColor.white.withAlphaComponent(0.82 * alpha).cgColor)
      context.setLineWidth(max(1.5, lineWidth * 0.70))
      context.strokeEllipse(in: rect.insetBy(dx: lineWidth * 1.25, dy: lineWidth * 1.25))
      let dotSide = max(4, min(rect.width, rect.height) * 0.24)
      let dotRect = CGRect(
        x: rect.midX - dotSide * 0.5,
        y: rect.midY - dotSide * 0.5,
        width: dotSide,
        height: dotSide
      )
      context.setFillColor(NSColor.white.withAlphaComponent(0.88 * alpha).cgColor)
      context.fillEllipse(in: dotRect)
    case .spotlight:
      if let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [
          color.withAlphaComponent(0.48 * alpha).cgColor,
          color.withAlphaComponent(0.16 * alpha).cgColor,
          NSColor.clear.cgColor
        ] as CFArray,
        locations: [0, 0.52, 1]
      ) {
        context.drawRadialGradient(
          gradient,
          startCenter: CGPoint(x: rect.midX, y: rect.midY),
          startRadius: 0,
          endCenter: CGPoint(x: rect.midX, y: rect.midY),
          endRadius: min(rect.width, rect.height) * 0.5,
          options: [.drawsAfterEndLocation]
        )
      }
      let dotSide = max(3, min(rect.width, rect.height) * 0.10)
      let dotRect = CGRect(
        x: rect.midX - dotSide * 0.5,
        y: rect.midY - dotSide * 0.5,
        width: dotSide,
        height: dotSide
      )
      context.setFillColor(NSColor.white.withAlphaComponent(0.68 * alpha).cgColor)
      context.fillEllipse(in: dotRect)
    }

    context.restoreGState()
  }

  private static func mouseClickColor(button: UInt8) -> NSColor {
    switch button {
    case 1:
      return NSColor.systemOrange
    case 2:
      return NSColor.systemGreen
    default:
      return NSColor.controlAccentColor
    }
  }

  private static func coreGraphicsRect(fromBottomLeft rect: CGRect) -> CGRect {
    CGRect(
      x: rect.minX,
      y: rect.minY,
      width: rect.width,
      height: rect.height
    )
  }

  private static func aspectFillRect(imageSize: CGSize, targetRect: CGRect) -> CGRect {
    guard imageSize.width > 0, imageSize.height > 0, targetRect.width > 0, targetRect.height > 0 else {
      return targetRect
    }
    let scale = max(targetRect.width / imageSize.width, targetRect.height / imageSize.height)
    let width = imageSize.width * scale
    let height = imageSize.height * scale
    return CGRect(
      x: targetRect.midX - width * 0.5,
      y: targetRect.midY - height * 0.5,
      width: width,
      height: height
    )
  }
}
