use crate::{
    vs_f32_point, vs_f32_rect, vs_gif_export_plan, vs_i32_rect, vs_rgba8,
    vs_stitch_autoscroll_state, vs_video_export_context, vs_video_export_decision,
    vs_video_export_plan, vs_video_post_recording_composition_plan, VS_RESIZE_CORNER_BOTTOM,
    VS_RESIZE_CORNER_BOTTOM_LEFT, VS_RESIZE_CORNER_BOTTOM_RIGHT, VS_RESIZE_CORNER_LEFT,
    VS_RESIZE_CORNER_RIGHT, VS_RESIZE_CORNER_TOP, VS_RESIZE_CORNER_TOP_LEFT,
    VS_RESIZE_CORNER_TOP_RIGHT, VS_TRIM_HANDLE_END, VS_TRIM_HANDLE_START, VS_TRIM_HANDLE_UNKNOWN,
    VS_VIDEO_EXPORT_CONTAINER_MOV, VS_VIDEO_EXPORT_CONTAINER_MP4, VS_VIDEO_EXPORT_PRESET_1280X720,
    VS_VIDEO_EXPORT_PRESET_1920X1080, VS_VIDEO_EXPORT_PRESET_HEVC_1920X1080,
    VS_VIDEO_EXPORT_PRESET_HEVC_HIGHEST_QUALITY, VS_VIDEO_EXPORT_PRESET_HIGHEST_QUALITY,
    VS_VIDEO_EXPORT_PRESET_MEDIUM_QUALITY,
};
use vivyshot_domain::{
    AffineTransform as DomainAffineTransform, F32Point as DomainF32Point, F32Rect as DomainF32Rect,
    GifExportPlan as DomainGifExportPlan, I32Rect as DomainI32Rect,
    ResizeCorner as DomainResizeCorner, Rgba8 as DomainRgba8,
    StitchAutoscrollState as DomainStitchAutoscrollState, TrimHandle as DomainTrimHandle,
    VideoExportBitratePreset as DomainVideoExportBitratePreset,
    VideoExportCodec as DomainVideoExportCodec, VideoExportContainer as DomainVideoExportContainer,
    VideoExportContext as DomainVideoExportContext,
    VideoExportDecision as DomainVideoExportDecision,
    VideoExportFrameRate as DomainVideoExportFrameRate, VideoExportPlan as DomainVideoExportPlan,
    VideoExportPreset as DomainVideoExportPreset, VideoExportQuality as DomainVideoExportQuality,
    VideoExportScale as DomainVideoExportScale,
    VideoPostRecordingCompositionPlan as DomainVideoPostRecordingCompositionPlan,
};

pub(crate) fn to_domain_trim_handle(raw: u8) -> Option<DomainTrimHandle> {
    match raw {
        VS_TRIM_HANDLE_UNKNOWN => Some(DomainTrimHandle::Unknown),
        VS_TRIM_HANDLE_START => Some(DomainTrimHandle::Start),
        VS_TRIM_HANDLE_END => Some(DomainTrimHandle::End),
        _ => None,
    }
}

pub(crate) fn to_domain_video_export_codec(raw: u8) -> Option<DomainVideoExportCodec> {
    match raw {
        0 => Some(DomainVideoExportCodec::H264),
        1 => Some(DomainVideoExportCodec::Hevc),
        _ => None,
    }
}

pub(crate) fn to_domain_video_export_quality(raw: u8) -> Option<DomainVideoExportQuality> {
    match raw {
        0 => Some(DomainVideoExportQuality::Standard),
        1 => Some(DomainVideoExportQuality::High),
        _ => None,
    }
}

pub(crate) fn to_domain_video_export_frame_rate(raw: u8) -> Option<DomainVideoExportFrameRate> {
    match raw {
        0 => Some(DomainVideoExportFrameRate::Fps30),
        1 => Some(DomainVideoExportFrameRate::Fps60),
        2 => Some(DomainVideoExportFrameRate::Fps120),
        _ => None,
    }
}

pub(crate) fn to_domain_video_export_scale(raw: u8) -> Option<DomainVideoExportScale> {
    match raw {
        0 => Some(DomainVideoExportScale::Full),
        1 => Some(DomainVideoExportScale::Percent75),
        2 => Some(DomainVideoExportScale::Percent50),
        _ => None,
    }
}

