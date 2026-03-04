import AppKit
import CoreGraphics

enum AnnotationResizeHandle: CaseIterable {
  case topLeft
  case topRight
  case bottomLeft
  case bottomRight
}

@MainActor
final class AnnotationCanvasView: NSView {
  var tool: AnnotationTool = .rect {
    didSet {
      if tool != .text {
        finishInlineTextEditing(commit: true)
      }
      if tool != .move {
        movingAnnotationIndex = nil
        resizingAnnotationIndex = nil
        activeResizeHandle = nil
        resizeStartBoundsInView = nil
        resizeStartPointInView = nil
        selectedAnnotationIndex = nil
        selectedAnnotationBoundsInView = nil
        movingCaptureArea = false
        lastCaptureMovePointInWindow = nil
        captureMoveGestureBegan = false
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
      onViewportChanged?()
    }
  }

  var onCommitRect: ((CGRect) -> Void)?
  var onCommitFilledRect: ((CGRect) -> Void)?
  var onCommitCircle: ((CGRect) -> Void)?
  var onCommitFilledCircle: ((CGRect) -> Void)?
  var onCommitLine: ((CGPoint, CGPoint) -> Void)?
  var onCommitArrow: ((CGPoint, CGPoint) -> Void)?
  var onCommitPaintPath: (([CGPoint]) -> Void)?
  var onCommitText: ((String, CGPoint) -> Void)?
  var onCommitPixelateRect: ((CGRect) -> Void)?
  var onCommitBlurRect: ((CGRect) -> Void)?
  var onHitTestAnnotation: ((CGPoint) -> RustAnnotationInfo?)?
  var onMoveAnnotation: ((Int, CGPoint) -> CGImage?)?
  var onResizeAnnotation: ((Int, CGRect) -> CGImage?)?
  var onDeleteAnnotation: ((Int) -> CGImage?)?
  var onBeginMovingCaptureArea: (() -> Void)?
  var onMoveCaptureArea: ((CGPoint) -> Bool)?
  var onFinishMovingCaptureArea: (() -> Void)?
  var onViewportChanged: (() -> Void)?

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
    guard image != nil else {
      super.scrollWheel(with: event)
      return
    }

    if event.modifierFlags.contains(.command) {
      let anchor = convert(event.locationInWindow, from: nil)
      let step = event.hasPreciseScrollingDeltas ? 0.012 : 0.08
      let factor = exp((-event.scrollingDeltaY) * step)
      setZoom(zoomScale * factor, anchorViewPoint: anchor)
      return
    }

    guard zoomScale > minZoomScale + 0.0001 else {
      super.scrollWheel(with: event)
      return
    }

    let deltaMultiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
    panOffset.x -= event.scrollingDeltaX * deltaMultiplier
    panOffset.y += event.scrollingDeltaY * deltaMultiplier
    clampPanOffset()
    needsDisplay = true
    onViewportChanged?()
  }

  override func magnify(with event: NSEvent) {
    guard image != nil else {
      super.magnify(with: event)
      return
    }
    let anchor = convert(event.locationInWindow, from: nil)
    let requestedScale = zoomScale * (1 + event.magnification)
    setZoom(requestedScale, anchorViewPoint: anchor)
  }

  override func keyDown(with event: NSEvent) {
    if tool == .move, isDeleteKey(event) {
      if !deleteSelectedAnnotation() {
        NSSound.beep()
      }
      return
    }
    super.keyDown(with: event)
  }

  override func menu(for event: NSEvent) -> NSMenu? {
    guard tool == .move else {
      return nil
    }

    let point = convert(event.locationInWindow, from: nil)
    guard let (hit, _, selectedBounds) = hitAnnotation(at: point) else {
      return nil
    }

    selectedAnnotationIndex = hit.index
    movingAnnotationIndex = nil
    resizingAnnotationIndex = nil
    activeResizeHandle = nil
    resizeStartBoundsInView = nil
    resizeStartPointInView = nil
    lastMovePointInImage = nil
    selectedAnnotationBoundsInView = selectedBounds
    needsDisplay = true

    let menu = NSMenu(title: "Annotation")
    let deleteItem = NSMenuItem(title: "Delete", action: #selector(handleDeleteFromMenu), keyEquivalent: "")
    deleteItem.target = self
    menu.addItem(deleteItem)
    return menu
  }

  override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)

    if tool == .text {
      if let inlineTextField, inlineTextField.frame.contains(point) {
        window?.makeFirstResponder(inlineTextField)
        return
      }
      finishInlineTextEditing(commit: true)
    }

    guard let imageRect = imageDestinationRect(), imageRect.contains(point) else {
      dragStart = nil
      dragCurrent = nil
      selectedAnnotationIndex = nil
      movingAnnotationIndex = nil
      resizingAnnotationIndex = nil
      activeResizeHandle = nil
      resizeStartBoundsInView = nil
      resizeStartPointInView = nil
      lastMovePointInImage = nil
      selectedAnnotationBoundsInView = nil
      paintPathPointsInView.removeAll(keepingCapacity: false)
      movingCaptureArea = false
      lastCaptureMovePointInWindow = nil
      captureMoveGestureBegan = false
      needsDisplay = true
      return
    }

