import AppKit
import CoreGraphics
import Foundation

struct TextAnnotationStyle {
  let fontSize: CGFloat
  let color: NSColor

  static let `default` = TextAnnotationStyle(
    fontSize: 16,
    color: .white
  )
}

struct RustAnnotationInfo {
  let index: Int
  let kind: Int
  let bounds: CGRect

  func contains(_ point: CGPoint) -> Bool {
    let x = point.x
    let y = point.y
    return x >= bounds.minX && x <= bounds.maxX && y >= bounds.minY && y <= bounds.maxY
  }
}

struct RustVideoSessionConfig {
  let frameRate: Int
  let captureSystemAudio: Bool
  let captureMicrophone: Bool
  let showWebcam: Bool
  let highlightMouseClicks: Bool
  let highlightKeystrokes: Bool
}

struct RustVideoExportPlan {
  let trimStartMS: Int
  let trimEndMS: Int
  let keyEventCount: Int
  let clickEventCount: Int
  let planMode: UInt8
  let includeAudio: Bool
  let includeWebcam: Bool
  let textOverlayCount: Int
  let overlayItemCount: Int
  let requiresIntermediateForGIF: Bool
  let needsCustomCompositor: Bool
}

struct RustVideoExportContext {
  let sourceHasAudio: Bool
  let sourceHasWebcamAsset: Bool
  let audioTrackVisible: Bool
  let webcamTrackVisible: Bool
  let textOverlayCount: Int
}

enum RustVideoPlanMode: UInt8 {
  case passthrough = 0
  case compositeMP4 = 1
}

struct RustStitchSessionResult {
  let accepted: Bool
  let rows: Int
  let side: UInt8
  let score: Double
  let directionLocked: Bool
  let expectedRows: Int
  let segmentCount: Int
  let scrollDirectionSign: Int
}

@MainActor
final class RustCoreBridge {
  static let shared = RustCoreBridge()

  private init() {}

  func makeSession(image: CGImage) -> RustDocumentSession? {
    RustDocumentSession(image: image)
  }

  func makeVideoSession(config: RustVideoSessionConfig) -> RustVideoSession? {
    RustVideoSession(config: config)
  }

  func makeStitchSession() -> RustStitchSession? {
    RustStitchSession()
  }

  func makeTimelineSession(durationMS: UInt32, width: UInt32, height: UInt32) -> RustTimelineSession? {
    RustTimelineSession(durationMS: durationMS, width: width, height: height)
  }
}

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

final class RustStitchSession {
  private let handle: UnsafeMutableRawPointer

  init?() {
    guard let rawHandle = vs_stitch_session_create() else {
      return nil
    }
    handle = rawHandle
  }

  deinit {
    vs_stitch_session_destroy(handle)
  }

  func reset(baseSegmentCount: Int = 1) -> Bool {
    vs_stitch_session_reset(handle, UInt32(max(1, baseSegmentCount))) == 0
  }

