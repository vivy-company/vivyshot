//! Portable domain logic for VivyShot.
//!
//! This crate is the cross-platform source of truth for timeline/video policy,
//! geometry transforms, selection math, stitching policy, and export planning.

mod types;

pub mod document;
pub mod geometry;
pub mod stats;
pub mod stitch;
pub mod timeline;
pub mod video;

pub use document::{
    Document, DocumentAnnotationInfo, DocumentArrowCommand, DocumentBlurRectCommand,
    DocumentCommand, DocumentEllipseCommand, DocumentError, DocumentLineCommand, DocumentPathStyle,
    DocumentPixelateRectCommand, DocumentRectCommand, DocumentTextCommand,
};
pub use geometry::{
    image_delta_to_view_delta, image_rect_to_view_rect, quantize_image_point, quantize_image_rect,
    quantize_rgba, selection_move_rect, selection_resize_rect, view_delta_to_image_delta,
    view_rect_to_image_rect, viewport_clamp_pan_offset,
};
pub use stats::{
    capture_statistics_daily_buckets, capture_statistics_ingest_event,
    capture_statistics_recent_daily_buckets, capture_statistics_reset, capture_statistics_summary,
    CaptureStatisticsError, CaptureStatisticsEvent, CaptureStatisticsEventType,
    CaptureStatisticsSession, CaptureStatisticsSessionSnapshot, CaptureStatisticsState,
    CaptureStatisticsStateSnapshot, CaptureStatisticsSummary, DailyCaptureStats, StatsDayKey,
    STATS_EVENT_RECORDING_COMPLETED, STATS_EVENT_SCREENSHOT_CAPTURED,
    STATS_EVENT_SCREENSHOT_SESSION_COMPLETED, STATS_SESSION_SNAPSHOT_VERSION,
};
pub use stitch::{
    bgra_view_to_owned, build_gif_export_plan, gif_frame_time_ms, normalize_trim_range,
    stitch_autoscroll_reset, stitch_autoscroll_update, stitch_crop_frame, stitch_estimate_delta,
    stitch_extract_strip, stitch_merge_frames, stitch_resize_width_nearest,
};
pub use timeline::{
    timeline_clamp_clip_end, timeline_collect_text_export_clips, timeline_full_duration_end,
    timeline_normalize_text_clip_range, timeline_validate_split,
    timeline_webcam_visible_for_export, Timeline, TimelineError, TIMELINE_TRACK_AUDIO,
    TIMELINE_TRACK_CURSOR, TIMELINE_TRACK_SHAPE, TIMELINE_TRACK_TEXT, TIMELINE_TRACK_VIDEO,
    TIMELINE_TRACK_WEBCAM, TIMELINE_TRACK_ZOOM,
};
pub use types::{
    AffineTransform, BgraImageOwned, BgraImageView, F32Point, F32Rect, GifExportPlan, I32Point,
    I32Rect, ResizeCorner, Rgba8, StitchAutoscrollState, StitchDelta, TimelineClip,
    TimelineClipData, TimelineClipSnapshot, TimelineClipTransform, TimelineShapeStyle,
    TimelineTextClipExportInput, TimelineTextClipExportRef, TimelineTextStyle, TimelineTrack,
    TimelineTrackSummary, TrimHandle, VideoExportBitratePreset, VideoExportCodec,
    VideoExportContainer, VideoExportContext, VideoExportDecision, VideoExportFrameRate,
    VideoExportPlan, VideoExportPreset, VideoExportQuality, VideoExportScale,
    VideoOverlayClipWindow, VideoOverlayLabelLayout, VideoPostRecordingCompositionPlan,
    STITCH_SIDE_BOTTOM, STITCH_SIDE_TOP, VIDEO_EXPORT_CONTAINER_MOV, VIDEO_EXPORT_CONTAINER_MP4,
    VIDEO_EXPORT_PRESET_1280X720, VIDEO_EXPORT_PRESET_1920X1080,
    VIDEO_EXPORT_PRESET_HEVC_1920X1080, VIDEO_EXPORT_PRESET_HEVC_HIGHEST_QUALITY,
    VIDEO_EXPORT_PRESET_HIGHEST_QUALITY, VIDEO_EXPORT_PRESET_MEDIUM_QUALITY,
    VIDEO_EXPORT_TARGET_GIF, VIDEO_EXPORT_TARGET_MP4, VIDEO_KEY_OVERLAY_FADE_DURATION_SECONDS,
    VIDEO_KEY_OVERLAY_FADE_HOLD_KEYTIME, VIDEO_KEY_OVERLAY_FADE_IN_KEYTIME,
    VIDEO_PLAN_MODE_COMPOSITE_MP4, VIDEO_PLAN_MODE_PASSTHROUGH,
    VIDEO_TEXT_OVERLAY_FADE_HOLD_KEYTIME, VIDEO_TEXT_OVERLAY_FADE_IN_KEYTIME,
    VIDEO_TEXT_OVERLAY_MIN_FADE_DURATION_SECONDS, VIDEO_TEXT_OVERLAY_MIN_VISIBLE_SECONDS,
};
pub use video::{
    allowed_video_export_containers, best_video_export_container, best_video_export_preset,
    click_event_is_duplicate, compute_video_export_plan, derive_key_overlay_label_layout,
    derive_overlay_clip_window, derive_text_overlay_label_layout, derive_video_export_context,
    derive_video_export_decision, estimated_video_file_length_limit, normalize_click_point,
    normalize_video_rect, overlay_fade_duration_seconds, post_recording_video_composition_plan,
    preferred_video_export_container, VideoClickOverlayEvent, VideoKeyOverlayEvent,
    VideoKeystrokeOverlay, VideoNormalizedRect, VideoOverlayPlacementKeyframe, VideoOverlaySet,
    VideoProject, VideoProjectExportOptions, VideoProjectProRequirement, VideoRenderItem,
    VideoRenderPlan, VideoRenderPlanQuery, VideoSourceMetadata, VideoWebcamOverlay,
    VIDEO_KEYSTROKE_SIZE_LARGE, VIDEO_KEYSTROKE_SIZE_MEDIUM, VIDEO_KEYSTROKE_SIZE_SMALL,
    VIDEO_KEYSTROKE_STYLE_COMPACT, VIDEO_KEYSTROKE_STYLE_GLASS, VIDEO_PROJECT_SNAPSHOT_VERSION,
    VIDEO_PRO_REASON_BAKED_TRANSITION, VIDEO_PRO_REASON_GIF_EXPORT, VIDEO_PRO_REASON_HEVC_EXPORT,
    VIDEO_PRO_REASON_HIGH_BITRATE, VIDEO_PRO_REASON_HIGH_QUALITY,
    VIDEO_PRO_REASON_KEYSTROKE_OVERLAY, VIDEO_PRO_REASON_MICROPHONE_AUDIO,
    VIDEO_PRO_REASON_SIXTY_FPS, VIDEO_PRO_REASON_WEBCAM_OVERLAY, VIDEO_RENDER_ITEM_KEYSTROKE,
    VIDEO_RENDER_ITEM_WEBCAM, VIDEO_RENDER_TARGET_EXPORT, VIDEO_RENDER_TARGET_PREVIEW,
    VIDEO_WEBCAM_ASPECT_FOUR_THREE, VIDEO_WEBCAM_ASPECT_SIXTEEN_NINE, VIDEO_WEBCAM_ASPECT_SQUARE,
    VIDEO_WEBCAM_SHAPE_CIRCLE, VIDEO_WEBCAM_SHAPE_ROUNDED_RECT,
};

