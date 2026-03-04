import AppKit
import CoreGraphics
import Foundation

// MARK: - Timeline Types

enum TimelineTrackKind: UInt8 {
  case video = 0
  case webcam = 1
  case audio = 2
  case text = 3
  case shape = 4
  case cursor = 5
  case zoom = 6
}

enum TimelineTool: Int {
  case select = 0
  case cut = 1
  case hand = 2
  case zoom = 3
}

struct TimelineTrackInfo {
  let kind: TimelineTrackKind
  let visible: Bool
  let clipCount: Int
}

struct ClipTransform {
  var x: Float
  var y: Float
  var width: Float
  var height: Float
  var rotation: Float
  var opacity: Float

  static let identity = ClipTransform(x: 0, y: 0, width: 1, height: 1, rotation: 0, opacity: 1)
}

struct TimelineClipInfo {
  let id: UInt32
  let trackIndex: Int
  let startMS: UInt32
  let endMS: UInt32
  let kind: TimelineTrackKind
  let transform: ClipTransform
}

struct TimelineTextExportClipInfo {
  let trackIndex: Int
  let clipID: UInt32
  let startMS: UInt32
  let endMS: UInt32
}

// MARK: - RustTimelineSession

final class RustTimelineSession {
  private let handle: UnsafeMutableRawPointer
  private static let maxTimelineBufferCount = 16_384
  private static let maxTextBytes = 1_048_576

  init?(durationMS: UInt32, width: UInt32, height: UInt32) {
    guard let rawHandle = vs_timeline_create(durationMS, width, height) else {
      return nil
    }
    handle = rawHandle
  }

  deinit {
    vs_timeline_destroy(handle)
  }

  // MARK: Tracks

  func addTrack(kind: TimelineTrackKind) -> Bool {
    vs_timeline_add_track(handle, kind.rawValue) == 0
  }

  func removeTrack(at index: Int) -> Bool {
    vs_timeline_remove_track(handle, UInt32(index)) == 0
  }

  func reorderTrack(from: Int, to: Int) -> Bool {
    vs_timeline_reorder_track(handle, UInt32(from), UInt32(to)) == 0
  }

  func setTrackVisible(at index: Int, visible: Bool) -> Bool {
    vs_timeline_set_track_visible(handle, UInt32(index), visible) == 0
  }

  func getTracks() -> [TimelineTrackInfo] {
    let infos = loadTrackInfos()
    return infos.map { info in
      return TimelineTrackInfo(
        kind: TimelineTrackKind(rawValue: info.kind) ?? .video,
        visible: info.visible,
        clipCount: Int(info.clip_count)
      )
    }
  }

  func deriveExportContext(sourceHasAudio: Bool, sourceHasWebcamAsset: Bool) -> RustVideoExportContext? {
    var raw = vs_video_export_context(
      source_has_audio: sourceHasAudio,
      source_has_webcam_asset: sourceHasWebcamAsset,
      audio_track_visible: false,
      webcam_track_visible: false,
      text_overlay_count: 0
    )
    let status = vs_timeline_derive_export_context(handle, sourceHasAudio, sourceHasWebcamAsset, &raw)
    guard RustFFIStatus.isSuccess(status) else {
      return nil
    }
    return RustVideoExportContext(
      sourceHasAudio: raw.source_has_audio,
      sourceHasWebcamAsset: raw.source_has_webcam_asset,
      audioTrackVisible: raw.audio_track_visible,
      webcamTrackVisible: raw.webcam_track_visible,
      textOverlayCount: Int(raw.text_overlay_count)
    )
  }

  func bootstrapCaptureTracks(sourceHasAudio: Bool, sourceHasWebcamAsset: Bool) -> Bool {
    vs_timeline_bootstrap_capture_tracks(handle, sourceHasAudio, sourceHasWebcamAsset) == 0
  }

  func addTextClipAutoTrack(startMS: UInt32, endMS: UInt32, text: String) -> UInt32? {
    let bytes = Array(text.utf8)
    guard !bytes.isEmpty else {
      return nil
    }
    var clipID: UInt32 = 0
    let status = bytes.withUnsafeBufferPointer { ptr in
      vs_timeline_add_text_clip_auto_track(
        handle,
        startMS,
        endMS,
        ptr.baseAddress,
        UInt32(ptr.count),
        &clipID
      )
    }
    return status == 0 ? clipID : nil
  }

  // MARK: Clips

  func addClip(trackIndex: Int, startMS: UInt32, endMS: UInt32, kind: TimelineTrackKind) -> UInt32? {
    var clipID: UInt32 = 0
    let result = vs_timeline_add_clip(handle, UInt32(trackIndex), startMS, endMS, kind.rawValue, &clipID)
    guard result == 0 else { return nil }
    return clipID
  }

  func removeClip(trackIndex: Int, clipID: UInt32) -> Bool {
    vs_timeline_remove_clip(handle, UInt32(trackIndex), clipID) == 0
  }

