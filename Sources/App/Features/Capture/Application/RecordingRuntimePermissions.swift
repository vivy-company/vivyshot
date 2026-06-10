import AVFoundation
import Foundation

@MainActor
struct RecordingRuntimePermissions {
  let settings: AppSettings
  let storeManager: StoreManager

  var captureMicrophoneEnabled: Bool {
    storeManager.canUse(.microphoneAudioExport) && settings.recordMicrophone
  }

  var showWebcamEnabled: Bool {
    storeManager.canUse(.webcamOverlay) && settings.showWebcam
  }

  var highlightKeystrokesEnabled: Bool {
    storeManager.canUse(.keystrokeOverlay) && settings.highlightKeystrokes
  }

  func ensureRuntimePermissions() async throws {
    if captureMicrophoneEnabled {
      try await ensureMediaAccess(
        for: .audio,
        errorTitle: "Microphone permission is required when microphone recording is enabled."
      )
    }

    if showWebcamEnabled {
      try await ensureMediaAccess(
        for: .video,
        errorTitle: "Camera permission is required when webcam recording is enabled."
      )
    }

    if highlightKeystrokesEnabled, !isAccessibilityTrusted(promptIfNeeded: true) {
      return
    }
  }

  func isAccessibilityTrusted(promptIfNeeded: Bool) -> Bool {
    AccessibilityPermission.isTrusted(promptIfNeeded: promptIfNeeded)
  }

  private func ensureMediaAccess(for mediaType: AVMediaType, errorTitle: String) async throws {
    let status = AVCaptureDevice.authorizationStatus(for: mediaType)
    switch status {
    case .authorized:
      return
    case .notDetermined:
      let granted = await AVCaptureDevice.requestAccess(for: mediaType)
      if granted {
        return
      }
      throw NSError(
        domain: "com.vivyshot.video",
        code: -57,
        userInfo: [NSLocalizedDescriptionKey: errorTitle]
      )
    case .denied, .restricted:
      throw NSError(
        domain: "com.vivyshot.video",
        code: -58,
        userInfo: [NSLocalizedDescriptionKey: errorTitle]
      )
    @unknown default:
      throw NSError(
        domain: "com.vivyshot.video",
        code: -59,
        userInfo: [NSLocalizedDescriptionKey: errorTitle]
      )
    }
  }
}
