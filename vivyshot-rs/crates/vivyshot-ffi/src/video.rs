use super::*;

fn compute_video_export_plan(
    trim_start_ms: u32,
    trim_end_ms: u32,
    key_event_count: u32,
    click_event_count: u32,
    context: vs_video_export_context,
) -> Option<vs_video_export_plan> {
    ffi_video::compute_export_plan(
        trim_start_ms,
        trim_end_ms,
        key_event_count,
        click_event_count,
        context,
    )
}

#[no_mangle]
pub unsafe extern "C" fn vs_video_compute_export_plan(
    trim_start_ms: u32,
    trim_end_ms: u32,
    key_event_count: u32,
    click_event_count: u32,
    context: vs_video_export_context,
    out_plan: *mut vs_video_export_plan,
) -> i32 {
    if out_plan.is_null() {
        return -1;
    }

    let Some(plan) = compute_video_export_plan(
        trim_start_ms,
        trim_end_ms,
        key_event_count,
        click_event_count,
        context,
    ) else {
        return -2;
    };

    // SAFETY: `out_plan` is validated non-null above.
    unsafe {
        *out_plan = plan;
    }
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_video_derive_export_decision(
    target: u8,
    plan: vs_video_export_plan,
    out_decision: *mut vs_video_export_decision,
) -> i32 {
    if out_decision.is_null() {
        return VS_STATUS_NULL_POINTER;
    }

    let target = match target {
        VS_VIDEO_EXPORT_TARGET_MP4 | VS_VIDEO_EXPORT_TARGET_GIF => target,
        _ => return VS_STATUS_INVALID_ARGUMENT,
    };

    let Some(decision) =
        domain_derive_video_export_decision(target, to_domain_video_export_plan(plan))
    else {
        return VS_STATUS_INVALID_ARGUMENT;
    };

    unsafe {
        *out_decision = to_ffi_video_export_decision(decision);
    }
    VS_STATUS_OK
}

#[no_mangle]
pub unsafe extern "C" fn vs_video_preferred_save_container(
    codec: u8,
    out_container: *mut u8,
) -> i32 {
    if out_container.is_null() {
        return VS_STATUS_NULL_POINTER;
    }

    let Some(container) = ffi_video::preferred_save_container(codec) else {
        return VS_STATUS_INVALID_ARGUMENT;
    };

    unsafe {
        *out_container = container;
    }
    VS_STATUS_OK
}

#[no_mangle]
pub unsafe extern "C" fn vs_video_best_save_container(
    codec: u8,
    supports_mp4: bool,
    supports_mov: bool,
    out_container: *mut u8,
) -> i32 {
    if out_container.is_null() {
        return VS_STATUS_NULL_POINTER;
    }

    let Some(container) = ffi_video::best_save_container(codec, supports_mp4, supports_mov) else {
        return VS_STATUS_INVALID_ARGUMENT;
    };

    unsafe {
        *out_container = container;
    }
    VS_STATUS_OK
}

#[no_mangle]
pub unsafe extern "C" fn vs_video_best_export_preset(
    codec: u8,
    quality: u8,
    compatible_mask: u32,
    out_preset: *mut u8,
) -> i32 {
    if out_preset.is_null() {
        return VS_STATUS_NULL_POINTER;
    }

    let Some(preset) = ffi_video::best_export_preset(codec, quality, compatible_mask) else {
        return VS_STATUS_INVALID_ARGUMENT;
    };

    unsafe {
        *out_preset = preset;
    }
    VS_STATUS_OK
}

#[no_mangle]
pub unsafe extern "C" fn vs_video_estimated_file_length_limit(
    duration_seconds: f64,
    codec: u8,
    frame_rate: u8,
    quality: u8,
    scale: u8,
    bitrate: u8,
    out_limit: *mut i64,
) -> i32 {
    if out_limit.is_null() {
        return VS_STATUS_NULL_POINTER;
    }

    let Some(limit) = ffi_video::estimated_file_length_limit(
        duration_seconds,
        codec,
        frame_rate,
        quality,
        scale,
        bitrate,
    ) else {
        return VS_STATUS_INVALID_ARGUMENT;
    };

    unsafe {
        *out_limit = limit;
    }
    VS_STATUS_OK
}

#[no_mangle]
pub unsafe extern "C" fn vs_video_post_recording_video_composition_plan(
    natural_width: f32,
    natural_height: f32,
    preferred_transform: crate::vs_affine_transform,
    scale: u8,
    out_plan: *mut vs_video_post_recording_composition_plan,
) -> i32 {
    if out_plan.is_null() {
        return VS_STATUS_NULL_POINTER;
    }

    let Some(plan) = ffi_video::post_recording_video_composition_plan(
        natural_width,
        natural_height,
        preferred_transform,
        scale,
    ) else {
        return VS_STATUS_INVALID_ARGUMENT;
    };

    unsafe {
        *out_plan = plan;
    }
    VS_STATUS_OK
}

#[no_mangle]
pub unsafe extern "C" fn vs_video_key_overlay_label_layout(
    render_width: f32,
    render_height: f32,
    char_count: u32,
    out_layout: *mut vs_video_overlay_label_layout,
) -> i32 {
    if out_layout.is_null() {
        return VS_STATUS_NULL_POINTER;
    }
    let Some(layout) = ffi_video::key_overlay_label_layout(render_width, render_height, char_count)
    else {
        return VS_STATUS_INVALID_ARGUMENT;
    };
    unsafe {
        *out_layout = layout;
    }
    VS_STATUS_OK
}

#[no_mangle]
pub unsafe extern "C" fn vs_video_text_overlay_label_layout(
    render_width: f32,
    render_height: f32,
    char_count: u32,
    out_layout: *mut vs_video_overlay_label_layout,
) -> i32 {
    if out_layout.is_null() {
        return VS_STATUS_NULL_POINTER;
    }
    let Some(layout) =
        ffi_video::text_overlay_label_layout(render_width, render_height, char_count)
    else {
        return VS_STATUS_INVALID_ARGUMENT;
    };
    unsafe {
        *out_layout = layout;
    }
    VS_STATUS_OK
}

#[no_mangle]
pub unsafe extern "C" fn vs_video_compute_overlay_clip_window(
    clip_start_seconds: f64,
    clip_end_seconds: f64,
    trim_start_seconds: f64,
    min_visible_seconds: f64,
    out_window: *mut vs_video_overlay_clip_window,
) -> i32 {
    if out_window.is_null() {
        return VS_STATUS_NULL_POINTER;
    }
    let Some(window) = ffi_video::overlay_clip_window(
        clip_start_seconds,
        clip_end_seconds,
        trim_start_seconds,
        min_visible_seconds,
    ) else {
        return VS_STATUS_INVALID_ARGUMENT;
    };
    unsafe {
        *out_window = window;
    }
    VS_STATUS_OK
}

unsafe fn write_bytes_to_output(
    bytes: &[u8],
    out_ptr: *mut u8,
    out_cap: u32,
    out_written: *mut u32,
) -> i32 {
    if out_written.is_null() {
        return -1;
    }

    let total_len = bytes.len();
    let total_u32 = if total_len > u32::MAX as usize {
        u32::MAX
    } else {
        total_len as u32
    };

    // SAFETY: caller provided non-null pointer to writable memory for `out_written`.
    unsafe {
        *out_written = total_u32;
    }

    if out_ptr.is_null() || out_cap == 0 || total_len == 0 {
        return 0;
    }

    let copy_len = total_len.min(out_cap as usize);
    // SAFETY: pointers are validated and destination capacity is bounded by `copy_len`.
    unsafe {
        std::ptr::copy_nonoverlapping(bytes.as_ptr(), out_ptr, copy_len);
    }
    0
}

fn fallback_key_label(key_code: u16) -> &'static str {
    match key_code as i32 {
        36 => "Return",
        48 => "Tab",
        49 => "Space",
        51 => "⌫",
        53 => "Esc",
        117 => "Del",
        123 => "←",
        124 => "→",
        125 => "↓",
        126 => "↑",
        122 => "F1",
        120 => "F2",
        99 => "F3",
        118 => "F4",
        96 => "F5",
        97 => "F6",
        98 => "F7",
        100 => "F8",
        101 => "F9",
        109 => "F10",
        103 => "F11",
        111 => "F12",
        _ => "Key",
    }
}

