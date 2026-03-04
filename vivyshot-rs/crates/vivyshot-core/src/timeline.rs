pub use crate::types::{
    TimelineTextClipExportInput, TimelineTextClipExportRef, TimelineTrackSummary,
};

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

pub fn timeline_validate_split(
    clip_start_ms: u32,
    clip_end_ms: u32,
    split_at_ms: u32,
    min_clip_ms: u32,
) -> Option<(u32, u32, u32, u32)> {
    if split_at_ms <= clip_start_ms.saturating_add(min_clip_ms) {
        return None;
    }
    if split_at_ms >= clip_end_ms.saturating_sub(min_clip_ms) {
        return None;
    }
    Some((clip_start_ms, split_at_ms, split_at_ms, clip_end_ms))
}
