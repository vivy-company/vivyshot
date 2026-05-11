use super::*;
use vivyshot_domain::{
    VideoNormalizedRect as DomainVideoNormalizedRect, VideoProject as DomainVideoProject,
    VideoProjectExportOptions as DomainVideoProjectExportOptions,
    VideoRenderItem as DomainVideoRenderItem, VideoRenderPlanQuery as DomainVideoRenderPlanQuery,
    VideoSourceMetadata as DomainVideoSourceMetadata,
};

unsafe fn video_project_from_handle_mut<'a>(
    handle: *mut c_void,
) -> Result<&'a mut DomainVideoProject, i32> {
    validate_handle(&VIDEO_PROJECT_HANDLES, handle)?;
    // SAFETY: pointer was validated by registry and originates from Box::into_raw.
    Ok(unsafe { &mut *handle.cast::<DomainVideoProject>() })
}

unsafe fn video_project_from_handle<'a>(
    handle: *const c_void,
) -> Result<&'a DomainVideoProject, i32> {
    validate_handle(&VIDEO_PROJECT_HANDLES, handle)?;
    // SAFETY: pointer was validated by registry and originates from Box::into_raw.
    Ok(unsafe { &*handle.cast::<DomainVideoProject>() })
}

fn to_domain_source(info: vs_video_project_recording_info) -> DomainVideoSourceMetadata {
    DomainVideoSourceMetadata {
        duration_ms: info.duration_ms,
        width: info.width,
        height: info.height,
        frame_rate: info.frame_rate,
        has_audio: info.has_audio,
        has_webcam_asset: info.has_webcam_asset,
        has_microphone_audio: info.has_microphone_audio,
    }
}

fn to_domain_rect(rect: vs_video_project_rect) -> DomainVideoNormalizedRect {
    DomainVideoNormalizedRect {
        x: rect.x,
        y: rect.y,
        width: rect.width,
        height: rect.height,
    }
}

fn to_domain_query(query: vs_video_project_render_plan_query) -> DomainVideoRenderPlanQuery {
    DomainVideoRenderPlanQuery {
        time_ms: query.time_ms,
        render_width: query.render_width,
        render_height: query.render_height,
        target: query.target,
    }
}

fn to_domain_export_options(
    options: vs_video_project_export_options,
) -> DomainVideoProjectExportOptions {
    DomainVideoProjectExportOptions {
        target: options.target,
        codec: options.codec,
        frame_rate: options.frame_rate,
        quality: options.quality,
        bitrate: options.bitrate,
        includes_baked_transition: options.includes_baked_transition,
    }
}

fn to_ffi_render_item(item: &DomainVideoRenderItem) -> vs_video_project_render_item {
    vs_video_project_render_item {
        kind: item.kind,
        x: item.x,
        y: item.y,
        width: item.width,
        height: item.height,
        opacity: item.opacity,
        style_flags: item.style_flags,
        text_offset: item.text_offset,
        text_len: item.text_len,
        asset_id: item.asset_id,
    }
}

unsafe fn write_bytes(bytes: &[u8], out_ptr: *mut u8, out_cap: u32, out_written: *mut u32) -> i32 {
    if out_written.is_null() {
        return VS_STATUS_NULL_POINTER;
    }
    let required = bytes.len().min(u32::MAX as usize) as u32;
    unsafe {
        *out_written = required;
    }
    if required > out_cap {
        return VS_STATUS_BUFFER_TOO_SMALL;
    }
    if required == 0 {
        return VS_STATUS_OK;
    }
    if out_ptr.is_null() {
        return VS_STATUS_NULL_POINTER;
    }
    unsafe {
        std::ptr::copy_nonoverlapping(bytes.as_ptr(), out_ptr, required as usize);
    }
    VS_STATUS_OK
}

#[no_mangle]
pub extern "C" fn vs_video_project_create_from_recording(
    info: vs_video_project_recording_info,
) -> *mut c_void {
    let Some(project) = DomainVideoProject::new(to_domain_source(info)) else {
        return std::ptr::null_mut();
    };
    let handle = Box::into_raw(Box::new(project)).cast();
    register_handle(&VIDEO_PROJECT_HANDLES, handle);
    handle
}

