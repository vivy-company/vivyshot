import AppKit
import Darwin
import XCTest

final class VivyShotTests: XCTestCase {
  private struct SyntheticRaster {
    let width: Int
    let height: Int
    let stride: Int
    let pixels: [UInt8]
  }

  func testSmoke() {
    XCTAssertTrue(true)
  }

  func testPortableVideoExportPlanContract() {
    let context = vs_video_export_context(
      source_has_audio: true,
      source_has_webcam_asset: false,
      audio_track_visible: false,
      webcam_track_visible: true,
      text_overlay_count: 1
    )
    var plan = vs_video_export_plan(
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
    let status = vs_video_compute_export_plan(100, 800, 2, 1, context, &plan)
    XCTAssertEqual(status, 0)
    XCTAssertEqual(plan.plan_mode, 1)
    XCTAssertEqual(plan.overlay_item_count, 3)
    XCTAssertFalse(plan.include_audio)
    XCTAssertTrue(plan.needs_custom_compositor)
  }

  func testPortableTrimNormalizationContract() {
    var start: UInt32 = 0
    var end: UInt32 = 0
    let status = vs_normalize_trim_range(1_000, 950, 960, 100, 2, &start, &end)
    XCTAssertEqual(status, 0)
    XCTAssertEqual(start, 860)
    XCTAssertEqual(end, 960)
  }

  func testPortableGIFPlanAndTimingContract() {
    var plan = vs_gif_export_plan(start_ms: 0, end_ms: 0, frame_rate: 0, frame_count: 0, max_dimension: 0, frame_delay_ms: 0)
    XCTAssertEqual(vs_build_gif_export_plan(0, 1_000, 12, 9_999, &plan), 0)
    XCTAssertEqual(plan.frame_count, 12)
    XCTAssertEqual(plan.max_dimension, 2_048)
    var t0: UInt32 = 0
    var tLast: UInt32 = 0
    XCTAssertEqual(vs_gif_frame_time_ms(plan, 0, &t0), 0)
    XCTAssertEqual(vs_gif_frame_time_ms(plan, plan.frame_count - 1, &tLast), 0)
    XCTAssertEqual(t0, 0)
    XCTAssertEqual(tLast, 1_000)
  }

  func testPortableStitchAutoscrollContract() {
    var state = vs_stitch_autoscroll_state(direction_sign: 0, no_motion_ticks: 0, did_flip_direction: false)
    XCTAssertEqual(vs_stitch_autoscroll_reset(&state), 0)
    for _ in 0..<4 {
      var out = vs_stitch_autoscroll_state(direction_sign: 0, no_motion_ticks: 0, did_flip_direction: false)
      XCTAssertEqual(vs_stitch_autoscroll_update(true, false, false, 4, state, &out), 0)
      state = out
    }
    XCTAssertEqual(state.direction_sign, 1)
    XCTAssertEqual(state.no_motion_ticks, 0)
    XCTAssertTrue(state.did_flip_direction)
  }

  func testTimelineExportContracts() {
    guard let timeline = vs_timeline_create(9_000, 1280, 720) else {
      XCTFail("Unable to create timeline")
      return
    }
    defer { vs_timeline_destroy(timeline) }

    XCTAssertEqual(vs_timeline_add_track(timeline, 0), 0) // video
    XCTAssertEqual(vs_timeline_add_track(timeline, 1), 0) // webcam
    XCTAssertEqual(vs_timeline_add_track(timeline, 3), 0) // text (track index 2)

    var clipID: UInt32 = 0
    XCTAssertEqual(vs_timeline_add_clip(timeline, 1, 0, 8_000, 1, &clipID), 0)
    XCTAssertEqual(vs_timeline_add_clip(timeline, 2, 3_000, 4_000, 3, &clipID), 0)
    XCTAssertEqual(vs_timeline_add_clip(timeline, 2, 1_000, 2_000, 3, &clipID), 0)

    var webcamVisible = false
    XCTAssertEqual(vs_timeline_is_webcam_track_visible_for_export(timeline, &webcamVisible), 0)
    XCTAssertTrue(webcamVisible)

    var written: UInt32 = 0
    XCTAssertEqual(vs_timeline_get_text_export_clips(timeline, nil, 0, &written), 0)
    XCTAssertEqual(written, 2)

    var clips = [vs_timeline_text_export_clip_info](repeating: vs_timeline_text_export_clip_info(), count: Int(written))
    clips.withUnsafeMutableBufferPointer { ptr in
      XCTAssertEqual(
        vs_timeline_get_text_export_clips(timeline, ptr.baseAddress, UInt32(ptr.count), &written),
        0
      )
    }
    XCTAssertEqual(written, 2)
    XCTAssertEqual(clips[0].start_ms, 1_000)
    XCTAssertEqual(clips[1].start_ms, 3_000)

    XCTAssertEqual(vs_timeline_set_track_visible(timeline, 1, false), 0)
    webcamVisible = true
    XCTAssertEqual(vs_timeline_is_webcam_track_visible_for_export(timeline, &webcamVisible), 0)
    XCTAssertFalse(webcamVisible)
  }

  func testGeometryErrorEdgeContracts() {
    var outRect = vs_f32_rect()
    XCTAssertEqual(
      vs_view_rect_to_image_rect(
        vs_f32_rect(x: 0, y: 0, width: 10, height: 10),
        vs_f32_rect(x: 0, y: 0, width: 100, height: 100),
        0,
        1080,
        &outRect
      ),
      -2
    )

    var moved = vs_f32_rect()
    XCTAssertEqual(
      vs_selection_move_rect(
        vs_f32_rect(x: 10, y: 10, width: 40, height: 20),
        vs_f32_rect(x: 0, y: 0, width: 100, height: 60),
        Float.nan,
        0,
        &moved
      ),
      -2
    )

    var resized = vs_f32_rect()
    XCTAssertEqual(
      vs_selection_resize_rect(
        vs_f32_rect(x: 10, y: 10, width: 40, height: 20),
        vs_f32_rect(x: 0, y: 0, width: 100, height: 60),
        99,
        5,
        5,
        10,
        10,
        &resized
      ),
      -3
    )
  }

  func testRustFFIStatusSemantics() {
    func isSuccess(_ raw: Int32, allowNoChange: Bool = false) -> Bool {
      if raw == VS_STATUS_OK {
        return true
      }
      if allowNoChange && raw == VS_STATUS_NO_CHANGE {
        return true
      }
      return false
    }

    XCTAssertTrue(isSuccess(VS_STATUS_OK))
    XCTAssertFalse(isSuccess(VS_STATUS_NO_CHANGE))
    XCTAssertTrue(isSuccess(VS_STATUS_NO_CHANGE, allowNoChange: true))
    XCTAssertFalse(isSuccess(VS_STATUS_INVALID_ARGUMENT))
    XCTAssertFalse(isSuccess(VS_STATUS_NULL_POINTER))
  }

  func testVideoDecisionAndABIVersionStatusContracts() {
    let rawPlan = vs_video_export_plan(
      trim_start_ms: 100,
      trim_end_ms: 800,
      key_event_count: 2,
      click_event_count: 1,
      plan_mode: 1,
      include_audio: true,
      include_webcam: true,
      text_overlay_count: 1,
      overlay_item_count: 3,
      requires_intermediate_for_gif: true,
      needs_custom_compositor: true
    )
    var decision = vs_video_export_decision(
      use_custom_compositor: false,
      requires_intermediate_for_gif: false,
      include_audio: false,
      include_webcam: false
    )

    XCTAssertEqual(
      vs_video_derive_export_decision(UInt8(VS_VIDEO_EXPORT_TARGET_MP4), rawPlan, &decision),
      VS_STATUS_OK
    )
    XCTAssertTrue(decision.use_custom_compositor)
    XCTAssertTrue(decision.requires_intermediate_for_gif)

    XCTAssertEqual(
      vs_video_derive_export_decision(255, rawPlan, &decision),
      VS_STATUS_INVALID_ARGUMENT
    )
    XCTAssertEqual(
      vs_video_derive_export_decision(UInt8(VS_VIDEO_EXPORT_TARGET_GIF), rawPlan, nil),
      VS_STATUS_NULL_POINTER
    )

    var major: UInt32 = 0
    var minor: UInt32 = 0
    var patch: UInt32 = 0
    XCTAssertEqual(
      vs_core_abi_version(&major, &minor, &patch),
      VS_STATUS_OK
    )
    XCTAssertEqual(major, UInt32(VS_CORE_ABI_VERSION_MAJOR))
    XCTAssertEqual(minor, UInt32(VS_CORE_ABI_VERSION_MINOR))
    XCTAssertEqual(patch, UInt32(VS_CORE_ABI_VERSION_PATCH))
    XCTAssertEqual(
      vs_core_abi_version(nil, &minor, &patch),
      VS_STATUS_NULL_POINTER
    )
  }

  func testVideoOverlayPolicyContracts() {
    var keyLayout = vs_video_overlay_label_layout()
    XCTAssertEqual(
      vs_video_key_overlay_label_layout(1920, 1080, 6, &keyLayout),
      VS_STATUS_OK
    )
    XCTAssertEqual(keyLayout.width, 108, accuracy: 0.01)
    XCTAssertEqual(keyLayout.height, 58, accuracy: 0.01)
    XCTAssertEqual(keyLayout.y, 75.6, accuracy: 0.1)
    XCTAssertEqual(keyLayout.font_size, 26.68, accuracy: 0.1)

    var textLayout = vs_video_overlay_label_layout()
    XCTAssertEqual(
      vs_video_text_overlay_label_layout(1920, 1080, 20, &textLayout),
      VS_STATUS_OK
    )
    XCTAssertEqual(textLayout.width, 280, accuracy: 0.01)
    XCTAssertEqual(textLayout.height, 62, accuracy: 0.01)
    XCTAssertEqual(textLayout.y, 129.6, accuracy: 0.1)
    XCTAssertEqual(textLayout.font_size, 26.04, accuracy: 0.1)

    var window = vs_video_overlay_clip_window()
    XCTAssertEqual(
      vs_video_compute_overlay_clip_window(
        3.0,
        4.0,
        1.5,
        Double(VS_VIDEO_TEXT_MIN_VISIBLE_SECONDS),
        &window
      ),
      VS_STATUS_OK
    )
    XCTAssertEqual(window.start_seconds, 1.5, accuracy: 0.0001)
    XCTAssertEqual(window.end_seconds, 2.5, accuracy: 0.0001)
    XCTAssertEqual(
      window.fade_duration_seconds,
      1.0,
      accuracy: 0.0001
    )
  }

  @MainActor
  func testScreenshotPipelineMemoryMetric() {
    let source = makeSyntheticScreenshotRaster(width: 2560, height: 1440)
    let options = XCTMeasureOptions()
    options.iterationCount = 5
    measure(metrics: [XCTMemoryMetric()], options: options) {
      autoreleasepool {
        for iteration in 0..<4 {
          runScreenshotCopyPipelineIteration(sourceRaster: source, iteration: iteration)
        }
      }
    }
  }

  @MainActor
  func testScreenshotPipelineResidentMemoryBoundedAfterBurst() throws {
    let source = makeSyntheticScreenshotRaster(width: 2560, height: 1440)
    let baseline = currentResidentMemoryBytes()
    if baseline == 0 {
      throw XCTSkip("Unable to read resident memory from task_info")
    }

    var peak = baseline
    for iteration in 0..<24 {
      autoreleasepool {
        runScreenshotCopyPipelineIteration(sourceRaster: source, iteration: iteration)
      }
      RunLoop.main.run(until: Date().addingTimeInterval(0.01))
      peak = max(peak, currentResidentMemoryBytes())
    }

    RunLoop.main.run(until: Date().addingTimeInterval(0.15))
    let settled = currentResidentMemoryBytes()
    if settled == 0 {
      throw XCTSkip("Unable to read settled resident memory from task_info")
    }

    let peakGrowth = peak >= baseline ? (peak - baseline) : 0
    let settledGrowth = settled >= baseline ? (settled - baseline) : 0
    let peakLimit: UInt64 = 700 * 1024 * 1024
    let settledLimit: UInt64 = 320 * 1024 * 1024
    if let baselineAbsoluteLimitMB = ProcessInfo.processInfo.environment["VIVYSHOT_PIPELINE_BASELINE_MB"].flatMap(UInt64.init) {
      let baselineAbsoluteLimit = baselineAbsoluteLimitMB * 1024 * 1024
      XCTAssertLessThanOrEqual(
        baseline,
        baselineAbsoluteLimit,
        "Baseline resident memory exceeded absolute budget. baseline=\(baseline)"
      )
    }
    if let peakAbsoluteLimitMB = ProcessInfo.processInfo.environment["VIVYSHOT_PIPELINE_PEAK_MB"].flatMap(UInt64.init) {
      let peakAbsoluteLimit = peakAbsoluteLimitMB * 1024 * 1024
      XCTAssertLessThanOrEqual(
        peak,
        peakAbsoluteLimit,
        "Peak resident memory exceeded absolute budget. peak=\(peak)"
      )
    }

    XCTAssertLessThanOrEqual(
      peakGrowth,
      peakLimit,
      "Peak resident memory grew too much. baseline=\(baseline) peak=\(peak) delta=\(peakGrowth)"
    )
    XCTAssertLessThanOrEqual(
      settledGrowth,
      settledLimit,
      "Settled resident memory grew too much. baseline=\(baseline) settled=\(settled) delta=\(settledGrowth)"
    )
  }

  @MainActor
  func testScreenshotPipelineLatencyBoundedAfterBurst() {
    let source = makeSyntheticScreenshotRaster(width: 2560, height: 1440)
    var samplesMS: [Double] = []
    samplesMS.reserveCapacity(24)

    for iteration in 0..<24 {
      let startNS = DispatchTime.now().uptimeNanoseconds
      autoreleasepool {
        runScreenshotCopyPipelineIteration(sourceRaster: source, iteration: iteration)
      }
      let elapsedNS = DispatchTime.now().uptimeNanoseconds - startNS
      samplesMS.append(Double(elapsedNS) / 1_000_000.0)
    }

    let medianMS = percentile(samplesMS, percentile: 50)
    let p95MS = percentile(samplesMS, percentile: 95)

    let medianLimit = ProcessInfo.processInfo.environment["VIVYSHOT_PIPELINE_MEDIAN_MS"]
      .flatMap(Double.init) ?? 75
    let p95Limit = ProcessInfo.processInfo.environment["VIVYSHOT_PIPELINE_P95_MS"]
      .flatMap(Double.init) ?? 110

    XCTAssertLessThanOrEqual(
      medianMS,
      medianLimit,
      "Median pipeline latency too high. median=\(medianMS)ms limit=\(medianLimit)ms samples=\(samplesMS)"
    )
    XCTAssertLessThanOrEqual(
      p95MS,
      p95Limit,
      "P95 pipeline latency too high. p95=\(p95MS)ms limit=\(p95Limit)ms samples=\(samplesMS)"
    )
  }

  @MainActor
  func testFullFrameEncodeResidentMemoryBoundedAfterBurst() throws {
    let source = makeSyntheticScreenshotRaster(width: 2560, height: 1440)
    let baseline = currentResidentMemoryBytes()
    if baseline == 0 {
      throw XCTSkip("Unable to read resident memory from task_info")
    }

    var peak = baseline
    for _ in 0..<24 {
      autoreleasepool {
        source.pixels.withUnsafeBytes { raw in
          guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
            XCTFail("Missing source pixels")
            return
          }

          let sourceView = vs_bgra_image_view(
            width: UInt32(source.width),
            height: UInt32(source.height),
            stride: UInt32(source.stride),
            ptr: base,
            len: UInt(raw.count)
          )

          var png = vs_encoded_bytes(ptr: nil, len: 0)
          var jpeg = vs_encoded_bytes(ptr: nil, len: 0)
          defer {
            vs_encoded_bytes_destroy(&png)
            vs_encoded_bytes_destroy(&jpeg)
          }

          XCTAssertEqual(vs_encode_bgra_image(sourceView, 0, 100, &png), VS_STATUS_OK)
          XCTAssertEqual(vs_encode_bgra_image(sourceView, 1, 88, &jpeg), VS_STATUS_OK)
          XCTAssertGreaterThan(Int(png.len), 1024)
          XCTAssertGreaterThan(Int(jpeg.len), 1024)
        }
      }
      RunLoop.main.run(until: Date().addingTimeInterval(0.01))
      peak = max(peak, currentResidentMemoryBytes())
    }

    if let baselineAbsoluteLimitMB = ProcessInfo.processInfo.environment["VIVYSHOT_PIPELINE_BASELINE_MB"].flatMap(UInt64.init) {
      let baselineAbsoluteLimit = baselineAbsoluteLimitMB * 1024 * 1024
      XCTAssertLessThanOrEqual(
        baseline,
        baselineAbsoluteLimit,
        "Baseline resident memory exceeded absolute budget. baseline=\(baseline)"
      )
    }
    if let peakAbsoluteLimitMB = ProcessInfo.processInfo.environment["VIVYSHOT_PIPELINE_PEAK_MB"].flatMap(UInt64.init) {
      let peakAbsoluteLimit = peakAbsoluteLimitMB * 1024 * 1024
      XCTAssertLessThanOrEqual(
        peak,
        peakAbsoluteLimit,
        "Peak resident memory exceeded absolute budget. peak=\(peak)"
      )
    }
  }

