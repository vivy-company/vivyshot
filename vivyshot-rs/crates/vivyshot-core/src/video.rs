use crate::types::TimelineTrackSummary;

pub use crate::types::{
    VideoExportContext, VideoExportDecision, VideoExportPlan, VideoOverlayClipWindow,
    VideoOverlayLabelLayout, VIDEO_EXPORT_TARGET_GIF, VIDEO_EXPORT_TARGET_MP4,
    VIDEO_KEY_OVERLAY_FADE_DURATION_SECONDS, VIDEO_KEY_OVERLAY_FADE_HOLD_KEYTIME,
    VIDEO_KEY_OVERLAY_FADE_IN_KEYTIME, VIDEO_PLAN_MODE_COMPOSITE_MP4,
    VIDEO_PLAN_MODE_PASSTHROUGH, VIDEO_TEXT_OVERLAY_FADE_HOLD_KEYTIME,
    VIDEO_TEXT_OVERLAY_FADE_IN_KEYTIME, VIDEO_TEXT_OVERLAY_MIN_FADE_DURATION_SECONDS,
    VIDEO_TEXT_OVERLAY_MIN_VISIBLE_SECONDS,
};

pub fn compute_video_export_plan(
    trim_start_ms: u32,
    trim_end_ms: u32,
    key_event_count: u32,
    click_event_count: u32,
    context: VideoExportContext,
) -> Option<VideoExportPlan> {
    if trim_end_ms < trim_start_ms {
        return None;
    }

    let include_audio = context.source_has_audio && context.audio_track_visible;
    let include_webcam = context.source_has_webcam_asset && context.webcam_track_visible;
    let has_text_overlays = context.text_overlay_count > 0;
    let has_key_overlays = key_event_count > 0;
    let overlay_item_count = context.text_overlay_count.saturating_add(key_event_count);
    let needs_custom_compositor = include_webcam
        || has_text_overlays
        || has_key_overlays
        || (context.source_has_audio && !include_audio);
    let plan_mode = if needs_custom_compositor {
        VIDEO_PLAN_MODE_COMPOSITE_MP4
    } else {
        VIDEO_PLAN_MODE_PASSTHROUGH
    };

    Some(VideoExportPlan {
        trim_start_ms,
        trim_end_ms,
        key_event_count,
        click_event_count,
        plan_mode,
        include_audio,
        include_webcam,
        text_overlay_count: context.text_overlay_count,
        overlay_item_count,
        requires_intermediate_for_gif: needs_custom_compositor,
        needs_custom_compositor,
    })
}

pub fn derive_video_export_context(
    source_has_audio: bool,
    source_has_webcam_asset: bool,
    tracks: &[TimelineTrackSummary],
) -> VideoExportContext {
    let mut audio_track_visible = false;
    let mut webcam_track_visible = false;
    let mut text_overlay_count = 0u32;

    for track in tracks {
        if !track.visible || track.clip_count == 0 {
            continue;
        }

        match track.kind {
            2 => audio_track_visible = true,
            1 => webcam_track_visible = true,
            3 => {
                text_overlay_count = text_overlay_count.saturating_add(track.clip_count);
            }
            _ => {}
        }
    }

    VideoExportContext {
        source_has_audio,
        source_has_webcam_asset,
        audio_track_visible,
        webcam_track_visible,
        text_overlay_count,
    }
}


pub fn derive_video_export_decision(
    target: u8,
    plan: VideoExportPlan,
) -> Option<VideoExportDecision> {
    let is_composite =
        plan.plan_mode == VIDEO_PLAN_MODE_COMPOSITE_MP4 || plan.needs_custom_compositor;
    let requires_intermediate_for_gif = plan.requires_intermediate_for_gif || is_composite;
    let use_custom_compositor = match target {
        VIDEO_EXPORT_TARGET_MP4 => is_composite,
        VIDEO_EXPORT_TARGET_GIF => requires_intermediate_for_gif,
        _ => return None,
    };

    Some(VideoExportDecision {
        use_custom_compositor,
        requires_intermediate_for_gif,
        include_audio: plan.include_audio,
        include_webcam: plan.include_webcam,
    })
}

