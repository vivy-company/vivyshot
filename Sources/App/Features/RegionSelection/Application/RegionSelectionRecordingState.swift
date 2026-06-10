import Foundation

struct RegionSelectionRecordingState {
  var active = false
  var startPending = false
  var flowHasStarted = false
  var startedAt: Date?
  var liveControls: RecordingLiveControlState?
}
