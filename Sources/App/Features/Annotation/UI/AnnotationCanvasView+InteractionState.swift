import CoreGraphics

@MainActor
extension AnnotationCanvasView {
  func clearDrawingDragState() {
    dragStart = nil
    dragCurrent = nil
  }

  func clearPaintDragState() {
    clearDrawingDragState()
    paintPathPointsInView.removeAll(keepingCapacity: false)
  }

  func clearAnnotationTransformState() {
    movingAnnotationIndex = nil
    resizingAnnotationIndex = nil
    activeResizeHandle = nil
    resizeStartBoundsInView = nil
    resizeStartPointInView = nil
    lastMovePointInImage = nil
  }

  func clearAnnotationSelectionState() {
    selectedAnnotationIndex = nil
    selectedAnnotationBoundsInView = nil
    clearAnnotationTransformState()
  }

  func clearCaptureAreaMoveState() {
    movingCaptureArea = false
    lastCaptureMovePointInWindow = nil
    captureMoveGestureBegan = false
  }

  func clearMoveToolState(preservingSelection: Bool = false) {
    clearAnnotationTransformState()
    if !preservingSelection {
      selectedAnnotationIndex = nil
      selectedAnnotationBoundsInView = nil
    }
    clearCaptureAreaMoveState()
  }

  func selectAnnotation(index: Int, bounds: CGRect) {
    selectedAnnotationIndex = index
    selectedAnnotationBoundsInView = bounds
    clearAnnotationTransformState()
    clearCaptureAreaMoveState()
  }

  func beginMovingAnnotation(index: Int, imagePoint: CGPoint, bounds: CGRect) {
    selectedAnnotationIndex = index
    movingAnnotationIndex = index
    resizingAnnotationIndex = nil
    activeResizeHandle = nil
    resizeStartBoundsInView = nil
    resizeStartPointInView = nil
    lastMovePointInImage = imagePoint
    selectedAnnotationBoundsInView = bounds
    clearCaptureAreaMoveState()
  }

  func beginResizingAnnotation(index: Int, handle: AnnotationResizeHandle, bounds: CGRect, point: CGPoint) {
    resizingAnnotationIndex = index
    movingAnnotationIndex = nil
    lastMovePointInImage = nil
    activeResizeHandle = handle
    resizeStartBoundsInView = bounds
    resizeStartPointInView = point
    clearCaptureAreaMoveState()
  }

  func beginMovingCaptureArea(at windowPoint: CGPoint) {
    clearAnnotationSelectionState()
    movingCaptureArea = true
    lastCaptureMovePointInWindow = windowPoint
    captureMoveGestureBegan = false
  }

  func finishMoveToolGesture() -> Bool {
    let didMoveCaptureArea = movingCaptureArea && captureMoveGestureBegan
    clearMoveToolState(preservingSelection: true)
    return didMoveCaptureArea
  }
}