  func setBaseImage(_ image: CGImage, baseSegmentCount: Int = 1) -> Bool {
    guard let raster = RasterImage.from(cgImage: image) else {
      return false
    }
    return raster.pixels.withUnsafeBytes { raw in
      guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
        return false
      }
      let view = vs_bgra_image_view(
        width: UInt32(raster.width),
        height: UInt32(raster.height),
        stride: UInt32(raster.stride),
        ptr: base,
        len: UInt(raw.count)
      )
      return vs_stitch_session_set_base_bgra(handle, view, UInt32(max(1, baseSegmentCount))) == 0
    }
  }

  func pushFrame(_ frame: CGImage) -> RustStitchSessionResult? {
    guard let raster = RasterImage.from(cgImage: frame) else {
      return nil
    }
    var rawResult = vs_stitch_session_result()
    let status = raster.pixels.withUnsafeBytes { raw in
      guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
        return Int32(-1)
      }
      let view = vs_bgra_image_view(
        width: UInt32(raster.width),
        height: UInt32(raster.height),
        stride: UInt32(raster.stride),
        ptr: base,
        len: UInt(raw.count)
      )
      return vs_stitch_session_push_frame_bgra(handle, view, &rawResult)
    }
    guard status == 0 else {
      return nil
    }
    return Self.mapResult(rawResult)
  }

  func pushFrameAndMerge(_ frame: CGImage) -> (RustStitchSessionResult, CGImage?)? {
    guard let raster = RasterImage.from(cgImage: frame) else {
      return nil
    }
    var rawResult = vs_stitch_session_result()
    var rawImage = vs_bgra_owned_image(width: 0, height: 0, stride: 0, ptr: nil, len: 0)
    defer {
      vs_bgra_owned_image_destroy(&rawImage)
    }

    let status = raster.pixels.withUnsafeBytes { raw in
      guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
        return Int32(-1)
      }
      let view = vs_bgra_image_view(
        width: UInt32(raster.width),
        height: UInt32(raster.height),
        stride: UInt32(raster.stride),
        ptr: base,
        len: UInt(raw.count)
      )
      return vs_stitch_session_push_frame_and_merge_bgra(handle, view, &rawResult, &rawImage)
    }
    guard status == 0 else {
      return nil
    }

    let mergedImage = Self.makeImage(from: rawImage)
    return (Self.mapResult(rawResult), mergedImage)
  }

  func mergedImage() -> CGImage? {
    var rawImage = vs_bgra_owned_image(width: 0, height: 0, stride: 0, ptr: nil, len: 0)
    defer {
      vs_bgra_owned_image_destroy(&rawImage)
    }
    let status = vs_stitch_session_get_merged_image_bgra(handle, &rawImage)
    guard status == 0 else {
      return nil
    }
    return Self.makeImage(from: rawImage)
  }

  private static func mapResult(_ raw: vs_stitch_session_result) -> RustStitchSessionResult {
    RustStitchSessionResult(
      accepted: raw.accepted,
      rows: Int(raw.rows),
      side: raw.side,
      score: Double(raw.score),
      directionLocked: raw.direction_locked,
      expectedRows: Int(raw.expected_rows),
      segmentCount: Int(raw.segment_count),
      scrollDirectionSign: Int(raw.scroll_direction_sign)
    )
  }

  private static func makeImage(from raw: vs_bgra_owned_image) -> CGImage? {
    guard let ptr = raw.ptr, raw.len > 0 else {
      return nil
    }
    let pixels = Array(UnsafeBufferPointer(start: ptr, count: Int(raw.len)))
    let raster = RasterImage(
      width: Int(raw.width),
      height: Int(raw.height),
      stride: Int(raw.stride),
      pixels: pixels
    )
    return raster.toCGImage()
  }
}

final class RustDocumentSession {
  private let handle: UnsafeMutableRawPointer
  private let width: Int
  private let height: Int
  private let stride: Int
  private var outputPixels: [UInt8]

  init?(image: CGImage) {
    guard let raster = RasterImage.from(cgImage: image) else {
      return nil
    }

    let createdHandle: UnsafeMutableRawPointer? = raster.pixels.withUnsafeBytes { raw in
      guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
        return nil
      }

      return vs_create_document_from_bgra(
        UInt32(raster.width),
        UInt32(raster.height),
        UInt32(raster.stride),
        base,
        UInt(raw.count)
      )
    }

    guard let createdHandle else {
      return nil
    }

    self.handle = createdHandle
    self.width = raster.width
    self.height = raster.height
    self.stride = raster.stride
    self.outputPixels = raster.pixels

