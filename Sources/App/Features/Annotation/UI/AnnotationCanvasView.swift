import AppKit
import CoreGraphics

/// Corner handle used when resizing an existing annotation.
enum AnnotationResizeHandle: CaseIterable {
  case topLeft
  case topRight
  case bottomLeft
  case bottomRight
}

/// AppKit-backed annotation canvas for drawing, selecting, editing, and moving screenshot markup.
@MainActor
enum AnnotationCanvasCommit {
  case rect(CGRect)
  case filledRect(CGRect)
  case circle(CGRect)
  case filledCircle(CGRect)
  case line(CGPoint, CGPoint)
  case arrow(CGPoint, CGPoint)
  case paintPath([CGPoint])
  case text(String, CGPoint)
  case pixelate(CGRect)
  case blur(CGRect)
}

@MainActor
protocol AnnotationCanvasViewDelegate: AnyObject {
  func annotationCanvasViewDidChangeViewport(_ canvasView: AnnotationCanvasView)
  func annotationCanvasView(_ canvasView: AnnotationCanvasView, didCommit commit: AnnotationCanvasCommit)
  func annotationCanvasView(_ canvasView: AnnotationCanvasView, hitTestAnnotationAt point: CGPoint) -> AnnotationInfo?
  func annotationCanvasView(_ canvasView: AnnotationCanvasView, moveAnnotationAt index: Int, by delta: CGPoint) -> CGImage?
  func annotationCanvasView(_ canvasView: AnnotationCanvasView, resizeAnnotationAt index: Int, to imageRect: CGRect) -> CGImage?
  func annotationCanvasView(_ canvasView: AnnotationCanvasView, deleteAnnotationAt index: Int) -> CGImage?
  func annotationCanvasViewWillMoveCaptureArea(_ canvasView: AnnotationCanvasView)
  func annotationCanvasView(_ canvasView: AnnotationCanvasView, moveCaptureAreaBy delta: CGPoint) -> Bool
  func annotationCanvasViewDidFinishMovingCaptureArea(_ canvasView: AnnotationCanvasView)
}

@MainActor
final class AnnotationCanvasView: NSView {
  var tool: AnnotationTool = .rect {
    didSet {
      if tool != .text {
        finishInlineTextEditing(commit: true)
      }
      if tool != .move {
        clearMoveToolState()
      }
      if tool != .paint {
        paintPathPointsInView.removeAll(keepingCapacity: false)
      }
      needsDisplay = true
    }
  }

  var textStyle = EditorTextStyle(fontSize: 16, color: .white) {
    didSet {
      updateInlineTextFieldStyle()
      needsDisplay = true
    }
  }

  var image: CGImage? {
    didSet {
      if imageSize(of: oldValue) != imageSize(of: image) {
        zoomScale = 1
        panOffset = .zero
      }
      needsDisplay = true
      window?.invalidateCursorRects(for: self)
      delegate?.annotationCanvasViewDidChangeViewport(self)
    }
  }

  weak var delegate: (any AnnotationCanvasViewDelegate)?

  var accentColor: NSColor = .systemOrange {
    didSet {
      needsDisplay = true
    }
  }

  var previewStrokeWidth: CGFloat = 3.5 {
    didSet {
      needsDisplay = true
    }
  }

  var dragStart: CGPoint?
  var dragCurrent: CGPoint?
  var inlineTextAnchorInView: CGPoint?
  var inlineTextField: NSTextField?
  var selectedAnnotationIndex: Int?
  var movingAnnotationIndex: Int?
  var resizingAnnotationIndex: Int?
  var lastMovePointInImage: CGPoint?
  var selectedAnnotationBoundsInView: CGRect?
  var activeResizeHandle: AnnotationResizeHandle?
  var resizeStartBoundsInView: CGRect?
  var resizeStartPointInView: CGPoint?
  var paintPathPointsInView: [CGPoint] = []
  var movingCaptureArea = false
  var lastCaptureMovePointInWindow: CGPoint?
  var captureMoveGestureBegan = false
  var zoomScale: CGFloat = 1
  var panOffset: CGPoint = .zero
  var pendingScrollingCaptureViewportConfiguration = false
  let minZoomScale: CGFloat = 1
  let maxZoomScale: CGFloat = 7

  override var acceptsFirstResponder: Bool { true }

