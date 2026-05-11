import AppKit
import CoreGraphics
import Foundation
import VivyShotKit

final class RustVideoProjectSession {
  private static let maxSerializedBytes = 8_388_608
  private static let maxRenderItems = 128
  private let handle: UnsafeMutableRawPointer

  init?(recordingInfo: RustVideoProjectRecordingInfo) {
    let raw = vs_video_project_recording_info(
      duration_ms: recordingInfo.durationMS,
      width: recordingInfo.width,
      height: recordingInfo.height,
      frame_rate: recordingInfo.frameRate,
      has_audio: recordingInfo.hasAudio,
      has_webcam_asset: recordingInfo.hasWebcamAsset,
      has_microphone_audio: recordingInfo.hasMicrophoneAudio
    )
    guard let rawHandle = vs_video_project_create_from_recording(raw) else {
      return nil
    }
    handle = rawHandle
  }

  private init(handle: UnsafeMutableRawPointer) {
    self.handle = handle
  }

  static func deserialize(json: Data) -> RustVideoProjectSession? {
    guard !json.isEmpty else {
      return nil
    }
    let rawHandle: UnsafeMutableRawPointer? = json.withUnsafeBytes { raw in
      guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
        return nil
      }
      return vs_video_project_deserialize_json(base, UInt32(raw.count))
    }
    guard let rawHandle else {
      return nil
    }
    return RustVideoProjectSession(handle: rawHandle)
  }

  deinit {
    vs_video_project_destroy(handle)
  }

  func addKeyEvent(timestampMS: UInt32, token: String) -> Bool {
    let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return false
    }
    let bytes = Array(trimmed.utf8)
    return bytes.withUnsafeBufferPointer { ptr in
      guard let base = ptr.baseAddress else {
        return false
      }
      return vs_video_project_add_key_event(handle, timestampMS, base, UInt32(ptr.count)) == 0
    }
  }

  func addClickEvent(timestampMS: UInt32, normalizedX: CGFloat, normalizedY: CGFloat, button: UInt32) -> Bool {
    vs_video_project_add_click_event(
      handle,
      timestampMS,
      Float(normalizedX),
      Float(normalizedY),
      button
    ) == 0
  }

  func setWebcamOverlay(
    enabled: Bool,
    shape: VideoWebcamOverlayShapeOption,
    aspectRatio: VideoWebcamOverlayAspectRatioOption,
    assetID: UInt32 = 1
  ) -> Bool {
    vs_video_project_set_webcam_overlay(
      handle,
      enabled,
      UInt8(shape.rawValue),
      UInt8(aspectRatio.rawValue),
      assetID
    ) == 0
  }

  func pushWebcamPlacement(timestampMS: UInt32, frame: CGRect) -> Bool {
    vs_video_project_push_webcam_placement(handle, timestampMS, Self.rawRect(frame)) == 0
  }

  func setKeystrokeOverlay(
    enabled: Bool,
    style: VideoKeystrokeOverlayStyleOption,
    size: VideoKeystrokeOverlaySizeOption
  ) -> Bool {
    vs_video_project_set_keystroke_overlay(
      handle,
      enabled,
      UInt8(style.rawValue),
      UInt8(size.rawValue)
    ) == 0
  }

  func pushKeystrokePlacement(timestampMS: UInt32, frame: CGRect) -> Bool {
    vs_video_project_push_keystroke_placement(handle, timestampMS, Self.rawRect(frame)) == 0
  }

  func renderPlan(
    timeSeconds: Double,
    renderSize: CGSize,
    target: RustVideoRenderTarget
  ) -> RustVideoRenderPlan? {
    let query = vs_video_project_render_plan_query(
      time_ms: Self.milliseconds(fromSeconds: timeSeconds),
      render_width: UInt32(max(1, Int(renderSize.width.rounded()))),
      render_height: UInt32(max(1, Int(renderSize.height.rounded()))),
      target: target.rawValue
    )
    var written: UInt32 = 0
    var items = [vs_video_project_render_item](
      repeating: vs_video_project_render_item(),
      count: Self.maxRenderItems
    )
    let status = items.withUnsafeMutableBufferPointer { ptr in
      vs_video_project_render_plan(
        handle,
        query,
        ptr.baseAddress,
        UInt32(ptr.count),
        &written
      )
    }
    guard RustFFIStatus.isSuccess(status), written <= items.count else {
      return nil
    }
    let textBytes = renderPlanText(query: query)
    let renderedItems = items.prefix(Int(written)).compactMap { raw -> RustVideoRenderItem? in
      guard let kind = RustVideoRenderItemKind(rawValue: raw.kind) else {
        return nil
      }
      let text: String
      let start = Int(raw.text_offset)
      let end = start + Int(raw.text_len)
      if start >= 0, end <= textBytes.count, end >= start {
        text = String(decoding: textBytes[start..<end], as: UTF8.self)
      } else {
        text = ""
      }
      return RustVideoRenderItem(
        kind: kind,
        rect: CGRect(
          x: CGFloat(raw.x),
          y: CGFloat(raw.y),
          width: CGFloat(raw.width),
          height: CGFloat(raw.height)
        ),
        opacity: CGFloat(raw.opacity),
        styleFlags: raw.style_flags,
        text: text,
        assetID: raw.asset_id
      )
    }
    return RustVideoRenderPlan(items: renderedItems)
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
    guard vs_video_project_export_plan(handle, &raw) == 0 else {
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

  func proRequirement(
    target: PostRecordingExportTarget,
    options: PostRecordingExportOptions?
  ) -> [ProExportReason]? {
    var raw = vs_video_project_pro_requirement_result(reasons_mask: 0)
    let status = vs_video_project_pro_requirement(
      handle,
      vs_video_project_export_options(
        target: target == .gif ? RustVideoExportTarget.gif.rawValue : RustVideoExportTarget.mp4.rawValue,
        codec: Self.videoExportCodecCode(options?.codec ?? .h264),
        frame_rate: Self.videoExportFrameRateCode(options?.frameRate ?? .fps30),
        quality: Self.videoExportQualityCode(options?.quality ?? .standard),
        bitrate: Self.videoExportBitrateCode(options?.bitrate ?? .standard),
        includes_baked_transition: false
      ),
      &raw
    )
    guard RustFFIStatus.isSuccess(status) else {
      return nil
    }
    return Self.proReasons(from: raw.reasons_mask)
  }

  func serializeJSON() -> Data? {
    var capacity = 1024
    while capacity <= Self.maxSerializedBytes {
      var buffer = [UInt8](repeating: 0, count: capacity)
      var written: UInt32 = 0
      let status = buffer.withUnsafeMutableBufferPointer { ptr in
        vs_video_project_serialize_json(handle, ptr.baseAddress, UInt32(ptr.count), &written)
      }
      if RustFFIStatus.isSuccess(status), Int(written) <= buffer.count {
        return Data(buffer.prefix(Int(written)))
      }
      guard status == RustFFIStatus.bufferTooSmall.rawValue else {
        return nil
      }
      capacity = max(capacity * 2, Int(written))
    }
    return nil
  }

  private func renderPlanText(query: vs_video_project_render_plan_query) -> [UInt8] {
    var capacity = 128
    while capacity <= 8192 {
      var buffer = [UInt8](repeating: 0, count: capacity)
      var written: UInt32 = 0
      let status = buffer.withUnsafeMutableBufferPointer { ptr in
        vs_video_project_render_plan_text(handle, query, ptr.baseAddress, UInt32(ptr.count), &written)
      }
      if RustFFIStatus.isSuccess(status), Int(written) <= buffer.count {
        return Array(buffer.prefix(Int(written)))
      }
      guard status == RustFFIStatus.bufferTooSmall.rawValue else {
        return []
      }
      capacity = max(capacity * 2, Int(written))
    }
    return []
  }

  private static func rawRect(_ rect: CGRect) -> vs_video_project_rect {
    let standardized = rect.standardized
    return vs_video_project_rect(
      x: Float(standardized.minX),
      y: Float(standardized.minY),
      width: Float(standardized.width),
      height: Float(standardized.height)
    )
  }

  private static func milliseconds(fromSeconds seconds: Double) -> UInt32 {
    guard seconds.isFinite, seconds > 0 else {
      return 0
    }
    return UInt32(min(Double(UInt32.max), (seconds * 1000).rounded()))
  }

  private static func videoExportCodecCode(_ codec: PostRecordingExportCodec) -> UInt8 {
    codec == .hevc ? 1 : 0
  }

  private static func videoExportFrameRateCode(_ frameRate: PostRecordingExportFrameRate) -> UInt8 {
    frameRate == .fps60 ? 1 : 0
  }

  private static func videoExportQualityCode(_ quality: PostRecordingExportQuality) -> UInt8 {
    quality == .high ? 1 : 0
  }

  private static func videoExportBitrateCode(_ bitrate: PostRecordingExportBitratePreset) -> UInt8 {
    switch bitrate {
    case .standard:
      return 0
    case .high:
      return 1
    case .veryHigh:
      return 2
    }
  }

  private static func proReasons(from mask: UInt32) -> [ProExportReason] {
    var reasons: [ProExportReason] = []
    if mask & (1 << 0) != 0 { reasons.append(.webcamOverlay) }
    if mask & (1 << 1) != 0 { reasons.append(.keystrokeOverlay) }
    if mask & (1 << 2) != 0 { reasons.append(.microphoneAudio) }
    if mask & (1 << 3) != 0 { reasons.append(.gifExport) }
    if mask & (1 << 4) != 0 { reasons.append(.hevcExport) }
    if mask & (1 << 5) != 0 { reasons.append(.sixtyFPS) }
    if mask & (1 << 6) != 0 { reasons.append(.highQuality) }
    if mask & (1 << 7) != 0 { reasons.append(.highBitrate) }
    if mask & (1 << 8) != 0 { reasons.append(.bakedTransition) }
    return reasons
  }
}
