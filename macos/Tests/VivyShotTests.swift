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
}