fn normalize_key_token_inner(key_code: u16, modifiers: u32, chars: Option<&str>) -> String {
    let mut token = String::new();
    if modifiers & VS_KEY_MOD_COMMAND != 0 {
        token.push('⌘');
    }
    if modifiers & VS_KEY_MOD_SHIFT != 0 {
        token.push('⇧');
    }
    if modifiers & VS_KEY_MOD_OPTION != 0 {
        token.push('⌥');
    }
    if modifiers & VS_KEY_MOD_CONTROL != 0 {
        token.push('⌃');
    }

    let key_label = match chars {
        Some(raw) => {
            let trimmed = raw.trim();
            let mut chars = trimmed.chars();
            if let Some(ch) = chars.next() {
                if chars.next().is_none() && !ch.is_control() {
                    ch.to_uppercase().collect()
                } else {
                    fallback_key_label(key_code).to_string()
                }
            } else {
                fallback_key_label(key_code).to_string()
            }
        }
        None => fallback_key_label(key_code).to_string(),
    };
    token.push_str(&key_label);

    token.chars().take(24).collect()
}

#[no_mangle]
pub unsafe extern "C" fn vs_normalize_key_token(
    key_code: u16,
    modifiers: u32,
    chars_ptr: *const u8,
    chars_len: u32,
    out_ptr: *mut u8,
    out_cap: u32,
    out_written: *mut u32,
) -> i32 {
    let chars = if chars_len > 0 {
        if chars_ptr.is_null() {
            return -1;
        }
        // SAFETY: pointer and length validated above.
        let bytes = unsafe { slice::from_raw_parts(chars_ptr, chars_len as usize) };
        std::str::from_utf8(bytes).ok()
    } else {
        None
    };

    let token = normalize_key_token_inner(key_code, modifiers, chars);
    // SAFETY: delegates to helper that validates output pointers.
    unsafe { write_bytes_to_output(token.as_bytes(), out_ptr, out_cap, out_written) }
}

