import Foundation
import VivyShotKit

struct CaptureBackendCapabilities {
  let h264: Bool
  let hevc: Bool
  let systemAudio: Bool
  let microphoneAudio: Bool

  static func load() -> Self {
    var raw = vs_capture_capabilities()
    let status = vs_capture_copy_capabilities(&raw)
    guard status == VS_CAPTURE_STATUS_OK else {
      return Self(h264: true, hevc: false, systemAudio: false, microphoneAudio: false)
    }
    return Self(
      h264: raw.h264,
      hevc: raw.hevc,
      systemAudio: raw.system_audio,
      microphoneAudio: raw.microphone_audio
    )
  }
}