#[cfg(test)]
mod tests {
    use super::*;
    use proptest::prelude::*;

    fn approx_eq(a: f32, b: f32, epsilon: f32) -> bool {
        (a - b).abs() <= epsilon
    }

    #[test]
    fn trim_normalization_keeps_min_gap() {
        let (start, end) = normalize_trim_range(1_000, 950, 960, 100, TrimHandle::End);
        assert_eq!(start, 860);
        assert_eq!(end, 960);
    }

    #[test]
    fn export_plan_marks_custom_compositor_when_audio_hidden() {
        let plan = compute_video_export_plan(
            100,
            800,
            2,
            1,
            VideoExportContext {
                source_has_audio: true,
                source_has_webcam_asset: false,
                audio_track_visible: false,
                webcam_track_visible: true,
                text_overlay_count: 1,
            },
        )
        .unwrap();

        assert_eq!(plan.plan_mode, VIDEO_PLAN_MODE_COMPOSITE_MP4);
        assert!(!plan.include_audio);
        assert!(plan.needs_custom_compositor);
        assert_eq!(plan.overlay_item_count, 3);
    }

    #[test]
    fn export_decision_derives_mp4_and_gif_paths_from_plan() {
        let plan = compute_video_export_plan(
            100,
            800,
            2,
            1,
            VideoExportContext {
                source_has_audio: true,
                source_has_webcam_asset: true,
                audio_track_visible: false,
                webcam_track_visible: true,
                text_overlay_count: 1,
            },
        )
        .unwrap();

        let mp4 = derive_video_export_decision(VIDEO_EXPORT_TARGET_MP4, plan).unwrap();
        assert!(mp4.use_custom_compositor);
        assert!(mp4.requires_intermediate_for_gif);
        assert!(!mp4.include_audio);
        assert!(mp4.include_webcam);

        let gif = derive_video_export_decision(VIDEO_EXPORT_TARGET_GIF, plan).unwrap();
        assert!(gif.use_custom_compositor);
        assert!(gif.requires_intermediate_for_gif);
    }

