mod common;

use common::approx_eq;
use vivyshot_core::{
    vs_build_gif_export_plan, vs_f32_point, vs_f32_rect, vs_gif_export_plan, vs_gif_frame_time_ms,
    vs_i32_rect, vs_image_delta_to_view_delta, vs_image_rect_to_view_rect, vs_normalize_trim_range,
    vs_quantize_image_point, vs_quantize_image_rect, vs_quantize_rgba, vs_rgba8,
    vs_selection_move_rect, vs_selection_resize_rect, vs_view_delta_to_image_delta,
    vs_view_rect_to_image_rect, vs_viewport_clamp_pan_offset,
};

#[test]
fn selection_move_and_resize_obey_bounds_and_minimums() {
    let mut moved = vs_f32_rect::default();
    let mut resized = vs_f32_rect::default();

    // SAFETY: output pointers are valid.
    unsafe {
        assert_eq!(
            vs_selection_move_rect(
                vs_f32_rect {
                    x: 50.0,
                    y: 40.0,
                    width: 120.0,
                    height: 80.0,
                },
                vs_f32_rect {
                    x: 0.0,
                    y: 0.0,
                    width: 200.0,
                    height: 160.0,
                },
                500.0,
                -500.0,
                &mut moved,
            ),
            0
        );
        assert_eq!(
            vs_selection_resize_rect(
                vs_f32_rect {
                    x: 60.0,
                    y: 30.0,
                    width: 120.0,
                    height: 100.0,
                },
                vs_f32_rect {
                    x: 0.0,
                    y: 0.0,
                    width: 300.0,
                    height: 220.0,
                },
                0,
                300.0,
                -300.0,
                80.0,
                60.0,
                &mut resized,
            ),
            0
        );
    }

    assert!(moved.x >= 0.0);
    assert!(moved.y >= 0.0);
    assert!(resized.width >= 80.0);
    assert!(resized.height >= 60.0);
}

#[test]
fn view_image_rect_and_delta_roundtrip() {
    let destination = vs_f32_rect {
        x: 100.0,
        y: 180.0,
        width: 640.0,
        height: 360.0,
    };
    let view_rect = vs_f32_rect {
        x: 190.0,
        y: 230.0,
        width: 240.0,
        height: 120.0,
    };

    let mut image_rect = vs_f32_rect::default();
    let mut roundtrip = vs_f32_rect::default();
    let mut image_delta = vs_f32_point::default();
    let mut view_delta = vs_f32_point::default();

    // SAFETY: output pointers are valid.
    unsafe {
        assert_eq!(
            vs_view_rect_to_image_rect(view_rect, destination, 1920, 1080, &mut image_rect),
            0
        );
        assert_eq!(
            vs_image_rect_to_view_rect(image_rect, destination, 1920, 1080, &mut roundtrip),
            0
        );
        assert_eq!(
            vs_view_delta_to_image_delta(12.0, -9.0, destination, 1920, 1080, &mut image_delta),
            0
        );
        assert_eq!(
            vs_image_delta_to_view_delta(
                image_delta.x,
                image_delta.y,
                destination,
                1920,
                1080,
                &mut view_delta,
            ),
            0
        );
    }

    assert!(approx_eq(roundtrip.x, view_rect.x, 1.0));
    assert!(approx_eq(roundtrip.y, view_rect.y, 1.0));
    assert!(approx_eq(roundtrip.width, view_rect.width, 1.0));
    assert!(approx_eq(roundtrip.height, view_rect.height, 1.0));
    assert!(approx_eq(view_delta.x, 12.0, 0.01));
    assert!(approx_eq(view_delta.y, -9.0, 0.01));
}

#[test]
fn quantize_and_policy_helpers_apply_expected_limits() {
    let mut rect = vs_i32_rect::default();
    let mut px = 0i32;
    let mut py = 0i32;
    let mut color = vs_rgba8::default();

    // SAFETY: output pointers are valid.
    unsafe {
        assert_eq!(
            vs_quantize_image_rect(
                400,
                300,
                vs_f32_rect {
                    x: -8.2,
                    y: 12.1,
                    width: 22.8,
                    height: 17.3,
                },
                &mut rect,
            ),
            0
        );
        assert_eq!(
            vs_quantize_image_point(400, 300, 500.0, -5.0, &mut px, &mut py),
            0
        );
        assert_eq!(vs_quantize_rgba(1.2, -1.0, 0.5, 0.9, &mut color), 0);
    }

    assert_eq!(rect.x, 0);
    assert!(rect.width >= 1);
    assert_eq!(px, 399);
    assert_eq!(py, 0);
    assert_eq!(color.r, 255);
    assert_eq!(color.g, 0);

    let mut start = 0u32;
    let mut end = 0u32;
    // SAFETY: output pointers are valid.
    unsafe {
        assert_eq!(
            vs_normalize_trim_range(1_000, 950, 960, 100, 2, &mut start, &mut end),
            0
        );
    }
    assert_eq!(start, 860);
    assert_eq!(end, 960);

    let mut plan = vs_gif_export_plan::default();
    // SAFETY: output pointers are valid.
    unsafe {
        assert_eq!(
            vs_build_gif_export_plan(0, 1_000, 12.0, 9_999, &mut plan),
            0
        );
    }
    assert_eq!(plan.frame_count, 12);
    assert_eq!(plan.max_dimension, 2_048);

    let mut first = 0u32;
    let mut last = 0u32;
    // SAFETY: output pointers are valid.
    unsafe {
        assert_eq!(vs_gif_frame_time_ms(plan, 0, &mut first), 0);
        assert_eq!(
            vs_gif_frame_time_ms(plan, plan.frame_count - 1, &mut last),
            0
        );
    }
    assert_eq!(first, plan.start_ms);
    assert_eq!(last, plan.end_ms);
}

#[test]
fn viewport_clamp_limits_offset_by_zoom_and_overscroll() {
    let mut out = vs_f32_point::default();

    // SAFETY: output pointer is valid.
    unsafe {
        assert_eq!(
            vs_viewport_clamp_pan_offset(
                1200.0, 800.0, 1920, 1080, 2.0, 24.0, 999.0, -999.0, &mut out
            ),
            0
        );
    }

    assert!(out.x.is_finite());
    assert!(out.y.is_finite());
    assert!(out.x.abs() > 0.0);
    assert!(out.y.abs() > 0.0);
}
