import CoreGraphics
import Foundation

extension RecordingOverlayState {
  @MainActor
  static func from(settings: AppSettings) -> RecordingOverlayState {
    RecordingOverlayState(
      webcamFrame: settings.webcamOverlayNormalizedFrame,
      keystrokeFrame: settings.keystrokeOverlayNormalizedFrame
    )
  }
}

extension RecordingCoordinator {
  static func milliseconds(fromSeconds seconds: Double) -> UInt32 {
    guard seconds.isFinite, seconds > 0 else {
      return 0
    }
    return UInt32(min(Double(UInt32.max), (seconds * 1000).rounded()))
  }

  static func milliseconds(fromNanoseconds nanoseconds: UInt64) -> UInt32 {
    UInt32(min(UInt64(UInt32.max), nanoseconds / 1_000_000))
  }

  static func webcamTimeOffsetSeconds(
    screenStartUptime: TimeInterval?,
    webcamStartUptime: TimeInterval?
  ) -> Double {
    guard let screenStartUptime, let webcamStartUptime else {
      return 0
    }
    return max(0, screenStartUptime - webcamStartUptime)
  }

  static func stopWebcamRecorder(_ recorder: WebcamRecorder?) async -> Result<URL?, Error> {
    guard let recorder else {
      return .success(nil)
    }

    do {
      return .success(try await recorder.stop())
    } catch {
      recorder.cancel()
      return .failure(error)
    }
  }

  static func normalizedWebcamFrameForRecording(
    _ frame: CGRect,
    shape: WebcamShape,
    aspectRatio: WebcamAspectRatio,
    in recordingSize: CGSize
  ) -> CGRect {
    let normalized = RecordingOverlayState.normalizedFrame(frame)
    guard recordingSize.width > 0, recordingSize.height > 0 else {
      return normalized
    }

    let bounds = CGRect(origin: .zero, size: recordingSize)
    let denormalized = RecordingOverlayFrameGeometry.denormalizedOverlayFrame(normalized, in: bounds)
    let constrained = (shape == .circle ? WebcamAspectRatio.square : aspectRatio)
      .constrainedFrame(denormalized, in: bounds, minimumSize: CGSize(width: 84, height: 84))
    return RecordingOverlayState.normalizedFrame(
      RecordingOverlayFrameGeometry.normalizedOverlayFrame(constrained, in: bounds)
    )
  }
}
