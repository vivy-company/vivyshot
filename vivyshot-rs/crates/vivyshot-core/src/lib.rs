//! Portable domain logic for VivyShot.
//!
//! This crate is the cross-platform source of truth for timeline/video policy,
//! geometry transforms, selection math, stitching policy, and export planning.

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TrimHandle {
    Unknown,
    Start,
    End,
}

pub const VIDEO_PLAN_MODE_PASSTHROUGH: u8 = 0;
pub const VIDEO_PLAN_MODE_COMPOSITE_MP4: u8 = 1;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct VideoExportContext {
    pub source_has_audio: bool,
    pub source_has_webcam_asset: bool,
    pub audio_track_visible: bool,
    pub webcam_track_visible: bool,
    pub text_overlay_count: u32,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct VideoExportPlan {
    pub trim_start_ms: u32,
    pub trim_end_ms: u32,
    pub key_event_count: u32,
    pub click_event_count: u32,
    pub plan_mode: u8,
    pub include_audio: bool,
    pub include_webcam: bool,
    pub text_overlay_count: u32,
    pub overlay_item_count: u32,
    pub requires_intermediate_for_gif: bool,
    pub needs_custom_compositor: bool,
}

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct GifExportPlan {
    pub start_ms: u32,
    pub end_ms: u32,
    pub frame_rate: f32,
    pub frame_count: u32,
    pub max_dimension: u32,
    pub frame_delay_ms: u32,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct StitchAutoscrollState {
    pub direction_sign: i32,
    pub no_motion_ticks: u32,
    pub did_flip_direction: bool,
}

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct F32Rect {
    pub x: f32,
    pub y: f32,
    pub width: f32,
    pub height: f32,
}

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct F32Point {
    pub x: f32,
    pub y: f32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ResizeCorner {
    TopLeft,
    Top,
    TopRight,
    Right,
    Bottom,
    Left,
    BottomLeft,
    BottomRight,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct TimelineTrackSummary {
    pub kind: u8,
    pub visible: bool,
    pub clip_count: u32,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct I32Rect {
    pub x: i32,
    pub y: i32,
    pub width: i32,
    pub height: i32,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Rgba8 {
    pub r: u8,
    pub g: u8,
    pub b: u8,
    pub a: u8,
}

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

pub fn normalize_trim_range(
    duration_ms: u32,
    start_ms: u32,
    end_ms: u32,
    min_gap_ms: u32,
    active_handle: TrimHandle,
) -> (u32, u32) {
    let min_gap = min_gap_ms.max(1);
    let mut start = start_ms.min(duration_ms);
    let mut end = end_ms.min(duration_ms);

    if start >= end.saturating_sub(min_gap) {
        match active_handle {
            TrimHandle::Start => {
                end = start.saturating_add(min_gap).min(duration_ms);
            }
            TrimHandle::End | TrimHandle::Unknown => {
                start = end.saturating_sub(min_gap);
            }
        }
    }

    if start > duration_ms {
        start = duration_ms;
    }
    if end < start.saturating_add(1) {
        end = start.saturating_add(1).min(duration_ms);
    }
    if end <= start {
        end = start.saturating_add(1);
    }

    (start, end.min(duration_ms.max(1)))
}

pub fn build_gif_export_plan(
    start_ms: u32,
    end_ms: u32,
    preferred_fps: f32,
    max_dimension: u32,
) -> GifExportPlan {
    let start = start_ms;
    let mut end = end_ms.max(start.saturating_add(1));
    if end <= start {
        end = start.saturating_add(1);
    }

    let duration_ms = end.saturating_sub(start).max(1);
    let fps = if preferred_fps.is_finite() {
        preferred_fps.clamp(1.0, 30.0)
    } else {
        12.0
    };
    let mut frame_count = (((duration_ms as f32) / 1000.0) * fps).ceil() as u32;
    frame_count = frame_count.clamp(1, 2400);

    let final_max_dim = max_dimension.clamp(64, 2048);
    let frame_delay_ms = ((1000.0 / fps).round() as u32).max(1);

    GifExportPlan {
        start_ms: start,
        end_ms: end,
        frame_rate: fps,
        frame_count,
        max_dimension: final_max_dim,
        frame_delay_ms,
    }
}

pub fn gif_frame_time_ms(plan: GifExportPlan, index: u32) -> Option<u32> {
    if plan.frame_count == 0 || plan.end_ms <= plan.start_ms {
        return None;
    }

    let idx = index.min(plan.frame_count - 1);
    let progress = if plan.frame_count <= 1 {
        0.0
    } else {
        idx as f64 / (plan.frame_count - 1) as f64
    };

    let span = (plan.end_ms - plan.start_ms) as f64;
    let t = plan.start_ms as f64 + span * progress;
    Some(t.round() as u32)
}

pub fn stitch_autoscroll_reset() -> StitchAutoscrollState {
    StitchAutoscrollState {
        direction_sign: -1,
        no_motion_ticks: 0,
        did_flip_direction: false,
    }
}

pub fn stitch_autoscroll_update(
    enabled: bool,
    direction_locked: bool,
    did_merge: bool,
    threshold_ticks: u32,
    state: StitchAutoscrollState,
) -> StitchAutoscrollState {
    let mut next = state;
    if next.direction_sign == 0 {
        next.direction_sign = -1;
    }

    if !enabled {
        next.no_motion_ticks = 0;
        next.did_flip_direction = false;
        next.direction_sign = -1;
        return next;
    }

    if did_merge {
        next.no_motion_ticks = 0;
        return next;
    }

    next.no_motion_ticks = next.no_motion_ticks.saturating_add(1);
    let threshold = threshold_ticks.max(1);
    if !direction_locked && !next.did_flip_direction && next.no_motion_ticks >= threshold {
        next.did_flip_direction = true;
        next.no_motion_ticks = 0;
        next.direction_sign = -next.direction_sign;
        if next.direction_sign == 0 {
            next.direction_sign = -1;
        }
    }

    next
}

fn standardize_rect(rect: F32Rect) -> Option<(f32, f32, f32, f32)> {
    if !rect.x.is_finite()
        || !rect.y.is_finite()
        || !rect.width.is_finite()
        || !rect.height.is_finite()
    {
        return None;
    }
    if rect.width == 0.0 || rect.height == 0.0 {
        return None;
    }

    let x0 = rect.x;
    let y0 = rect.y;
    let x1 = rect.x + rect.width;
    let y1 = rect.y + rect.height;

    let min_x = x0.min(x1);
    let max_x = x0.max(x1);
    let min_y = y0.min(y1);
    let max_y = y0.max(y1);

    if !min_x.is_finite() || !max_x.is_finite() || !min_y.is_finite() || !max_y.is_finite() {
        return None;
    }

    if max_x <= min_x || max_y <= min_y {
        return None;
    }

    Some((min_x, min_y, max_x, max_y))
}

fn clamp_f32(value: f32, min_value: f32, max_value: f32) -> f32 {
    value.clamp(min_value, max_value)
}

pub fn view_rect_to_image_rect(
    view_rect: F32Rect,
    destination_rect: F32Rect,
    image_width: u32,
    image_height: u32,
) -> Option<F32Rect> {
    if image_width == 0 || image_height == 0 {
        return None;
    }

    let (view_min_x, view_min_y, view_max_x, view_max_y) = standardize_rect(view_rect)?;
    let (dst_min_x, dst_min_y, dst_max_x, dst_max_y) = standardize_rect(destination_rect)?;

    let clipped_min_x = view_min_x.max(dst_min_x);
    let clipped_min_y = view_min_y.max(dst_min_y);
    let clipped_max_x = view_max_x.min(dst_max_x);
    let clipped_max_y = view_max_y.min(dst_max_y);
    if clipped_max_x <= clipped_min_x || clipped_max_y <= clipped_min_y {
        return None;
    }

    let dst_width = dst_max_x - dst_min_x;
    let dst_height = dst_max_y - dst_min_y;
    if dst_width <= 0.0 || dst_height <= 0.0 {
        return None;
    }

    let scale_x = image_width as f32 / dst_width;
    let scale_y = image_height as f32 / dst_height;
    let image_h = image_height as f32;

    let x0 = (clipped_min_x - dst_min_x) * scale_x;
    let x1 = (clipped_max_x - dst_min_x) * scale_x;
    let y0_from_bottom = (clipped_min_y - dst_min_y) * scale_y;
    let y1_from_bottom = (clipped_max_y - dst_min_y) * scale_y;
    let y0 = image_h - y1_from_bottom;
    let y1 = image_h - y0_from_bottom;
    if x1 <= x0 || y1 <= y0 {
        return None;
    }

    Some(F32Rect {
        x: x0,
        y: y0,
        width: x1 - x0,
        height: y1 - y0,
    })
}

pub fn image_rect_to_view_rect(
    image_rect: F32Rect,
    destination_rect: F32Rect,
    image_width: u32,
    image_height: u32,
) -> Option<F32Rect> {
    if image_width == 0 || image_height == 0 {
        return None;
    }

    let (img_min_x, img_min_y, img_max_x, img_max_y) = standardize_rect(image_rect)?;
    let (dst_min_x, dst_min_y, dst_max_x, dst_max_y) = standardize_rect(destination_rect)?;

    let dst_width = dst_max_x - dst_min_x;
    let dst_height = dst_max_y - dst_min_y;
    if dst_width <= 0.0 || dst_height <= 0.0 {
        return None;
    }

    let scale_x = dst_width / image_width as f32;
    let scale_y = dst_height / image_height as f32;
    if scale_x <= 0.0 || scale_y <= 0.0 {
        return None;
    }

    let image_h = image_height as f32;
    let x0 = dst_min_x + img_min_x * scale_x;
    let x1 = dst_min_x + img_max_x * scale_x;
    let y_top = dst_min_y + (image_h - img_min_y) * scale_y;
    let y_bottom = dst_min_y + (image_h - img_max_y) * scale_y;
    let min_x = x0.min(x1);
    let max_x = x0.max(x1);
    let min_y = y_bottom.min(y_top);
    let max_y = y_bottom.max(y_top);
    if max_x <= min_x || max_y <= min_y {
        return None;
    }

    Some(F32Rect {
        x: min_x,
        y: min_y,
        width: max_x - min_x,
        height: max_y - min_y,
    })
}

pub fn view_delta_to_image_delta(
    delta_x: f32,
    delta_y: f32,
    destination_rect: F32Rect,
    image_width: u32,
    image_height: u32,
) -> Option<F32Point> {
    if !delta_x.is_finite() || !delta_y.is_finite() || image_width == 0 || image_height == 0 {
        return None;
    }
    let (dst_min_x, dst_min_y, dst_max_x, dst_max_y) = standardize_rect(destination_rect)?;
    let dst_width = dst_max_x - dst_min_x;
    let dst_height = dst_max_y - dst_min_y;
    if dst_width <= 0.0 || dst_height <= 0.0 {
        return None;
    }

    let scale_x = image_width as f32 / dst_width;
    let scale_y = image_height as f32 / dst_height;
    if scale_x <= 0.0 || scale_y <= 0.0 {
        return None;
    }

    Some(F32Point {
        x: delta_x * scale_x,
        y: -delta_y * scale_y,
    })
}

pub fn image_delta_to_view_delta(
    delta_x: f32,
    delta_y: f32,
    destination_rect: F32Rect,
    image_width: u32,
    image_height: u32,
) -> Option<F32Point> {
    if !delta_x.is_finite() || !delta_y.is_finite() || image_width == 0 || image_height == 0 {
        return None;
    }
    let (dst_min_x, dst_min_y, dst_max_x, dst_max_y) = standardize_rect(destination_rect)?;
    let dst_width = dst_max_x - dst_min_x;
    let dst_height = dst_max_y - dst_min_y;
    if dst_width <= 0.0 || dst_height <= 0.0 {
        return None;
    }

    let scale_x = image_width as f32 / dst_width;
    let scale_y = image_height as f32 / dst_height;
    if scale_x <= 0.0 || scale_y <= 0.0 {
        return None;
    }

    Some(F32Point {
        x: delta_x / scale_x,
        y: -delta_y / scale_y,
    })
}

#[allow(clippy::too_many_arguments)]
pub fn viewport_clamp_pan_offset(
    bounds_width: f32,
    bounds_height: f32,
    image_width: u32,
    image_height: u32,
    zoom_scale: f32,
    overscroll: f32,
    candidate_x: f32,
    candidate_y: f32,
) -> Option<F32Point> {
    if image_width == 0
        || image_height == 0
        || !bounds_width.is_finite()
        || !bounds_height.is_finite()
        || !zoom_scale.is_finite()
        || !overscroll.is_finite()
        || !candidate_x.is_finite()
        || !candidate_y.is_finite()
    {
        return None;
    }
    if bounds_width <= 0.0 || bounds_height <= 0.0 || zoom_scale <= 0.0 {
        return None;
    }

    let image_width_f = image_width as f32;
    let image_height_f = image_height as f32;
    let fit_scale = (bounds_width / image_width_f).min(bounds_height / image_height_f);
    let draw_scale = fit_scale * zoom_scale;
    let draw_width = image_width_f * draw_scale;
    let draw_height = image_height_f * draw_scale;
    let max_x = ((draw_width - bounds_width) * 0.5 + overscroll).max(0.0);
    let max_y = ((draw_height - bounds_height) * 0.5 + overscroll).max(0.0);

    Some(F32Point {
        x: clamp_f32(candidate_x, -max_x, max_x),
        y: clamp_f32(candidate_y, -max_y, max_y),
    })
}

pub fn selection_move_rect(
    current: F32Rect,
    bounds: F32Rect,
    delta_x: f32,
    delta_y: f32,
) -> Option<(F32Rect, bool)> {
    if !delta_x.is_finite() || !delta_y.is_finite() {
        return None;
    }

    let (current_min_x, current_min_y, current_max_x, current_max_y) = standardize_rect(current)?;
    let (bounds_min_x, bounds_min_y, bounds_max_x, bounds_max_y) = standardize_rect(bounds)?;

    let width = current_max_x - current_min_x;
    let height = current_max_y - current_min_y;
    let bounds_width = bounds_max_x - bounds_min_x;
    let bounds_height = bounds_max_y - bounds_min_y;
    if width <= 0.0 || height <= 0.0 || width > bounds_width || height > bounds_height {
        return None;
    }

    let candidate_x = clamp_f32(current_min_x + delta_x, bounds_min_x, bounds_max_x - width);
    let candidate_y = clamp_f32(current_min_y + delta_y, bounds_min_y, bounds_max_y - height);
    let moved =
        (candidate_x - current_min_x).abs() > 0.01 || (candidate_y - current_min_y).abs() > 0.01;

    Some((
        F32Rect {
            x: candidate_x,
            y: candidate_y,
            width,
            height,
        },
        moved,
    ))
}

pub fn selection_resize_rect(
    start: F32Rect,
    bounds: F32Rect,
    corner: ResizeCorner,
    delta_x: f32,
    delta_y: f32,
    min_width: f32,
    min_height: f32,
) -> Option<F32Rect> {
    if !delta_x.is_finite()
        || !delta_y.is_finite()
        || !min_width.is_finite()
        || !min_height.is_finite()
        || min_width <= 0.0
        || min_height <= 0.0
    {
        return None;
    }

    let (start_min_x, start_min_y, start_max_x, start_max_y) = standardize_rect(start)?;
    let (bounds_min_x, bounds_min_y, bounds_max_x, bounds_max_y) = standardize_rect(bounds)?;

    let mut min_x = start_min_x;
    let mut max_x = start_max_x;
    let mut min_y = start_min_y;
    let mut max_y = start_max_y;

    match corner {
        ResizeCorner::TopLeft => {
            min_x += delta_x;
            max_y += delta_y;
        }
        ResizeCorner::Top => {
            max_y += delta_y;
        }
        ResizeCorner::TopRight => {
            max_x += delta_x;
            max_y += delta_y;
        }
        ResizeCorner::Right => {
            max_x += delta_x;
        }
        ResizeCorner::Bottom => {
            min_y += delta_y;
        }
        ResizeCorner::Left => {
            min_x += delta_x;
        }
        ResizeCorner::BottomLeft => {
            min_x += delta_x;
            min_y += delta_y;
        }
        ResizeCorner::BottomRight => {
            max_x += delta_x;
            min_y += delta_y;
        }
    }

    match corner {
        ResizeCorner::TopLeft => {
            min_x = min_x.min(max_x - min_width);
            max_y = max_y.max(min_y + min_height);
        }
        ResizeCorner::Top => {
            max_y = max_y.max(min_y + min_height);
        }
        ResizeCorner::TopRight => {
            max_x = max_x.max(min_x + min_width);
            max_y = max_y.max(min_y + min_height);
        }
        ResizeCorner::Right => {
            max_x = max_x.max(min_x + min_width);
        }
        ResizeCorner::Bottom => {
            min_y = min_y.min(max_y - min_height);
        }
        ResizeCorner::Left => {
            min_x = min_x.min(max_x - min_width);
        }
        ResizeCorner::BottomLeft => {
            min_x = min_x.min(max_x - min_width);
            min_y = min_y.min(max_y - min_height);
        }
        ResizeCorner::BottomRight => {
            max_x = max_x.max(min_x + min_width);
            min_y = min_y.min(max_y - min_height);
        }
    }

    min_x = min_x.max(bounds_min_x);
    max_x = max_x.min(bounds_max_x);
    min_y = min_y.max(bounds_min_y);
    max_y = max_y.min(bounds_max_y);

    let width = max_x - min_x;
    let height = max_y - min_y;
    if width < min_width || height < min_height {
        return None;
    }

    Some(F32Rect {
        x: min_x,
        y: min_y,
        width,
        height,
    })
}

pub fn quantize_image_rect(image_width: u32, image_height: u32, rect: F32Rect) -> Option<I32Rect> {
    if image_width == 0 || image_height == 0 {
        return None;
    }
    let (min_x, min_y, max_x, max_y) = standardize_rect(rect)?;

    let mut x = min_x.floor() as i32;
    let mut y = min_y.floor() as i32;
    let mut width = (max_x - min_x).ceil() as i32;
    let mut height = (max_y - min_y).ceil() as i32;
    if width <= 0 || height <= 0 {
        return None;
    }

    let max_w = image_width as i32;
    let max_h = image_height as i32;
    x = x.clamp(0, max_w - 1);
    y = y.clamp(0, max_h - 1);
    width = width.clamp(1, max_w - x);
    height = height.clamp(1, max_h - y);

    Some(I32Rect {
        x,
        y,
        width,
        height,
    })
}

pub fn quantize_image_point(
    image_width: u32,
    image_height: u32,
    x: f32,
    y: f32,
) -> Option<(i32, i32)> {
    if image_width == 0 || image_height == 0 || !x.is_finite() || !y.is_finite() {
        return None;
    }

    let max_x = image_width as i32 - 1;
    let max_y = image_height as i32 - 1;
    let px = (x.round() as i32).clamp(0, max_x);
    let py = (y.round() as i32).clamp(0, max_y);
    Some((px, py))
}

pub fn quantize_rgba(r: f32, g: f32, b: f32, a: f32) -> Option<Rgba8> {
    if !r.is_finite() || !g.is_finite() || !b.is_finite() || !a.is_finite() {
        return None;
    }

    let to_u8 = |v: f32| -> u8 { (v.clamp(0.0, 1.0) * 255.0).round() as u8 };
    Some(Rgba8 {
        r: to_u8(r),
        g: to_u8(g),
        b: to_u8(b),
        a: to_u8(a),
    })
}

pub fn timeline_full_duration_end(video_duration_ms: u32) -> u32 {
    if video_duration_ms == 0 {
        1
    } else {
        video_duration_ms.max(1)
    }
}

pub fn timeline_clamp_clip_end(video_duration_ms: u32, start_ms: u32, end_ms: u32) -> u32 {
    let clamped_end = if video_duration_ms > 0 {
        end_ms.min(video_duration_ms)
    } else {
        end_ms
    };
    clamped_end.max(start_ms.saturating_add(1))
}

pub fn timeline_normalize_text_clip_range(
    video_duration_ms: u32,
    start_ms: u32,
    end_ms: u32,
) -> (u32, u32) {
    let duration = timeline_full_duration_end(video_duration_ms);
    let mut clamped_start = start_ms.min(duration.saturating_sub(1));
    let mut clamped_end = end_ms.min(duration);
    if clamped_end <= clamped_start {
        clamped_end = clamped_start.saturating_add(1).min(duration);
    }
    if clamped_end <= clamped_start {
        clamped_start = clamped_end.saturating_sub(1);
    }
    (clamped_start, clamped_end)
}

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
}
