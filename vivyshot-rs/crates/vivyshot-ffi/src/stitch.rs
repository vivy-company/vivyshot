use super::*;

unsafe fn stitch_session_from_handle_mut<'a>(
    session: *mut c_void,
) -> Result<&'a mut vs_stitch_session, i32> {
    validate_handle(&STITCH_SESSION_HANDLES, session)?;
    // SAFETY: pointer was validated by registry and originates from Box::into_raw.
    Ok(unsafe { &mut *session.cast::<vs_stitch_session>() })
}

unsafe fn stitch_session_from_handle<'a>(
    session: *const c_void,
) -> Result<&'a vs_stitch_session, i32> {
    validate_handle(&STITCH_SESSION_HANDLES, session)?;
    // SAFETY: pointer was validated by registry and originates from Box::into_raw.
    Ok(unsafe { &*session.cast::<vs_stitch_session>() })
}

pub(crate) unsafe fn bgra_view_slice<'a>(
    view: vs_bgra_image_view,
) -> Option<(&'a [u8], usize, usize, usize)> {
    if view.ptr.is_null() || view.width == 0 || view.height == 0 {
        return None;
    }

    let width = view.width as usize;
    let height = view.height as usize;
    let stride = view.stride as usize;
    let row_bytes = width.checked_mul(4)?;
    if stride < row_bytes {
        return None;
    }

    let required_len = stride.checked_mul(height)?;
    if view.len < required_len {
        return None;
    }

    // SAFETY: pointer/len are validated above.
    let bytes = unsafe { slice::from_raw_parts(view.ptr, required_len) };
    Some((bytes, width, height, stride))
}

#[derive(Clone)]
struct OwnedBgraFrame {
    width: u32,
    height: u32,
    stride: u32,
    pixels: Vec<u8>,
}

impl OwnedBgraFrame {
    fn as_view(&self) -> vs_bgra_image_view {
        vs_bgra_image_view {
            width: self.width,
            height: self.height,
            stride: self.stride,
            ptr: self.pixels.as_ptr(),
            len: self.pixels.len(),
        }
    }

    fn to_domain_owned(&self) -> DomainBgraImageOwned {
        DomainBgraImageOwned {
            width: self.width,
            height: self.height,
            stride: self.stride,
            pixels: self.pixels.clone(),
        }
    }

    fn from_domain_owned(frame: DomainBgraImageOwned) -> Self {
        OwnedBgraFrame {
            width: frame.width,
            height: frame.height,
            stride: frame.stride,
            pixels: frame.pixels,
        }
    }

    fn to_owned_image(&self) -> vs_bgra_owned_image {
        let mut pixels = self.pixels.clone();
        let ptr = pixels.as_mut_ptr();
        let len = pixels.len();
        std::mem::forget(pixels);
        vs_bgra_owned_image {
            width: self.width,
            height: self.height,
            stride: self.stride,
            ptr,
            len,
        }
    }
}

#[repr(C)]
struct vs_stitch_session {
    working_image: Option<OwnedBgraFrame>,
    last_frame: Option<OwnedBgraFrame>,
    direction: Option<u8>,
    expected_rows: Option<u32>,
    segment_count: u32,
}

fn copy_bgra_view_to_owned(view: vs_bgra_image_view) -> Option<OwnedBgraFrame> {
    // SAFETY: `bgra_view_slice` validates all pointer/length invariants.
    let (bytes, width, height, stride) = unsafe { bgra_view_slice(view) }?;
    let domain = domain_bgra_view_to_owned(DomainBgraImageView {
        width: width as u32,
        height: height as u32,
        stride: stride as u32,
        pixels: bytes,
    })?;
    Some(OwnedBgraFrame::from_domain_owned(domain))
}

