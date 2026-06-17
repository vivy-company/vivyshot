import CoreGraphics
import Foundation

struct RecordingConfig {
  let encoder: RecordingEncoder
  let frameRate: Int
  let colorProfile: RecordingColorProfile
  let captureResolution: RecordingCaptureResolution
  let captureBuffering: RecordingCaptureBuffering
  let showsPointer: Bool
  let showsSystemClickRings: Bool
  let captureSystemAudio: Bool
  let captureMicrophone: Bool
  let microphoneDeviceID: String
  let includesAppAudio: Bool
  let windowID: CGWindowID?
  let capturedOverlayWindowIDs: [CGWindowID]
}

/// Normalized overlay placement state captured at the moment recording starts.
struct RecordingOverlayState {
  var webcamFrame: CGRect
  var keystrokeFrame: CGRect

  static func normalizedFrame(_ frame: CGRect) -> CGRect {
    RecordingOverlayFrameGeometry.normalizedUnitFrame(frame)
  }
}

/// Timestamped user movement of a draggable recording overlay.
struct OverlayPlacementChange: Equatable {
  let timestampSeconds: Double
  let normalizedFrame: CGRect
}

/// Files and timeline state produced immediately after recording stops.
struct PostRecordingProject {
  let inputURL: URL
  let webcamURL: URL?
  let webcamTimeOffsetSeconds: Double
  let videoProject: RecordingProject
  let details: PostRecordingDetails
  let durationSeconds: Double
  let videoSize: CGSize?
  let overlaysBurnedIn: Bool

  var hasNativeCompositedOverlays: Bool {
    !overlaysBurnedIn && webcamURL != nil
  }
}

/// Captured keyboard label ready for overlay rendering.
struct RecordedKeystrokeEvent {
  let timestampNS: UInt64
  let displayToken: String
}

/// Captured mouse click position normalized to the selected recording area.
struct RecordedMouseClickEvent {
  let timestampNS: UInt64
  let normalizedX: CGFloat
  let normalizedY: CGFloat
  let button: UInt32
}

/// Snapshot of all input events collected during a recording.
struct RecordingInputResult {
  let keyEvents: [RecordedKeystrokeEvent]
  let clickEvents: [RecordedMouseClickEvent]
}
