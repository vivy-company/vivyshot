use crate::{
    vs_video_export_context, vs_video_export_plan, vs_video_overlay_clip_window,
    vs_video_overlay_label_layout,
};
use vivyshot_domain::{
    compute_video_export_plan as domain_compute_video_export_plan,
    derive_key_overlay_label_layout as domain_derive_key_overlay_label_layout,
    derive_overlay_clip_window as domain_derive_overlay_clip_window,
    derive_text_overlay_label_layout as domain_derive_text_overlay_label_layout,
    overlay_fade_duration_seconds as domain_overlay_fade_duration_seconds,
};

use super::domain::{to_domain_video_export_context, to_ffi_video_export_plan};

pub(crate) fn compute_export_plan(
    trim_start_ms: u32,
    trim_end_ms: u32,
    key_event_count: u32,
    click_event_count: u32,
    context: vs_video_export_context,
) -> Option<vs_video_export_plan> {
    domain_compute_video_export_plan(
        trim_start_ms,
        trim_end_ms,
        key_event_count,
        click_event_count,
        to_domain_video_export_context(context),
    )
    .map(to_ffi_video_export_plan)
}

pub(crate) fn key_overlay_label_layout(
    render_width: f32,
    render_height: f32,
    char_count: u32,
) -> Option<vs_video_overlay_label_layout> {
    domain_derive_key_overlay_label_layout(render_width, render_height, char_count).map(|layout| {
        vs_video_overlay_label_layout {
            width: layout.width,
            height: layout.height,
            y: layout.y,
            font_size: layout.font_size,
        }
    })
}

pub(crate) fn text_overlay_label_layout(
    render_width: f32,
    render_height: f32,
    char_count: u32,
) -> Option<vs_video_overlay_label_layout> {
    domain_derive_text_overlay_label_layout(render_width, render_height, char_count).map(|layout| {
        vs_video_overlay_label_layout {
            width: layout.width,
            height: layout.height,
            y: layout.y,
            font_size: layout.font_size,
        }
    })
}

pub(crate) fn overlay_clip_window(
    clip_start_seconds: f64,
    clip_end_seconds: f64,
    trim_start_seconds: f64,
    min_visible_seconds: f64,
) -> Option<vs_video_overlay_clip_window> {
    domain_derive_overlay_clip_window(
        clip_start_seconds,
        clip_end_seconds,
        trim_start_seconds,
        min_visible_seconds,
    )
    .and_then(|window| {
        let fade_duration = domain_overlay_fade_duration_seconds(
            window,
            crate::VS_VIDEO_TEXT_MIN_FADE_DURATION_SECONDS,
        )?;
        Some(vs_video_overlay_clip_window {
            start_seconds: window.start_seconds,
            end_seconds: window.end_seconds,
            fade_duration_seconds: fade_duration,
        })
    })
}
