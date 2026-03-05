import Foundation

@MainActor
protocol CaptureCoordinating: AnyObject {
  var onRecordingStateChanged: ((Bool) -> Void)? { get set }
  var isVideoRecordingActive: Bool { get }
  func startRegionCapture()
  func stopActiveRecordingFromStatusItem()
}

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