#[no_mangle]
pub unsafe extern "C" fn vs_video_project_destroy(handle: *mut c_void) {
    if !unregister_handle(&VIDEO_PROJECT_HANDLES, handle) {
        return;
    }
    unsafe {
        drop(Box::from_raw(handle.cast::<DomainVideoProject>()));
    }
}

#[no_mangle]
pub unsafe extern "C" fn vs_video_project_add_key_event(
    handle: *mut c_void,
    timestamp_ms: u32,
    token_ptr: *const u8,
    token_len: u32,
) -> i32 {
    let project = match unsafe { video_project_from_handle_mut(handle) } {
        Ok(value) => value,
        Err(code) => return code,
    };
    if token_ptr.is_null() || token_len == 0 || token_len > 512 {
        return VS_STATUS_INVALID_ARGUMENT;
    }
    let bytes = unsafe { slice::from_raw_parts(token_ptr, token_len as usize) };
    let token = match std::str::from_utf8(bytes) {
        Ok(value) => value,
        Err(_) => return VS_STATUS_INVALID_ARGUMENT,
    };
    if project.add_key_event(timestamp_ms, token) {
        VS_STATUS_OK
    } else {
        VS_STATUS_INVALID_ARGUMENT
    }
}

#[no_mangle]
pub unsafe extern "C" fn vs_video_project_add_click_event(
    handle: *mut c_void,
    timestamp_ms: u32,
    normalized_x: f32,
    normalized_y: f32,
    button: u32,
) -> i32 {
    let project = match unsafe { video_project_from_handle_mut(handle) } {
        Ok(value) => value,
        Err(code) => return code,
    };
    if project.add_click_event(timestamp_ms, normalized_x, normalized_y, button) {
        VS_STATUS_OK
    } else {
        VS_STATUS_INVALID_ARGUMENT
    }
}

#[no_mangle]
pub unsafe extern "C" fn vs_video_project_set_webcam_overlay(
    handle: *mut c_void,
    enabled: bool,
    shape: u8,
    aspect_ratio: u8,
    asset_id: u32,
) -> i32 {
    let project = match unsafe { video_project_from_handle_mut(handle) } {
        Ok(value) => value,
        Err(code) => return code,
    };
    if project.set_webcam_overlay(enabled, shape, aspect_ratio, asset_id) {
        VS_STATUS_OK
    } else {
        VS_STATUS_INVALID_ARGUMENT
    }
}

#[no_mangle]
pub unsafe extern "C" fn vs_video_project_push_webcam_placement(
    handle: *mut c_void,
    timestamp_ms: u32,
    frame: vs_video_project_rect,
) -> i32 {
    let project = match unsafe { video_project_from_handle_mut(handle) } {
        Ok(value) => value,
        Err(code) => return code,
    };
    project.push_webcam_placement(timestamp_ms, to_domain_rect(frame));
    VS_STATUS_OK
}

#[no_mangle]
pub unsafe extern "C" fn vs_video_project_set_keystroke_overlay(
    handle: *mut c_void,
    enabled: bool,
    style: u8,
    size: u8,
) -> i32 {
    let project = match unsafe { video_project_from_handle_mut(handle) } {
        Ok(value) => value,
        Err(code) => return code,
    };
    if project.set_keystroke_overlay(enabled, style, size) {
        VS_STATUS_OK
    } else {
        VS_STATUS_INVALID_ARGUMENT
    }
}

#[no_mangle]
pub unsafe extern "C" fn vs_video_project_push_keystroke_placement(
    handle: *mut c_void,
    timestamp_ms: u32,
    frame: vs_video_project_rect,
) -> i32 {
    let project = match unsafe { video_project_from_handle_mut(handle) } {
        Ok(value) => value,
        Err(code) => return code,
    };
    project.push_keystroke_placement(timestamp_ms, to_domain_rect(frame));
    VS_STATUS_OK
}

