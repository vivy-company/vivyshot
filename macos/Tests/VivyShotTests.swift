import XCTest

final class VivyShotTests: XCTestCase {
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
}