    let renderStatus = outputPixels.withUnsafeMutableBytes { raw in
      guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
        return Int32(-1)
      }
      return vs_render_full(handle, base, UInt(raw.count))
    }

    guard renderStatus == 0 else {
      vs_destroy_document(createdHandle)
      return nil
    }
  }

  deinit {
    vs_destroy_document(handle)
  }

  func currentImage() -> CGImage? {
    RasterImage(width: width, height: height, stride: stride, pixels: outputPixels).toCGImage()
  }

  func addRect(
    imageRect: CGRect,
    color: NSColor = .systemOrange,
    strokeWidth: UInt32 = 4
  ) -> CGImage? {
    let cmd = makeRectCommand(from: imageRect, color: color, strokeWidth: strokeWidth)
    guard vs_add_rect(handle, cmd) == 0 else {
      return nil
    }

    guard renderDirty() else {
      return nil
    }

    return currentImage()
  }

  func addFilledRect(
    imageRect: CGRect,
    color: NSColor = .systemOrange
  ) -> CGImage? {
    let cmd = makeRectCommand(from: imageRect, color: color, strokeWidth: 1)
    guard vs_add_filled_rect(handle, cmd) == 0 else {
      return nil
    }

    guard renderDirty() else {
      return nil
    }

    return currentImage()
  }

  func addCircle(
    imageRect: CGRect,
    color: NSColor = .systemOrange,
    strokeWidth: UInt32 = 4
  ) -> CGImage? {
    let cmd = makeEllipseCommand(from: imageRect, color: color, strokeWidth: strokeWidth)
    guard vs_add_ellipse(handle, cmd) == 0 else {
      return nil
    }

    guard renderDirty() else {
      return nil
    }

    return currentImage()
  }

  func addFilledCircle(
    imageRect: CGRect,
    color: NSColor = .systemOrange
  ) -> CGImage? {
    let cmd = makeEllipseCommand(from: imageRect, color: color, strokeWidth: 1)
    guard vs_add_filled_ellipse(handle, cmd) == 0 else {
      return nil
    }

    guard renderDirty() else {
      return nil
    }

    return currentImage()
  }

  func addLine(
    from start: CGPoint,
    to end: CGPoint,
    color: NSColor = .systemOrange,
    strokeWidth: UInt32 = 4
  ) -> CGImage? {
    let cmd = makeLineCommand(from: start, to: end, color: color, strokeWidth: strokeWidth)
    guard vs_add_line(handle, cmd) == 0 else {
      return nil
    }

    guard renderDirty() else {
      return nil
    }

    return currentImage()
  }

  func addPath(
    _ points: [CGPoint],
    color: NSColor = .systemOrange,
    strokeWidth: UInt32 = 6
  ) -> CGImage? {
    let commandPoints = makePathPoints(points)
    guard !commandPoints.isEmpty else {
      return currentImage()
    }

    let style = makePathStyle(color: color, strokeWidth: strokeWidth)
    let status = commandPoints.withUnsafeBufferPointer { buffer in
      guard let base = buffer.baseAddress else {
        return Int32(-1)
      }
      return vs_add_path(handle, base, UInt(buffer.count), style)
    }

    guard status == 0 else {
      return nil
    }

    guard renderDirty() else {
      return nil
    }

    return currentImage()
  }

  func addArrow(
    from start: CGPoint,
    to end: CGPoint,
    color: NSColor = .systemOrange,
    strokeWidth: UInt32 = 5
  ) -> CGImage? {
    let cmd = makeArrowCommand(from: start, to: end, color: color, strokeWidth: strokeWidth)
    guard vs_add_arrow(handle, cmd) == 0 else {
      return nil
    }

    guard renderDirty() else {
      return nil
    }

    return currentImage()
  }

  func addText(_ text: String, at point: CGPoint, style: TextAnnotationStyle) -> CGImage? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return currentImage()
    }

    let cmd = makeTextCommand(at: point, style: style)
    let utf8 = Array(trimmed.utf8)

    let status = utf8.withUnsafeBytes { raw in
      guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
        return Int32(-1)
      }
      return vs_add_text(handle, base, UInt(raw.count), cmd)
    }

    guard status == 0 else {
      return nil
    }

    guard renderDirty() else {
      return nil
    }

    return currentImage()
  }

  func addPixelate(imageRect: CGRect) -> CGImage? {
    let cmd = makePixelateCommand(from: imageRect)
    guard vs_add_pixelate_rect(handle, cmd) == 0 else {
      return nil
    }

    guard renderDirty() else {
      return nil
    }

    return currentImage()
  }

  func addBlur(imageRect: CGRect) -> CGImage? {
    let cmd = makeBlurCommand(from: imageRect)
    guard vs_add_blur_rect(handle, cmd) == 0 else {
      return nil
    }

    guard renderDirty() else {
      return nil
    }

    return currentImage()
  }

  func undo() -> CGImage? {
    let status = vs_undo(handle)
    if status == 1 {
      return currentImage()
    }
    guard status == 0 else {
      return nil
    }

    guard renderDirty() else {
      return nil
    }

    return currentImage()
  }

  func redo() -> CGImage? {
    let status = vs_redo(handle)
    if status == 1 {
      return currentImage()
    }
    guard status == 0 else {
      return nil
    }

    guard renderDirty() else {
      return nil
    }

    return currentImage()
  }

  func listAnnotations() -> [RustAnnotationInfo] {
    var needed: UInt = 0
    let countStatus = vs_list_annotations(handle, nil, 0, &needed)
    guard countStatus == 0, needed > 0 else {
      return []
    }

    var rawInfos = Array(
      repeating: vs_annotation_info(index: 0, kind: 0, x: 0, y: 0, width: 0, height: 0),
      count: Int(needed)
    )
    var totalWritten: UInt = 0
    let listStatus = rawInfos.withUnsafeMutableBufferPointer { buffer in
      guard let base = buffer.baseAddress else {
        return Int32(-1)
      }
      return vs_list_annotations(handle, base, UInt(buffer.count), &totalWritten)
    }

    guard listStatus == 0 else {
      return []
    }

    let outputCount = min(rawInfos.count, Int(totalWritten))
    return rawInfos.prefix(outputCount).map { raw in
      RustAnnotationInfo(
        index: Int(raw.index),
        kind: Int(raw.kind),
        bounds: CGRect(
          x: CGFloat(raw.x),
          y: CGFloat(raw.y),
          width: CGFloat(max(0, raw.width)),
          height: CGFloat(max(0, raw.height))
        )
      )
    }
  }

  func hitTestAnnotation(at point: CGPoint) -> RustAnnotationInfo? {
    let infos = listAnnotations()
    for info in infos.reversed() where info.contains(point) {
      return info
    }
    return nil
  }

  func annotationInfo(index: Int) -> RustAnnotationInfo? {
    guard index >= 0 else {
      return nil
    }
    return listAnnotations().first { $0.index == index }
  }

  func moveAnnotation(index: Int, delta: CGPoint) -> CGImage? {
    let dx = Int32(delta.x.rounded())
    let dy = Int32(delta.y.rounded())
    if dx == 0 && dy == 0 {
      return currentImage()
    }

    guard index >= 0 else {
      return nil
    }

    let status = vs_move_annotation(handle, UInt32(index), dx, dy)
    if status == 1 {
      return currentImage()
    }
    guard status == 0 else {
      return nil
    }

    guard renderDirty() else {
      return nil
    }

    return currentImage()
  }

  func removeAnnotation(index: Int) -> CGImage? {
    guard index >= 0 else {
      return nil
    }

    let status = vs_remove_annotation(handle, UInt32(index))
    if status == 1 {
      return currentImage()
    }
    guard status == 0 else {
      return nil
    }

    guard renderDirty() else {
      return nil
    }

    return currentImage()
  }

  func resizeAnnotation(index: Int, imageRect: CGRect) -> CGImage? {
    guard index >= 0 else {
      return nil
    }

    let normalized = imageRect.standardized

    let x = clampToImageCoordinate(Int(normalized.minX.rounded(.down)), limit: width)
    let y = clampToImageCoordinate(Int(normalized.minY.rounded(.down)), limit: height)
    let maxWidth = max(1, width - x)
    let maxHeight = max(1, height - y)
    let commandWidth = min(maxWidth, max(1, Int(normalized.width.rounded(.up))))
    let commandHeight = min(maxHeight, max(1, Int(normalized.height.rounded(.up))))

    let status = vs_resize_annotation(
      handle,
      UInt32(index),
      Int32(x),
      Int32(y),
      Int32(commandWidth),
      Int32(commandHeight)
    )
    if status == 1 {
      return currentImage()
    }
    guard status == 0 else {
      return nil
    }

    guard renderDirty() else {
      return nil
    }

    return currentImage()
  }

  private func renderDirty() -> Bool {
    var dirty = vs_dirty_rect(x: 0, y: 0, width: 0, height: 0)
    var written: UInt = 0

    let status = outputPixels.withUnsafeMutableBytes { raw in
      guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
        return Int32(-1)
      }

      return vs_render_dirty(
        handle,
        base,
        UInt(raw.count),
        &dirty,
        1,
        &written
      )
    }

    return status == 0
  }

  private func makeRectCommand(
    from imageRect: CGRect,
    color: NSColor,
    strokeWidth: UInt32
  ) -> vs_rect_command {
    let normalized = imageRect.standardized

    let x = clampToImageCoordinate(Int(normalized.minX.rounded(.down)), limit: width)
    let y = clampToImageCoordinate(Int(normalized.minY.rounded(.down)), limit: height)

    let maxWidth = max(1, width - x)
    let maxHeight = max(1, height - y)
    let commandWidth = min(maxWidth, max(1, Int(normalized.width.rounded(.up))))
    let commandHeight = min(maxHeight, max(1, Int(normalized.height.rounded(.up))))

    let rgba = colorComponents(color)

    return vs_rect_command(
      x: Int32(x),
      y: Int32(y),
      width: Int32(commandWidth),
      height: Int32(commandHeight),
      stroke_width: strokeWidth,
      r: rgba.r,
      g: rgba.g,
      b: rgba.b,
      a: rgba.a
    )
  }

  private func makeLineCommand(
    from start: CGPoint,
    to end: CGPoint,
    color: NSColor,
    strokeWidth: UInt32
  ) -> vs_line_command {
    let sx = clampToImageCoordinate(Int(start.x.rounded()), limit: width)
    let sy = clampToImageCoordinate(Int(start.y.rounded()), limit: height)
    let ex = clampToImageCoordinate(Int(end.x.rounded()), limit: width)
    let ey = clampToImageCoordinate(Int(end.y.rounded()), limit: height)
    let rgba = colorComponents(color)

    return vs_line_command(
      x0: Int32(sx),
      y0: Int32(sy),
      x1: Int32(ex),
      y1: Int32(ey),
      stroke_width: strokeWidth,
      r: rgba.r,
      g: rgba.g,
      b: rgba.b,
      a: rgba.a
    )
  }

  private func makeEllipseCommand(
    from imageRect: CGRect,
    color: NSColor,
    strokeWidth: UInt32
  ) -> vs_ellipse_command {
    let normalized = imageRect.standardized

    let x = clampToImageCoordinate(Int(normalized.minX.rounded(.down)), limit: width)
    let y = clampToImageCoordinate(Int(normalized.minY.rounded(.down)), limit: height)

    let maxWidth = max(1, width - x)
    let maxHeight = max(1, height - y)
    let commandWidth = min(maxWidth, max(1, Int(normalized.width.rounded(.up))))
    let commandHeight = min(maxHeight, max(1, Int(normalized.height.rounded(.up))))

    let rgba = colorComponents(color)

    return vs_ellipse_command(
      x: Int32(x),
      y: Int32(y),
      width: Int32(commandWidth),
      height: Int32(commandHeight),
      stroke_width: strokeWidth,
      r: rgba.r,
      g: rgba.g,
      b: rgba.b,
      a: rgba.a
    )
  }

  private func makeArrowCommand(
    from start: CGPoint,
    to end: CGPoint,
    color: NSColor,
    strokeWidth: UInt32
  ) -> vs_arrow_command {
    let sx = clampToImageCoordinate(Int(start.x.rounded()), limit: width)
    let sy = clampToImageCoordinate(Int(start.y.rounded()), limit: height)
    let ex = clampToImageCoordinate(Int(end.x.rounded()), limit: width)
    let ey = clampToImageCoordinate(Int(end.y.rounded()), limit: height)
    let rgba = colorComponents(color)

    return vs_arrow_command(
      x0: Int32(sx),
      y0: Int32(sy),
      x1: Int32(ex),
      y1: Int32(ey),
      stroke_width: strokeWidth,
      r: rgba.r,
      g: rgba.g,
      b: rgba.b,
      a: rgba.a
    )
  }

  private func makePathStyle(color: NSColor, strokeWidth: UInt32) -> vs_path_style {
    let rgba = colorComponents(color)
    return vs_path_style(
      stroke_width: max(1, strokeWidth),
      r: rgba.r,
      g: rgba.g,
      b: rgba.b,
      a: rgba.a
    )
  }

  private func makePathPoints(_ points: [CGPoint]) -> [vs_point_i32] {
    var output: [vs_point_i32] = []
    output.reserveCapacity(points.count)

    var lastX = Int32.min
    var lastY = Int32.min
    for point in points {
      let x = Int32(clampToImageCoordinate(Int(point.x.rounded()), limit: width))
      let y = Int32(clampToImageCoordinate(Int(point.y.rounded()), limit: height))
      if x == lastX, y == lastY {
        continue
      }
      output.append(vs_point_i32(x: x, y: y))
      lastX = x
      lastY = y
    }

    return output
  }

  private func makeTextCommand(at point: CGPoint, style: TextAnnotationStyle) -> vs_text_command {
    let x = clampToImageCoordinate(Int(point.x.rounded()), limit: width)
    let y = clampToImageCoordinate(Int(point.y.rounded()), limit: height)
    let color = colorComponents(style.color)
    let fontPx = UInt32(clampToRange(Int(style.fontSize.rounded()), min: 8, max: 96))

    return vs_text_command(
      x: Int32(x),
      y: Int32(y),
      font_px: fontPx,
      r: color.r,
      g: color.g,
      b: color.b,
      a: color.a
    )
  }

  private func makePixelateCommand(from imageRect: CGRect) -> vs_pixelate_rect_command {
    let normalized = imageRect.standardized

    let x = clampToImageCoordinate(Int(normalized.minX.rounded(.down)), limit: width)
    let y = clampToImageCoordinate(Int(normalized.minY.rounded(.down)), limit: height)

    let maxWidth = max(1, width - x)
    let maxHeight = max(1, height - y)
    let commandWidth = min(maxWidth, max(1, Int(normalized.width.rounded(.up))))
    let commandHeight = min(maxHeight, max(1, Int(normalized.height.rounded(.up))))

    return vs_pixelate_rect_command(
      x: Int32(x),
      y: Int32(y),
      width: Int32(commandWidth),
      height: Int32(commandHeight),
      block_size: 12
    )
  }

  private func makeBlurCommand(from imageRect: CGRect) -> vs_blur_rect_command {
    let normalized = imageRect.standardized

    let x = clampToImageCoordinate(Int(normalized.minX.rounded(.down)), limit: width)
    let y = clampToImageCoordinate(Int(normalized.minY.rounded(.down)), limit: height)

    let maxWidth = max(1, width - x)
    let maxHeight = max(1, height - y)
    let commandWidth = min(maxWidth, max(1, Int(normalized.width.rounded(.up))))
    let commandHeight = min(maxHeight, max(1, Int(normalized.height.rounded(.up))))

    return vs_blur_rect_command(
      x: Int32(x),
      y: Int32(y),
      width: Int32(commandWidth),
      height: Int32(commandHeight),
      radius: 4
    )
  }

  private func clampToImageCoordinate(_ value: Int, limit: Int) -> Int {
    guard limit > 0 else {
      return 0
    }
    return min(max(0, value), limit - 1)
  }

  private func clampToRange(_ value: Int, min lower: Int, max upper: Int) -> Int {
    Swift.max(lower, Swift.min(value, upper))
  }

  private func colorComponents(_ color: NSColor) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
    guard let rgb = color.usingColorSpace(.deviceRGB) else {
      return (255, 255, 255, 245)
    }

    var r: CGFloat = 1
    var g: CGFloat = 1
    var b: CGFloat = 1
    var a: CGFloat = 1
    rgb.getRed(&r, green: &g, blue: &b, alpha: &a)

    return (
      uint8FromUnit(r),
      uint8FromUnit(g),
      uint8FromUnit(b),
      uint8FromUnit(a)
    )
  }

  private func uint8FromUnit(_ value: CGFloat) -> UInt8 {
    let scaled = (value * 255).rounded()
    let clamped = Swift.max(0, Swift.min(255, scaled))
    return UInt8(clamped)
  }
}

