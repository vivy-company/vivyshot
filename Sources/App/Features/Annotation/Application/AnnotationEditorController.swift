import AppKit
import CoreGraphics

enum AnnotationEditOperation {
  case rect(CGRect, NSColor, UInt32)
  case filledRect(CGRect, NSColor)
  case circle(CGRect, NSColor, UInt32)
  case filledCircle(CGRect, NSColor)
  case line(CGPoint, CGPoint, NSColor, UInt32)
  case arrow(CGPoint, CGPoint, NSColor, UInt32, CGFloat)
  case paintPath([CGPoint], NSColor, UInt32)
  case text(String, CGPoint, TextAnnotationStyle)
  case pixelate(CGRect)
  case blur(CGRect)
}

@MainActor
final class AnnotationEditorController {
  private var session: AnnotationSession?

  func setSession(_ session: AnnotationSession?) {
    self.session = session
  }

  func reset() {
    session = nil
  }

  func currentImage() -> CGImage? {
    session?.currentImage()
  }

  func commit(_ operation: AnnotationEditOperation, currentImage: CGImage?) -> CGImage? {
    guard let session = ensureSession(currentImage: currentImage) else {
      return nil
    }

    switch operation {
    case .rect(let rect, let color, let strokeWidth):
      return session.addRect(imageRect: rect, color: color, strokeWidth: strokeWidth)
    case .filledRect(let rect, let color):
      return session.addFilledRect(imageRect: rect, color: color)
    case .circle(let rect, let color, let strokeWidth):
      return session.addCircle(imageRect: rect, color: color, strokeWidth: strokeWidth)
    case .filledCircle(let rect, let color):
      return session.addFilledCircle(imageRect: rect, color: color)
    case .line(let start, let end, let color, let strokeWidth):
      return session.addLine(from: start, to: end, color: color, strokeWidth: strokeWidth)
    case .arrow(let start, let end, let color, let strokeWidth, let minimumHeadLength):
      return session.addArrow(
        from: start,
        to: end,
        color: color,
        strokeWidth: strokeWidth,
        minimumHeadLength: minimumHeadLength
      )
    case .paintPath(let points, let color, let strokeWidth):
      return session.addPath(points, color: color, strokeWidth: strokeWidth)
    case .text(let text, let point, let style):
      return session.addText(text, at: point, style: style)
    case .pixelate(let rect):
      return session.addPixelate(imageRect: rect)
    case .blur(let rect):
      return session.addBlur(imageRect: rect)
    }
  }

  func undo(currentImage: CGImage?) -> CGImage? {
    ensureSession(currentImage: currentImage)?.undo()
  }

  func redo(currentImage: CGImage?) -> CGImage? {
    ensureSession(currentImage: currentImage)?.redo()
  }

  func hitTestAnnotation(at point: CGPoint, currentImage: CGImage?) -> AnnotationInfo? {
    ensureSession(currentImage: currentImage)?.hitTestAnnotation(at: point)
  }

  func moveAnnotation(index: Int, delta: CGPoint, currentImage: CGImage?) -> CGImage? {
    ensureSession(currentImage: currentImage)?.moveAnnotation(index: index, delta: delta)
  }

  func resizeAnnotation(index: Int, imageRect: CGRect, currentImage: CGImage?) -> CGImage? {
    ensureSession(currentImage: currentImage)?.resizeAnnotation(index: index, imageRect: imageRect)
  }

  func removeAnnotation(index: Int, currentImage: CGImage?) -> CGImage? {
    ensureSession(currentImage: currentImage)?.removeAnnotation(index: index)
  }

  private func ensureSession(currentImage: CGImage?) -> AnnotationSession? {
    if let session {
      return session
    }
    guard let currentImage,
          let createdSession = AnnotationSession(image: currentImage)
    else {
      return nil
    }
    session = createdSession
    return createdSession
  }
}
