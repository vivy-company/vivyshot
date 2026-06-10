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

  func commitAnnotationCanvasChange(_ commit: AnnotationCanvasCommit) {
    switch commit {
    case .rect(let imageRect):
      applyAnnotationEdit(.rect(imageRect, annotationColor, scaledStrokeWidth()))
    case .filledRect(let imageRect):
      applyAnnotationEdit(.filledRect(imageRect, annotationColor))
    case .circle(let imageRect):
      applyAnnotationEdit(.circle(imageRect, annotationColor, scaledStrokeWidth()))
    case .filledCircle(let imageRect):
      applyAnnotationEdit(.filledCircle(imageRect, annotationColor))
    case .line(let start, let end):
      applyAnnotationEdit(.line(start, end, annotationColor, scaledStrokeWidth()))
    case .arrow(let start, let end):
      applyAnnotationEdit(.arrow(start, end, annotationColor, scaledStrokeWidth(), scaledArrowHeadMinimumLength()))
    case .paintPath(let points):
      applyAnnotationEdit(.paintPath(points, annotationColor, scaledStrokeWidth()))
    case .text(let text, let point):
      applyAnnotationEdit(.text(text, point, scaledTextAnnotationStyle()), selectAnnotationAt: point, switchesToMoveTool: true)
    case .pixelate(let imageRect):
      applyAnnotationEdit(.pixelate(imageRect))
    case .blur(let imageRect):
      applyAnnotationEdit(.blur(imageRect))
    }
  }

  func performUndo() {
    canvasView.finishInlineTextEditing(commit: true)

    guard let image = annotationEditor.undo(currentImage: canvasView.image) else {
      NSSound.beep()
      return
    }

    canvasView.image = image
    updateCanvasPreviewStrokeWidth()
  }

  func performRedo() {
    canvasView.finishInlineTextEditing(commit: true)

    guard let image = annotationEditor.redo(currentImage: canvasView.image) else {
      NSSound.beep()
      return
    }

    canvasView.image = image
    updateCanvasPreviewStrokeWidth()
  }

  private func applyAnnotationEdit(
    _ operation: AnnotationEditOperation,
    selectAnnotationAt point: CGPoint? = nil,
    switchesToMoveTool: Bool = false
  ) {
    guard let image = annotationEditor.commit(operation, currentImage: canvasView.image) else {
      NSSound.beep()
      return
    }

    canvasView.image = image
    if switchesToMoveTool {
      currentTool = .move
    }
    if let point {
      canvasView.selectAnnotation(atImagePoint: point)
    }
    updateCanvasPreviewStrokeWidth()
    needsLayout = true
  }
}