    if tool == .paint {
      let clamped = clampedToImageRect(point)
      dragStart = clamped
      dragCurrent = clamped
      paintPathPointsInView = [clamped]
      needsDisplay = true
      return
    }

    if tool == .move {
      movingCaptureArea = false
      lastCaptureMovePointInWindow = nil
      captureMoveGestureBegan = false

      if let selectedAnnotationIndex,
         let selectedBounds = selectedAnnotationBoundsInView,
         let handle = resizeHandle(at: point, in: selectedBounds) {
        resizingAnnotationIndex = selectedAnnotationIndex
        movingAnnotationIndex = nil
        lastMovePointInImage = nil
        activeResizeHandle = handle
        resizeStartBoundsInView = selectedBounds
        resizeStartPointInView = point
        needsDisplay = true
        return
      }

      guard let imagePoint = imagePointFromViewPoint(point),
            let hit = onHitTestAnnotation?(imagePoint),
            let selectedBounds = viewRectFromImageRect(hit.bounds) else {
        if onMoveCaptureArea != nil {
          selectedAnnotationIndex = nil
          movingAnnotationIndex = nil
          resizingAnnotationIndex = nil
          activeResizeHandle = nil
          resizeStartBoundsInView = nil
          resizeStartPointInView = nil
          lastMovePointInImage = nil
          selectedAnnotationBoundsInView = nil
          movingCaptureArea = true
          lastCaptureMovePointInWindow = event.locationInWindow
          captureMoveGestureBegan = false
          needsDisplay = true
          return
        }

        selectedAnnotationIndex = nil
        movingAnnotationIndex = nil
        resizingAnnotationIndex = nil
        activeResizeHandle = nil
        resizeStartBoundsInView = nil
        resizeStartPointInView = nil
        lastMovePointInImage = nil
        selectedAnnotationBoundsInView = nil
        movingCaptureArea = false
        lastCaptureMovePointInWindow = nil
        captureMoveGestureBegan = false
        needsDisplay = true
        return
      }

      selectedAnnotationIndex = hit.index
      movingAnnotationIndex = hit.index
      resizingAnnotationIndex = nil
      activeResizeHandle = nil
      resizeStartBoundsInView = nil
      resizeStartPointInView = nil
      lastMovePointInImage = imagePoint
      selectedAnnotationBoundsInView = selectedBounds
      movingCaptureArea = false
      lastCaptureMovePointInWindow = nil
      captureMoveGestureBegan = false
      needsDisplay = true
      return
    }