pub(crate) fn to_domain_video_export_bitrate_preset(
    raw: u8,
) -> Option<DomainVideoExportBitratePreset> {
    match raw {
        0 => Some(DomainVideoExportBitratePreset::Standard),
        1 => Some(DomainVideoExportBitratePreset::High),
        2 => Some(DomainVideoExportBitratePreset::VeryHigh),
        _ => None,
    }
}

pub(crate) fn to_ffi_gif_plan(plan: DomainGifExportPlan) -> vs_gif_export_plan {
    vs_gif_export_plan {
        start_ms: plan.start_ms,
        end_ms: plan.end_ms,
        frame_rate: plan.frame_rate,
        frame_count: plan.frame_count,
        max_dimension: plan.max_dimension,
        frame_delay_ms: plan.frame_delay_ms,
    }
}

pub(crate) fn to_domain_gif_plan(plan: vs_gif_export_plan) -> DomainGifExportPlan {
    DomainGifExportPlan {
        start_ms: plan.start_ms,
        end_ms: plan.end_ms,
        frame_rate: plan.frame_rate,
        frame_count: plan.frame_count,
        max_dimension: plan.max_dimension,
        frame_delay_ms: plan.frame_delay_ms,
    }
}

pub(crate) fn to_ffi_stitch_autoscroll_state(
    state: DomainStitchAutoscrollState,
) -> vs_stitch_autoscroll_state {
    vs_stitch_autoscroll_state {
        direction_sign: state.direction_sign,
        no_motion_ticks: state.no_motion_ticks,
        did_flip_direction: state.did_flip_direction,
    }
}

pub(crate) fn to_domain_stitch_autoscroll_state(
    state: vs_stitch_autoscroll_state,
) -> DomainStitchAutoscrollState {
    DomainStitchAutoscrollState {
        direction_sign: state.direction_sign,
        no_motion_ticks: state.no_motion_ticks,
        did_flip_direction: state.did_flip_direction,
    }
}

pub(crate) fn to_domain_video_export_context(
    context: vs_video_export_context,
) -> DomainVideoExportContext {
    DomainVideoExportContext {
        source_has_audio: context.source_has_audio,
        source_has_webcam_asset: context.source_has_webcam_asset,
        audio_track_visible: context.audio_track_visible,
        webcam_track_visible: context.webcam_track_visible,
        text_overlay_count: context.text_overlay_count,
    }
}

pub(crate) fn to_ffi_video_export_context(
    context: DomainVideoExportContext,
) -> vs_video_export_context {
    vs_video_export_context {
        source_has_audio: context.source_has_audio,
        source_has_webcam_asset: context.source_has_webcam_asset,
        audio_track_visible: context.audio_track_visible,
        webcam_track_visible: context.webcam_track_visible,
        text_overlay_count: context.text_overlay_count,
    }
}

pub(crate) fn to_ffi_video_export_plan(plan: DomainVideoExportPlan) -> vs_video_export_plan {
    vs_video_export_plan {
        trim_start_ms: plan.trim_start_ms,
        trim_end_ms: plan.trim_end_ms,
        key_event_count: plan.key_event_count,
        click_event_count: plan.click_event_count,
        plan_mode: plan.plan_mode,
        include_audio: plan.include_audio,
        include_webcam: plan.include_webcam,
        text_overlay_count: plan.text_overlay_count,
        overlay_item_count: plan.overlay_item_count,
        requires_intermediate_for_gif: plan.requires_intermediate_for_gif,
        needs_custom_compositor: plan.needs_custom_compositor,
    }
}

pub(crate) fn to_domain_video_export_plan(plan: vs_video_export_plan) -> DomainVideoExportPlan {
    DomainVideoExportPlan {
        trim_start_ms: plan.trim_start_ms,
        trim_end_ms: plan.trim_end_ms,
        key_event_count: plan.key_event_count,
        click_event_count: plan.click_event_count,
        plan_mode: plan.plan_mode,
        include_audio: plan.include_audio,
        include_webcam: plan.include_webcam,
        text_overlay_count: plan.text_overlay_count,
        overlay_item_count: plan.overlay_item_count,
        requires_intermediate_for_gif: plan.requires_intermediate_for_gif,
        needs_custom_compositor: plan.needs_custom_compositor,
    }
}

pub(crate) fn to_ffi_video_export_decision(
    decision: DomainVideoExportDecision,
) -> vs_video_export_decision {
    vs_video_export_decision {
        use_custom_compositor: decision.use_custom_compositor,
        requires_intermediate_for_gif: decision.requires_intermediate_for_gif,
        include_audio: decision.include_audio,
        include_webcam: decision.include_webcam,
    }
}

