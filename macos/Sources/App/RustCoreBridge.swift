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

struct RustVideoExportDecision {
  let useCustomCompositor: Bool
  let requiresIntermediateForGIF: Bool
  let includeAudio: Bool
  let includeWebcam: Bool
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

enum RustVideoExportTarget: UInt8 {
  case mp4 = 0
  case gif = 1
}

enum RustImageEncodeFormat: UInt8 {
  case png = 0
  case jpeg = 1
}

enum RustFFIStatus: Int32 {
  case ok = 0
  case noChange = 1
  case nullPointer = -1
  case invalidArgument = -2
  case rejected = -3
  case bufferTooSmall = -4
  case notFound = -5

  static func isSuccess(_ raw: Int32, allowNoChange: Bool = false) -> Bool {
    if raw == RustFFIStatus.ok.rawValue {
      return true
    }
    if allowNoChange, raw == RustFFIStatus.noChange.rawValue {
      return true
    }
    return false
  }
}

enum RustTrimHandle: UInt8 {
  case unknown = 0
  case start = 1
  case end = 2
}

struct RustGIFExportPlan {
  let startMS: UInt32
  let endMS: UInt32
  let frameRate: Double
  let frameCount: Int
  let maxDimension: Int
  let frameDelayMS: Int
}

struct RustStitchAutoScrollState {
  var directionSign: Int32
  var noMotionTicks: UInt32
  var didFlipDirection: Bool
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

  func cropImage(_ image: CGImage, imageRect: CGRect) -> CGImage? {
    guard let raster = RasterImage.from(cgImage: image) else {
      return nil
    }

    let standardized = imageRect.standardized.integral
    let maxWidth = raster.width
    let maxHeight = raster.height
    guard maxWidth > 0, maxHeight > 0 else {
      return nil
    }

    var x = Int(floor(standardized.minX))
    var y = Int(floor(standardized.minY))
    var width = Int(ceil(standardized.width))
    var height = Int(ceil(standardized.height))
    guard width > 0, height > 0 else {
      return nil
    }

    x = min(max(0, x), maxWidth - 1)
    y = min(max(0, y), maxHeight - 1)
    width = min(width, maxWidth - x)
    height = min(height, maxHeight - y)
    guard width > 0, height > 0 else {
      return nil
    }

    var rawCropped = vs_bgra_owned_image(width: 0, height: 0, stride: 0, ptr: nil, len: 0)
    defer {
      vs_bgra_owned_image_destroy(&rawCropped)
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
      return vs_bgra_crop(
        view,
        UInt32(x),
        UInt32(y),
        UInt32(width),
        UInt32(height),
        &rawCropped
      )
    }

    guard status == 0, let ptr = rawCropped.ptr, rawCropped.len > 0 else {
      return nil
    }

    let pixels = Array(UnsafeBufferPointer(start: ptr, count: Int(rawCropped.len)))
    let cropped = RasterImage(
      width: Int(rawCropped.width),
      height: Int(rawCropped.height),
      stride: Int(rawCropped.stride),
      pixels: pixels
    )
    return cropped.toCGImage()
  }

  func moveSelectionRect(current: CGRect, bounds: CGRect, delta: CGPoint) -> CGRect? {
    var outRect = vs_f32_rect()
    let status = vs_selection_move_rect(
      Self.makeF32Rect(current),
      Self.makeF32Rect(bounds),
      Float(delta.x),
      Float(delta.y),
      &outRect
    )
    guard status == 0 else {
      return nil
    }
    return Self.makeCGRect(outRect).standardized
  }

  func resizeSelectionRect(
    start: CGRect,
    bounds: CGRect,
    corner: ResizeCorner,
    delta: CGPoint,
    minWidth: CGFloat = 80,
    minHeight: CGFloat = 60
  ) -> CGRect? {
    var outRect = vs_f32_rect()
    let status = vs_selection_resize_rect(
      Self.makeF32Rect(start),
      Self.makeF32Rect(bounds),
      Self.resizeCornerCode(corner),
      Float(delta.x),
      Float(delta.y),
      Float(minWidth),
      Float(minHeight),
      &outRect
    )
    guard status == 0 else {
      return nil
    }
    return Self.makeCGRect(outRect).standardized
  }