#[no_mangle]
pub unsafe extern "C" fn vs_key_event_is_duplicate(
    last_timestamp_ns: u64,
    last_token_ptr: *const u8,
    last_token_len: u32,
    timestamp_ns: u64,
    token_ptr: *const u8,
    token_len: u32,
) -> bool {
    if last_timestamp_ns != timestamp_ns || last_token_len != token_len || token_len == 0 {
        return false;
    }
    if last_token_ptr.is_null() || token_ptr.is_null() {
        return false;
    }

    // SAFETY: pointers are non-null and sizes are bounded by caller.
    let last = unsafe { slice::from_raw_parts(last_token_ptr, last_token_len as usize) };
    // SAFETY: pointers are non-null and sizes are bounded by caller.
    let curr = unsafe { slice::from_raw_parts(token_ptr, token_len as usize) };
    last == curr
}

#[no_mangle]
pub unsafe extern "C" fn vs_normalize_click_point(
    normalized_x: f32,
    normalized_y: f32,
    out_x: *mut f32,
    out_y: *mut f32,
) -> i32 {
    if out_x.is_null() || out_y.is_null() {
        return -1;
    }

    let Some((x, y)) = domain_normalize_click_point(normalized_x, normalized_y) else {
        return -1;
    };

    // SAFETY: output pointers are validated non-null above.
    unsafe {
        *out_x = x;
        *out_y = y;
    }
    0
}

#[no_mangle]
pub extern "C" fn vs_click_event_is_duplicate(
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
    domain_click_event_is_duplicate(
        last_timestamp_ns,
        last_button,
        last_x,
        last_y,
        timestamp_ns,
        button,
        x,
        y,
        epsilon,
    )
}