pub(crate) fn to_ffi_video_export_container(container: DomainVideoExportContainer) -> u8 {
    match container {
        DomainVideoExportContainer::Mp4 => VS_VIDEO_EXPORT_CONTAINER_MP4,
        DomainVideoExportContainer::Mov => VS_VIDEO_EXPORT_CONTAINER_MOV,
    }
}

pub(crate) fn to_ffi_video_export_preset(preset: DomainVideoExportPreset) -> u8 {
    match preset {
        DomainVideoExportPreset::HighestQuality => VS_VIDEO_EXPORT_PRESET_HIGHEST_QUALITY,
        DomainVideoExportPreset::Resolution1920x1080 => VS_VIDEO_EXPORT_PRESET_1920X1080,
        DomainVideoExportPreset::Resolution1280x720 => VS_VIDEO_EXPORT_PRESET_1280X720,
        DomainVideoExportPreset::MediumQuality => VS_VIDEO_EXPORT_PRESET_MEDIUM_QUALITY,
        DomainVideoExportPreset::HevcResolution1920x1080 => VS_VIDEO_EXPORT_PRESET_HEVC_1920X1080,
        DomainVideoExportPreset::HevcHighestQuality => VS_VIDEO_EXPORT_PRESET_HEVC_HIGHEST_QUALITY,
    }
}

pub(crate) fn to_ffi_post_recording_video_composition_plan(
    plan: DomainVideoPostRecordingCompositionPlan,
) -> vs_video_post_recording_composition_plan {
    vs_video_post_recording_composition_plan {
        render_width: plan.render_width,
        render_height: plan.render_height,
        transform: crate::vs_affine_transform {
            a: plan.transform.a,
            b: plan.transform.b,
            c: plan.transform.c,
            d: plan.transform.d,
            tx: plan.transform.tx,
            ty: plan.transform.ty,
        },
    }
}

pub(crate) fn to_domain_affine_transform(
    transform: crate::vs_affine_transform,
) -> DomainAffineTransform {
    DomainAffineTransform {
        a: transform.a,
        b: transform.b,
        c: transform.c,
        d: transform.d,
        tx: transform.tx,
        ty: transform.ty,
    }
}

pub(crate) fn to_domain_f32_rect(rect: vs_f32_rect) -> DomainF32Rect {
    DomainF32Rect {
        x: rect.x,
        y: rect.y,
        width: rect.width,
        height: rect.height,
    }
}

pub(crate) fn to_ffi_f32_rect(rect: DomainF32Rect) -> vs_f32_rect {
    vs_f32_rect {
        x: rect.x,
        y: rect.y,
        width: rect.width,
        height: rect.height,
    }
}

pub(crate) fn to_ffi_f32_point(point: DomainF32Point) -> vs_f32_point {
    vs_f32_point {
        x: point.x,
        y: point.y,
    }
}

pub(crate) fn to_ffi_i32_rect(rect: DomainI32Rect) -> vs_i32_rect {
    vs_i32_rect {
        x: rect.x,
        y: rect.y,
        width: rect.width,
        height: rect.height,
    }
}

pub(crate) fn to_ffi_rgba8(color: DomainRgba8) -> vs_rgba8 {
    vs_rgba8 {
        r: color.r,
        g: color.g,
        b: color.b,
        a: color.a,
    }
}

pub(crate) fn to_domain_resize_corner(raw: u8) -> Option<DomainResizeCorner> {
    match raw {
        VS_RESIZE_CORNER_TOP_LEFT => Some(DomainResizeCorner::TopLeft),
        VS_RESIZE_CORNER_TOP => Some(DomainResizeCorner::Top),
        VS_RESIZE_CORNER_TOP_RIGHT => Some(DomainResizeCorner::TopRight),
        VS_RESIZE_CORNER_RIGHT => Some(DomainResizeCorner::Right),
        VS_RESIZE_CORNER_BOTTOM => Some(DomainResizeCorner::Bottom),
        VS_RESIZE_CORNER_LEFT => Some(DomainResizeCorner::Left),
        VS_RESIZE_CORNER_BOTTOM_LEFT => Some(DomainResizeCorner::BottomLeft),
        VS_RESIZE_CORNER_BOTTOM_RIGHT => Some(DomainResizeCorner::BottomRight),
        _ => None,
    }
}
