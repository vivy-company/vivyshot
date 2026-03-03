use crate::{vs_video_export_context, TimelineTrack};
use vivyshot_domain::derive_video_export_context as domain_derive_video_export_context;

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