  @MainActor
  private func runScreenshotCopyPipelineIteration(sourceRaster: SyntheticRaster, iteration: Int) {
    let cropRect = CGRect(
      x: 40 + (iteration % 9) * 18,
      y: 30 + (iteration % 7) * 14,
      width: 1920,
      height: 1080
    )

    var cropped = vs_bgra_owned_image(width: 0, height: 0, stride: 0, ptr: nil, len: 0)
    defer {
      vs_bgra_owned_image_destroy(&cropped)
    }

    let cropStatus = sourceRaster.pixels.withUnsafeBytes { raw -> Int32 in
      guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
        return VS_STATUS_NULL_POINTER
      }
      let sourceView = vs_bgra_image_view(
        width: UInt32(sourceRaster.width),
        height: UInt32(sourceRaster.height),
        stride: UInt32(sourceRaster.stride),
        ptr: base,
        len: UInt(raw.count)
      )
      return vs_bgra_crop(
        sourceView,
        UInt32(cropRect.minX),
        UInt32(cropRect.minY),
        UInt32(cropRect.width),
        UInt32(cropRect.height),
        &cropped
      )
    }
    XCTAssertEqual(cropStatus, VS_STATUS_OK)
    guard cropStatus == VS_STATUS_OK, let croppedPtr = cropped.ptr, cropped.len > 0 else {
      return
    }

