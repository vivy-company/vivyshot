use crate::{vs_f32_point, vs_f32_rect};
use vivyshot_domain::{
    image_delta_to_view_delta as domain_image_delta_to_view_delta,
    image_rect_to_view_rect as domain_image_rect_to_view_rect,
    selection_move_rect as domain_selection_move_rect,
    selection_resize_rect as domain_selection_resize_rect,
    view_delta_to_image_delta as domain_view_delta_to_image_delta,
    view_rect_to_image_rect as domain_view_rect_to_image_rect,
    viewport_clamp_pan_offset as domain_viewport_clamp_pan_offset,
};

use super::domain::{
    to_domain_f32_rect, to_domain_resize_corner, to_ffi_f32_point, to_ffi_f32_rect,
};

pub(crate) fn view_rect_to_image_rect(
    view_rect: vs_f32_rect,
    destination_rect: vs_f32_rect,
    image_width: u32,
    image_height: u32,
) -> Option<vs_f32_rect> {
    domain_view_rect_to_image_rect(
        to_domain_f32_rect(view_rect),
        to_domain_f32_rect(destination_rect),
        image_width,
        image_height,
    )
    .map(to_ffi_f32_rect)
}

pub(crate) fn image_rect_to_view_rect(
    image_rect: vs_f32_rect,
    destination_rect: vs_f32_rect,
    image_width: u32,
    image_height: u32,
) -> Option<vs_f32_rect> {
    domain_image_rect_to_view_rect(
        to_domain_f32_rect(image_rect),
        to_domain_f32_rect(destination_rect),
        image_width,
        image_height,
    )
    .map(to_ffi_f32_rect)
}

pub(crate) fn view_delta_to_image_delta(
    delta_x: f32,
    delta_y: f32,
    destination_rect: vs_f32_rect,
    image_width: u32,
    image_height: u32,
) -> Option<vs_f32_point> {
    domain_view_delta_to_image_delta(
        delta_x,
        delta_y,
        to_domain_f32_rect(destination_rect),
        image_width,
        image_height,
    )
    .map(to_ffi_f32_point)
}

pub(crate) fn image_delta_to_view_delta(
    delta_x: f32,
    delta_y: f32,
    destination_rect: vs_f32_rect,
    image_width: u32,
    image_height: u32,
) -> Option<vs_f32_point> {
    domain_image_delta_to_view_delta(
        delta_x,
        delta_y,
        to_domain_f32_rect(destination_rect),
        image_width,
        image_height,
    )
    .map(to_ffi_f32_point)
}

#[allow(clippy::too_many_arguments)]
pub(crate) fn viewport_clamp_pan_offset(
    bounds_width: f32,
    bounds_height: f32,
    image_width: u32,
    image_height: u32,
    zoom_scale: f32,
    overscroll: f32,
    candidate_x: f32,
    candidate_y: f32,
) -> Option<vs_f32_point> {
    domain_viewport_clamp_pan_offset(
        bounds_width,
        bounds_height,
        image_width,
        image_height,
        zoom_scale,
        overscroll,
        candidate_x,
        candidate_y,
    )
    .map(to_ffi_f32_point)
}

pub(crate) fn selection_move_rect(
    current: vs_f32_rect,
    bounds: vs_f32_rect,
    delta_x: f32,
    delta_y: f32,
) -> Option<(vs_f32_rect, bool)> {
    domain_selection_move_rect(
        to_domain_f32_rect(current),
        to_domain_f32_rect(bounds),
        delta_x,
        delta_y,
    )
    .map(|(rect, moved)| (to_ffi_f32_rect(rect), moved))
}

pub(crate) fn selection_resize_rect(
    start: vs_f32_rect,
    bounds: vs_f32_rect,
    corner: u8,
    delta_x: f32,
    delta_y: f32,
    min_width: f32,
    min_height: f32,
) -> Option<vs_f32_rect> {
    let corner = to_domain_resize_corner(corner)?;
    domain_selection_resize_rect(
        to_domain_f32_rect(start),
        to_domain_f32_rect(bounds),
        corner,
        delta_x,
        delta_y,
        min_width,
        min_height,
    )
    .map(to_ffi_f32_rect)
}