  func encodeImage(_ image: CGImage, format: RustImageEncodeFormat, jpegQuality: Int = 90) -> Data? {
    guard let raster = RasterImage.from(cgImage: image) else {
      return nil
    }

    var rawBytes = vs_encoded_bytes(ptr: nil, len: 0)
    defer {
      vs_encoded_bytes_destroy(&rawBytes)
    }

    let clampedQuality = UInt8(max(1, min(100, jpegQuality)))
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
      return vs_encode_bgra_image(view, format.rawValue, clampedQuality, &rawBytes)
    }
    guard status == 0, let ptr = rawBytes.ptr, rawBytes.len > 0 else {
      return nil
    }
    return Data(bytes: ptr, count: Int(rawBytes.len))
  }

  func computeVideoExportPlan(
    trimStartMS: Int,
    trimEndMS: Int,
    keyEventCount: Int,
    clickEventCount: Int,
    context: RustVideoExportContext
  ) -> RustVideoExportPlan? {
    guard trimStartMS >= 0, trimEndMS >= 0, keyEventCount >= 0, clickEventCount >= 0 else {
      return nil
    }
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
    let rawContext = vs_video_export_context(
      source_has_audio: context.sourceHasAudio,
      source_has_webcam_asset: context.sourceHasWebcamAsset,
      audio_track_visible: context.audioTrackVisible,
      webcam_track_visible: context.webcamTrackVisible,
      text_overlay_count: UInt32(max(0, context.textOverlayCount))
    )
    let status = vs_video_compute_export_plan(
      UInt32(trimStartMS),
      UInt32(trimEndMS),
      UInt32(keyEventCount),
      UInt32(clickEventCount),
      rawContext,
      &raw
    )
    guard RustFFIStatus.isSuccess(status) else {
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

  func deriveVideoExportDecision(
    target: RustVideoExportTarget,
    plan: RustVideoExportPlan
  ) -> RustVideoExportDecision? {
    let rawPlan = vs_video_export_plan(
      trim_start_ms: UInt32(max(0, plan.trimStartMS)),
      trim_end_ms: UInt32(max(0, plan.trimEndMS)),
      key_event_count: UInt32(max(0, plan.keyEventCount)),
      click_event_count: UInt32(max(0, plan.clickEventCount)),
      plan_mode: plan.planMode,
      include_audio: plan.includeAudio,
      include_webcam: plan.includeWebcam,
      text_overlay_count: UInt32(max(0, plan.textOverlayCount)),
      overlay_item_count: UInt32(max(0, plan.overlayItemCount)),
      requires_intermediate_for_gif: plan.requiresIntermediateForGIF,
      needs_custom_compositor: plan.needsCustomCompositor
    )
    var rawDecision = vs_video_export_decision(
      use_custom_compositor: false,
      requires_intermediate_for_gif: false,
      include_audio: false,
      include_webcam: false
    )
    let status = vs_video_derive_export_decision(target.rawValue, rawPlan, &rawDecision)
    guard RustFFIStatus.isSuccess(status) else {
      return nil
    }
    return RustVideoExportDecision(
      useCustomCompositor: rawDecision.use_custom_compositor,
      requiresIntermediateForGIF: rawDecision.requires_intermediate_for_gif,
      includeAudio: rawDecision.include_audio,
      includeWebcam: rawDecision.include_webcam
    )
  }

  nonisolated static func normalizeKeyTokenPortable(
    keyCode: UInt16,
    modifiers: UInt32,
    characters: String?
  ) -> String? {
    let charsData = characters?.data(using: .utf8)
    let charsLen = UInt32(charsData?.count ?? 0)

    var capacity = 64
    while capacity <= 1024 {
      var buffer = [UInt8](repeating: 0, count: capacity)
      var written: UInt32 = 0
      let status: Int32 = buffer.withUnsafeMutableBufferPointer { out in
        let outPtr = out.baseAddress
        let outCap = UInt32(out.count)
        return charsData.map { data in
          data.withUnsafeBytes { raw in
            let charsPtr = raw.baseAddress?.assumingMemoryBound(to: UInt8.self)
            return vs_normalize_key_token(
              keyCode,
              modifiers,
              charsPtr,
              charsLen,
              outPtr,
              outCap,
              &written
            )
          }
        } ?? vs_normalize_key_token(
          keyCode,
          modifiers,
          nil,
          0,
          outPtr,
          outCap,
          &written
        )
      }

      guard status == 0 else {
        return nil
      }
      if Int(written) <= buffer.count {
        let token = String(decoding: buffer.prefix(Int(written)), as: UTF8.self)
        return token.isEmpty ? nil : token
      }
      capacity = max(capacity * 2, Int(written))
    }
    return nil
  }

  func normalizeKeyToken(keyCode: UInt16, modifiers: UInt32, characters: String?) -> String? {
    Self.normalizeKeyTokenPortable(keyCode: keyCode, modifiers: modifiers, characters: characters)
  }

  nonisolated static func isDuplicateKeyEventPortable(
    lastTimestampNS: UInt64,
    lastToken: String,
    timestampNS: UInt64,
    token: String
  ) -> Bool {
    let lastBytes = Array(lastToken.utf8)
    let tokenBytes = Array(token.utf8)
    guard !lastBytes.isEmpty, !tokenBytes.isEmpty else {
      return false
    }
    return lastBytes.withUnsafeBufferPointer { lastPtr in
      tokenBytes.withUnsafeBufferPointer { tokenPtr in
        vs_key_event_is_duplicate(
          lastTimestampNS,
          lastPtr.baseAddress,
          UInt32(lastPtr.count),
          timestampNS,
          tokenPtr.baseAddress,
          UInt32(tokenPtr.count)
        )
      }
    }
  }

  func isDuplicateKeyEvent(
    lastTimestampNS: UInt64,
    lastToken: String,
    timestampNS: UInt64,
    token: String
  ) -> Bool {
    Self.isDuplicateKeyEventPortable(
      lastTimestampNS: lastTimestampNS,
      lastToken: lastToken,
      timestampNS: timestampNS,
      token: token
    )
  }

  nonisolated static func normalizeClickPointPortable(x: CGFloat, y: CGFloat) -> CGPoint? {
    var outX: Float = 0
    var outY: Float = 0
    let status = vs_normalize_click_point(Float(x), Float(y), &outX, &outY)
    guard status == 0 else {
      return nil
    }
    return CGPoint(x: CGFloat(outX), y: CGFloat(outY))
  }

  func normalizeClickPoint(x: CGFloat, y: CGFloat) -> CGPoint? {
    Self.normalizeClickPointPortable(x: x, y: y)
  }

  nonisolated static func isDuplicateClickEventPortable(
    lastTimestampNS: UInt64,
    lastButton: UInt32,
    lastX: CGFloat,
    lastY: CGFloat,
    timestampNS: UInt64,
    button: UInt32,
    x: CGFloat,
    y: CGFloat,
    epsilon: CGFloat = 0.0001
  ) -> Bool {
    vs_click_event_is_duplicate(
      lastTimestampNS,
      lastButton,
      Float(lastX),
      Float(lastY),
      timestampNS,
      button,
      Float(x),
      Float(y),
      Float(epsilon)
    )
  }

  func isDuplicateClickEvent(
    lastTimestampNS: UInt64,
    lastButton: UInt32,
    lastX: CGFloat,
    lastY: CGFloat,
    timestampNS: UInt64,
    button: UInt32,
    x: CGFloat,
    y: CGFloat,
    epsilon: CGFloat = 0.0001
  ) -> Bool {
    Self.isDuplicateClickEventPortable(
      lastTimestampNS: lastTimestampNS,
      lastButton: lastButton,
      lastX: lastX,
      lastY: lastY,
      timestampNS: timestampNS,
      button: button,
      x: x,
      y: y,
      epsilon: epsilon
    )
  }

  func viewRectToImageRect(viewRect: CGRect, destinationRect: CGRect, imageSize: CGSize) -> CGRect? {
    guard imageSize.width >= 1, imageSize.height >= 1 else {
      return nil
    }
    var outRect = vs_f32_rect()
    let status = vs_view_rect_to_image_rect(
      Self.makeF32Rect(viewRect),
      Self.makeF32Rect(destinationRect),
      UInt32(imageSize.width.rounded()),
      UInt32(imageSize.height.rounded()),
      &outRect
    )
    guard status == 0 else {
      return nil
    }
    return Self.makeCGRect(outRect).integral
  }

  func imageRectToViewRect(imageRect: CGRect, destinationRect: CGRect, imageSize: CGSize) -> CGRect? {
    guard imageSize.width >= 1, imageSize.height >= 1 else {
      return nil
    }
    var outRect = vs_f32_rect()
    let status = vs_image_rect_to_view_rect(
      Self.makeF32Rect(imageRect),
      Self.makeF32Rect(destinationRect),
      UInt32(imageSize.width.rounded()),
      UInt32(imageSize.height.rounded()),
      &outRect
    )
    guard status == 0 else {
      return nil
    }
    return Self.makeCGRect(outRect).integral
  }

  func viewDeltaToImageDelta(_ delta: CGPoint, destinationRect: CGRect, imageSize: CGSize) -> CGPoint? {
    guard imageSize.width >= 1, imageSize.height >= 1 else {
      return nil
    }
    var out = vs_f32_point()
    let status = vs_view_delta_to_image_delta(
      Float(delta.x),
      Float(delta.y),
      Self.makeF32Rect(destinationRect),
      UInt32(imageSize.width.rounded()),
      UInt32(imageSize.height.rounded()),
      &out
    )
    guard status == 0 else {
      return nil
    }
    return CGPoint(x: CGFloat(out.x), y: CGFloat(out.y))
  }

  func imageDeltaToViewDelta(_ delta: CGPoint, destinationRect: CGRect, imageSize: CGSize) -> CGPoint? {
    guard imageSize.width >= 1, imageSize.height >= 1 else {
      return nil
    }
    var out = vs_f32_point()
    let status = vs_image_delta_to_view_delta(
      Float(delta.x),
      Float(delta.y),
      Self.makeF32Rect(destinationRect),
      UInt32(imageSize.width.rounded()),
      UInt32(imageSize.height.rounded()),
      &out
    )
    guard status == 0 else {
      return nil
    }
    return CGPoint(x: CGFloat(out.x), y: CGFloat(out.y))
  }

  func clampPanOffset(
    boundsSize: CGSize,
    imageSize: CGSize,
    zoomScale: CGFloat,
    overscroll: CGFloat,
    candidate: CGPoint
  ) -> CGPoint? {
    guard imageSize.width >= 1, imageSize.height >= 1 else {
      return nil
    }
    var out = vs_f32_point()
    let status = vs_viewport_clamp_pan_offset(
      Float(boundsSize.width),
      Float(boundsSize.height),
      UInt32(imageSize.width.rounded()),
      UInt32(imageSize.height.rounded()),
      Float(zoomScale),
      Float(overscroll),
      Float(candidate.x),
      Float(candidate.y),
      &out
    )
    guard status == 0 else {
      return nil
    }
    return CGPoint(x: CGFloat(out.x), y: CGFloat(out.y))
  }

  func resizeRect(
    start: CGRect,
    bounds: CGRect,
    cornerCode: UInt8,
    delta: CGPoint,
    minWidth: CGFloat,
    minHeight: CGFloat
  ) -> CGRect? {
    var outRect = vs_f32_rect()
    let status = vs_selection_resize_rect(
      Self.makeF32Rect(start),
      Self.makeF32Rect(bounds),
      cornerCode,
      Float(delta.x),
      Float(delta.y),
      Float(minWidth),
      Float(minHeight),
      &outRect
    )
    guard status == 0 else {
      return nil
    }
    return Self.makeCGRect(outRect).standardized
  }

  func normalizeTrimRange(
    durationMS: UInt32,
    startMS: UInt32,
    endMS: UInt32,
    minGapMS: UInt32,
    activeHandle: RustTrimHandle
  ) -> (startMS: UInt32, endMS: UInt32)? {
    var outStart: UInt32 = 0
    var outEnd: UInt32 = 0
    let status = vs_normalize_trim_range(
      durationMS,
      startMS,
      endMS,
      minGapMS,
      activeHandle.rawValue,
      &outStart,
      &outEnd
    )
    guard status == 0 else {
      return nil
    }
    return (outStart, outEnd)
  }

  func buildGIFExportPlan(
    startMS: UInt32,
    endMS: UInt32,
    preferredFPS: Double = 12,
    maxDimension: Int = 960
  ) -> RustGIFExportPlan? {
    var raw = vs_gif_export_plan()
    let status = vs_build_gif_export_plan(
      startMS,
      endMS,
      Float(preferredFPS),
      UInt32(max(64, min(2048, maxDimension))),
      &raw
    )
    guard status == 0 else {
      return nil
    }
    return RustGIFExportPlan(
      startMS: raw.start_ms,
      endMS: raw.end_ms,
      frameRate: Double(raw.frame_rate),
      frameCount: Int(raw.frame_count),
      maxDimension: Int(raw.max_dimension),
      frameDelayMS: Int(raw.frame_delay_ms)
    )
  }

  func gifFrameTimeMS(plan: RustGIFExportPlan, index: Int) -> UInt32? {
    guard index >= 0 else {
      return nil
    }
    let rawPlan = vs_gif_export_plan(
      start_ms: plan.startMS,
      end_ms: plan.endMS,
      frame_rate: Float(plan.frameRate),
      frame_count: UInt32(max(1, plan.frameCount)),
      max_dimension: UInt32(max(64, plan.maxDimension)),
      frame_delay_ms: UInt32(max(1, plan.frameDelayMS))
    )
    var out: UInt32 = 0
    let status = vs_gif_frame_time_ms(rawPlan, UInt32(index), &out)
    return status == 0 ? out : nil
  }

  func resetStitchAutoScrollState() -> RustStitchAutoScrollState {
    var raw = vs_stitch_autoscroll_state()
    let status = vs_stitch_autoscroll_reset(&raw)
    if status == 0 {
      return RustStitchAutoScrollState(
        directionSign: raw.direction_sign,
        noMotionTicks: raw.no_motion_ticks,
        didFlipDirection: raw.did_flip_direction
      )
    }
    return RustStitchAutoScrollState(directionSign: -1, noMotionTicks: 0, didFlipDirection: false)
  }

  func updateStitchAutoScrollState(
    enabled: Bool,
    directionLocked: Bool,
    didMerge: Bool,
    thresholdTicks: UInt32,
    state: RustStitchAutoScrollState
  ) -> RustStitchAutoScrollState {
    var out = vs_stitch_autoscroll_state()
    let rawState = vs_stitch_autoscroll_state(
      direction_sign: state.directionSign,
      no_motion_ticks: state.noMotionTicks,
      did_flip_direction: state.didFlipDirection
    )
    let status = vs_stitch_autoscroll_update(
      enabled,
      directionLocked,
      didMerge,
      thresholdTicks,
      rawState,
      &out
    )
    guard status == 0 else {
      return state
    }
    return RustStitchAutoScrollState(
      directionSign: out.direction_sign,
      noMotionTicks: out.no_motion_ticks,
      didFlipDirection: out.did_flip_direction
    )
  }

  private static func makeF32Rect(_ rect: CGRect) -> vs_f32_rect {
    vs_f32_rect(
      x: Float(rect.origin.x),
      y: Float(rect.origin.y),
      width: Float(rect.size.width),
      height: Float(rect.size.height)
    )
  }

  private static func makeCGRect(_ rect: vs_f32_rect) -> CGRect {
    CGRect(
      x: CGFloat(rect.x),
      y: CGFloat(rect.y),
      width: CGFloat(rect.width),
      height: CGFloat(rect.height)
    )
  }

  private static func resizeCornerCode(_ corner: ResizeCorner) -> UInt8 {
    switch corner {
    case .topLeft:
      return 0
    case .top:
      return 1
    case .topRight:
      return 2
    case .right:
      return 3
    case .bottom:
      return 4
    case .left:
      return 5
    case .bottomLeft:
      return 6
    case .bottomRight:
      return 7
    }
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
    let rect = quantizedImageRect(imageRect)

    let status = vs_resize_annotation(
      handle,
      UInt32(index),
      rect.x,
      rect.y,
      rect.width,
      rect.height
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
    let rect = quantizedImageRect(imageRect)
    let rgba = quantizedColor(color)

    return vs_rect_command(
      x: rect.x,
      y: rect.y,
      width: rect.width,
      height: rect.height,
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
    let (sx, sy) = quantizedImagePoint(start)
    let (ex, ey) = quantizedImagePoint(end)
    let rgba = quantizedColor(color)

    return vs_line_command(
      x0: sx,
      y0: sy,
      x1: ex,
      y1: ey,
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
    let rect = quantizedImageRect(imageRect)
    let rgba = quantizedColor(color)

    return vs_ellipse_command(
      x: rect.x,
      y: rect.y,
      width: rect.width,
      height: rect.height,
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
    let (sx, sy) = quantizedImagePoint(start)
    let (ex, ey) = quantizedImagePoint(end)
    let rgba = quantizedColor(color)

    return vs_arrow_command(
      x0: sx,
      y0: sy,
      x1: ex,
      y1: ey,
      stroke_width: strokeWidth,
      r: rgba.r,
      g: rgba.g,
      b: rgba.b,
      a: rgba.a
    )
  }

  private func makePathStyle(color: NSColor, strokeWidth: UInt32) -> vs_path_style {
    let rgba = quantizedColor(color)
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
      let (x, y) = quantizedImagePoint(point)
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
    let (x, y) = quantizedImagePoint(point)
    let color = quantizedColor(style.color)
    let fontPx = UInt32(clampToRange(Int(style.fontSize.rounded()), min: 8, max: 96))

    return vs_text_command(
      x: x,
      y: y,
      font_px: fontPx,
      r: color.r,
      g: color.g,
      b: color.b,
      a: color.a
    )
  }

  private func makePixelateCommand(from imageRect: CGRect) -> vs_pixelate_rect_command {
    let rect = quantizedImageRect(imageRect)

    return vs_pixelate_rect_command(
      x: rect.x,
      y: rect.y,
      width: rect.width,
      height: rect.height,
      block_size: 12
    )
  }

  private func makeBlurCommand(from imageRect: CGRect) -> vs_blur_rect_command {
    let rect = quantizedImageRect(imageRect)

    return vs_blur_rect_command(
      x: rect.x,
      y: rect.y,
      width: rect.width,
      height: rect.height,
      radius: 4
    )
  }

  private func clampToRange(_ value: Int, min lower: Int, max upper: Int) -> Int {
    Swift.max(lower, Swift.min(value, upper))
  }

  private func quantizedImageRect(_ imageRect: CGRect) -> vs_i32_rect {
    var raw = vs_i32_rect()
    let status = vs_quantize_image_rect(
      UInt32(max(1, width)),
      UInt32(max(1, height)),
      vs_f32_rect(
        x: Float(imageRect.origin.x),
        y: Float(imageRect.origin.y),
        width: Float(imageRect.size.width),
        height: Float(imageRect.size.height)
      ),
      &raw
    )
    if status == 0 {
      return raw
    }
    return vs_i32_rect(x: 0, y: 0, width: Int32(max(1, width)), height: Int32(max(1, height)))
  }

  private func quantizedImagePoint(_ point: CGPoint) -> (Int32, Int32) {
    var outX: Int32 = 0
    var outY: Int32 = 0
    let status = vs_quantize_image_point(
      UInt32(max(1, width)),
      UInt32(max(1, height)),
      Float(point.x),
      Float(point.y),
      &outX,
      &outY
    )
    if status == 0 {
      return (outX, outY)
    }
    return (0, 0)
  }

  private func quantizedColor(_ color: NSColor) -> vs_rgba8 {
    guard let rgb = color.usingColorSpace(.deviceRGB) else {
      return vs_rgba8(r: 255, g: 255, b: 255, a: 245)
    }

    var r: CGFloat = 1
    var g: CGFloat = 1
    var b: CGFloat = 1
    var a: CGFloat = 1
    rgb.getRed(&r, green: &g, blue: &b, alpha: &a)

    var raw = vs_rgba8()
    let status = vs_quantize_rgba(Float(r), Float(g), Float(b), Float(a), &raw)
    if status == 0 {
      return raw
    }
    return vs_rgba8(r: 255, g: 255, b: 255, a: 245)
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
