use super::*;
use vivyshot_domain::{
    Timeline as DomainTimeline, TimelineClipTransform as DomainTimelineClipTransform,
    TimelineError as DomainTimelineError,
    TimelineShapeStyle as DomainTimelineShapeStyle,
    TimelineTextClipExportRef as DomainTimelineTextClipExportRef,
    TimelineTextStyle as DomainTimelineTextStyle,
};

unsafe fn timeline_from_handle_mut<'a>(
    handle: *mut c_void,
) -> Result<&'a mut DomainTimeline, i32> {
    validate_handle(&TIMELINE_HANDLES, handle)?;
    // SAFETY: pointer was validated by registry and originates from Box::into_raw.
    Ok(unsafe { &mut *handle.cast::<DomainTimeline>() })
}

unsafe fn timeline_from_handle<'a>(handle: *const c_void) -> Result<&'a DomainTimeline, i32> {
    validate_handle(&TIMELINE_HANDLES, handle)?;
    // SAFETY: pointer was validated by registry and originates from Box::into_raw.
    Ok(unsafe { &*handle.cast::<DomainTimeline>() })
}

fn map_timeline_error(error: DomainTimelineError) -> i32 {
    match error {
        DomainTimelineError::InvalidArgument | DomainTimelineError::NotFound => {
            VS_STATUS_INVALID_ARGUMENT
        }
        DomainTimelineError::NoChange => VS_STATUS_NO_CHANGE,
    }
}

fn to_domain_clip_transform(transform: vs_clip_transform) -> DomainTimelineClipTransform {
    DomainTimelineClipTransform {
        x: transform.x,
        y: transform.y,
        width: transform.width,
        height: transform.height,
        rotation: transform.rotation,
        opacity: transform.opacity,
    }
}

fn to_ffi_clip_transform(transform: DomainTimelineClipTransform) -> vs_clip_transform {
    vs_clip_transform {
        x: transform.x,
        y: transform.y,
        width: transform.width,
        height: transform.height,
        rotation: transform.rotation,
        opacity: transform.opacity,
    }
}