  func moveClip(trackIndex: Int, clipID: UInt32, newStartMS: UInt32) -> Bool {
    vs_timeline_move_clip(handle, UInt32(trackIndex), clipID, newStartMS) == 0
  }

  func resizeClip(trackIndex: Int, clipID: UInt32, newStartMS: UInt32, newEndMS: UInt32) -> Bool {
    vs_timeline_resize_clip(handle, UInt32(trackIndex), clipID, newStartMS, newEndMS) == 0
  }

  func splitClip(trackIndex: Int, clipID: UInt32, splitAtMS: UInt32) -> UInt32? {
    var newClipID: UInt32 = 0
    let result = vs_timeline_split_clip(handle, UInt32(trackIndex), clipID, splitAtMS, &newClipID)
    guard result == 0 else { return nil }
    return newClipID
  }

  func updateClipTransform(trackIndex: Int, clipID: UInt32, transform: ClipTransform) -> Bool {
    let ffiTransform = vs_clip_transform(
      x: transform.x,
      y: transform.y,
      width: transform.width,
      height: transform.height,
      rotation: transform.rotation,
      opacity: transform.opacity
    )
    return vs_timeline_update_clip_transform(handle, UInt32(trackIndex), clipID, ffiTransform) == 0
  }

  // MARK: Clip Data

  func setClipText(trackIndex: Int, clipID: UInt32, text: String) -> Bool {
    let bytes = Array(text.utf8)
    return bytes.withUnsafeBufferPointer { ptr in
      vs_timeline_set_clip_text(handle, UInt32(trackIndex), clipID, ptr.baseAddress, UInt32(ptr.count))
    } == 0
  }

  func setClipTextStyle(trackIndex: Int, clipID: UInt32, fontSize: Float, color: UInt32, bgColor: UInt32) -> Bool {
    vs_timeline_set_clip_text_style(handle, UInt32(trackIndex), clipID, fontSize, color, bgColor) == 0
  }

  func setClipShapeStyle(trackIndex: Int, clipID: UInt32, fill: UInt32, border: UInt32, borderWidth: Float, cornerRadius: Float) -> Bool {
    vs_timeline_set_clip_shape_style(handle, UInt32(trackIndex), clipID, fill, border, borderWidth, cornerRadius) == 0
  }

  struct ShapeClipStyle {
    let fill: UInt32
    let border: UInt32
    let borderWidth: Float
    let cornerRadius: Float
  }

  func getClipShapeStyle(trackIndex: Int, clipID: UInt32) -> ShapeClipStyle? {
    var fill: UInt32 = 0
    var border: UInt32 = 0
    var borderWidth: Float = 0
    var cornerRadius: Float = 0
    let result = vs_timeline_get_clip_shape_style(
      handle, UInt32(trackIndex), clipID,
      &fill, &border, &borderWidth, &cornerRadius
    )
    guard result == 0 else { return nil }
    return ShapeClipStyle(fill: fill, border: border, borderWidth: borderWidth, cornerRadius: cornerRadius)
  }

  // MARK: Query

  func getClips(trackIndex: Int) -> [TimelineClipInfo] {
    let infos = loadClipInfos(trackIndex: trackIndex)
    return infos.map { info in
      return TimelineClipInfo(
        id: info.id,
        trackIndex: Int(info.track_index),
        startMS: info.start_ms,
        endMS: info.end_ms,
        kind: TimelineTrackKind(rawValue: info.kind) ?? .video,
        transform: ClipTransform(
          x: info.transform.x,
          y: info.transform.y,
          width: info.transform.width,
          height: info.transform.height,
          rotation: info.transform.rotation,
          opacity: info.transform.opacity
        )
      )
    }
  }

  func getVisibleClips(atTimeMS: UInt32) -> [TimelineClipInfo] {
    let infos = loadVisibleClipInfos(atTimeMS: atTimeMS)
    return infos.map { info in
      return TimelineClipInfo(
        id: info.id,
        trackIndex: Int(info.track_index),
        startMS: info.start_ms,
        endMS: info.end_ms,
        kind: TimelineTrackKind(rawValue: info.kind) ?? .video,
        transform: ClipTransform(
          x: info.transform.x,
          y: info.transform.y,
          width: info.transform.width,
          height: info.transform.height,
          rotation: info.transform.rotation,
          opacity: info.transform.opacity
        )
      )
    }
  }

  func isWebcamTrackVisibleForExport() -> Bool {
    var visible = false
    let result = vs_timeline_is_webcam_track_visible_for_export(handle, &visible)
    return RustFFIStatus.isSuccess(result) ? visible : false
  }

  func getTextExportClips() -> [TimelineTextExportClipInfo] {
    let infos = loadTextExportClipInfos()
    return infos.map { info in
      TimelineTextExportClipInfo(
        trackIndex: Int(info.track_index),
        clipID: info.clip_id,
        startMS: info.start_ms,
        endMS: info.end_ms
      )
    }
  }

