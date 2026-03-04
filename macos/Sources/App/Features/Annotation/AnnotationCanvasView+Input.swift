import AppKit
import CoreGraphics

@MainActor
extension AnnotationCanvasView {
  func zoomIn() {
    let anchor = CGPoint(x: bounds.midX, y: bounds.midY)
    setZoom(zoomScale * 1.18, anchorViewPoint: anchor)
  }

  func zoomOut() {
    let anchor = CGPoint(x: bounds.midX, y: bounds.midY)
    setZoom(zoomScale / 1.18, anchorViewPoint: anchor)
  }

  func resetZoomAndPan() {
    zoomScale = 1
    panOffset = .zero
    needsDisplay = true
    onViewportChanged?()
  }

  func configureForScrollingCaptureEditing() {
    guard let image else {
      pendingScrollingCaptureViewportConfiguration = false
      return
    }

    let imageWidth = CGFloat(image.width)
    let imageHeight = CGFloat(image.height)
    guard imageWidth > 0, imageHeight > 0 else {
      pendingScrollingCaptureViewportConfiguration = false
      return
    }

    // Only apply this specialized viewport setup for tall stitched captures.
    guard imageHeight > imageWidth * 1.6 else {
      pendingScrollingCaptureViewportConfiguration = false
      return
    }

    guard bounds.width > 0, bounds.height > 0 else {
      pendingScrollingCaptureViewportConfiguration = true
      return
    }

    let fitScale = min(bounds.width / imageWidth, bounds.height / imageHeight)
    guard fitScale > 0 else {
      pendingScrollingCaptureViewportConfiguration = false
      return
    }

    // Keep default long-capture viewport minimal (full image visible first).
    zoomScale = minZoomScale
    panOffset = .zero
    clampPanOffset()
    pendingScrollingCaptureViewportConfiguration = false
    needsDisplay = true
    onViewportChanged?()
  }

  @objc
  func handleDeleteFromMenu(_: Any?) {
    _ = deleteSelectedAnnotation()
  }

  func deleteSelectedAnnotation() -> Bool {
    guard tool == .move, let selectedAnnotationIndex else {
      return false
    }

    guard let updatedImage = onDeleteAnnotation?(selectedAnnotationIndex) else {
      return false
    }

    image = updatedImage
    movingAnnotationIndex = nil
    resizingAnnotationIndex = nil
    activeResizeHandle = nil
    resizeStartBoundsInView = nil
    resizeStartPointInView = nil
    lastMovePointInImage = nil
    self.selectedAnnotationIndex = nil
    selectedAnnotationBoundsInView = nil
    movingCaptureArea = false
    lastCaptureMovePointInWindow = nil
    captureMoveGestureBegan = false
    needsDisplay = true
    return true
  }

  func selectAnnotation(atImagePoint imagePoint: CGPoint) {
    guard let hit = onHitTestAnnotation?(imagePoint),
          let selectedBounds = viewRectFromImageRect(hit.bounds) else {
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
    movingAnnotationIndex = nil
    resizingAnnotationIndex = nil
    activeResizeHandle = nil
    resizeStartBoundsInView = nil
    resizeStartPointInView = nil
    lastMovePointInImage = nil
    selectedAnnotationBoundsInView = selectedBounds
    movingCaptureArea = false
    lastCaptureMovePointInWindow = nil
    captureMoveGestureBegan = false
    needsDisplay = true
  }

  func isDeleteKey(_ event: NSEvent) -> Bool {
    guard event.type == .keyDown else {
      return false
    }
    return event.keyCode == 51 || event.keyCode == 117
  }

  func hitAnnotation(at viewPoint: CGPoint) -> (RustAnnotationInfo, CGPoint, CGRect)? {
    guard let imagePoint = imagePointFromViewPoint(viewPoint),
          let hit = onHitTestAnnotation?(imagePoint),
          let selectedBounds = viewRectFromImageRect(hit.bounds) else {
      return nil
    }
    return (hit, imagePoint, selectedBounds)
  }
}
