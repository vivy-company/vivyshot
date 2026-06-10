import CoreGraphics
import Foundation

struct RecordingProjectBuilder {
  let fallbackSize: CGSize
  let frameRate: Int
  let systemAudioEnabled: Bool
  let microphoneEnabled: Bool
  let webcamAssetAvailable: Bool
  let webcamOverlayEnabled: Bool
  let webcamShape: WebcamShape
  let webcamAspectRatio: WebcamAspectRatio
  let webcamPlacementChanges: [OverlayPlacementChange]
  let keystrokeOverlayEnabled: Bool
  let keystrokeStyle: KeystrokeStyle
  let keystrokeSize: KeystrokeSize
  let keystrokePlacementChanges: [OverlayPlacementChange]
  let mouseClickHighlightStyle: MouseClickHighlightStyle?
  let monitorResult: RecordingInputResult

  func makeProject(durationSeconds: Double, videoSize: CGSize?) -> RecordingProject {
    let resolvedVideoSize = videoSize ?? fallbackSize
    let durationMS = UInt32(max(1, min(Double(UInt32.max), (durationSeconds * 1000).rounded())))
    let videoProject = RecordingProject(
      recordingInfo: RecordingInfo(
        durationMS: durationMS,
        width: UInt32(max(1, Int(resolvedVideoSize.width.rounded()))),
        height: UInt32(max(1, Int(resolvedVideoSize.height.rounded()))),
        frameRate: UInt32(max(1, frameRate)),
        hasAudio: systemAudioEnabled || microphoneEnabled,
        hasWebcamAsset: webcamAssetAvailable,
        hasMicrophoneAudio: microphoneEnabled
      )
    )

    guard let videoProject else {
      // The caller provides valid fallback size and duration, so this should not fail.
      preconditionFailure("Unable to create video project")
    }

    configureWebcamOverlay(on: videoProject)
    configureKeystrokeOverlay(on: videoProject)
    configureInputEvents(on: videoProject)
    return videoProject
  }

  private func configureWebcamOverlay(on videoProject: RecordingProject) {
    _ = videoProject.setWebcamOverlay(
      enabled: webcamOverlayEnabled,
      shape: webcamShape,
      aspectRatio: webcamAspectRatio
    )
    for change in webcamPlacementChanges.sorted(by: { $0.timestampSeconds < $1.timestampSeconds }) {
      _ = videoProject.pushWebcamPlacement(
        timestampMS: Self.milliseconds(fromSeconds: change.timestampSeconds),
        frame: change.normalizedFrame
      )
    }
  }

  private func configureKeystrokeOverlay(on videoProject: RecordingProject) {
    _ = videoProject.setKeystrokeOverlay(
      enabled: keystrokeOverlayEnabled,
      style: keystrokeStyle,
      size: keystrokeSize
    )
    for change in keystrokePlacementChanges.sorted(by: { $0.timestampSeconds < $1.timestampSeconds }) {
      _ = videoProject.pushKeystrokePlacement(
        timestampMS: Self.milliseconds(fromSeconds: change.timestampSeconds),
        frame: change.normalizedFrame
      )
    }
  }

  private func configureInputEvents(on videoProject: RecordingProject) {
    for keyEvent in monitorResult.keyEvents {
      _ = videoProject.addKeyEvent(
        timestampMS: Self.milliseconds(fromNanoseconds: keyEvent.timestampNS),
        token: keyEvent.displayToken
      )
    }

    _ = videoProject.setMouseClickOverlay(style: mouseClickHighlightStyle)
    for clickEvent in monitorResult.clickEvents {
      _ = videoProject.addClickEvent(
        timestampMS: Self.milliseconds(fromNanoseconds: clickEvent.timestampNS),
        normalizedX: clickEvent.normalizedX,
        normalizedY: clickEvent.normalizedY,
        button: clickEvent.button
      )
    }
  }

  private static func milliseconds(fromSeconds seconds: Double) -> UInt32 {
    guard seconds.isFinite, seconds > 0 else {
      return 0
    }
    return UInt32(min(Double(UInt32.max), (seconds * 1000).rounded()))
  }

  private static func milliseconds(fromNanoseconds nanoseconds: UInt64) -> UInt32 {
    UInt32(min(UInt64(UInt32.max), nanoseconds / 1_000_000))
  }
}
