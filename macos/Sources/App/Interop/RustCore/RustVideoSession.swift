import AppKit
import CoreGraphics
import Foundation
import VivyShotKit

final class RustVideoSession {
  private static let maxSerializedBytes = 8_388_608
  private let handle: UnsafeMutableRawPointer

  init?(config: RustVideoSessionConfig) {
    let rawConfig = vs_video_session_config(
      frame_rate: UInt32(max(1, config.frameRate)),
      capture_system_audio: config.captureSystemAudio,
      capture_microphone: config.captureMicrophone,
      show_webcam: config.showWebcam,
      highlight_mouse_clicks: config.highlightMouseClicks,
      highlight_keystrokes: config.highlightKeystrokes
    )
    guard let rawHandle = vs_video_session_create(rawConfig) else {
      return nil
    }
    handle = rawHandle
  }

  private init(handle: UnsafeMutableRawPointer) {
    self.handle = handle
  }

  static func deserialize(json: Data) -> RustVideoSession? {
    guard !json.isEmpty else {
      return nil
    }
    let rawHandle: UnsafeMutableRawPointer? = json.withUnsafeBytes { raw in
      guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
        return nil
      }
      return vs_video_session_deserialize_json(base, UInt32(raw.count))
    }
    guard let rawHandle else {
      return nil
    }
    return RustVideoSession(handle: rawHandle)
  }

  deinit {
    vs_video_session_destroy(handle)
  }

  func addKeyEvent(timestampNS: UInt64, token: String) -> Bool {
    let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return false
    }

    let utf8 = Array(trimmed.utf8)
    return utf8.withUnsafeBytes { raw in
      guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
        return false
      }
      let event = vs_video_key_event(
        timestamp_ns: timestampNS,
        token_ptr: base,
        token_len: UInt(raw.count)
      )
      return vs_video_session_add_key_event(handle, event) == 0
    }
  }

  func addClickEvent(timestampNS: UInt64, normalizedX: CGFloat, normalizedY: CGFloat, button: UInt32) -> Bool {
    let event = vs_video_click_event(
      timestamp_ns: timestampNS,
      normalized_x: Float(normalizedX),
      normalized_y: Float(normalizedY),
      button: button
    )
    return vs_video_session_add_click_event(handle, event) == 0
  }

  func setTrim(startMS: Int, endMS: Int) -> Bool {
    guard startMS >= 0, endMS >= 0 else {
      return false
    }
    return vs_video_session_set_trim(handle, UInt32(startMS), UInt32(endMS)) == 0
  }

  func exportPlan() -> RustVideoExportPlan? {
    var raw = vs_video_export_plan(
      trim_start_ms: 0,
      trim_end_ms: 0,
      key_event_count: 0,
      click_event_count: 0,
      plan_mode: 0,
      include_audio: false,
      include_webcam: false,
      text_overlay_count: 0,
      overlay_item_count: 0,
      requires_intermediate_for_gif: false,
      needs_custom_compositor: false
    )
    guard vs_video_session_get_export_plan(handle, &raw) == 0 else {
      return nil
    }
    return RustVideoExportPlan(
      trimStartMS: Int(raw.trim_start_ms),
      trimEndMS: Int(raw.trim_end_ms),
      keyEventCount: Int(raw.key_event_count),
      clickEventCount: Int(raw.click_event_count),
      planMode: raw.plan_mode,
      includeAudio: raw.include_audio,
      includeWebcam: raw.include_webcam,
      textOverlayCount: Int(raw.text_overlay_count),
      overlayItemCount: Int(raw.overlay_item_count),
      requiresIntermediateForGIF: raw.requires_intermediate_for_gif,
      needsCustomCompositor: raw.needs_custom_compositor
    )
  }

  func setExportContext(_ context: RustVideoExportContext) -> Bool {
    let raw = vs_video_export_context(
      source_has_audio: context.sourceHasAudio,
      source_has_webcam_asset: context.sourceHasWebcamAsset,
      audio_track_visible: context.audioTrackVisible,
      webcam_track_visible: context.webcamTrackVisible,
      text_overlay_count: UInt32(max(0, context.textOverlayCount))
    )
    return vs_video_session_set_export_context(handle, raw) == 0
  }

  func serializeJSON() -> Data? {
    var capacity = 1024
    while capacity <= Self.maxSerializedBytes {
      var buffer = [UInt8](repeating: 0, count: capacity)
      var written: UInt32 = 0
      let result = buffer.withUnsafeMutableBufferPointer { ptr in
        vs_video_session_serialize_json(handle, ptr.baseAddress, UInt32(ptr.count), &written)
      }
      guard result == 0 else {
        return nil
      }

      let required = Int(written)
      if required <= buffer.count {
        return Data(buffer.prefix(required))
      }
      capacity = max(capacity * 2, required)
    }
    return nil
  }
}