fn crop_bgra_view_to_owned(
    source: vs_bgra_image_view,
    x: u32,
    y: u32,
    width: u32,
    height: u32,
) -> Option<OwnedBgraFrame> {
    if width == 0 || height == 0 {
        return None;
    }

    // SAFETY: `bgra_view_slice` validates all pointer/length invariants.
    let (bytes, src_width, src_height, src_stride) = unsafe { bgra_view_slice(source) }?;
    let x_end = x.checked_add(width)?;
    let y_end = y.checked_add(height)?;
    if x_end as usize > src_width || y_end as usize > src_height {
        return None;
    }

    let x_usize = x as usize;
    let y_usize = y as usize;
    let out_width = width as usize;
    let out_height = height as usize;
    let out_stride = out_width.checked_mul(4)?;
    let out_stride_u32 = u32::try_from(out_stride).ok()?;
    let out_len = out_stride.checked_mul(out_height)?;
    let x_offset = x_usize.checked_mul(4)?;

    let mut pixels = vec![0u8; out_len];
    for row in 0..out_height {
        let src_start = (y_usize + row)
            .checked_mul(src_stride)?
            .checked_add(x_offset)?;
        let dst_start = row.checked_mul(out_stride)?;
        pixels[dst_start..dst_start + out_stride]
            .copy_from_slice(&bytes[src_start..src_start + out_stride]);
    }

    Some(OwnedBgraFrame {
        width,
        height,
        stride: out_stride_u32,
        pixels,
    })
}

fn extract_strip(frame: &OwnedBgraFrame, rows: u32, side: u8) -> Option<OwnedBgraFrame> {
    domain_stitch_extract_strip(&frame.to_domain_owned(), rows, side)
        .map(OwnedBgraFrame::from_domain_owned)
}

fn resize_frame_width_nearest(frame: &OwnedBgraFrame, target_width: u32) -> Option<OwnedBgraFrame> {
    domain_stitch_resize_width_nearest(&frame.to_domain_owned(), target_width)
        .map(OwnedBgraFrame::from_domain_owned)
}

fn merge_bgra_frames(
    base: &OwnedBgraFrame,
    segment: &OwnedBgraFrame,
    side: u8,
) -> Option<OwnedBgraFrame> {
    domain_stitch_merge_frames(&base.to_domain_owned(), &segment.to_domain_owned(), side)
        .map(OwnedBgraFrame::from_domain_owned)
}

fn default_stitch_session_result(
    session: &vs_stitch_session,
    accepted: bool,
    delta: Option<vs_stitch_delta>,
) -> vs_stitch_session_result {
    let direction_locked = session.direction.is_some();
    let expected_rows = session.expected_rows.unwrap_or(0);
    let scroll_direction_sign = match session.direction {
        Some(VS_STITCH_SIDE_BOTTOM) => -1,
        Some(VS_STITCH_SIDE_TOP) => 1,
        _ => -1,
    };
    let (rows, side, score) = match delta {
        Some(d) => (d.rows, d.side, d.score),
        None => (0, 0, 0.0),
    };
    vs_stitch_session_result {
        accepted,
        rows,
        side,
        score,
        direction_locked,
        expected_rows,
        segment_count: session.segment_count,
        scroll_direction_sign,
    }
}

#[no_mangle]
pub extern "C" fn vs_stitch_session_create() -> *mut c_void {
    let session = vs_stitch_session {
        working_image: None,
        last_frame: None,
        direction: None,
        expected_rows: None,
        segment_count: 1,
    };
    let handle = Box::into_raw(Box::new(session)).cast();
    register_handle(&STITCH_SESSION_HANDLES, handle);
    handle
}

#[no_mangle]
pub unsafe extern "C" fn vs_stitch_session_destroy(session: *mut c_void) {
    if !unregister_handle(&STITCH_SESSION_HANDLES, session) {
        return;
    }

    // SAFETY: `session` was created by `vs_stitch_session_create`.
    unsafe {
        drop(Box::from_raw(session.cast::<vs_stitch_session>()));
    }
}

