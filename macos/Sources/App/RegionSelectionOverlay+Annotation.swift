import AppKit
import CoreGraphics

@MainActor
extension RegionSelectionView {
  func currentTextAnnotationStyle() -> TextAnnotationStyle {
    TextAnnotationStyle(
      fontSize: textStyle.fontSize,
      color: textStyle.color
    )
  }

  func scaledTextAnnotationStyle() -> TextAnnotationStyle {
    TextAnnotationStyle(
      fontSize: textStyle.fontSize * canvasPixelScale(),
      color: textStyle.color
    )
  }

  func scaledStrokeWidth(base: CGFloat) -> UInt32 {
    UInt32(max(1, Int((base * canvasPixelScale()).rounded())))
  }

  func displayedStrokeWidth(base: CGFloat) -> CGFloat {
    let scale = max(1, canvasPixelScale())
    let committedWidth = CGFloat(scaledStrokeWidth(base: base))
    return max(1, committedWidth / scale)
  }

  func baseStrokeWidth(for tool: AnnotationTool) -> CGFloat {
    switch tool {
    case .arrow:
      return 5
    case .paint:
      return 6
    default:
      return 4
    }
  }

  func updateCanvasPreviewStrokeWidth() {
    canvasView.previewStrokeWidth = displayedStrokeWidth(base: baseStrokeWidth(for: currentTool))
  }

  func canvasPixelScale() -> CGFloat {
    guard let image = canvasView.image else {
      return 1
    }

    guard canvasView.bounds.width > 0, canvasView.bounds.height > 0 else {
      return 1
    }

    let scaleX = CGFloat(image.width) / canvasView.bounds.width
    let scaleY = CGFloat(image.height) / canvasView.bounds.height
    return max(1, (scaleX + scaleY) * 0.5)
  }

  func commitRect(_ imageRect: CGRect) {
    guard let session else {
      NSSound.beep()
      return
    }

    guard let image = session.addRect(
      imageRect: imageRect,
      color: annotationColor,
      strokeWidth: scaledStrokeWidth(base: 4)
    ) else {
      NSSound.beep()
      return
    }

    canvasView.image = image
    updateCanvasPreviewStrokeWidth()
    needsLayout = true
  }

  func commitFilledRect(_ imageRect: CGRect) {
    guard let session else {
      NSSound.beep()
      return
    }

    guard let image = session.addFilledRect(
      imageRect: imageRect,
      color: annotationColor
    ) else {
      NSSound.beep()
      return
    }

    canvasView.image = image
    updateCanvasPreviewStrokeWidth()
    needsLayout = true
  }

  func commitCircle(_ imageRect: CGRect) {
    guard let session else {
      NSSound.beep()
      return
    }

    guard let image = session.addCircle(
      imageRect: imageRect,
      color: annotationColor,
      strokeWidth: scaledStrokeWidth(base: 4)
    ) else {
      NSSound.beep()
      return
    }

    canvasView.image = image
    updateCanvasPreviewStrokeWidth()
    needsLayout = true
  }

  func commitFilledCircle(_ imageRect: CGRect) {
    guard let session else {
      NSSound.beep()
      return
    }

    guard let image = session.addFilledCircle(
      imageRect: imageRect,
      color: annotationColor
    ) else {
      NSSound.beep()
      return
    }

    canvasView.image = image
    updateCanvasPreviewStrokeWidth()
    needsLayout = true
  }

  func commitLine(from start: CGPoint, to end: CGPoint) {
    guard let session else {
      NSSound.beep()
      return
    }

    guard let image = session.addLine(
      from: start,
      to: end,
      color: annotationColor,
      strokeWidth: scaledStrokeWidth(base: 4)
    ) else {
      NSSound.beep()
      return
    }

    canvasView.image = image
    updateCanvasPreviewStrokeWidth()
    needsLayout = true
  }

  func commitArrow(from start: CGPoint, to end: CGPoint) {
    guard let session else {
      NSSound.beep()
      return
    }

    guard let image = session.addArrow(
      from: start,
      to: end,
      color: annotationColor,
      strokeWidth: scaledStrokeWidth(base: 5)
    ) else {
      NSSound.beep()
      return
    }

    canvasView.image = image
    updateCanvasPreviewStrokeWidth()
    needsLayout = true
  }

  func commitPaintPath(_ points: [CGPoint]) {
    guard let session else {
      NSSound.beep()
      return
    }

    guard let image = session.addPath(
      points,
      color: annotationColor,
      strokeWidth: scaledStrokeWidth(base: 6)
    ) else {
      NSSound.beep()
      return
    }

    canvasView.image = image
    updateCanvasPreviewStrokeWidth()
    needsLayout = true
  }

  func commitText(_ text: String, at point: CGPoint) {
    guard let session else {
      NSSound.beep()
      return
    }

    guard let image = session.addText(text, at: point, style: scaledTextAnnotationStyle()) else {
      NSSound.beep()
      return
    }

    canvasView.image = image
    currentTool = .move
    canvasView.selectAnnotation(atImagePoint: point)
    updateCanvasPreviewStrokeWidth()
    needsLayout = true
  }

  func commitPixelate(_ imageRect: CGRect) {
    guard let session else {
      NSSound.beep()
      return
    }

    guard let image = session.addPixelate(imageRect: imageRect) else {
      NSSound.beep()
      return
    }

    canvasView.image = image
    updateCanvasPreviewStrokeWidth()
    needsLayout = true
  }

  func commitBlur(_ imageRect: CGRect) {
    guard let session else {
      NSSound.beep()
      return
    }

    guard let image = session.addBlur(imageRect: imageRect) else {
      NSSound.beep()
      return
    }

    canvasView.image = image
    updateCanvasPreviewStrokeWidth()
    needsLayout = true
  }

  func performUndo() {
    canvasView.finishInlineTextEditing(commit: true)

    guard let session else {
      NSSound.beep()
      return
    }

    guard let image = session.undo() else {
      NSSound.beep()
      return
    }

    canvasView.image = image
    updateCanvasPreviewStrokeWidth()
  }

  func performRedo() {
    canvasView.finishInlineTextEditing(commit: true)

    guard let session else {
      NSSound.beep()
      return
    }

    guard let image = session.redo() else {
      NSSound.beep()
      return
    }

    canvasView.image = image
    updateCanvasPreviewStrokeWidth()
  }
}