  func getClipText(trackIndex: Int, clipID: UInt32) -> String? {
    var capacity = 256
    while capacity <= Self.maxTextBytes {
      var buffer = [UInt8](repeating: 0, count: capacity)
      var written: UInt32 = 0
      let result = buffer.withUnsafeMutableBufferPointer { ptr in
        vs_timeline_get_clip_text(handle, UInt32(trackIndex), clipID, ptr.baseAddress, UInt32(ptr.count), &written)
      }
      guard result == 0 else { return nil }

      let required = Int(written)
      guard required > 0 else { return nil }

      if required <= buffer.count {
        return String(bytes: buffer[0..<required], encoding: .utf8)
      }

      capacity = max(capacity * 2, required)
    }
    return nil
  }

  // MARK: Undo/Redo

  func undo() -> Bool {
    vs_timeline_undo(handle) == 0
  }

  func redo() -> Bool {
    vs_timeline_redo(handle) == 0
  }

  // MARK: Video Info

  func getVideoInfo() -> (durationMS: UInt32, width: UInt32, height: UInt32)? {
    var durationMS: UInt32 = 0
    var width: UInt32 = 0
    var height: UInt32 = 0
    let result = vs_timeline_get_video_info(handle, &durationMS, &width, &height)
    guard result == 0 else { return nil }
    return (durationMS, width, height)
  }

  // MARK: Zoom Scale

  func setClipZoomScale(trackIndex: Int, clipID: UInt32, scale: Float) -> Bool {
    vs_timeline_set_clip_zoom_scale(handle, UInt32(trackIndex), clipID, scale) == 0
  }

  func getClipZoomScale(trackIndex: Int, clipID: UInt32) -> Float? {
    var scale: Float = 0
    let result = vs_timeline_get_clip_zoom_scale(handle, UInt32(trackIndex), clipID, &scale)
    guard result == 0 else { return nil }
    return scale
  }

  private func loadTrackInfos() -> [vs_timeline_track_info] {
    var capacity = 64
    while capacity <= Self.maxTimelineBufferCount {
      var buffer = [vs_timeline_track_info](repeating: vs_timeline_track_info(), count: capacity)
      var written: UInt32 = 0
      let result = buffer.withUnsafeMutableBufferPointer { ptr in
        vs_timeline_get_tracks(handle, ptr.baseAddress, UInt32(ptr.count), &written)
      }
      guard result == 0 else { return [] }

      let total = Int(written)
      if total <= buffer.count {
        return Array(buffer.prefix(total))
      }

      capacity = max(capacity * 2, total)
    }
    return []
  }

  private func loadClipInfos(trackIndex: Int) -> [vs_timeline_clip_info] {
    var capacity = 256
    while capacity <= Self.maxTimelineBufferCount {
      var buffer = [vs_timeline_clip_info](repeating: vs_timeline_clip_info(), count: capacity)
      var written: UInt32 = 0
      let result = buffer.withUnsafeMutableBufferPointer { ptr in
        vs_timeline_get_clips(handle, UInt32(trackIndex), ptr.baseAddress, UInt32(ptr.count), &written)
      }
      guard result == 0 else { return [] }

      let total = Int(written)
      if total <= buffer.count {
        return Array(buffer.prefix(total))
      }

      capacity = max(capacity * 2, total)
    }
    return []
  }

  private func loadVisibleClipInfos(atTimeMS: UInt32) -> [vs_timeline_clip_info] {
    var capacity = 256
    while capacity <= Self.maxTimelineBufferCount {
      var buffer = [vs_timeline_clip_info](repeating: vs_timeline_clip_info(), count: capacity)
      var written: UInt32 = 0
      let result = buffer.withUnsafeMutableBufferPointer { ptr in
        vs_timeline_get_visible_clips_at(handle, atTimeMS, ptr.baseAddress, UInt32(ptr.count), &written)
      }
      guard result == 0 else { return [] }

      let total = Int(written)
      if total <= buffer.count {
        return Array(buffer.prefix(total))
      }

      capacity = max(capacity * 2, total)
    }
    return []
  }

  private func loadTextExportClipInfos() -> [vs_timeline_text_export_clip_info] {
    var capacity = 256
    while capacity <= Self.maxTimelineBufferCount {
      var buffer = [vs_timeline_text_export_clip_info](
        repeating: vs_timeline_text_export_clip_info(),
        count: capacity
      )
      var written: UInt32 = 0
      let result = buffer.withUnsafeMutableBufferPointer { ptr in
        vs_timeline_get_text_export_clips(handle, ptr.baseAddress, UInt32(ptr.count), &written)
      }
      guard RustFFIStatus.isSuccess(result) else { return [] }

      let total = Int(written)
      if total <= buffer.count {
        return Array(buffer.prefix(total))
      }

      capacity = max(capacity * 2, total)
    }
    return []
  }
}