    #[test]
    fn key_and_text_overlay_layouts_match_policy() {
        let key = derive_key_overlay_label_layout(1920.0, 1080.0, 6).unwrap();
        assert!((key.width - 108.0).abs() < 0.001);
        assert!((key.height - 58.0).abs() < 0.001);
        assert!((key.y - 75.6).abs() < 0.001);
        assert!((key.font_size - 26.68).abs() < 0.001);

        let text = derive_text_overlay_label_layout(1920.0, 1080.0, 20).unwrap();
        assert!((text.width - 280.0).abs() < 0.001);
        assert!((text.height - 62.0).abs() < 0.001);
        assert!((text.y - 129.6).abs() < 0.001);
        assert!((text.font_size - 26.04).abs() < 0.001);
    }

    #[test]
    fn video_export_helper_fallbacks_remain_safe() {
        assert_eq!(
            best_video_export_preset(VideoExportCodec::Hevc, VideoExportQuality::High, 0),
            Some(VideoExportPreset::HighestQuality)
        );
        assert_eq!(
            best_video_export_container(VideoExportCodec::H264, false, false),
            None
        );
        assert_eq!(
            best_video_export_container(VideoExportCodec::Hevc, false, true),
            Some(VideoExportContainer::Mov)
        );
    }

    #[test]
    fn overlay_clip_window_and_fade_duration_enforce_thresholds() {
        let window =
            derive_overlay_clip_window(3.0, 4.0, 1.5, VIDEO_TEXT_OVERLAY_MIN_VISIBLE_SECONDS)
                .unwrap();
        assert!((window.start_seconds - 1.5).abs() < 0.0001);
        assert!((window.end_seconds - 2.5).abs() < 0.0001);

        let duration =
            overlay_fade_duration_seconds(window, VIDEO_TEXT_OVERLAY_MIN_FADE_DURATION_SECONDS)
                .unwrap();
        assert!((duration - 1.0).abs() < 0.0001);

        assert!(
            derive_overlay_clip_window(1.0, 1.02, 0.0, VIDEO_TEXT_OVERLAY_MIN_VISIBLE_SECONDS)
                .is_none()
        );
    }