private struct RasterImage {
  let width: Int
  let height: Int
  let stride: Int
  let pixels: [UInt8]

  static func from(cgImage: CGImage) -> RasterImage? {
    let width = cgImage.width
    let height = cgImage.height
    let stride = width * 4
    var pixels = [UInt8](repeating: 0, count: stride * height)

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue

    let drawStatus = pixels.withUnsafeMutableBytes { raw -> Bool in
      guard let baseAddress = raw.baseAddress else {
        return false
      }

      guard let context = CGContext(
        data: baseAddress,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: stride,
        space: colorSpace,
        bitmapInfo: bitmapInfo
      ) else {
        return false
      }

      context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }

    guard drawStatus else {
      return nil
    }

    return RasterImage(width: width, height: height, stride: stride, pixels: pixels)
  }

  func toCGImage() -> CGImage? {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue

    let data = Data(pixels)
    guard let provider = CGDataProvider(data: data as CFData) else {
      return nil
    }

    return CGImage(
      width: width,
      height: height,
      bitsPerComponent: 8,
      bitsPerPixel: 32,
      bytesPerRow: stride,
      space: colorSpace,
      bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
      provider: provider,
      decode: nil,
      shouldInterpolate: false,
      intent: .defaultIntent
    )
  }
}

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
}