#[no_mangle]
pub unsafe extern "C" fn vs_video_project_render_plan(
    handle: *const c_void,
    query: vs_video_project_render_plan_query,
    out_items: *mut vs_video_project_render_item,
    out_cap: u32,
    out_written: *mut u32,
) -> i32 {
    if out_written.is_null() {
        return VS_STATUS_NULL_POINTER;
    }
    let project = match unsafe { video_project_from_handle(handle) } {
        Ok(value) => value,
        Err(code) => return code,
    };
    let Some(plan) = project.render_plan(to_domain_query(query)) else {
        return VS_STATUS_INVALID_ARGUMENT;
    };
    let required = plan.items.len().min(u32::MAX as usize) as u32;
    unsafe {
        *out_written = required;
    }
    if required > out_cap {
        return VS_STATUS_BUFFER_TOO_SMALL;
    }
    if required == 0 {
        return VS_STATUS_OK;
    }
    if out_items.is_null() {
        return VS_STATUS_NULL_POINTER;
    }
    for (index, item) in plan.items.iter().enumerate() {
        unsafe {
            *out_items.add(index) = to_ffi_render_item(item);
        }
    }
    VS_STATUS_OK
}

#[no_mangle]
pub unsafe extern "C" fn vs_video_project_render_plan_text(
    handle: *const c_void,
    query: vs_video_project_render_plan_query,
    out_ptr: *mut u8,
    out_cap: u32,
    out_written: *mut u32,
) -> i32 {
    let project = match unsafe { video_project_from_handle(handle) } {
        Ok(value) => value,
        Err(code) => return code,
    };
    let Some(plan) = project.render_plan(to_domain_query(query)) else {
        return VS_STATUS_INVALID_ARGUMENT;
    };
    unsafe { write_bytes(&plan.text_bytes, out_ptr, out_cap, out_written) }
}

#[no_mangle]
pub unsafe extern "C" fn vs_video_project_export_plan(
    handle: *const c_void,
    out_plan: *mut vs_video_export_plan,
) -> i32 {
    if out_plan.is_null() {
        return VS_STATUS_NULL_POINTER;
    }
    let project = match unsafe { video_project_from_handle(handle) } {
        Ok(value) => value,
        Err(code) => return code,
    };
    let Some(plan) = project.export_plan() else {
        return VS_STATUS_INVALID_ARGUMENT;
    };
    unsafe {
        *out_plan = to_ffi_video_export_plan(plan);
    }
    VS_STATUS_OK
}

#[no_mangle]
pub unsafe extern "C" fn vs_video_project_pro_requirement(
    handle: *const c_void,
    options: vs_video_project_export_options,
    out_requirement: *mut vs_video_project_pro_requirement_result,
) -> i32 {
    if out_requirement.is_null() {
        return VS_STATUS_NULL_POINTER;
    }
    let project = match unsafe { video_project_from_handle(handle) } {
        Ok(value) => value,
        Err(code) => return code,
    };
    let Some(requirement) = project.pro_requirement(to_domain_export_options(options)) else {
        return VS_STATUS_INVALID_ARGUMENT;
    };
    unsafe {
        *out_requirement = vs_video_project_pro_requirement_result {
            reasons_mask: requirement.reasons_mask,
        };
    }
    VS_STATUS_OK
}

#[no_mangle]
pub unsafe extern "C" fn vs_video_project_serialize_json(
    handle: *const c_void,
    out_ptr: *mut u8,
    out_cap: u32,
    out_written: *mut u32,
) -> i32 {
    let project = match unsafe { video_project_from_handle(handle) } {
        Ok(value) => value,
        Err(code) => return code,
    };
    let json = match project.serialize_snapshot_json() {
        Ok(value) => value,
        Err(_) => return VS_STATUS_REJECTED,
    };
    unsafe { write_bytes(&json, out_ptr, out_cap, out_written) }
}

#[no_mangle]
pub unsafe extern "C" fn vs_video_project_deserialize_json(
    json_ptr: *const u8,
    json_len: u32,
) -> *mut c_void {
    if json_ptr.is_null() || json_len == 0 {
        return std::ptr::null_mut();
    }
    let json = unsafe { slice::from_raw_parts(json_ptr, json_len as usize) };
    let Some(project) = DomainVideoProject::deserialize_snapshot_json(json) else {
        return std::ptr::null_mut();
    };
    let handle = Box::into_raw(Box::new(project)).cast();
    register_handle(&VIDEO_PROJECT_HANDLES, handle);
    handle
}