pub fn derive_key_overlay_label_layout(
    render_width: f32,
    render_height: f32,
    char_count: u32,
) -> Option<VideoOverlayLabelLayout> {
    if !render_width.is_finite()
        || !render_height.is_finite()
        || render_width <= 0.0
        || render_height <= 0.0
    {
        return None;
    }

    let height = (render_height * 0.085).clamp(34.0, 58.0);
    let max_width = render_width * 0.72;
    let width = (char_count.saturating_mul(18).max(84) as f32).min(max_width);
    let y = (render_height * 0.07).max(18.0);
    let font_size = (height * 0.46).max(16.0);
    Some(VideoOverlayLabelLayout {
        width: width.max(1.0),
        height,
        y,
        font_size,
    })
}

pub fn derive_text_overlay_label_layout(
    render_width: f32,
    render_height: f32,
    char_count: u32,
) -> Option<VideoOverlayLabelLayout> {
    if !render_width.is_finite()
        || !render_height.is_finite()
        || render_width <= 0.0
        || render_height <= 0.0
    {
        return None;
    }

    let height = (render_height * 0.09).clamp(34.0, 62.0);
    let max_width = render_width * 0.78;
    let width = (char_count.saturating_mul(14).max(90) as f32).min(max_width);
    let y = (render_height * 0.12).max(20.0);
    let font_size = (height * 0.42).max(15.0);
    Some(VideoOverlayLabelLayout {
        width: width.max(1.0),
        height,
        y,
        font_size,
    })
}

pub fn derive_overlay_clip_window(
    clip_start_seconds: f64,
    clip_end_seconds: f64,
    trim_start_seconds: f64,
    min_visible_seconds: f64,
) -> Option<VideoOverlayClipWindow> {
    if !clip_start_seconds.is_finite()
        || !clip_end_seconds.is_finite()
        || !trim_start_seconds.is_finite()
        || !min_visible_seconds.is_finite()
    {
        return None;
    }

    let start = clip_start_seconds - trim_start_seconds;
    let end = clip_end_seconds - trim_start_seconds;
    let display_start = start.max(0.0);
    let display_end = end.max(display_start);
    if display_end - display_start < min_visible_seconds.max(0.0) {
        return None;
    }

    Some(VideoOverlayClipWindow {
        start_seconds: display_start,
        end_seconds: display_end,
    })
}

pub fn overlay_fade_duration_seconds(
    window: VideoOverlayClipWindow,
    min_duration_seconds: f64,
) -> Option<f64> {
    if !window.start_seconds.is_finite()
        || !window.end_seconds.is_finite()
        || !min_duration_seconds.is_finite()
    {
        return None;
    }
    if window.end_seconds < window.start_seconds {
        return None;
    }

    Some((window.end_seconds - window.start_seconds).max(min_duration_seconds.max(0.0)))
}

pub fn normalize_click_point(normalized_x: f32, normalized_y: f32) -> Option<(f32, f32)> {
    if !normalized_x.is_finite() || !normalized_y.is_finite() {
        return None;
    }
    Some((normalized_x.clamp(0.0, 1.0), normalized_y.clamp(0.0, 1.0)))
}

#[allow(clippy::too_many_arguments)]
pub fn click_event_is_duplicate(
    last_timestamp_ns: u64,
    last_button: u32,
    last_x: f32,
    last_y: f32,
    timestamp_ns: u64,
    button: u32,
    x: f32,
    y: f32,
    epsilon: f32,
) -> bool {
    if !last_x.is_finite() || !last_y.is_finite() || !x.is_finite() || !y.is_finite() {
        return false;
    }
    if last_timestamp_ns != timestamp_ns || last_button != button {
        return false;
    }

    let eps = if epsilon.is_finite() {
        epsilon.max(0.000_001)
    } else {
        0.0001
    };

    (last_x - x).abs() <= eps && (last_y - y).abs() <= eps
}

