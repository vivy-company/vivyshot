import AppKit

@MainActor
extension RegionSelectionView {
  func beginManualSelection(at point: CGPoint) {
    interactionState.beginManualSelection(at: point)
    invalidateSelectingOverlay(animatedHint: true)
  }

  func beginSmartSelection(at point: CGPoint, target: WindowCaptureTarget?) {
    interactionState.beginSmartSelection(at: point, target: target)
    invalidateSelectingOverlay(animatedHint: true)
  }

  func updateManualSelection(to point: CGPoint) {
    dragCurrent = point
    invalidateSelectingOverlay(animatedHint: false)
  }

  func activateSmartSelectionDrag(from point: CGPoint) {
    interactionState.activateSmartSelectionDrag(from: point)
    updateSelectingHintVisibility(animated: true)
  }

  func commitManualSelection(at point: CGPoint) -> CGRect? {
    dragCurrent = point
    let selection = selectionRect().map { $0.integral }
    commitSelectingOverlay(rect: selection)
    return selection
  }

  func commitSmartSelection(at point: CGPoint) -> (rect: CGRect?, mode: CaptureMode, windowID: CGWindowID?) {
    let committedMode: CaptureMode
    let committedRect: CGRect?
    let committedWindowID: CGWindowID?

    if smartDragActivated {
      dragCurrent = point
      committedMode = .selection
      committedRect = selectionRect().map { $0.integral }
      committedWindowID = nil
    } else {
      let target = smartWindowTargetForInitialSelection(at: point)
      committedMode = .window
      committedRect = target?.rect ?? smartMouseDownWindowRect
      committedWindowID = target?.windowID ?? smartMouseDownWindowID
    }

    resetSmartSelectionState()
    commitSelectingOverlay(rect: committedRect)
    return (committedRect, committedMode, committedWindowID)
  }

  func commitSelectingOverlay(rect: CGRect?) {
    interactionState.commitSelectingOverlay(rect: rect)
    invalidateSelectingOverlay(animatedHint: true)
  }

  func invalidateSelectingOverlay(animatedHint: Bool) {
    updateSelectingHintVisibility(animated: animatedHint)
    needsLayout = true
    needsDisplay = true
  }

  func resetSmartSelectionState() {
    interactionState.resetSmartSelection()
  }
}