fn write_text_export_clip_refs(
    refs: &[DomainTimelineTextClipExportRef],
    out_ptr: *mut vs_timeline_text_export_clip_info,
    out_cap: u32,
) {
    for (index, clip) in refs
        .iter()
        .copied()
        .take((out_cap as usize).min(refs.len()))
        .enumerate()
    {
        // SAFETY: caller validates pointer and capacity.
        unsafe {
            *out_ptr.add(index) = vs_timeline_text_export_clip_info {
                track_index: clip.track_index,
                clip_id: clip.clip_id,
                start_ms: clip.start_ms,
                end_ms: clip.end_ms,
            };
        }
    }
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct vs_timeline_text_export_clip_info {
    pub track_index: u32,
    pub clip_id: u32,
    pub start_ms: u32,
    pub end_ms: u32,
}

// ---------------------------------------------------------------------------
// Timeline FFI: lifecycle
// ---------------------------------------------------------------------------

#[no_mangle]
pub extern "C" fn vs_timeline_create(duration_ms: u32, width: u32, height: u32) -> *mut c_void {
    let Some(timeline) = DomainTimeline::new(duration_ms, width, height) else {
        return std::ptr::null_mut();
    };

    let handle = Box::into_raw(Box::new(timeline)).cast();
    register_handle(&TIMELINE_HANDLES, handle);
    handle
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_destroy(handle: *mut c_void) {
    if !unregister_handle(&TIMELINE_HANDLES, handle) {
        return;
    }

    unsafe {
        drop(Box::from_raw(handle.cast::<DomainTimeline>()));
    }
}

// ---------------------------------------------------------------------------
// Timeline FFI: tracks
// ---------------------------------------------------------------------------

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_add_track(handle: *mut c_void, kind: u8) -> i32 {
    let timeline = match unsafe { timeline_from_handle_mut(handle) } {
        Ok(value) => value,
        Err(code) => return code,
    };

    match timeline.add_track(kind) {
        Ok(()) => VS_STATUS_OK,
        Err(error) => map_timeline_error(error),
    }
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_remove_track(handle: *mut c_void, track_index: u32) -> i32 {
    let timeline = match unsafe { timeline_from_handle_mut(handle) } {
        Ok(value) => value,
        Err(code) => return code,
    };

    match timeline.remove_track(track_index as usize) {
        Ok(()) => VS_STATUS_OK,
        Err(error) => map_timeline_error(error),
    }
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_reorder_track(
    handle: *mut c_void,
    from_index: u32,
    to_index: u32,
) -> i32 {
    let timeline = match unsafe { timeline_from_handle_mut(handle) } {
        Ok(value) => value,
        Err(code) => return code,
    };

    match timeline.reorder_track(from_index as usize, to_index as usize) {
        Ok(()) => VS_STATUS_OK,
        Err(error) => map_timeline_error(error),
    }
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_set_track_visible(
    handle: *mut c_void,
    track_index: u32,
    visible: bool,
) -> i32 {
    let timeline = match unsafe { timeline_from_handle_mut(handle) } {
        Ok(value) => value,
        Err(code) => return code,
    };

    match timeline.set_track_visible(track_index as usize, visible) {
        Ok(()) => VS_STATUS_OK,
        Err(error) => map_timeline_error(error),
    }
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_get_tracks(
    handle: *mut c_void,
    out_ptr: *mut vs_timeline_track_info,
    out_cap: u32,
    out_written: *mut u32,
) -> i32 {
    if out_written.is_null() {
        return VS_STATUS_NULL_POINTER;
    }
    if out_cap > 0 && out_ptr.is_null() {
        return VS_STATUS_INVALID_ARGUMENT;
    }

    let timeline = match unsafe { timeline_from_handle(handle) } {
        Ok(value) => value,
        Err(code) => return code,
    };

    let tracks = timeline.tracks();
    let total = tracks.len().min(u32::MAX as usize) as u32;
    let write_count = (out_cap as usize).min(total as usize);

    for (index, track) in tracks.iter().take(write_count).enumerate() {
        unsafe {
            *out_ptr.add(index) = vs_timeline_track_info {
                kind: track.kind,
                visible: track.visible,
                clip_count: track.clips.len().min(u32::MAX as usize) as u32,
            };
        }
    }

    unsafe {
        *out_written = total;
    }
    VS_STATUS_OK
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_derive_export_context(
    handle: *const c_void,
    source_has_audio: bool,
    source_has_webcam_asset: bool,
    out_context: *mut vs_video_export_context,
) -> i32 {
    if out_context.is_null() {
        return VS_STATUS_NULL_POINTER;
    }

    let timeline = match unsafe { timeline_from_handle(handle) } {
        Ok(value) => value,
        Err(code) => return code,
    };
    let context = timeline.export_context(source_has_audio, source_has_webcam_asset);

    unsafe {
        *out_context = ffi::domain::to_ffi_video_export_context(context);
    }
    VS_STATUS_OK
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_is_webcam_track_visible_for_export(
    handle: *const c_void,
    out_visible: *mut bool,
) -> i32 {
    if out_visible.is_null() {
        return VS_STATUS_NULL_POINTER;
    }

    let timeline = match unsafe { timeline_from_handle(handle) } {
        Ok(value) => value,
        Err(code) => return code,
    };

    unsafe {
        *out_visible = timeline.webcam_visible_for_export();
    }
    VS_STATUS_OK
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_get_text_export_clips(
    handle: *const c_void,
    out_ptr: *mut vs_timeline_text_export_clip_info,
    out_cap: u32,
    out_written: *mut u32,
) -> i32 {
    if out_written.is_null() {
        return VS_STATUS_NULL_POINTER;
    }
    if out_cap > 0 && out_ptr.is_null() {
        return VS_STATUS_INVALID_ARGUMENT;
    }

    let timeline = match unsafe { timeline_from_handle(handle) } {
        Ok(value) => value,
        Err(code) => return code,
    };
    let refs = timeline.text_export_clips();

    if out_cap > 0 {
        write_text_export_clip_refs(&refs, out_ptr, out_cap);
    }

    unsafe {
        *out_written = refs.len().min(u32::MAX as usize) as u32;
    }
    VS_STATUS_OK
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_bootstrap_capture_tracks(
    handle: *mut c_void,
    source_has_audio: bool,
    source_has_webcam_asset: bool,
) -> i32 {
    let timeline = match unsafe { timeline_from_handle_mut(handle) } {
        Ok(value) => value,
        Err(code) => return code,
    };
    timeline.bootstrap_capture_tracks(source_has_audio, source_has_webcam_asset);
    VS_STATUS_OK
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_add_text_clip_auto_track(
    handle: *mut c_void,
    start_ms: u32,
    end_ms: u32,
    text_ptr: *const u8,
    text_len: u32,
    out_clip_id: *mut u32,
) -> i32 {
    if text_ptr.is_null() || text_len == 0 {
        return VS_STATUS_NULL_POINTER;
    }

    let text_bytes = unsafe { slice::from_raw_parts(text_ptr, text_len as usize) };
    let raw_text = match std::str::from_utf8(text_bytes) {
        Ok(value) => value,
        Err(_) => return VS_STATUS_INVALID_ARGUMENT,
    };

    let timeline = match unsafe { timeline_from_handle_mut(handle) } {
        Ok(value) => value,
        Err(code) => return code,
    };

    match timeline.add_text_clip_auto_track(start_ms, end_ms, raw_text) {
        Ok(clip_id) => {
            if !out_clip_id.is_null() {
                unsafe {
                    *out_clip_id = clip_id;
                }
            }
            VS_STATUS_OK
        }
        Err(error) => map_timeline_error(error),
    }
}

// ---------------------------------------------------------------------------
// Timeline FFI: clips
// ---------------------------------------------------------------------------

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_add_clip(
    handle: *mut c_void,
    track_index: u32,
    start_ms: u32,
    end_ms: u32,
    kind: u8,
    out_clip_id: *mut u32,
) -> i32 {
    let timeline = match unsafe { timeline_from_handle_mut(handle) } {
        Ok(value) => value,
        Err(code) => return code,
    };

    match timeline.add_clip(track_index as usize, start_ms, end_ms, kind) {
        Ok(clip_id) => {
            if !out_clip_id.is_null() {
                unsafe {
                    *out_clip_id = clip_id;
                }
            }
            VS_STATUS_OK
        }
        Err(error) => map_timeline_error(error),
    }
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_remove_clip(
    handle: *mut c_void,
    track_index: u32,
    clip_id: u32,
) -> i32 {
    let timeline = match unsafe { timeline_from_handle_mut(handle) } {
        Ok(value) => value,
        Err(code) => return code,
    };

    match timeline.remove_clip(track_index as usize, clip_id) {
        Ok(()) => VS_STATUS_OK,
        Err(error) => map_timeline_error(error),
    }
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_move_clip(
    handle: *mut c_void,
    track_index: u32,
    clip_id: u32,
    new_start_ms: u32,
) -> i32 {
    let timeline = match unsafe { timeline_from_handle_mut(handle) } {
        Ok(value) => value,
        Err(code) => return code,
    };

    match timeline.move_clip(track_index as usize, clip_id, new_start_ms) {
        Ok(()) => VS_STATUS_OK,
        Err(error) => map_timeline_error(error),
    }
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_resize_clip(
    handle: *mut c_void,
    track_index: u32,
    clip_id: u32,
    new_start_ms: u32,
    new_end_ms: u32,
) -> i32 {
    let timeline = match unsafe { timeline_from_handle_mut(handle) } {
        Ok(value) => value,
        Err(code) => return code,
    };

    match timeline.resize_clip(track_index as usize, clip_id, new_start_ms, new_end_ms) {
        Ok(()) => VS_STATUS_OK,
        Err(error) => map_timeline_error(error),
    }
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_split_clip(
    handle: *mut c_void,
    track_index: u32,
    clip_id: u32,
    split_at_ms: u32,
    out_new_clip_id: *mut u32,
) -> i32 {
    if out_new_clip_id.is_null() {
        return VS_STATUS_NULL_POINTER;
    }

    let timeline = match unsafe { timeline_from_handle_mut(handle) } {
        Ok(value) => value,
        Err(code) => return code,
    };

    match timeline.split_clip(track_index as usize, clip_id, split_at_ms) {
        Ok(new_clip_id) => {
            unsafe {
                *out_new_clip_id = new_clip_id;
            }
            VS_STATUS_OK
        }
        Err(error) => map_timeline_error(error),
    }
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_update_clip_transform(
    handle: *mut c_void,
    track_index: u32,
    clip_id: u32,
    transform: vs_clip_transform,
) -> i32 {
    let timeline = match unsafe { timeline_from_handle_mut(handle) } {
        Ok(value) => value,
        Err(code) => return code,
    };

    match timeline.update_clip_transform(
        track_index as usize,
        clip_id,
        to_domain_clip_transform(transform),
    ) {
        Ok(()) => VS_STATUS_OK,
        Err(error) => map_timeline_error(error),
    }
}

// ---------------------------------------------------------------------------
// Timeline FFI: clip data
// ---------------------------------------------------------------------------

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_set_clip_text(
    handle: *mut c_void,
    track_index: u32,
    clip_id: u32,
    text_ptr: *const u8,
    text_len: u32,
) -> i32 {
    if text_ptr.is_null() || text_len == 0 {
        return VS_STATUS_INVALID_ARGUMENT;
    }

    let text_bytes = unsafe { slice::from_raw_parts(text_ptr, text_len as usize) };
    let text = match std::str::from_utf8(text_bytes) {
        Ok(value) => value.to_string(),
        Err(_) => return VS_STATUS_INVALID_ARGUMENT,
    };

    let timeline = match unsafe { timeline_from_handle_mut(handle) } {
        Ok(value) => value,
        Err(code) => return code,
    };

    match timeline.set_clip_text(track_index as usize, clip_id, text) {
        Ok(()) => VS_STATUS_OK,
        Err(error) => map_timeline_error(error),
    }
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_set_clip_text_style(
    handle: *mut c_void,
    track_index: u32,
    clip_id: u32,
    font_size: f32,
    color: u32,
    bg_color: u32,
) -> i32 {
    let timeline = match unsafe { timeline_from_handle_mut(handle) } {
        Ok(value) => value,
        Err(code) => return code,
    };

    match timeline.set_clip_text_style(
        track_index as usize,
        clip_id,
        DomainTimelineTextStyle {
            font_size,
            color,
            bg_color,
        },
    ) {
        Ok(()) => VS_STATUS_OK,
        Err(error) => map_timeline_error(error),
    }
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_set_clip_shape_style(
    handle: *mut c_void,
    track_index: u32,
    clip_id: u32,
    fill: u32,
    border: u32,
    border_width: f32,
    corner_radius: f32,
) -> i32 {
    let timeline = match unsafe { timeline_from_handle_mut(handle) } {
        Ok(value) => value,
        Err(code) => return code,
    };

    match timeline.set_clip_shape_style(
        track_index as usize,
        clip_id,
        DomainTimelineShapeStyle {
            fill,
            border,
            border_width,
            corner_radius,
        },
    ) {
        Ok(()) => VS_STATUS_OK,
        Err(error) => map_timeline_error(error),
    }
}

// ---------------------------------------------------------------------------
// Timeline FFI: queries
// ---------------------------------------------------------------------------

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_get_clips(
    handle: *mut c_void,
    track_index: u32,
    out_ptr: *mut vs_timeline_clip_info,
    out_cap: u32,
    out_written: *mut u32,
) -> i32 {
    if out_written.is_null() {
        return VS_STATUS_NULL_POINTER;
    }
    if out_cap > 0 && out_ptr.is_null() {
        return VS_STATUS_INVALID_ARGUMENT;
    }

    let timeline = match unsafe { timeline_from_handle(handle) } {
        Ok(value) => value,
        Err(code) => return code,
    };
    let clips = match timeline.clips(track_index as usize) {
        Ok(value) => value,
        Err(error) => return map_timeline_error(error),
    };

    let total = clips.len().min(u32::MAX as usize) as u32;
    let write_count = (out_cap as usize).min(total as usize);

    for (index, clip) in clips.iter().take(write_count).enumerate() {
        unsafe {
            *out_ptr.add(index) = vs_timeline_clip_info {
                id: clip.id,
                track_index,
                start_ms: clip.start_ms,
                end_ms: clip.end_ms,
                kind: clip.data.kind(),
                transform: to_ffi_clip_transform(clip.transform),
            };
        }
    }

    unsafe {
        *out_written = total;
    }
    VS_STATUS_OK
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_get_visible_clips_at(
    handle: *mut c_void,
    time_ms: u32,
    out_ptr: *mut vs_timeline_clip_info,
    out_cap: u32,
    out_written: *mut u32,
) -> i32 {
    if out_written.is_null() {
        return VS_STATUS_NULL_POINTER;
    }
    if out_cap > 0 && out_ptr.is_null() {
        return VS_STATUS_INVALID_ARGUMENT;
    }

    let timeline = match unsafe { timeline_from_handle(handle) } {
        Ok(value) => value,
        Err(code) => return code,
    };

    let mut written = 0u32;
    for (track_index, track) in timeline.tracks().iter().enumerate() {
        if !track.visible {
            continue;
        }

        for clip in &track.clips {
            if time_ms >= clip.start_ms && time_ms < clip.end_ms {
                if written < out_cap {
                    unsafe {
                        *out_ptr.add(written as usize) = vs_timeline_clip_info {
                            id: clip.id,
                            track_index: track_index as u32,
                            start_ms: clip.start_ms,
                            end_ms: clip.end_ms,
                            kind: track.kind,
                            transform: to_ffi_clip_transform(clip.transform),
                        };
                    }
                }
                written += 1;
            }
        }
    }

    unsafe {
        *out_written = written;
    }
    VS_STATUS_OK
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_get_clip_text(
    handle: *mut c_void,
    track_index: u32,
    clip_id: u32,
    out_ptr: *mut u8,
    out_cap: u32,
    out_written: *mut u32,
) -> i32 {
    if out_written.is_null() {
        return VS_STATUS_NULL_POINTER;
    }
    if out_cap > 0 && out_ptr.is_null() {
        return VS_STATUS_INVALID_ARGUMENT;
    }

    let timeline = match unsafe { timeline_from_handle(handle) } {
        Ok(value) => value,
        Err(code) => return code,
    };
    let text = match timeline.clip_text(track_index as usize, clip_id) {
        Ok(value) => value,
        Err(error) => return map_timeline_error(error),
    };

    let bytes = text.as_bytes();
    let copy_len = bytes.len().min(out_cap as usize);
    if copy_len > 0 {
        unsafe {
            std::ptr::copy_nonoverlapping(bytes.as_ptr(), out_ptr, copy_len);
        }
    }

    unsafe {
        *out_written = bytes.len() as u32;
    }
    VS_STATUS_OK
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_get_clip_shape_style(
    handle: *mut c_void,
    track_index: u32,
    clip_id: u32,
    out_fill: *mut u32,
    out_border: *mut u32,
    out_border_width: *mut f32,
    out_corner_radius: *mut f32,
) -> i32 {
    if out_fill.is_null()
        || out_border.is_null()
        || out_border_width.is_null()
        || out_corner_radius.is_null()
    {
        return VS_STATUS_NULL_POINTER;
    }

    let timeline = match unsafe { timeline_from_handle(handle) } {
        Ok(value) => value,
        Err(code) => return code,
    };
    let style = match timeline.clip_shape_style(track_index as usize, clip_id) {
        Ok(value) => value,
        Err(error) => return map_timeline_error(error),
    };

    unsafe {
        *out_fill = style.fill;
        *out_border = style.border;
        *out_border_width = style.border_width;
        *out_corner_radius = style.corner_radius;
    }
    VS_STATUS_OK
}

// ---------------------------------------------------------------------------
// Timeline FFI: undo/redo
// ---------------------------------------------------------------------------

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_undo(handle: *mut c_void) -> i32 {
    let timeline = match unsafe { timeline_from_handle_mut(handle) } {
        Ok(value) => value,
        Err(code) => return code,
    };

    match timeline.undo() {
        Ok(()) => VS_STATUS_OK,
        Err(error) => map_timeline_error(error),
    }
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_redo(handle: *mut c_void) -> i32 {
    let timeline = match unsafe { timeline_from_handle_mut(handle) } {
        Ok(value) => value,
        Err(code) => return code,
    };

    match timeline.redo() {
        Ok(()) => VS_STATUS_OK,
        Err(error) => map_timeline_error(error),
    }
}

// ---------------------------------------------------------------------------
// Timeline FFI: info and zoom scale
// ---------------------------------------------------------------------------

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_get_video_info(
    handle: *mut c_void,
    out_duration_ms: *mut u32,
    out_width: *mut u32,
    out_height: *mut u32,
) -> i32 {
    let timeline = match unsafe { timeline_from_handle(handle) } {
        Ok(value) => value,
        Err(code) => return code,
    };

    if !out_duration_ms.is_null() {
        unsafe {
            *out_duration_ms = timeline.video_duration_ms();
        }
    }
    if !out_width.is_null() {
        unsafe {
            *out_width = timeline.width();
        }
    }
    if !out_height.is_null() {
        unsafe {
            *out_height = timeline.height();
        }
    }

    VS_STATUS_OK
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_set_clip_zoom_scale(
    handle: *mut c_void,
    track_index: u32,
    clip_id: u32,
    scale: f32,
) -> i32 {
    let timeline = match unsafe { timeline_from_handle_mut(handle) } {
        Ok(value) => value,
        Err(code) => return code,
    };

    match timeline.set_clip_zoom_scale(track_index as usize, clip_id, scale) {
        Ok(()) => VS_STATUS_OK,
        Err(error) => map_timeline_error(error),
    }
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_get_clip_zoom_scale(
    handle: *mut c_void,
    track_index: u32,
    clip_id: u32,
    out_scale: *mut f32,
) -> i32 {
    if out_scale.is_null() {
        return VS_STATUS_NULL_POINTER;
    }

    let timeline = match unsafe { timeline_from_handle(handle) } {
        Ok(value) => value,
        Err(code) => return code,
    };

    match timeline.clip_zoom_scale(track_index as usize, clip_id) {
        Ok(scale) => {
            unsafe {
                *out_scale = scale;
            }
            VS_STATUS_OK
        }
        Err(error) => map_timeline_error(error),
    }
}