#[no_mangle]
pub unsafe extern "C" fn vs_stitch_session_reset(
    session: *mut c_void,
    base_segment_count: u32,
) -> i32 {
    let session_ref = match unsafe { stitch_session_from_handle_mut(session) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    session_ref.working_image = None;
    session_ref.last_frame = None;
    session_ref.direction = None;
    session_ref.expected_rows = None;
    session_ref.segment_count = base_segment_count.max(1);
    0
}

pub(crate) fn zero_bgra_owned_image(image: &mut vs_bgra_owned_image) {
    image.width = 0;
    image.height = 0;
    image.stride = 0;
    image.ptr = std::ptr::null_mut();
    image.len = 0;
}

#[no_mangle]
pub unsafe extern "C" fn vs_normalize_trim_range(
    duration_ms: u32,
    start_ms: u32,
    end_ms: u32,
    min_gap_ms: u32,
    active_handle: u8,
    out_start_ms: *mut u32,
    out_end_ms: *mut u32,
) -> i32 {
    if out_start_ms.is_null() || out_end_ms.is_null() {
        return -1;
    }
    let Some(handle) = to_domain_trim_handle(active_handle) else {
        return -2;
    };
    let (start, end) =
        domain_normalize_trim_range(duration_ms, start_ms, end_ms, min_gap_ms, handle);

    unsafe {
        *out_start_ms = start;
        *out_end_ms = end;
    }
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_build_gif_export_plan(
    start_ms: u32,
    end_ms: u32,
    preferred_fps: f32,
    max_dimension: u32,
    out_plan: *mut vs_gif_export_plan,
) -> i32 {
    if out_plan.is_null() {
        return -1;
    }
    let plan = domain_build_gif_export_plan(start_ms, end_ms, preferred_fps, max_dimension);

    unsafe {
        *out_plan = to_ffi_gif_plan(plan);
    }
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_gif_frame_time_ms(
    plan: vs_gif_export_plan,
    index: u32,
    out_time_ms: *mut u32,
) -> i32 {
    if out_time_ms.is_null() {
        return -1;
    }
    let Some(value) = domain_gif_frame_time_ms(to_domain_gif_plan(plan), index) else {
        return -1;
    };
    unsafe {
        *out_time_ms = value;
    }
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_stitch_autoscroll_reset(
    out_state: *mut vs_stitch_autoscroll_state,
) -> i32 {
    if out_state.is_null() {
        return -1;
    }
    let state = domain_stitch_autoscroll_reset();
    unsafe {
        *out_state = to_ffi_stitch_autoscroll_state(state);
    }
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_stitch_autoscroll_update(
    enabled: bool,
    direction_locked: bool,
    did_merge: bool,
    threshold_ticks: u32,
    state: vs_stitch_autoscroll_state,
    out_state: *mut vs_stitch_autoscroll_state,
) -> i32 {
    if out_state.is_null() {
        return -1;
    }
    let next = domain_stitch_autoscroll_update(
        enabled,
        direction_locked,
        did_merge,
        threshold_ticks,
        to_domain_stitch_autoscroll_state(state),
    );

    unsafe {
        *out_state = to_ffi_stitch_autoscroll_state(next);
    }
    0
}

fn stitch_session_push_internal(
    session_ref: &mut vs_stitch_session,
    current_frame: OwnedBgraFrame,
) -> (vs_stitch_session_result, Option<OwnedBgraFrame>) {
    let mut maybe_delta: Option<vs_stitch_delta> = None;
    let mut merged_output: Option<OwnedBgraFrame> = None;
    let mut accepted = false;

    if let Some(previous_frame) = session_ref.last_frame.as_ref() {
        let prev_view = previous_frame.as_view();
        let curr_view = current_frame.as_view();
        if prev_view.width == curr_view.width && prev_view.height == curr_view.height {
            let preferred_side = match session_ref.direction {
                Some(VS_STITCH_SIDE_TOP) => 0,
                Some(VS_STITCH_SIDE_BOTTOM) => 1,
                _ => -1,
            };
            let expected_rows = session_ref.expected_rows.unwrap_or(0);
            let has_expected_rows = session_ref.expected_rows.is_some();
            let mut delta = vs_stitch_delta::default();
            let direction_locked = session_ref.direction.is_some();

            // SAFETY: views point to owned frame memory and remain valid for call duration.
            let strict_status = unsafe {
                vs_stitch_estimate_delta_bgra(
                    prev_view,
                    curr_view,
                    preferred_side,
                    expected_rows,
                    has_expected_rows,
                    false,
                    &mut delta,
                )
            };
            let relaxed_status = if strict_status == 0 {
                0
            } else if direction_locked {
                // Once direction is locked, only accept strict matches. Relaxed fallback can
                // accept weak reverse-motion matches and create overlapping stitched segments.
                -3
            } else {
                // SAFETY: same as strict call.
                unsafe {
                    vs_stitch_estimate_delta_bgra(
                        prev_view,
                        curr_view,
                        preferred_side,
                        expected_rows,
                        has_expected_rows,
                        true,
                        &mut delta,
                    )
                }
            };

            if relaxed_status == 0 && delta.rows >= 4 {
                let direction_conflict =
                    matches!(session_ref.direction, Some(locked_side) if delta.side != locked_side);
                if !direction_conflict {
                    let mut merge_ok = true;
                    if let Some(base_image) = session_ref.working_image.as_ref() {
                        merge_ok = false;
                        if let Some(strip) = extract_strip(&current_frame, delta.rows, delta.side) {
                            let normalized_strip = if strip.width == base_image.width {
                                Some(strip)
                            } else {
                                resize_frame_width_nearest(&strip, base_image.width)
                            };
                            if let Some(normalized_strip) = normalized_strip {
                                if let Some(merged) =
                                    merge_bgra_frames(base_image, &normalized_strip, delta.side)
                                {
                                    merge_ok = true;
                                    merged_output = Some(merged);
                                }
                            }
                        }
                    }

                    if merge_ok {
                        accepted = true;
                        maybe_delta = Some(delta);
                        if session_ref.direction.is_none() {
                            session_ref.direction = Some(delta.side);
                        }
                        session_ref.expected_rows = Some(match session_ref.expected_rows {
                            Some(previous_expected) => {
                                let blended = ((previous_expected as f64) * 0.65
                                    + (delta.rows as f64) * 0.35)
                                    .round() as u32;
                                blended.max(4)
                            }
                            None => delta.rows,
                        });
                        session_ref.segment_count = session_ref.segment_count.saturating_add(1);
                        if let Some(merged) = merged_output.as_ref() {
                            session_ref.working_image = Some(merged.clone());
                        }
                    }
                }
            }
        } else {
            session_ref.direction = None;
            session_ref.expected_rows = None;
        }
    }

    session_ref.last_frame = Some(current_frame);
    let result = default_stitch_session_result(session_ref, accepted, maybe_delta);
    (result, merged_output)
}

#[no_mangle]
pub unsafe extern "C" fn vs_stitch_session_set_base_bgra(
    session: *mut c_void,
    base: vs_bgra_image_view,
    base_segment_count: u32,
) -> i32 {
    let session_ref = match unsafe { stitch_session_from_handle_mut(session) } {
        Ok(v) => v,
        Err(code) => return code,
    };

    let base_frame = match copy_bgra_view_to_owned(base) {
        Some(v) => v,
        None => return -2,
    };

    session_ref.working_image = Some(base_frame);
    session_ref.last_frame = None;
    session_ref.direction = None;
    session_ref.expected_rows = None;
    session_ref.segment_count = base_segment_count.max(1);
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_stitch_session_get_merged_image_bgra(
    session: *mut c_void,
    out_image: *mut vs_bgra_owned_image,
) -> i32 {
    if out_image.is_null() {
        return -1;
    }
    let session_ref = match unsafe { stitch_session_from_handle(session) } {
        Ok(v) => v,
        Err(code) => return code,
    };

    // SAFETY: caller passed a valid writable pointer.
    let out_image_ref = unsafe { &mut *out_image };
    zero_bgra_owned_image(out_image_ref);

    let Some(merged) = session_ref.working_image.as_ref() else {
        return 1;
    };

    *out_image_ref = merged.to_owned_image();
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_stitch_session_push_frame_bgra(
    session: *mut c_void,
    frame: vs_bgra_image_view,
    out_result: *mut vs_stitch_session_result,
) -> i32 {
    if out_result.is_null() {
        return -1;
    }
    let session_ref = match unsafe { stitch_session_from_handle_mut(session) } {
        Ok(v) => v,
        Err(code) => return code,
    };

    let current_frame = match copy_bgra_view_to_owned(frame) {
        Some(v) => v,
        None => return -2,
    };

    let (result, _) = stitch_session_push_internal(session_ref, current_frame);
    // SAFETY: `out_result` was checked non-null and points to writable memory.
    unsafe {
        *out_result = result;
    }
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_stitch_session_push_frame_and_merge_bgra(
    session: *mut c_void,
    frame: vs_bgra_image_view,
    out_result: *mut vs_stitch_session_result,
    out_image: *mut vs_bgra_owned_image,
) -> i32 {
    if out_result.is_null() || out_image.is_null() {
        return -1;
    }
    let session_ref = match unsafe { stitch_session_from_handle_mut(session) } {
        Ok(v) => v,
        Err(code) => return code,
    };

    let current_frame = match copy_bgra_view_to_owned(frame) {
        Some(v) => v,
        None => return -2,
    };

    // SAFETY: output pointer is non-null and owned by caller.
    let out_image_ref = unsafe { &mut *out_image };
    zero_bgra_owned_image(out_image_ref);

    let (result, merged) = stitch_session_push_internal(session_ref, current_frame);
    unsafe {
        *out_result = result;
    }
    if let Some(merged) = merged {
        *out_image_ref = merged.to_owned_image();
    }
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_stitch_estimate_delta_bgra(
    previous: vs_bgra_image_view,
    current: vs_bgra_image_view,
    preferred_side: i32,
    expected_rows: u32,
    has_expected_rows: bool,
    relaxed: bool,
    out_delta: *mut vs_stitch_delta,
) -> i32 {
    if out_delta.is_null() {
        return -1;
    }

    let (prev, prev_width, prev_height, prev_stride) = match unsafe { bgra_view_slice(previous) } {
        Some(v) => v,
        None => return -2,
    };
    let (curr, curr_width, curr_height, curr_stride) = match unsafe { bgra_view_slice(current) } {
        Some(v) => v,
        None => return -2,
    };
    let Some(delta) = ffi_stitch::estimate_delta(
        DomainBgraImageView {
            width: prev_width as u32,
            height: prev_height as u32,
            stride: prev_stride as u32,
            pixels: prev,
        },
        DomainBgraImageView {
            width: curr_width as u32,
            height: curr_height as u32,
            stride: curr_stride as u32,
            pixels: curr,
        },
        preferred_side,
        expected_rows,
        has_expected_rows,
        relaxed,
    ) else {
        return -3;
    };

    unsafe {
        *out_delta = vs_stitch_delta {
            rows: delta.rows,
            side: delta.side,
            score: delta.score,
        };
    }
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_stitch_merge_bgra(
    base: vs_bgra_image_view,
    segment: vs_bgra_image_view,
    side: u8,
    out_image: *mut vs_bgra_owned_image,
) -> i32 {
    if out_image.is_null() {
        return -1;
    }

    let base_owned = match copy_bgra_view_to_owned(base) {
        Some(v) => v,
        None => return -2,
    };
    let segment_owned = match copy_bgra_view_to_owned(segment) {
        Some(v) => v,
        None => return -2,
    };
    let merged = match merge_bgra_frames(&base_owned, &segment_owned, side) {
        Some(v) => v,
        None => return -2,
    };

    unsafe {
        *out_image = merged.to_owned_image();
    }
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_bgra_crop(
    source: vs_bgra_image_view,
    x: u32,
    y: u32,
    width: u32,
    height: u32,
    out_image: *mut vs_bgra_owned_image,
) -> i32 {
    if out_image.is_null() {
        return -1;
    }

    let cropped = match crop_bgra_view_to_owned(source, x, y, width, height) {
        Some(v) => v,
        None => return -2,
    };
    unsafe {
        *out_image = cropped.to_owned_image();
    }
    0
}
