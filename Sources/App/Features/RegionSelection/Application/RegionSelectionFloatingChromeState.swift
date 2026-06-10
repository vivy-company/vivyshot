import CoreGraphics

struct RegionSelectionFloatingChromeState {
  var toolbarOffset: CGSize = .zero
  var toolbarDragStartOffset: CGSize?
  var recordingControlOffset: CGSize = .zero
  var recordingControlDragStartOffset: CGSize?
  var recordingControlDragStartMouseLocation: CGPoint?
  var recordingControlPanelSize: CGSize?
}
