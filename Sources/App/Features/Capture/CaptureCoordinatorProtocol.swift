import Foundation

/// Menu-facing capture coordination contract used by the app and UI-test harness.
@MainActor
protocol CaptureCoordinating: AnyObject {
  var onRecordingStateChanged: ((Bool) -> Void)? { get set }
  var isVideoRecordingActive: Bool { get }
  func startRegionCapture()
  func stopActiveRecordingFromStatusItem()
}

/// Minimal coordinator used for deterministic UI tests without ScreenCaptureKit.
@MainActor
final class UITestCaptureCoordinator: CaptureCoordinating {
  var onRecordingStateChanged: ((Bool) -> Void)?
  private var isRecording = false

  var isVideoRecordingActive: Bool {
    isRecording
  }

  func startRegionCapture() {
    isRecording = true
    onRecordingStateChanged?(true)
  }

  func stopActiveRecordingFromStatusItem() {
    isRecording = false
    onRecordingStateChanged?(false)
  }
}
