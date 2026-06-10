import AppKit

@MainActor
extension RegionSelectionView {
  func beginManualSelection(at point: CGPoint) {
    interactionState.beginManualSelection(at: point)
    invalidateSelectingOverlay(animatedHint: true)
  }

  func beginSmartSelection(at point: CGPoint, windowRect: CGRect?) {
    interactionState.beginSmartSelection(at: point, windowRect: windowRect)
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

  func commitSmartSelection(at point: CGPoint) -> (rect: CGRect?, mode: CaptureMode) {
    let committedMode: CaptureMode
    let committedRect: CGRect?

    if smartDragActivated {
      dragCurrent = point
      committedMode = .selection
      committedRect = selectionRect().map { $0.integral }
    } else {
      committedMode = .window
      committedRect = smartWindowRectForInitialSelection(at: point) ?? smartMouseDownWindowRect
    }

    resetSmartSelectionState()
    commitSelectingOverlay(rect: committedRect)
    return (committedRect, committedMode)
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