  override func layout() {
    super.layout()
    clampPanOffset()
    if pendingScrollingCaptureViewportConfiguration {
      pendingScrollingCaptureViewportConfiguration = false
      configureForScrollingCaptureEditing()
    }
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    guard let context = NSGraphicsContext.current?.cgContext else {
      return
    }

    guard let image, let destination = imageDestinationRect() else {
      return
    }

    context.interpolationQuality = .high
    context.draw(image, in: destination)

    switch tool {
    case .move:
      break
    case .rect:
      guard let previewRect = dragRectInView() else {
        return
      }
      context.setFillColor(accentColor.withAlphaComponent(0.12).cgColor)
      context.fill(previewRect)
      context.setStrokeColor(accentColor.cgColor)
      context.setLineWidth(previewStrokeWidth)
      context.stroke(previewRect)
    case .filledRect:
      guard let previewRect = dragRectInView() else {
        return
      }
      context.setFillColor(accentColor.withAlphaComponent(0.3).cgColor)
      context.fill(previewRect)
      context.setStrokeColor(accentColor.withAlphaComponent(0.9).cgColor)
      context.setLineWidth(max(1.6, previewStrokeWidth * 0.33))
      context.stroke(previewRect)
    case .circle:
      guard let previewRect = dragRectInView() else {
        return
      }
      context.setFillColor(accentColor.withAlphaComponent(0.12).cgColor)
      context.fillEllipse(in: previewRect)
      context.setStrokeColor(accentColor.cgColor)
      context.setLineWidth(previewStrokeWidth)
      context.strokeEllipse(in: previewRect)
    case .filledCircle:
      guard let previewRect = dragRectInView() else {
        return
      }
      context.setFillColor(accentColor.withAlphaComponent(0.3).cgColor)
      context.fillEllipse(in: previewRect)
      context.setStrokeColor(accentColor.withAlphaComponent(0.9).cgColor)
      context.setLineWidth(max(1.6, previewStrokeWidth * 0.33))
      context.strokeEllipse(in: previewRect)
    case .line:
      guard let (start, end) = dragLineInView() else {
        return
      }
      context.setStrokeColor(accentColor.cgColor)
      context.setLineWidth(previewStrokeWidth)
      context.setLineCap(.round)
      context.setLineJoin(.round)
      context.move(to: start)
      context.addLine(to: end)
      context.strokePath()
    case .arrow:
      guard let (start, end) = dragLineInView() else {
        return
      }
      drawArrowPreview(context: context, start: start, end: end, color: accentColor)
    case .paint:
      drawPaintPathPreview(context: context)
    case .text:
      if inlineTextField != nil {
        return
      }
      guard let point = dragCurrent ?? dragStart else {
        return
      }
      drawTextCursorPreview(context: context, point: point, color: textStyle.color)
    case .pixelate:
      guard let previewRect = dragRectInView() else {
        return
      }
      context.setFillColor(accentColor.withAlphaComponent(0.12).cgColor)
      context.fill(previewRect)
      context.setStrokeColor(accentColor.cgColor)
      context.setLineWidth(previewStrokeWidth)
      context.stroke(previewRect)
    case .blur:
      guard let previewRect = dragRectInView() else {
        return
      }
      context.setFillColor(accentColor.withAlphaComponent(0.12).cgColor)
      context.fill(previewRect)
      context.setStrokeColor(accentColor.cgColor)
      context.setLineWidth(previewStrokeWidth)
      context.stroke(previewRect)
    }

    if tool == .move {
      drawMoveSelectionPreview(context: context)
    }
  }

  override func resetCursorRects() {
    if let imageRect = imageDestinationRect() {
      addCursorRect(imageRect, cursor: tool == .move ? .openHand : .crosshair)
    } else {
      addCursorRect(bounds, cursor: .arrow)
    }
  }

  override func scrollWheel(with event: NSEvent) {
    guard handleScrollWheel(with: event) else {
      super.scrollWheel(with: event)
      return
    }
  }

  override func magnify(with event: NSEvent) {
    guard handleMagnify(with: event) else {
      super.magnify(with: event)
      return
    }
  }

  override func keyDown(with event: NSEvent) {
    if handleKeyDown(with: event) {
      return
    }
    super.keyDown(with: event)
  }

  override func menu(for event: NSEvent) -> NSMenu? {
    annotationContextMenu(for: event)
  }

  override func mouseDown(with event: NSEvent) {
    handleMouseDown(with: event)
  }

  override func mouseDragged(with event: NSEvent) {
    handleMouseDragged(with: event)
  }

  override func mouseUp(with event: NSEvent) {
    handleMouseUp(with: event)
  }
}
