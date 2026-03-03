use crate::{vs_video_export_context, vs_video_export_plan};
use vivyshot_domain::compute_video_export_plan as domain_compute_video_export_plan;

use super::domain::{to_domain_video_export_context, to_ffi_video_export_plan};

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