    let croppedView = vs_bgra_image_view(
      width: cropped.width,
      height: cropped.height,
      stride: cropped.stride,
      ptr: UnsafePointer(croppedPtr),
      len: cropped.len
    )

    var png = vs_encoded_bytes(ptr: nil, len: 0)
    var jpeg = vs_encoded_bytes(ptr: nil, len: 0)
    defer {
      vs_encoded_bytes_destroy(&png)
      vs_encoded_bytes_destroy(&jpeg)
    }

    XCTAssertEqual(vs_encode_bgra_image(croppedView, 0, 100, &png), VS_STATUS_OK)
    XCTAssertEqual(vs_encode_bgra_image(croppedView, 1, 88, &jpeg), VS_STATUS_OK)

    let croppedData = Data(bytes: croppedPtr, count: Int(cropped.len))
    guard let croppedImage = makeCGImageFromBGRA(
      width: Int(cropped.width),
      height: Int(cropped.height),
      stride: Int(cropped.stride),
      data: croppedData
    ) else {
      XCTFail("Failed to rebuild CGImage from cropped BGRA bytes")
      return
    }

    let image = NSImage(
      cgImage: croppedImage,
      size: NSSize(width: Int(cropped.width), height: Int(cropped.height))
    )
    XCTAssertGreaterThan(Int(png.len), 1024)
    XCTAssertGreaterThan(Int(jpeg.len), 1024)
    XCTAssertGreaterThan(image.size.width, 0)
  }

  private func currentResidentMemoryBytes() -> UInt64 {
    var info = mach_task_basic_info_data_t()
    var count = mach_msg_type_number_t(
      MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size
    )
    let status: kern_return_t = withUnsafeMutablePointer(to: &info) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { integerPointer in
        task_info(
          mach_task_self_,
          task_flavor_t(MACH_TASK_BASIC_INFO),
          integerPointer,
          &count
        )
      }
    }
    guard status == KERN_SUCCESS else {
      return 0
    }
    return UInt64(info.resident_size)
  }

  @MainActor
  private func makeSyntheticScreenshotRaster(width: Int, height: Int) -> SyntheticRaster {
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
      for x in 0..<width {
        let idx = (y * width + x) * 4
        pixels[idx] = UInt8((x * 3 + y * 7) % 251)
        pixels[idx + 1] = UInt8((x * 11 + y * 5 + 31) % 251)
        pixels[idx + 2] = UInt8((x * 2 + y * 13 + 17) % 251)
        pixels[idx + 3] = 255
      }
    }

    return SyntheticRaster(
      width: width,
      height: height,
      stride: width * 4,
      pixels: pixels
    )
  }

  private func makeCGImageFromBGRA(width: Int, height: Int, stride: Int, data: Data) -> CGImage? {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue
      | CGImageAlphaInfo.premultipliedFirst.rawValue
    let provider = CGDataProvider(data: data as CFData)
    guard let provider else {
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

  private func percentile(_ samples: [Double], percentile: Double) -> Double {
    guard !samples.isEmpty else {
      return 0
    }
    let sorted = samples.sorted()
    let rank = Int(((percentile / 100.0) * Double(sorted.count - 1)).rounded())
    return sorted[min(max(rank, 0), sorted.count - 1)]
  }
}
