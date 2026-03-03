use crate::{
    vs_f32_rect, vs_gif_export_plan, vs_i32_rect, vs_rgba8, vs_stitch_autoscroll_state,
    vs_video_export_context, vs_video_export_plan, VS_TRIM_HANDLE_END, VS_TRIM_HANDLE_START,
    VS_TRIM_HANDLE_UNKNOWN,
};
use vivyshot_domain::{
    F32Rect as DomainF32Rect, GifExportPlan as DomainGifExportPlan, I32Rect as DomainI32Rect,
    Rgba8 as DomainRgba8, StitchAutoscrollState as DomainStitchAutoscrollState,
    TrimHandle as DomainTrimHandle, VideoExportContext as DomainVideoExportContext,
    VideoExportPlan as DomainVideoExportPlan,
};

pub(crate) fn to_domain_trim_handle(raw: u8) -> Option<DomainTrimHandle> {
    match raw {
        VS_TRIM_HANDLE_UNKNOWN => Some(DomainTrimHandle::Unknown),
        VS_TRIM_HANDLE_START => Some(DomainTrimHandle::Start),
        VS_TRIM_HANDLE_END => Some(DomainTrimHandle::End),
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

pub(crate) fn to_domain_f32_rect(rect: vs_f32_rect) -> DomainF32Rect {
    DomainF32Rect {
        x: rect.x,
        y: rect.y,
        width: rect.width,
        height: rect.height,
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
