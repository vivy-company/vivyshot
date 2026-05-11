use crate::{
    vs_video_export_context, vs_video_export_plan, vs_video_overlay_clip_window,
    vs_video_overlay_label_layout, vs_video_post_recording_composition_plan,
};
use vivyshot_domain::{
    best_video_export_container as domain_best_video_export_container,
    best_video_export_preset as domain_best_video_export_preset,
    compute_video_export_plan as domain_compute_video_export_plan,
    derive_key_overlay_label_layout as domain_derive_key_overlay_label_layout,
    derive_overlay_clip_window as domain_derive_overlay_clip_window,
    derive_text_overlay_label_layout as domain_derive_text_overlay_label_layout,
    estimated_video_file_length_limit as domain_estimated_video_file_length_limit,
    overlay_fade_duration_seconds as domain_overlay_fade_duration_seconds,
    post_recording_video_composition_plan as domain_post_recording_video_composition_plan,
    preferred_video_export_container as domain_preferred_video_export_container,
};

use super::domain::{
    to_domain_affine_transform, to_domain_video_export_bitrate_preset,
    to_domain_video_export_codec, to_domain_video_export_context,
    to_domain_video_export_frame_rate, to_domain_video_export_quality,
    to_domain_video_export_scale, to_ffi_post_recording_video_composition_plan,
    to_ffi_video_export_plan,
};

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

pub(crate) fn preferred_save_container(codec: u8) -> Option<u8> {
    let codec = to_domain_video_export_codec(codec)?;
    Some(super::domain::to_ffi_video_export_container(
        domain_preferred_video_export_container(codec),
    ))
}

pub(crate) fn best_save_container(codec: u8, supports_mp4: bool, supports_mov: bool) -> Option<u8> {
    let codec = to_domain_video_export_codec(codec)?;
    domain_best_video_export_container(codec, supports_mp4, supports_mov)
        .map(super::domain::to_ffi_video_export_container)
}

pub(crate) fn best_export_preset(codec: u8, quality: u8, compatible_mask: u32) -> Option<u8> {
    let codec = to_domain_video_export_codec(codec)?;
    let quality = to_domain_video_export_quality(quality)?;
    domain_best_video_export_preset(codec, quality, compatible_mask)
        .map(super::domain::to_ffi_video_export_preset)
}

pub(crate) fn estimated_file_length_limit(
    duration_seconds: f64,
    codec: u8,
    frame_rate: u8,
    quality: u8,
    scale: u8,
    bitrate: u8,
) -> Option<i64> {
    domain_estimated_video_file_length_limit(
        duration_seconds,
        to_domain_video_export_codec(codec)?,
        to_domain_video_export_frame_rate(frame_rate)?,
        to_domain_video_export_quality(quality)?,
        to_domain_video_export_scale(scale)?,
        to_domain_video_export_bitrate_preset(bitrate)?,
    )
}

pub(crate) fn post_recording_video_composition_plan(
    natural_width: f32,
    natural_height: f32,
    preferred_transform: crate::vs_affine_transform,
    scale: u8,
) -> Option<vs_video_post_recording_composition_plan> {
    let scale = to_domain_video_export_scale(scale)?;
    domain_post_recording_video_composition_plan(
        natural_width,
        natural_height,
        to_domain_affine_transform(preferred_transform),
        scale,
    )
    .map(to_ffi_post_recording_video_composition_plan)
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