    dragStart = point
    dragCurrent = point
    needsDisplay = true
  }

  override func mouseDragged(with event: NSEvent) {
    if tool == .text {
      return
    }

    if tool == .paint {
      guard dragStart != nil else {
        return
      }

      let point = clampedToImageRect(convert(event.locationInWindow, from: nil))
      dragCurrent = point
      if let last = paintPathPointsInView.last {
        let distance = hypot(point.x - last.x, point.y - last.y)
        if distance >= 0.8 {
          paintPathPointsInView.append(point)
        } else if paintPathPointsInView.count == 1 {
          paintPathPointsInView.append(point)
        }
      } else {
        paintPathPointsInView.append(point)
      }
      needsDisplay = true
      return
    }

    if tool == .move {
      if let resizingAnnotationIndex,
         let activeResizeHandle,
         let resizeStartBoundsInView,
         let resizeStartPointInView {
        let currentPointInView = clampedToImageRect(convert(event.locationInWindow, from: nil))
        let delta = CGPoint(
          x: currentPointInView.x - resizeStartPointInView.x,
          y: currentPointInView.y - resizeStartPointInView.y
        )
        guard let resizedBoundsInView = resizedAnnotationBounds(
          from: resizeStartBoundsInView,
          handle: activeResizeHandle,
          delta: delta
        ) else {
          return
        }
        guard let resizedBoundsInImage = imageRectFromViewRect(resizedBoundsInView),
              let updatedImage = onResizeAnnotation?(resizingAnnotationIndex, resizedBoundsInImage) else {
          return
        }
        image = updatedImage
        selectedAnnotationBoundsInView = resizedBoundsInView
        needsDisplay = true
        return
      }

      if movingCaptureArea {
        let currentPointInWindow = event.locationInWindow
        guard let previousPointInWindow = lastCaptureMovePointInWindow else {
          lastCaptureMovePointInWindow = currentPointInWindow
          return
        }

        let delta = CGPoint(
          x: currentPointInWindow.x - previousPointInWindow.x,
          y: currentPointInWindow.y - previousPointInWindow.y
        )
        lastCaptureMovePointInWindow = currentPointInWindow

        guard abs(delta.x) >= 0.25 || abs(delta.y) >= 0.25 else {
          return
        }

        if !captureMoveGestureBegan {
          captureMoveGestureBegan = true
          onBeginMovingCaptureArea?()
        }

        if onMoveCaptureArea?(delta) == true {
          needsDisplay = true
        }
        return
      }

      guard let movingAnnotationIndex,
            let previousImagePoint = lastMovePointInImage else {
        return
      }

      let currentPointInView = clampedToImageRect(convert(event.locationInWindow, from: nil))
      guard let currentImagePoint = imagePointFromViewPoint(currentPointInView) else {
        return
      }

      let dx = Int((currentImagePoint.x - previousImagePoint.x).rounded())
      let dy = Int((currentImagePoint.y - previousImagePoint.y).rounded())
      guard dx != 0 || dy != 0 else {
        return
      }

      let delta = CGPoint(x: CGFloat(dx), y: CGFloat(dy))
      guard let updatedImage = onMoveAnnotation?(movingAnnotationIndex, delta) else {
        return
      }

      image = updatedImage
      selectedAnnotationIndex = movingAnnotationIndex
      lastMovePointInImage = CGPoint(
        x: previousImagePoint.x + CGFloat(dx),
        y: previousImagePoint.y + CGFloat(dy)
      )

      if let viewDelta = viewDeltaFromImageDelta(delta), var selected = selectedAnnotationBoundsInView {
        selected.origin.x += viewDelta.x
        selected.origin.y += viewDelta.y
        selectedAnnotationBoundsInView = selected
      }

      needsDisplay = true
      return
    }

    guard dragStart != nil else {
      return
    }

    dragCurrent = clampedToImageRect(convert(event.locationInWindow, from: nil))
    needsDisplay = true
  }

  override func mouseUp(with event: NSEvent) {
    if tool == .move {
      let didMoveCaptureArea = movingCaptureArea && captureMoveGestureBegan
      movingAnnotationIndex = nil
      resizingAnnotationIndex = nil
      activeResizeHandle = nil
      resizeStartBoundsInView = nil
      resizeStartPointInView = nil
      lastMovePointInImage = nil
      movingCaptureArea = false
      lastCaptureMovePointInWindow = nil
      captureMoveGestureBegan = false
      needsDisplay = true
      if didMoveCaptureArea {
        onFinishMovingCaptureArea?()
      }
      return
    }

    guard dragStart != nil else {
      return
    }

    if tool == .paint {
      let point = clampedToImageRect(convert(event.locationInWindow, from: nil))
      dragCurrent = point
      if let last = paintPathPointsInView.last {
        let distance = hypot(point.x - last.x, point.y - last.y)
        if distance >= 0.1 {
          paintPathPointsInView.append(point)
        }
      } else {
        paintPathPointsInView.append(point)
      }

      let committedPath = paintPathPointsInView
      dragStart = nil
      dragCurrent = nil
      paintPathPointsInView.removeAll(keepingCapacity: false)
      needsDisplay = true

      let imagePoints = imagePointsFromViewPoints(committedPath)
      if !imagePoints.isEmpty {
        onCommitPaintPath?(imagePoints)
      }
      return
    }

    dragCurrent = clampedToImageRect(convert(event.locationInWindow, from: nil))
    let committedViewRect = dragRectInView()
    let committedViewLine = dragLineInView()
    let committedViewPoint = dragCurrent
    dragStart = nil
    dragCurrent = nil
    needsDisplay = true

    switch tool {
    case .move:
      return
    case .rect:
      guard let committedViewRect, let imageRect = imageRectFromViewRect(committedViewRect) else {
        return
      }
      onCommitRect?(imageRect)
    case .filledRect:
      guard let committedViewRect, let imageRect = imageRectFromViewRect(committedViewRect) else {
        return
      }
      onCommitFilledRect?(imageRect)
    case .circle:
      guard let committedViewRect, let imageRect = imageRectFromViewRect(committedViewRect) else {
        return
      }
      onCommitCircle?(imageRect)
    case .filledCircle:
      guard let committedViewRect, let imageRect = imageRectFromViewRect(committedViewRect) else {
        return
      }
      onCommitFilledCircle?(imageRect)
    case .line:
      guard let (start, end) = committedViewLine,
            let imageStart = imagePointFromViewPoint(start),
            let imageEnd = imagePointFromViewPoint(end) else {
        return
      }
      onCommitLine?(imageStart, imageEnd)
    case .arrow:
      guard let (start, end) = committedViewLine,
            let imageStart = imagePointFromViewPoint(start),
            let imageEnd = imagePointFromViewPoint(end) else {
        return
      }
      onCommitArrow?(imageStart, imageEnd)
    case .paint:
      return
    case .text:
      guard let pointInView = committedViewPoint,
            let imagePoint = imagePointFromViewPoint(pointInView) else {
        return
      }
      beginInlineTextEditor(at: pointInView, imagePoint: imagePoint)
    case .pixelate:
      guard let committedViewRect, let imageRect = imageRectFromViewRect(committedViewRect) else {
        return
      }
      onCommitPixelateRect?(imageRect)
    case .blur:
      guard let committedViewRect, let imageRect = imageRectFromViewRect(committedViewRect) else {
        return
      }
      onCommitBlurRect?(imageRect)
    }
  }
}