    #[test]
    fn timeline_context_derivation_counts_visible_tracks() {
        let tracks = [
            TimelineTrackSummary {
                kind: 2,
                visible: true,
                clip_count: 1,
            },
            TimelineTrackSummary {
                kind: 1,
                visible: false,
                clip_count: 2,
            },
            TimelineTrackSummary {
                kind: 3,
                visible: true,
                clip_count: 2,
            },
            TimelineTrackSummary {
                kind: 3,
                visible: true,
                clip_count: 0,
            },
        ];

        let context = derive_video_export_context(true, true, &tracks);
        assert!(context.source_has_audio);
        assert!(context.source_has_webcam_asset);
        assert!(context.audio_track_visible);
        assert!(!context.webcam_track_visible);
        assert_eq!(context.text_overlay_count, 2);
    }

    #[test]
    fn timeline_export_clip_collection_filters_and_orders() {
        let clips = vec![
            TimelineTextClipExportInput {
                track_index: 2,
                track_order: 2,
                clip_id: 10,
                start_ms: 4_000,
                end_ms: 5_000,
                track_visible: true,
            },
            TimelineTextClipExportInput {
                track_index: 1,
                track_order: 1,
                clip_id: 9,
                start_ms: 2_000,
                end_ms: 3_000,
                track_visible: true,
            },
            TimelineTextClipExportInput {
                track_index: 1,
                track_order: 1,
                clip_id: 8,
                start_ms: 1_000,
                end_ms: 1_000,
                track_visible: true,
            },
            TimelineTextClipExportInput {
                track_index: 3,
                track_order: 3,
                clip_id: 11,
                start_ms: 1_500,
                end_ms: 2_500,
                track_visible: false,
            },
        ];

        let refs = timeline_collect_text_export_clips(&clips);
        assert_eq!(refs.len(), 2);
        assert_eq!(refs[0].track_index, 1);
        assert_eq!(refs[0].clip_id, 9);
        assert_eq!(refs[1].track_index, 2);
        assert_eq!(refs[1].clip_id, 10);
    }

    #[test]
    fn gif_plan_and_frame_time_are_stable() {
        let plan = build_gif_export_plan(0, 1_000, 12.0, 9_999);
        assert_eq!(plan.frame_count, 12);
        assert_eq!(plan.max_dimension, 2_048);
        assert_eq!(gif_frame_time_ms(plan, 0), Some(0));
        assert_eq!(gif_frame_time_ms(plan, plan.frame_count - 1), Some(1_000));
    }

    #[test]
    fn autoscroll_flips_once_after_threshold() {
        let mut state = stitch_autoscroll_reset();
        for _ in 0..4 {
            state = stitch_autoscroll_update(true, false, false, 4, state);
        }
        assert_eq!(state.direction_sign, 1);
        assert!(state.did_flip_direction);
        assert_eq!(state.no_motion_ticks, 0);
    }

