import Foundation

/// Observer for menu-facing recording state changes.
@MainActor
protocol RecordingStateObserving: AnyObject {
  func recordingStateDidChange(isRecording: Bool)
}

/// Menu-facing capture coordination contract used by the app and UI-test harness.
@MainActor
protocol CaptureCoordinating: AnyObject {
  var recordingStateObserver: (any RecordingStateObserving)? { get set }
  var isVideoRecordingActive: Bool { get }
  func startRegionCapture()
  func stopActiveRecordingFromStatusItem()
}

/// Minimal coordinator used for deterministic UI tests without ScreenCaptureKit.
@MainActor
final class UITestCaptureCoordinator: CaptureCoordinating {
  weak var recordingStateObserver: (any RecordingStateObserving)? {
    didSet {
      recordingStateObserver?.recordingStateDidChange(isRecording: isRecording)
    }
  }
  private var isRecording = false

  var isVideoRecordingActive: Bool {
    isRecording
  }

  func startRegionCapture() {
    isRecording = true
    recordingStateObserver?.recordingStateDidChange(isRecording: true)
  }

  func stopActiveRecordingFromStatusItem() {
    isRecording = false
    recordingStateObserver?.recordingStateDidChange(isRecording: false)
  }
}
