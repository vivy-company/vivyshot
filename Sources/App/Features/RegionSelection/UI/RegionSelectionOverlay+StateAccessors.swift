import CoreGraphics
import Foundation

@MainActor
extension RegionSelectionView {
  var dragStart: CGPoint? {
    get { interactionState.dragStart }
    set { interactionState.dragStart = newValue }
  }

  var dragCurrent: CGPoint? {
    get { interactionState.dragCurrent }
    set { interactionState.dragCurrent = newValue }
  }

  var committedSelectionRect: CGRect? {
    get { interactionState.committedSelectionRect }
    set { interactionState.committedSelectionRect = newValue }
  }

  var smartMouseDownPoint: CGPoint? {
    get { interactionState.smartMouseDownPoint }
    set { interactionState.smartMouseDownPoint = newValue }
  }

  var smartMouseDownWindowRect: CGRect? {
    get { interactionState.smartMouseDownWindowRect }
    set { interactionState.smartMouseDownWindowRect = newValue }
  }

  var smartMouseDownWindowID: CGWindowID? {
    get { interactionState.smartMouseDownWindowID }
    set { interactionState.smartMouseDownWindowID = newValue }
  }

  var smartDragActivated: Bool {
    get { interactionState.smartDragActivated }
    set { interactionState.smartDragActivated = newValue }
  }

  var smartWindowHoverRect: CGRect? {
    get { interactionState.smartWindowHoverRect }
    set { interactionState.smartWindowHoverRect = newValue }
  }

  var smartWindowHoverID: CGWindowID? {
    get { interactionState.smartWindowHoverID }
    set { interactionState.smartWindowHoverID = newValue }
  }

  var toolbarOffset: CGSize {
    get { floatingChromeState.toolbarOffset }
    set { floatingChromeState.toolbarOffset = newValue }
  }

  var toolbarDragStartOffset: CGSize? {
    get { floatingChromeState.toolbarDragStartOffset }
    set { floatingChromeState.toolbarDragStartOffset = newValue }
  }

  var recordingActive: Bool {
    get { recordingState.active }
    set {
      let oldValue = recordingState.active
      recordingState.active = newValue
      guard oldValue != newValue else {
        return
      }
      updateRecordingFocusPresentation()
    }
  }

  var recordingStartPending: Bool {
    get { recordingState.startPending }
    set { recordingState.startPending = newValue }
  }

  var recordingFlowHasStarted: Bool {
    get { recordingState.flowHasStarted }
    set { recordingState.flowHasStarted = newValue }
  }

  var recordingStartedAt: Date? {
    get { recordingState.startedAt }
    set { recordingState.startedAt = newValue }
  }

  var recordingLiveControlState: RecordingLiveControlState? {
    get { recordingState.liveControls }
    set { recordingState.liveControls = newValue }
  }
}