    #[test]
    fn stitch_estimator_detects_bottom_shift() {
        let width = 96usize;
        let height = 64usize;
        let shift = 9usize;
        let stride = width * 4;

        let mut previous = vec![0u8; stride * height];
        for y in 0..height {
            for x in 0..width {
                let idx = y * stride + x * 4;
                previous[idx] = ((x * 5 + y * 11) % 251) as u8;
                previous[idx + 1] = ((x * 13 + y * 7) % 251) as u8;
                previous[idx + 2] = ((x * 3 + y * 17) % 251) as u8;
                previous[idx + 3] = 255;
            }
        }

        let mut current = vec![0u8; stride * height];
        for y in 0..(height - shift) {
            let src = (y + shift) * stride;
            let dst = y * stride;
            current[dst..dst + stride].copy_from_slice(&previous[src..src + stride]);
        }
        for y in (height - shift)..height {
            for x in 0..width {
                let idx = y * stride + x * 4;
                current[idx] = ((x * 19 + y * 23 + 31) % 251) as u8;
                current[idx + 1] = ((x * 29 + y * 7 + 41) % 251) as u8;
                current[idx + 2] = ((x * 3 + y * 37 + 53) % 251) as u8;
                current[idx + 3] = 255;
            }
        }

        let delta = stitch_estimate_delta(
            BgraImageView {
                width: width as u32,
                height: height as u32,
                stride: stride as u32,
                pixels: &previous,
            },
            BgraImageView {
                width: width as u32,
                height: height as u32,
                stride: stride as u32,
                pixels: &current,
            },
            None,
            None,
            false,
        )
        .unwrap();

        assert_eq!(delta.side, STITCH_SIDE_BOTTOM);
        assert_eq!(delta.rows, shift as u32);
    }

    #[test]
    fn stitch_merge_and_crop_preserve_dimensions() {
        let base = BgraImageOwned {
            width: 4,
            height: 3,
            stride: 16,
            pixels: vec![10; 16 * 3],
        };
        let segment = BgraImageOwned {
            width: 4,
            height: 2,
            stride: 16,
            pixels: vec![200; 16 * 2],
        };

        let merged = stitch_merge_frames(&base, &segment, STITCH_SIDE_BOTTOM).unwrap();
        assert_eq!(merged.width, 4);
        assert_eq!(merged.height, 5);

        let cropped = stitch_crop_frame(&merged, 1, 1, 2, 3).unwrap();
        assert_eq!(cropped.width, 2);
        assert_eq!(cropped.height, 3);
    }

    #[test]
    fn click_normalization_and_dedupe_work() {
        assert_eq!(normalize_click_point(-0.2, 1.4), Some((0.0, 1.0)));
        assert!(click_event_is_duplicate(
            7, 0, 0.4, 0.6, 7, 0, 0.40005, 0.59995, 0.001
        ));
    }

    #[test]
    fn quantize_helpers_clamp() {
        let rect = quantize_image_rect(
            400,
            300,
            F32Rect {
                x: -8.2,
                y: 12.1,
                width: 22.8,
                height: 17.3,
            },
        )
        .unwrap();
        assert_eq!(rect.x, 0);
        assert!(rect.width >= 1);

        assert_eq!(quantize_image_point(400, 300, 500.0, -5.0), Some((399, 0)));

        let color = quantize_rgba(1.2, -1.0, 0.5, 0.9).unwrap();
        assert_eq!(color.r, 255);
        assert_eq!(color.g, 0);
    }

    #[test]
    fn geometry_helpers_round_trip_and_selection_clamp() {
        let destination = F32Rect {
            x: 100.0,
            y: 200.0,
            width: 640.0,
            height: 360.0,
        };
        let view_rect = F32Rect {
            x: 180.0,
            y: 250.0,
            width: 220.0,
            height: 90.0,
        };

        let image_rect = view_rect_to_image_rect(view_rect, destination, 1920, 1080).unwrap();
        let roundtrip = image_rect_to_view_rect(image_rect, destination, 1920, 1080).unwrap();
        assert!(approx_eq(roundtrip.x, view_rect.x, 1.0));
        assert!(approx_eq(roundtrip.y, view_rect.y, 1.0));
        assert!(approx_eq(roundtrip.width, view_rect.width, 1.0));
        assert!(approx_eq(roundtrip.height, view_rect.height, 1.0));

        let image_delta = view_delta_to_image_delta(12.0, -8.0, destination, 1920, 1080).unwrap();
        let view_delta =
            image_delta_to_view_delta(image_delta.x, image_delta.y, destination, 1920, 1080)
                .unwrap();
        assert!(approx_eq(view_delta.x, 12.0, 0.01));
        assert!(approx_eq(view_delta.y, -8.0, 0.01));

        let (moved, did_move) = selection_move_rect(
            F32Rect {
                x: 50.0,
                y: 40.0,
                width: 120.0,
                height: 80.0,
            },
            F32Rect {
                x: 0.0,
                y: 0.0,
                width: 200.0,
                height: 160.0,
            },
            500.0,
            -500.0,
        )
        .unwrap();
        assert!(did_move);
        assert_eq!(moved.x, 80.0);
        assert_eq!(moved.y, 0.0);
        assert_eq!(moved.width, 120.0);
        assert_eq!(moved.height, 80.0);
    }

