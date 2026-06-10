import CoreGraphics

struct RegionSelectionInteractionState {
  var dragStart: CGPoint?
  var dragCurrent: CGPoint?
  var committedSelectionRect: CGRect?
  var smartMouseDownPoint: CGPoint?
  var smartMouseDownWindowRect: CGRect?
  var smartDragActivated = false
  var smartWindowHoverRect: CGRect?

  var isIdle: Bool {
    smartMouseDownPoint == nil
      && !smartDragActivated
      && dragStart == nil
      && dragCurrent == nil
      && committedSelectionRect == nil
  }

  mutating func resetSmartSelection() {
    smartMouseDownPoint = nil
    smartMouseDownWindowRect = nil
    smartDragActivated = false
    smartWindowHoverRect = nil
  }

  mutating func beginManualSelection(at point: CGPoint) {
    resetSmartSelection()
    dragStart = point
    dragCurrent = point
    committedSelectionRect = nil
  }

  mutating func beginSmartSelection(at point: CGPoint, windowRect: CGRect?) {
    smartMouseDownPoint = point
    smartMouseDownWindowRect = windowRect
    smartWindowHoverRect = windowRect
    smartDragActivated = false
    dragStart = nil
    dragCurrent = nil
    committedSelectionRect = nil
  }

  mutating func activateSmartSelectionDrag(from point: CGPoint) {
    smartDragActivated = true
    smartWindowHoverRect = nil
    smartMouseDownWindowRect = nil
    dragStart = point
  }

  mutating func commitSelectingOverlay(rect: CGRect?) {
    dragStart = nil
    dragCurrent = nil
    committedSelectionRect = rect
  }
}
