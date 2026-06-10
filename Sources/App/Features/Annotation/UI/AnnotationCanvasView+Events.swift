import AppKit

@MainActor
extension AnnotationCanvasView {
  func handleScrollWheel(with event: NSEvent) -> Bool {
    guard image != nil else {
      return false
    }

    if event.modifierFlags.contains(.command) {
      let anchor = convert(event.locationInWindow, from: nil)
      let step = event.hasPreciseScrollingDeltas ? 0.012 : 0.08
      let factor = exp((-event.scrollingDeltaY) * step)
      setZoom(zoomScale * factor, anchorViewPoint: anchor)
      return true
    }

    guard zoomScale > minZoomScale + 0.0001 else {
      return false
    }

    let deltaMultiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
    panOffset.x -= event.scrollingDeltaX * deltaMultiplier
    panOffset.y += event.scrollingDeltaY * deltaMultiplier
    clampPanOffset()
    needsDisplay = true
    delegate?.annotationCanvasViewDidChangeViewport(self)
    return true
  }

  func handleMagnify(with event: NSEvent) -> Bool {
    guard image != nil else {
      return false
    }
    let anchor = convert(event.locationInWindow, from: nil)
    let requestedScale = zoomScale * (1 + event.magnification)
    setZoom(requestedScale, anchorViewPoint: anchor)
    return true
  }

  func handleKeyDown(with event: NSEvent) -> Bool {
    guard tool == .move, isDeleteKey(event) else {
      return false
    }
    if !deleteSelectedAnnotation() {
      NSSound.beep()
    }
    return true
  }

  func annotationContextMenu(for event: NSEvent) -> NSMenu? {
    guard tool == .move else {
      return nil
    }

    let point = convert(event.locationInWindow, from: nil)
    guard let (hit, _, selectedBounds) = hitAnnotation(at: point) else {
      return nil
    }

    selectAnnotation(index: hit.index, bounds: selectedBounds)
    needsDisplay = true

    let menu = NSMenu(title: "Annotation")
    let deleteItem = NSMenuItem(title: "Delete", action: #selector(handleDeleteFromMenu), keyEquivalent: "")
    deleteItem.target = self
    menu.addItem(deleteItem)
    return menu
  }

  func handleMouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)

    if tool == .text {
      if let inlineTextField, inlineTextField.frame.contains(point) {
        window?.makeFirstResponder(inlineTextField)
        return
      }
      finishInlineTextEditing(commit: true)
    }

    guard let imageRect = imageDestinationRect(), imageRect.contains(point) else {
      clearPaintDragState()
      clearMoveToolState()
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
      clearCaptureAreaMoveState()

      if let selectedAnnotationIndex,
         let selectedBounds = selectedAnnotationBoundsInView,
         let handle = resizeHandle(at: point, in: selectedBounds) {
        beginResizingAnnotation(
          index: selectedAnnotationIndex,
          handle: handle,
          bounds: selectedBounds,
          point: point
        )
        needsDisplay = true
        return
      }

      guard let imagePoint = imagePointFromViewPoint(point),
            let hit = delegate?.annotationCanvasView(self, hitTestAnnotationAt: imagePoint),
            let selectedBounds = viewRectFromImageRect(hit.bounds) else {
        if delegate != nil {
          beginMovingCaptureArea(at: event.locationInWindow)
          needsDisplay = true
          return
        }

        clearMoveToolState()
        needsDisplay = true
        return
      }

      beginMovingAnnotation(index: hit.index, imagePoint: imagePoint, bounds: selectedBounds)
      needsDisplay = true
      return
    }

    dragStart = point
    dragCurrent = point
    needsDisplay = true
  }

  func handleMouseDragged(with event: NSEvent) {
    if tool == .text {
      return
    }

    if tool == .paint {
      handlePaintMouseDragged(with: event)
      return
    }

    if tool == .move {
      handleMoveMouseDragged(with: event)
      return
    }

    guard dragStart != nil else {
      return
    }

    dragCurrent = clampedToImageRect(convert(event.locationInWindow, from: nil))
    needsDisplay = true
  }

  func handleMouseUp(with event: NSEvent) {
    if tool == .move {
      let didMoveCaptureArea = finishMoveToolGesture()
      needsDisplay = true
      if didMoveCaptureArea {
        delegate?.annotationCanvasViewDidFinishMovingCaptureArea(self)
      }
      return
    }

    guard dragStart != nil else {
      return
    }

    if tool == .paint {
      commitPaintMouseUp(with: event)
      return
    }

    dragCurrent = clampedToImageRect(convert(event.locationInWindow, from: nil))
    let committedViewRect = dragRectInView()
    let committedViewLine = dragLineInView()
    let committedViewPoint = dragCurrent
    clearDrawingDragState()
    needsDisplay = true

    commitDrawingGesture(
      committedViewRect: committedViewRect,
      committedViewLine: committedViewLine,
      committedViewPoint: committedViewPoint
    )
  }

  private func handlePaintMouseDragged(with event: NSEvent) {
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
  }

  private func handleMoveMouseDragged(with event: NSEvent) {
    if let resizingAnnotationIndex,
       let activeResizeHandle,
       let resizeStartBoundsInView,
       let resizeStartPointInView {
      handleResizeMouseDragged(
        event: event,
        annotationIndex: resizingAnnotationIndex,
        handle: activeResizeHandle,
        startBoundsInView: resizeStartBoundsInView,
        startPointInView: resizeStartPointInView
      )
      return
    }

    if movingCaptureArea {
      handleCaptureAreaMoveMouseDragged(with: event)
      return
    }

    handleAnnotationMoveMouseDragged(with: event)
  }

  private func handleResizeMouseDragged(
    event: NSEvent,
    annotationIndex: Int,
    handle: AnnotationResizeHandle,
    startBoundsInView: CGRect,
    startPointInView: CGPoint
  ) {
    let currentPointInView = clampedToImageRect(convert(event.locationInWindow, from: nil))
    let delta = CGPoint(
      x: currentPointInView.x - startPointInView.x,
      y: currentPointInView.y - startPointInView.y
    )
    guard let resizedBoundsInView = resizedAnnotationBounds(
      from: startBoundsInView,
      handle: handle,
      delta: delta
    ) else {
      return
    }
    guard let resizedBoundsInImage = imageRectFromViewRect(resizedBoundsInView),
          let updatedImage = delegate?.annotationCanvasView(
            self,
            resizeAnnotationAt: annotationIndex,
            to: resizedBoundsInImage
          ) else {
      return
    }
    image = updatedImage
    selectedAnnotationBoundsInView = resizedBoundsInView
    needsDisplay = true
  }

  private func handleCaptureAreaMoveMouseDragged(with event: NSEvent) {
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
      delegate?.annotationCanvasViewWillMoveCaptureArea(self)
    }

    if delegate?.annotationCanvasView(self, moveCaptureAreaBy: delta) == true {
      needsDisplay = true
    }
  }

  private func handleAnnotationMoveMouseDragged(with event: NSEvent) {
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
    guard let updatedImage = delegate?.annotationCanvasView(self, moveAnnotationAt: movingAnnotationIndex, by: delta) else {
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
  }

  private func commitPaintMouseUp(with event: NSEvent) {
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
    clearPaintDragState()
    needsDisplay = true

    let imagePoints = imagePointsFromViewPoints(committedPath)
    if !imagePoints.isEmpty {
      delegate?.annotationCanvasView(self, didCommit: .paintPath(imagePoints))
    }
  }

}
