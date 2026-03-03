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
pub struct TimelineTextClipExportInput {
    pub track_index: u32,
    pub track_order: u32,
    pub clip_id: u32,
    pub start_ms: u32,
    pub end_ms: u32,
    pub track_visible: bool,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct TimelineTextClipExportRef {
    pub track_index: u32,
    pub clip_id: u32,
    pub start_ms: u32,
    pub end_ms: u32,
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

pub const STITCH_SIDE_TOP: u8 = 0;
pub const STITCH_SIDE_BOTTOM: u8 = 1;

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct StitchDelta {
    pub rows: u32,
    pub side: u8,
    pub score: f32,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct BgraImageOwned {
    pub width: u32,
    pub height: u32,
    pub stride: u32,
    pub pixels: Vec<u8>,
}

#[derive(Clone, Copy, Debug)]
pub struct BgraImageView<'a> {
    pub width: u32,
    pub height: u32,
    pub stride: u32,
    pub pixels: &'a [u8],
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

pub fn timeline_webcam_visible_for_export(tracks: &[TimelineTrackSummary]) -> bool {
    tracks
        .iter()
        .any(|track| track.kind == 1 && track.visible && track.clip_count > 0)
}

pub fn timeline_collect_text_export_clips(
    clips: &[TimelineTextClipExportInput],
) -> Vec<TimelineTextClipExportRef> {
    let mut visible = clips
        .iter()
        .copied()
        .filter(|clip| clip.track_visible && clip.end_ms > clip.start_ms)
        .collect::<Vec<_>>();
    visible.sort_by_key(|clip| (clip.track_order, clip.start_ms, clip.clip_id));

    visible
        .into_iter()
        .map(|clip| TimelineTextClipExportRef {
            track_index: clip.track_index,
            clip_id: clip.clip_id,
            start_ms: clip.start_ms,
            end_ms: clip.end_ms,
        })
        .collect()
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

impl BgraImageOwned {
    pub fn view(&self) -> BgraImageView<'_> {
        BgraImageView {
            width: self.width,
            height: self.height,
            stride: self.stride,
            pixels: &self.pixels,
        }
    }

    fn row_bytes(&self) -> Option<usize> {
        (self.width as usize).checked_mul(4)
    }
}

pub fn bgra_view_to_owned(view: BgraImageView<'_>) -> Option<BgraImageOwned> {
    let width = view.width as usize;
    let height = view.height as usize;
    let stride = view.stride as usize;
    if width == 0 || height == 0 {
        return None;
    }

    let row_bytes = width.checked_mul(4)?;
    if stride < row_bytes {
        return None;
    }
    let required_len = stride.checked_mul(height)?;
    if view.pixels.len() < required_len {
        return None;
    }

    Some(BgraImageOwned {
        width: view.width,
        height: view.height,
        stride: view.stride,
        pixels: view.pixels[..required_len].to_vec(),
    })
}

fn stitch_pixel_diff(a: &[u8], ai: usize, b: &[u8], bi: usize) -> u64 {
    let db = (a[ai] as i32 - b[bi] as i32).unsigned_abs() as u64;
    let dg = (a[ai + 1] as i32 - b[bi + 1] as i32).unsigned_abs() as u64;
    let dr = (a[ai + 2] as i32 - b[bi + 2] as i32).unsigned_abs() as u64;
    dr + dg + db
}

pub fn stitch_extract_strip(frame: &BgraImageOwned, rows: u32, side: u8) -> Option<BgraImageOwned> {
    if rows == 0 || rows >= frame.height {
        return None;
    }
    let row_bytes = frame.row_bytes()?;
    if frame.stride < row_bytes as u32 {
        return None;
    }

    let rows_usize = rows as usize;
    let height_usize = frame.height as usize;
    let stride = frame.stride as usize;
    let start_row = if side == STITCH_SIDE_BOTTOM {
        0usize
    } else if side == STITCH_SIDE_TOP {
        height_usize.saturating_sub(rows_usize)
    } else {
        return None;
    };

    let mut pixels = vec![0u8; rows_usize.checked_mul(row_bytes)?];
    for row in 0..rows_usize {
        let src_row = start_row + row;
        let src_start = src_row.checked_mul(stride)?;
        let dst_start = row.checked_mul(row_bytes)?;
        pixels[dst_start..dst_start + row_bytes]
            .copy_from_slice(&frame.pixels[src_start..src_start + row_bytes]);
    }

    Some(BgraImageOwned {
        width: frame.width,
        height: rows,
        stride: row_bytes as u32,
        pixels,
    })
}

pub fn stitch_resize_width_nearest(
    frame: &BgraImageOwned,
    target_width: u32,
) -> Option<BgraImageOwned> {
    if frame.width == target_width {
        return Some(frame.clone());
    }
    if frame.width == 0 || frame.height == 0 || target_width == 0 {
        return None;
    }

    let src_width = frame.width as usize;
    let src_height = frame.height as usize;
    let src_stride = frame.stride as usize;
    let src_row_bytes = frame.row_bytes()?;
    if src_stride < src_row_bytes {
        return None;
    }

    let dst_width = target_width as usize;
    let scale = dst_width as f64 / src_width as f64;
    let dst_height = ((src_height as f64 * scale).round() as usize).max(1);
    let dst_row_bytes = dst_width.checked_mul(4)?;
    let dst_len = dst_row_bytes.checked_mul(dst_height)?;
    let mut dst_pixels = vec![0u8; dst_len];

    for y in 0..dst_height {
        let src_y = ((y as f64 / dst_height as f64) * src_height as f64)
            .floor()
            .clamp(0.0, (src_height.saturating_sub(1)) as f64) as usize;
        let src_row_start = src_y.checked_mul(src_stride)?;
        let dst_row_start = y.checked_mul(dst_row_bytes)?;

        for x in 0..dst_width {
            let src_x = ((x as f64 / dst_width as f64) * src_width as f64)
                .floor()
                .clamp(0.0, (src_width.saturating_sub(1)) as f64) as usize;
            let src_idx = src_row_start + src_x * 4;
            let dst_idx = dst_row_start + x * 4;
            dst_pixels[dst_idx..dst_idx + 4].copy_from_slice(&frame.pixels[src_idx..src_idx + 4]);
        }
    }

    Some(BgraImageOwned {
        width: target_width,
        height: dst_height as u32,
        stride: dst_row_bytes as u32,
        pixels: dst_pixels,
    })
}

pub fn stitch_merge_frames(
    base: &BgraImageOwned,
    segment: &BgraImageOwned,
    side: u8,
) -> Option<BgraImageOwned> {
    if side != STITCH_SIDE_TOP && side != STITCH_SIDE_BOTTOM {
        return None;
    }
    if base.width != segment.width {
        return None;
    }

    let width = base.width as usize;
    let base_height = base.height as usize;
    let segment_height = segment.height as usize;
    let base_stride = base.stride as usize;
    let segment_stride = segment.stride as usize;
    let row_bytes = width.checked_mul(4)?;
    if base_stride < row_bytes || segment_stride < row_bytes {
        return None;
    }

    let out_height = base_height.checked_add(segment_height)?;
    let out_stride = row_bytes;
    let out_len = out_stride.checked_mul(out_height)?;
    let mut out_pixels = vec![0u8; out_len];

    let mut copy_rows = |src: &[u8], src_stride: usize, src_height: usize, dst_start_row: usize| {
        for row in 0..src_height {
            let src_start = row * src_stride;
            let dst_start = (dst_start_row + row) * out_stride;
            out_pixels[dst_start..dst_start + row_bytes]
                .copy_from_slice(&src[src_start..src_start + row_bytes]);
        }
    };

    if side == STITCH_SIDE_BOTTOM {
        copy_rows(&base.pixels, base_stride, base_height, 0);
        copy_rows(&segment.pixels, segment_stride, segment_height, base_height);
    } else {
        copy_rows(&segment.pixels, segment_stride, segment_height, 0);
        copy_rows(&base.pixels, base_stride, base_height, segment_height);
    }

    Some(BgraImageOwned {
        width: base.width,
        height: out_height as u32,
        stride: out_stride as u32,
        pixels: out_pixels,
    })
}

pub fn stitch_crop_frame(
    frame: &BgraImageOwned,
    x: u32,
    y: u32,
    width: u32,
    height: u32,
) -> Option<BgraImageOwned> {
    if width == 0 || height == 0 {
        return None;
    }

    let x_end = x.checked_add(width)?;
    let y_end = y.checked_add(height)?;
    if x_end > frame.width || y_end > frame.height {
        return None;
    }

    let src_stride = frame.stride as usize;
    let src_row_bytes = frame.row_bytes()?;
    if src_stride < src_row_bytes {
        return None;
    }

    let x_usize = x as usize;
    let y_usize = y as usize;
    let width_usize = width as usize;
    let height_usize = height as usize;
    let out_row_bytes = width_usize.checked_mul(4)?;
    let out_len = out_row_bytes.checked_mul(height_usize)?;
    let mut out_pixels = vec![0u8; out_len];

    for row in 0..height_usize {
        let src_row = y_usize + row;
        let src_start = src_row
            .checked_mul(src_stride)?
            .checked_add(x_usize.checked_mul(4)?)?;
        let dst_start = row.checked_mul(out_row_bytes)?;
        out_pixels[dst_start..dst_start + out_row_bytes]
            .copy_from_slice(&frame.pixels[src_start..src_start + out_row_bytes]);
    }

    Some(BgraImageOwned {
        width,
        height,
        stride: out_row_bytes as u32,
        pixels: out_pixels,
    })
}

pub fn stitch_estimate_delta(
    previous: BgraImageView<'_>,
    current: BgraImageView<'_>,
    preferred_side: Option<u8>,
    expected_rows: Option<u32>,
    relaxed: bool,
) -> Option<StitchDelta> {
    let prev_width = previous.width as usize;
    let prev_height = previous.height as usize;
    let prev_stride = previous.stride as usize;
    let curr_width = current.width as usize;
    let curr_height = current.height as usize;
    let curr_stride = current.stride as usize;
    let prev = previous.pixels;
    let curr = current.pixels;

    let prev_row_bytes = prev_width.checked_mul(4)?;
    let curr_row_bytes = curr_width.checked_mul(4)?;
    if prev_row_bytes > prev_stride || curr_row_bytes > curr_stride {
        return None;
    }
    if prev_stride.checked_mul(prev_height)? > prev.len()
        || curr_stride.checked_mul(curr_height)? > curr.len()
    {
        return None;
    }
    if prev_width != curr_width || prev_height != curr_height {
        return None;
    }

    let width = prev_width;
    let height = prev_height;
    if width < 32 || height < 24 {
        return None;
    }

    if matches!(preferred_side, Some(side) if side != STITCH_SIDE_TOP && side != STITCH_SIDE_BOTTOM)
    {
        return None;
    }

    let min_overlap_rows = 24usize.max((height as f64 * 0.14).round() as usize);
    let max_shift = 4usize.max((height - 4).min(height.saturating_sub(min_overlap_rows)));
    if max_shift < 2 {
        return None;
    }

    let x_inset = 8usize.max(width / 16);
    let y_inset = 10usize.max(height / 8);
    let sample_min_x = x_inset;
    let sample_max_x = (sample_min_x + 8).max(width.saturating_sub(x_inset));
    if sample_max_x <= sample_min_x {
        return None;
    }
    let sample_span_x = (sample_max_x - sample_min_x).max(8);
    let step_x = (sample_span_x / 74).max(2);

    let mut best_rows = 0usize;
    let mut best_side = STITCH_SIDE_BOTTOM;
    let mut best_score = f64::MAX;
    let mut second_best_score = f64::MAX;
    let mut consider = |rows: usize, side: u8, score: f64| {
        if score < best_score {
            second_best_score = best_score;
            best_score = score;
            best_rows = rows;
            best_side = side;
        } else if score < second_best_score {
            second_best_score = score;
        }
    };

    let mut search_start = 2usize;
    let mut search_end = max_shift;
    if let Some(expected) = expected_rows {
        let expected = expected as usize;
        let band_scale = if relaxed { 1.05 } else { 0.65 };
        let band = 10usize.max((expected.max(6) as f64 * band_scale).round() as usize);
        search_start = 2usize.max(expected.saturating_sub(band));
        search_end = max_shift.min(expected.saturating_add(band));
        if search_start > search_end {
            search_start = 2;
            search_end = max_shift;
        }
    }

    for shift in search_start..=search_end {
        let overlap = height.saturating_sub(shift);
        if overlap < 10 {
            continue;
        }

        let sample_min_y = y_inset;
        let sample_max_y = (sample_min_y + 8).max(overlap.saturating_sub(y_inset));
        if sample_max_y <= sample_min_y {
            continue;
        }

        let sample_span_y = sample_max_y - sample_min_y;
        if sample_span_y < 8 {
            continue;
        }
        let step_y = (sample_span_y / 64).max(2);

        let mut diff_bottom: u64 = 0;
        let mut diff_top: u64 = 0;
        let mut samples: u64 = 0;

        let mut y = sample_min_y;
        while y < sample_max_y {
            let prev_bottom_row = y + shift;
            let curr_bottom_row = y;
            let prev_top_row = y;
            let curr_top_row = y + shift;

            let prev_bottom_base = prev_bottom_row * prev_stride;
            let curr_bottom_base = curr_bottom_row * curr_stride;
            let prev_top_base = prev_top_row * prev_stride;
            let curr_top_base = curr_top_row * curr_stride;

            let mut x = sample_min_x;
            while x < sample_max_x {
                let prev_bottom_index = prev_bottom_base + x * 4;
                let curr_bottom_index = curr_bottom_base + x * 4;
                diff_bottom += stitch_pixel_diff(prev, prev_bottom_index, curr, curr_bottom_index);

                let prev_top_index = prev_top_base + x * 4;
                let curr_top_index = curr_top_base + x * 4;
                diff_top += stitch_pixel_diff(prev, prev_top_index, curr, curr_top_index);

                samples += 1;
                x += step_x;
            }
            y += step_y;
        }

        if samples == 0 {
            continue;
        }

        if preferred_side.is_none() || preferred_side == Some(STITCH_SIDE_BOTTOM) {
            let score = diff_bottom as f64 / samples as f64;
            consider(shift, STITCH_SIDE_BOTTOM, score);
        }
        if preferred_side.is_none() || preferred_side == Some(STITCH_SIDE_TOP) {
            let score = diff_top as f64 / samples as f64;
            consider(shift, STITCH_SIDE_TOP, score);
        }
    }

    if best_rows < 4 {
        return None;
    }

    let score_threshold = if relaxed {
        if preferred_side.is_none() {
            82.0
        } else {
            94.0
        }
    } else if preferred_side.is_none() {
        56.0
    } else {
        62.0
    };

    if best_score >= score_threshold {
        return None;
    }

    if !relaxed && second_best_score.is_finite() {
        let separation = (second_best_score - best_score) / second_best_score.max(1.0);
        let minimum = if preferred_side.is_none() {
            0.08
        } else {
            0.055
        };
        if separation < minimum {
            return None;
        }
    }

    Some(StitchDelta {
        rows: best_rows as u32,
        side: best_side,
        score: best_score as f32,
    })
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

/// Video export and interaction policy APIs.
pub mod video {
    pub use super::{
        click_event_is_duplicate, compute_video_export_plan, derive_video_export_context,
        normalize_click_point, VideoExportContext, VideoExportPlan, VIDEO_PLAN_MODE_COMPOSITE_MP4,
        VIDEO_PLAN_MODE_PASSTHROUGH,
    };
}

/// Timeline normalization and export-query APIs.
pub mod timeline {
    pub use super::{
        timeline_clamp_clip_end, timeline_collect_text_export_clips, timeline_full_duration_end,
        timeline_normalize_text_clip_range, timeline_webcam_visible_for_export,
        TimelineTextClipExportInput, TimelineTextClipExportRef, TimelineTrackSummary,
    };
}

/// Geometry and selection transformation APIs.
pub mod geometry {
    pub use super::{
        image_delta_to_view_delta, image_rect_to_view_rect, quantize_image_point,
        quantize_image_rect, quantize_rgba, selection_move_rect, selection_resize_rect,
        view_delta_to_image_delta, view_rect_to_image_rect, viewport_clamp_pan_offset, F32Point,
        F32Rect, I32Rect, ResizeCorner, Rgba8,
    };
}

/// Stitching and GIF/trim policy APIs.
pub mod stitch {
    pub use super::{
        bgra_view_to_owned, build_gif_export_plan, gif_frame_time_ms, normalize_trim_range,
        stitch_autoscroll_reset, stitch_autoscroll_update, stitch_crop_frame,
        stitch_estimate_delta, stitch_extract_strip, stitch_merge_frames,
        stitch_resize_width_nearest, BgraImageOwned, BgraImageView, GifExportPlan,
        StitchAutoscrollState, StitchDelta, TrimHandle, STITCH_SIDE_BOTTOM, STITCH_SIDE_TOP,
    };
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
}