    #[test]
    fn timeline_helpers_enforce_nonempty_ranges() {
        assert_eq!(timeline_full_duration_end(0), 1);
        assert_eq!(timeline_clamp_clip_end(1_000, 950, 960), 960);
        let (start, end) = timeline_normalize_text_clip_range(1_000, 990, 991);
        assert!(end > start);
        assert!(end <= 1_000);
    }

    proptest! {
        #[test]
        fn prop_timeline_text_range_is_non_empty(
            duration in 0u32..50_000u32,
            start in 0u32..60_000u32,
            end in 0u32..60_000u32,
        ) {
            let (normalized_start, normalized_end) =
                timeline_normalize_text_clip_range(duration, start, end);
            let full_end = timeline_full_duration_end(duration);
            prop_assert!(normalized_end > normalized_start);
            prop_assert!(normalized_end <= full_end);
        }

        #[test]
        fn prop_selection_move_stays_inside_bounds(
            delta_x in -5000.0f32..5000.0f32,
            delta_y in -5000.0f32..5000.0f32,
        ) {
            let bounds = F32Rect { x: 0.0, y: 0.0, width: 400.0, height: 300.0 };
            let current = F32Rect { x: 50.0, y: 40.0, width: 120.0, height: 80.0 };
            let (moved, _) = selection_move_rect(current, bounds, delta_x, delta_y).unwrap();
            prop_assert!(moved.x >= bounds.x);
            prop_assert!(moved.y >= bounds.y);
            prop_assert!(moved.x + moved.width <= bounds.x + bounds.width + 0.001);
            prop_assert!(moved.y + moved.height <= bounds.y + bounds.height + 0.001);
        }

        #[test]
        fn prop_geometry_delta_roundtrip_is_stable(
            image_width in 1u32..4000u32,
            image_height in 1u32..3000u32,
            delta_x in -1000.0f32..1000.0f32,
            delta_y in -1000.0f32..1000.0f32,
        ) {
            let destination = F32Rect { x: -120.0, y: 50.0, width: 640.0, height: 360.0 };
            let image_delta =
                view_delta_to_image_delta(delta_x, delta_y, destination, image_width, image_height)
                    .unwrap();
            let roundtrip = image_delta_to_view_delta(
                image_delta.x,
                image_delta.y,
                destination,
                image_width,
                image_height,
            )
            .unwrap();

            prop_assert!((roundtrip.x - delta_x).abs() <= 0.05);
            prop_assert!((roundtrip.y - delta_y).abs() <= 0.05);
        }
    }

    #[test]
    fn split_validation_accepts_valid_midpoint() {
        let result = timeline_validate_split(0, 10000, 5000, 10);
        assert_eq!(result, Some((0, 5000, 5000, 10000)));
    }

    #[test]
    fn split_validation_rejects_too_close_to_start() {
        assert_eq!(timeline_validate_split(0, 10000, 5, 10), None);
    }

    #[test]
    fn split_validation_rejects_too_close_to_end() {
        assert_eq!(timeline_validate_split(0, 10000, 9995, 10), None);
    }

    #[test]
    fn split_validation_rejects_at_boundary() {
        assert_eq!(timeline_validate_split(1000, 5000, 1000, 10), None);
        assert_eq!(timeline_validate_split(1000, 5000, 5000, 10), None);
    }
}
