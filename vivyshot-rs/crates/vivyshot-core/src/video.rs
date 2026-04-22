use crate::types::{
    AffineTransform, TimelineTrackSummary, VideoExportBitratePreset, VideoExportCodec,
    VideoExportContainer, VideoExportFrameRate, VideoExportPreset, VideoExportQuality,
    VideoExportScale, VideoPostRecordingCompositionPlan,
};

pub use crate::types::{
    VideoExportContext, VideoExportDecision, VideoExportPlan, VideoOverlayClipWindow,
    VideoOverlayLabelLayout, VIDEO_EXPORT_TARGET_GIF, VIDEO_EXPORT_TARGET_MP4,
    VIDEO_KEY_OVERLAY_FADE_DURATION_SECONDS, VIDEO_KEY_OVERLAY_FADE_HOLD_KEYTIME,
    VIDEO_KEY_OVERLAY_FADE_IN_KEYTIME, VIDEO_PLAN_MODE_COMPOSITE_MP4, VIDEO_PLAN_MODE_PASSTHROUGH,
    VIDEO_TEXT_OVERLAY_FADE_HOLD_KEYTIME, VIDEO_TEXT_OVERLAY_FADE_IN_KEYTIME,
    VIDEO_TEXT_OVERLAY_MIN_FADE_DURATION_SECONDS, VIDEO_TEXT_OVERLAY_MIN_VISIBLE_SECONDS,
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

pub fn preferred_video_export_container(codec: VideoExportCodec) -> VideoExportContainer {
    match codec {
        VideoExportCodec::H264 => VideoExportContainer::Mp4,
        VideoExportCodec::Hevc => VideoExportContainer::Mov,
    }
}

pub fn allowed_video_export_containers(
    codec: VideoExportCodec,
) -> (VideoExportContainer, VideoExportContainer) {
    match codec {
        VideoExportCodec::H264 => (VideoExportContainer::Mp4, VideoExportContainer::Mov),
        VideoExportCodec::Hevc => (VideoExportContainer::Mov, VideoExportContainer::Mp4),
    }
}

pub fn best_video_export_container(
    codec: VideoExportCodec,
    supports_mp4: bool,
    supports_mov: bool,
) -> Option<VideoExportContainer> {
    let (preferred, fallback) = allowed_video_export_containers(codec);
    match preferred {
        VideoExportContainer::Mp4 if supports_mp4 => Some(VideoExportContainer::Mp4),
        VideoExportContainer::Mov if supports_mov => Some(VideoExportContainer::Mov),
        _ => match fallback {
            VideoExportContainer::Mp4 if supports_mp4 => Some(VideoExportContainer::Mp4),
            VideoExportContainer::Mov if supports_mov => Some(VideoExportContainer::Mov),
            _ => None,
        },
    }
}

pub fn best_video_export_preset(
    codec: VideoExportCodec,
    quality: VideoExportQuality,
    compatible_mask: u32,
) -> Option<VideoExportPreset> {
    let candidates: &[VideoExportPreset] = match (codec, quality) {
        (VideoExportCodec::H264, VideoExportQuality::Standard) => &[
            VideoExportPreset::Resolution1920x1080,
            VideoExportPreset::Resolution1280x720,
            VideoExportPreset::MediumQuality,
            VideoExportPreset::HighestQuality,
        ],
        (VideoExportCodec::H264, VideoExportQuality::High) => &[
            VideoExportPreset::HighestQuality,
            VideoExportPreset::Resolution1920x1080,
            VideoExportPreset::Resolution1280x720,
        ],
        (VideoExportCodec::Hevc, VideoExportQuality::Standard) => &[
            VideoExportPreset::HevcResolution1920x1080,
            VideoExportPreset::HevcHighestQuality,
            VideoExportPreset::HighestQuality,
        ],
        (VideoExportCodec::Hevc, VideoExportQuality::High) => &[
            VideoExportPreset::HevcHighestQuality,
            VideoExportPreset::HevcResolution1920x1080,
            VideoExportPreset::HighestQuality,
        ],
    };

    candidates
        .iter()
        .copied()
        .find(|preset| compatible_mask & preset_compatibility_bit(*preset) != 0)
        .or(Some(VideoExportPreset::HighestQuality))
}

pub fn estimated_video_file_length_limit(
    duration_seconds: f64,
    codec: VideoExportCodec,
    frame_rate: VideoExportFrameRate,
    quality: VideoExportQuality,
    scale: VideoExportScale,
    bitrate: VideoExportBitratePreset,
) -> Option<i64> {
    if !duration_seconds.is_finite() || duration_seconds <= 0.0 {
        return None;
    }

    let mut video_bitrate = bitrate.base_bits_per_second();
    video_bitrate *= quality.multiplier();
    video_bitrate *= frame_rate.multiplier();
    video_bitrate *= scale.multiplier();
    video_bitrate *= codec.compression_multiplier();

    let total_bits_per_second = video_bitrate.round().max(2_000_000.0);
    let bytes = (duration_seconds * total_bits_per_second) / 8.0;
    Some(bytes.ceil() as i64)
}

pub fn post_recording_video_composition_plan(
    natural_width: f32,
    natural_height: f32,
    preferred_transform: AffineTransform,
    scale: VideoExportScale,
) -> Option<VideoPostRecordingCompositionPlan> {
    if !natural_width.is_finite()
        || !natural_height.is_finite()
        || natural_width <= 0.0
        || natural_height <= 0.0
        || !preferred_transform.a.is_finite()
        || !preferred_transform.b.is_finite()
        || !preferred_transform.c.is_finite()
        || !preferred_transform.d.is_finite()
        || !preferred_transform.tx.is_finite()
        || !preferred_transform.ty.is_finite()
    {
        return None;
    }

    let scale_factor = scale.factor() as f32;
    let scaled = AffineTransform {
        a: preferred_transform.a * scale_factor,
        b: preferred_transform.b * scale_factor,
        c: preferred_transform.c * scale_factor,
        d: preferred_transform.d * scale_factor,
        tx: preferred_transform.tx,
        ty: preferred_transform.ty,
    };

    let corners = [
        transform_point(scaled, 0.0, 0.0),
        transform_point(scaled, natural_width, 0.0),
        transform_point(scaled, 0.0, natural_height),
        transform_point(scaled, natural_width, natural_height),
    ];
    let (min_x, max_x) = corners
        .iter()
        .map(|(x, _)| *x)
        .fold((f32::INFINITY, f32::NEG_INFINITY), |(min, max), value| {
            (min.min(value), max.max(value))
        });
    let (min_y, max_y) = corners
        .iter()
        .map(|(_, y)| *y)
        .fold((f32::INFINITY, f32::NEG_INFINITY), |(min, max), value| {
            (min.min(value), max.max(value))
        });

    let render_width = u32::max(2, rounded_even_dimension(max_x - min_x));
    let render_height = u32::max(2, rounded_even_dimension(max_y - min_y));
    let translated = concatenate(
        scaled,
        AffineTransform {
            a: 1.0,
            b: 0.0,
            c: 0.0,
            d: 1.0,
            tx: -min_x,
            ty: -min_y,
        },
    );

    Some(VideoPostRecordingCompositionPlan {
        render_width,
        render_height,
        transform: translated,
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

fn preset_compatibility_bit(preset: VideoExportPreset) -> u32 {
    match preset {
        VideoExportPreset::HighestQuality => 1 << 0,
        VideoExportPreset::Resolution1920x1080 => 1 << 1,
        VideoExportPreset::Resolution1280x720 => 1 << 2,
        VideoExportPreset::MediumQuality => 1 << 3,
        VideoExportPreset::HevcResolution1920x1080 => 1 << 4,
        VideoExportPreset::HevcHighestQuality => 1 << 5,
    }
}

fn transform_point(transform: AffineTransform, x: f32, y: f32) -> (f32, f32) {
    (
        (transform.a * x) + (transform.c * y) + transform.tx,
        (transform.b * x) + (transform.d * y) + transform.ty,
    )
}

fn concatenate(left: AffineTransform, right: AffineTransform) -> AffineTransform {
    AffineTransform {
        a: left.a * right.a + left.b * right.c,
        b: left.a * right.b + left.b * right.d,
        c: left.c * right.a + left.d * right.c,
        d: left.c * right.b + left.d * right.d,
        tx: left.tx * right.a + left.ty * right.c + right.tx,
        ty: left.tx * right.b + left.ty * right.d + right.ty,
    }
}

fn rounded_even_dimension(value: f32) -> u32 {
    if !value.is_finite() {
        return 2;
    }
    let rounded = value.abs().round().max(2.0) as u32;
    rounded & !1
}
