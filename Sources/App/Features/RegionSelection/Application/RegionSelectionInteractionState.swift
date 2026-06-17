import CoreGraphics

struct RegionSelectionInteractionState {
  var dragStart: CGPoint?
  var dragCurrent: CGPoint?
  var committedSelectionRect: CGRect?
  var smartMouseDownPoint: CGPoint?
  var smartMouseDownWindowRect: CGRect?
  var smartMouseDownWindowID: CGWindowID?
  var smartDragActivated = false
  var smartWindowHoverRect: CGRect?
  var smartWindowHoverID: CGWindowID?

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
    smartMouseDownWindowID = nil
    smartDragActivated = false
    smartWindowHoverRect = nil
    smartWindowHoverID = nil
  }

  mutating func beginManualSelection(at point: CGPoint) {
    resetSmartSelection()
    dragStart = point
    dragCurrent = point
    committedSelectionRect = nil
  }

  mutating func beginSmartSelection(at point: CGPoint, target: WindowCaptureTarget?) {
    smartMouseDownPoint = point
    smartMouseDownWindowRect = target?.rect
    smartMouseDownWindowID = target?.windowID
    smartWindowHoverRect = target?.rect
    smartWindowHoverID = target?.windowID
    smartDragActivated = false
    dragStart = nil
    dragCurrent = nil
    committedSelectionRect = nil
  }

  mutating func activateSmartSelectionDrag(from point: CGPoint) {
    smartDragActivated = true
    smartWindowHoverRect = nil
    smartWindowHoverID = nil
    smartMouseDownWindowRect = nil
    smartMouseDownWindowID = nil
    dragStart = point
  }

  mutating func commitSelectingOverlay(rect: CGRect?) {
    dragStart = nil
    dragCurrent = nil
    committedSelectionRect = rect
  }
}
