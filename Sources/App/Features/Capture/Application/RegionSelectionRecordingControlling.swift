import CoreGraphics

@MainActor
protocol RecordingFlowHandling: AnyObject {
  func recordingFlowWillStartWebcamCapture() async
  func recordingFlowDidStart(liveState: RecordingLiveControlState)
  func recordingFlowDidFinish()
  func recordingFlowDidFail(message: String)
}

@MainActor
protocol RegionSelectionRecordingControlling: AnyObject {
  var liveControlState: RecordingLiveControlState { get }

  func startRecording(
    selectionRectInScreen: CGRect,
    overlayState: RecordingOverlayState?,
    showFloatingHUD: Bool,
    flowHandler: any RecordingFlowHandling
  )

  func stopRecordingFromInlineToolbar()
  func setLiveRecordingTool(_ tool: RecordingTool, enabled: Bool) async -> RecordingLiveControlState
  func setMicrophoneDeviceIDForNextRecording(_ deviceID: String)
  func setWebcamDeviceIDForNextRecording(_ deviceID: String)
}
