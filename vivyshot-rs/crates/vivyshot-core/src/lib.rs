#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TrimHandle {
    Unknown,
    Start,
    End,
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

pub fn normalize_click_point(normalized_x: f32, normalized_y: f32) -> Option<(f32, f32)> {
    if !normalized_x.is_finite() || !normalized_y.is_finite() {
        return None;
    }
    Some((normalized_x.clamp(0.0, 1.0), normalized_y.clamp(0.0, 1.0)))
}

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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn trim_normalization_keeps_min_gap() {
        let (start, end) = normalize_trim_range(1_000, 950, 960, 100, TrimHandle::End);
        assert_eq!(start, 860);
        assert_eq!(end, 960);
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
}
