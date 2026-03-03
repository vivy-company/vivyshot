use crate::{
    vs_timeline_text_export_clip_info, vs_video_export_context, ClipData,
    TimelineTextClipExportRef, TimelineTrack,
};
use vivyshot_domain::{
    derive_video_export_context as domain_derive_video_export_context,
    timeline_collect_text_export_clips as domain_timeline_collect_text_export_clips,
    timeline_webcam_visible_for_export as domain_timeline_webcam_visible_for_export,
    TimelineTextClipExportInput as DomainTimelineTextClipExportInput,
};

use super::domain::{to_domain_timeline_track_summary, to_ffi_video_export_context};

pub(crate) fn derive_export_context(
    source_has_audio: bool,
    source_has_webcam_asset: bool,
    tracks: &[TimelineTrack],
) -> vs_video_export_context {
    let track_summaries = tracks
        .iter()
        .map(|track| {
            to_domain_timeline_track_summary(
                track.kind,
                track.visible,
                track.clips.len().min(u32::MAX as usize) as u32,
            )
        })
        .collect::<Vec<_>>();

    to_ffi_video_export_context(domain_derive_video_export_context(
        source_has_audio,
        source_has_webcam_asset,
        &track_summaries,
    ))
}

pub(crate) fn webcam_visible_for_export(tracks: &[TimelineTrack]) -> bool {
    let track_summaries = tracks
        .iter()
        .map(|track| {
            to_domain_timeline_track_summary(
                track.kind,
                track.visible,
                track.clips.len().min(u32::MAX as usize) as u32,
            )
        })
        .collect::<Vec<_>>();
    domain_timeline_webcam_visible_for_export(&track_summaries)
}

pub(crate) fn text_export_clip_refs(tracks: &[TimelineTrack]) -> Vec<TimelineTextClipExportRef> {
    let inputs = tracks
        .iter()
        .enumerate()
        .flat_map(|(track_order, track)| {
            track.clips.iter().filter_map(move |clip| {
                if track.kind != 3 {
                    return None;
                }
                if !matches!(clip.data, ClipData::Text { .. }) {
                    return None;
                }
                Some(DomainTimelineTextClipExportInput {
                    track_index: track_order.min(u32::MAX as usize) as u32,
                    track_order: track_order.min(u32::MAX as usize) as u32,
                    clip_id: clip.id,
                    start_ms: clip.start_ms,
                    end_ms: clip.end_ms,
                    track_visible: track.visible,
                })
            })
        })
        .collect::<Vec<_>>();

    domain_timeline_collect_text_export_clips(&inputs)
        .into_iter()
        .map(|clip| TimelineTextClipExportRef {
            track_index: clip.track_index,
            clip_id: clip.clip_id,
            start_ms: clip.start_ms,
            end_ms: clip.end_ms,
        })
        .collect()
}

pub(crate) fn write_text_export_clip_refs(
    refs: &[TimelineTextClipExportRef],
    out_ptr: *mut vs_timeline_text_export_clip_info,
    out_cap: u32,
) {
    for (i, clip) in refs
        .iter()
        .copied()
        .take((out_cap as usize).min(refs.len()))
        .enumerate()
    {
        // SAFETY: caller validates pointer and capacity.
        unsafe {
            *out_ptr.add(i) = vs_timeline_text_export_clip_info {
                track_index: clip.track_index,
                clip_id: clip.clip_id,
                start_ms: clip.start_ms,
                end_ms: clip.end_ms,
            };
        }
    }
}
