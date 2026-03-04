import AppKit
import CoreGraphics
import Foundation

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

  nonisolated static func keyOverlayLabelLayoutPortable(
    renderSize: CGSize,
    charCount: Int
  ) -> RustVideoOverlayLabelLayout? {
    guard charCount >= 0 else {
      return nil
    }
    var raw = vs_video_overlay_label_layout()
    let status = vs_video_key_overlay_label_layout(
      Float(max(1, renderSize.width)),
      Float(max(1, renderSize.height)),
      UInt32(max(0, charCount)),
      &raw
    )
    guard RustFFIStatus.isSuccess(status) else {
      return nil
    }
    return RustVideoOverlayLabelLayout(
      width: CGFloat(raw.width),
      height: CGFloat(raw.height),
      y: CGFloat(raw.y),
      fontSize: CGFloat(raw.font_size)
    )
  }

  func keyOverlayLabelLayout(renderSize: CGSize, charCount: Int) -> RustVideoOverlayLabelLayout? {
    Self.keyOverlayLabelLayoutPortable(renderSize: renderSize, charCount: charCount)
  }

  nonisolated static func textOverlayLabelLayoutPortable(
    renderSize: CGSize,
    charCount: Int
  ) -> RustVideoOverlayLabelLayout? {
    guard charCount >= 0 else {
      return nil
    }
    var raw = vs_video_overlay_label_layout()
    let status = vs_video_text_overlay_label_layout(
      Float(max(1, renderSize.width)),
      Float(max(1, renderSize.height)),
      UInt32(max(0, charCount)),
      &raw
    )
    guard RustFFIStatus.isSuccess(status) else {
      return nil
    }
    return RustVideoOverlayLabelLayout(
      width: CGFloat(raw.width),
      height: CGFloat(raw.height),
      y: CGFloat(raw.y),
      fontSize: CGFloat(raw.font_size)
    )
  }

  func textOverlayLabelLayout(renderSize: CGSize, charCount: Int) -> RustVideoOverlayLabelLayout? {
    Self.textOverlayLabelLayoutPortable(renderSize: renderSize, charCount: charCount)
  }

  nonisolated static func overlayClipWindowPortable(
    clipStartSeconds: Double,
    clipEndSeconds: Double,
    trimStartSeconds: Double,
    minVisibleSeconds: Double = Double(VS_VIDEO_TEXT_MIN_VISIBLE_SECONDS)
  ) -> RustVideoOverlayClipWindow? {
    var raw = vs_video_overlay_clip_window()
    let status = vs_video_compute_overlay_clip_window(
      clipStartSeconds,
      clipEndSeconds,
      trimStartSeconds,
      minVisibleSeconds,
      &raw
    )
    guard RustFFIStatus.isSuccess(status) else {
      return nil
    }
    return RustVideoOverlayClipWindow(
      startSeconds: raw.start_seconds,
      endSeconds: raw.end_seconds,
      fadeDurationSeconds: raw.fade_duration_seconds
    )
  }

  func overlayClipWindow(
    clipStartSeconds: Double,
    clipEndSeconds: Double,
    trimStartSeconds: Double,
    minVisibleSeconds: Double = Double(VS_VIDEO_TEXT_MIN_VISIBLE_SECONDS)
  ) -> RustVideoOverlayClipWindow? {
    Self.overlayClipWindowPortable(
      clipStartSeconds: clipStartSeconds,
      clipEndSeconds: clipEndSeconds,
      trimStartSeconds: trimStartSeconds,
      minVisibleSeconds: minVisibleSeconds
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


