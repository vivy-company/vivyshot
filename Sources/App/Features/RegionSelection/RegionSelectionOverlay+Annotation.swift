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

  func scaledStrokeWidth() -> UInt32 {
    UInt32(max(1, Int((CGFloat(settings.drawingStrokeWidth) * canvasPixelScale()).rounded())))
  }

  func scaledArrowHeadMinimumLength() -> CGFloat {
    AnnotationArrowGeometry.minimumHeadLength * canvasPixelScale()
  }

  func displayedStrokeWidth() -> CGFloat {
    let scale = max(1, canvasPixelScale())
    let committedWidth = CGFloat(scaledStrokeWidth())
    return max(1, committedWidth / scale)
  }

  func updateCanvasPreviewStrokeWidth() {
    canvasView.previewStrokeWidth = displayedStrokeWidth()
  }

  func canvasPixelScale() -> CGFloat {
    guard let image = canvasView.image else {
      return 1
    }

    guard let destination = canvasView.imageDestinationRect(),
          destination.width > 0,
          destination.height > 0
    else {
      return 1
    }

    let scaleX = CGFloat(image.width) / destination.width
    let scaleY = CGFloat(image.height) / destination.height
    return max(1, (scaleX + scaleY) * 0.5)
  }

  func ensureEditingSession() -> AnnotationSession? {
    if let session {
      return session
    }
    guard let image = canvasView.image,
          let createdSession = AnnotationSession(image: image)
    else {
      return nil
    }
    session = createdSession
    return createdSession
  }

  func editingSessionOrBeep() -> AnnotationSession? {
    guard let session = ensureEditingSession() else {
      NSSound.beep()
      return nil
    }
    return session
  }

  func commitRect(_ imageRect: CGRect) {
    guard let session = editingSessionOrBeep() else { return }

    guard let image = session.addRect(
      imageRect: imageRect,
      color: annotationColor,
      strokeWidth: scaledStrokeWidth()
    ) else {
      NSSound.beep()
      return
    }

    canvasView.image = image
    updateCanvasPreviewStrokeWidth()
    needsLayout = true
  }

  func commitFilledRect(_ imageRect: CGRect) {
    guard let session = editingSessionOrBeep() else { return }

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
    guard let session = editingSessionOrBeep() else { return }

    guard let image = session.addCircle(
      imageRect: imageRect,
      color: annotationColor,
      strokeWidth: scaledStrokeWidth()
    ) else {
      NSSound.beep()
      return
    }

    canvasView.image = image
    updateCanvasPreviewStrokeWidth()
    needsLayout = true
  }

  func commitFilledCircle(_ imageRect: CGRect) {
    guard let session = editingSessionOrBeep() else { return }

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
    guard let session = editingSessionOrBeep() else { return }

    guard let image = session.addLine(
      from: start,
      to: end,
      color: annotationColor,
      strokeWidth: scaledStrokeWidth()
    ) else {
      NSSound.beep()
      return
    }

    canvasView.image = image
    updateCanvasPreviewStrokeWidth()
    needsLayout = true
  }

  func commitArrow(from start: CGPoint, to end: CGPoint) {
    guard let session = editingSessionOrBeep() else { return }

    guard let image = session.addArrow(
      from: start,
      to: end,
      color: annotationColor,
      strokeWidth: scaledStrokeWidth(),
      minimumHeadLength: scaledArrowHeadMinimumLength()
    ) else {
      NSSound.beep()
      return
    }

    canvasView.image = image
    updateCanvasPreviewStrokeWidth()
    needsLayout = true
  }

  func commitPaintPath(_ points: [CGPoint]) {
    guard let session = editingSessionOrBeep() else { return }

    guard let image = session.addPath(
      points,
      color: annotationColor,
      strokeWidth: scaledStrokeWidth()
    ) else {
      NSSound.beep()
      return
    }

    canvasView.image = image
    updateCanvasPreviewStrokeWidth()
    needsLayout = true
  }

  func commitText(_ text: String, at point: CGPoint) {
    guard let session = editingSessionOrBeep() else { return }

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
    guard let session = editingSessionOrBeep() else { return }

    guard let image = session.addPixelate(imageRect: imageRect) else {
      NSSound.beep()
      return
    }

    canvasView.image = image
    updateCanvasPreviewStrokeWidth()
    needsLayout = true
  }

  func commitBlur(_ imageRect: CGRect) {
    guard let session = editingSessionOrBeep() else { return }

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

    guard let session = editingSessionOrBeep() else { return }

    guard let image = session.undo() else {
      NSSound.beep()
      return
    }

    canvasView.image = image
    updateCanvasPreviewStrokeWidth()
  }

  func performRedo() {
    canvasView.finishInlineTextEditing(commit: true)

    guard let session = editingSessionOrBeep() else { return }

    guard let image = session.redo() else {
      NSSound.beep()
      return
    }

    canvasView.image = image
    updateCanvasPreviewStrokeWidth()
  }
}
