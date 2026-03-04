use super::*;

#[no_mangle]
pub unsafe extern "C" fn vs_view_rect_to_image_rect(
    view_rect: vs_f32_rect,
    destination_rect: vs_f32_rect,
    image_width: u32,
    image_height: u32,
    out_rect: *mut vs_f32_rect,
) -> i32 {
    if out_rect.is_null() {
        return -1;
    }
    let Some(rect) = ffi_geometry::view_rect_to_image_rect(
        view_rect,
        destination_rect,
        image_width,
        image_height,
    ) else {
        return -2;
    };
    unsafe {
        *out_rect = rect;
    }
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_image_rect_to_view_rect(
    image_rect: vs_f32_rect,
    destination_rect: vs_f32_rect,
    image_width: u32,
    image_height: u32,
    out_rect: *mut vs_f32_rect,
) -> i32 {
    if out_rect.is_null() {
        return -1;
    }
    let Some(rect) = ffi_geometry::image_rect_to_view_rect(
        image_rect,
        destination_rect,
        image_width,
        image_height,
    ) else {
        return -2;
    };
    unsafe {
        *out_rect = rect;
    }
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_view_delta_to_image_delta(
    delta_x: f32,
    delta_y: f32,
    destination_rect: vs_f32_rect,
    image_width: u32,
    image_height: u32,
    out_point: *mut vs_f32_point,
) -> i32 {
    if out_point.is_null() {
        return -1;
    }
    let Some(point) = ffi_geometry::view_delta_to_image_delta(
        delta_x,
        delta_y,
        destination_rect,
        image_width,
        image_height,
    ) else {
        return -2;
    };
    unsafe {
        *out_point = point;
    }
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_image_delta_to_view_delta(
    delta_x: f32,
    delta_y: f32,
    destination_rect: vs_f32_rect,
    image_width: u32,
    image_height: u32,
    out_point: *mut vs_f32_point,
) -> i32 {
    if out_point.is_null() {
        return -1;
    }
    let Some(point) = ffi_geometry::image_delta_to_view_delta(
        delta_x,
        delta_y,
        destination_rect,
        image_width,
        image_height,
    ) else {
        return -2;
    };
    unsafe {
        *out_point = point;
    }
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_viewport_clamp_pan_offset(
    bounds_width: f32,
    bounds_height: f32,
    image_width: u32,
    image_height: u32,
    zoom_scale: f32,
    overscroll: f32,
    candidate_x: f32,
    candidate_y: f32,
    out_point: *mut vs_f32_point,
) -> i32 {
    if out_point.is_null() {
        return -1;
    }
    let Some(point) = ffi_geometry::viewport_clamp_pan_offset(
        bounds_width,
        bounds_height,
        image_width,
        image_height,
        zoom_scale,
        overscroll,
        candidate_x,
        candidate_y,
    ) else {
        return -2;
    };
    unsafe {
        *out_point = point;
    }
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_quantize_image_rect(
    image_width: u32,
    image_height: u32,
    rect: vs_f32_rect,
    out_rect: *mut vs_i32_rect,
) -> i32 {
    if out_rect.is_null() {
        return -1;
    }
    let Some(result) =
        domain_quantize_image_rect(image_width, image_height, to_domain_f32_rect(rect))
    else {
        return -2;
    };

    // SAFETY: `out_rect` validated non-null above.
    unsafe {
        *out_rect = to_ffi_i32_rect(result);
    }
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_quantize_image_point(
    image_width: u32,
    image_height: u32,
    x: f32,
    y: f32,
    out_x: *mut i32,
    out_y: *mut i32,
) -> i32 {
    if out_x.is_null() || out_y.is_null() {
        return -1;
    }
    let Some((px, py)) = domain_quantize_image_point(image_width, image_height, x, y) else {
        return -1;
    };
    unsafe {
        *out_x = px;
        *out_y = py;
    }
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_quantize_rgba(
    r: f32,
    g: f32,
    b: f32,
    a: f32,
    out_color: *mut vs_rgba8,
) -> i32 {
    if out_color.is_null() {
        return -1;
    }
    let Some(color) = domain_quantize_rgba(r, g, b, a) else {
        return -1;
    };
    // SAFETY: output pointer validated non-null above.
    unsafe {
        *out_color = to_ffi_rgba8(color);
    }
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_selection_move_rect(
    current: vs_f32_rect,
    bounds: vs_f32_rect,
    delta_x: f32,
    delta_y: f32,
    out_rect: *mut vs_f32_rect,
) -> i32 {
    if out_rect.is_null() {
        return -1;
    }
    let Some((rect, moved)) = ffi_geometry::selection_move_rect(current, bounds, delta_x, delta_y)
    else {
        return -2;
    };
    unsafe {
        *out_rect = rect;
    }
    if moved {
        0
    } else {
        1
    }
}

#[no_mangle]
pub unsafe extern "C" fn vs_selection_resize_rect(
    start: vs_f32_rect,
    bounds: vs_f32_rect,
    corner: u8,
    delta_x: f32,
    delta_y: f32,
    min_width: f32,
    min_height: f32,
    out_rect: *mut vs_f32_rect,
) -> i32 {
    if out_rect.is_null() {
        return -1;
    }
    let Some(rect) = ffi_geometry::selection_resize_rect(
        start, bounds, corner, delta_x, delta_y, min_width, min_height,
    ) else {
        return -3;
    };
    unsafe { *out_rect = rect };
    0
}
