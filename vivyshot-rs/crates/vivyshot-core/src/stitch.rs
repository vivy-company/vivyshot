pub use crate::types::{
    BgraImageOwned, BgraImageView, GifExportPlan, StitchAutoscrollState, StitchDelta, TrimHandle,
    STITCH_SIDE_BOTTOM, STITCH_SIDE_TOP,
};

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
