pub use crate::types::{F32Point, F32Rect, I32Rect, ResizeCorner, Rgba8};

fn standardize_rect(rect: F32Rect) -> Option<(f32, f32, f32, f32)> {
    if !rect.x.is_finite()
        || !rect.y.is_finite()
        || !rect.width.is_finite()
        || !rect.height.is_finite()
    {
        return None;
    }
    if rect.width == 0.0 || rect.height == 0.0 {
        return None;
    }

    let x0 = rect.x;
    let y0 = rect.y;
    let x1 = rect.x + rect.width;
    let y1 = rect.y + rect.height;

    let min_x = x0.min(x1);
    let max_x = x0.max(x1);
    let min_y = y0.min(y1);
    let max_y = y0.max(y1);

    if !min_x.is_finite() || !max_x.is_finite() || !min_y.is_finite() || !max_y.is_finite() {
        return None;
    }

    if max_x <= min_x || max_y <= min_y {
        return None;
    }

    Some((min_x, min_y, max_x, max_y))
}

fn clamp_f32(value: f32, min_value: f32, max_value: f32) -> f32 {
    value.clamp(min_value, max_value)
}

pub fn view_rect_to_image_rect(
    view_rect: F32Rect,
    destination_rect: F32Rect,
    image_width: u32,
    image_height: u32,
) -> Option<F32Rect> {
    if image_width == 0 || image_height == 0 {
        return None;
    }

    let (view_min_x, view_min_y, view_max_x, view_max_y) = standardize_rect(view_rect)?;
    let (dst_min_x, dst_min_y, dst_max_x, dst_max_y) = standardize_rect(destination_rect)?;

    let clipped_min_x = view_min_x.max(dst_min_x);
    let clipped_min_y = view_min_y.max(dst_min_y);
    let clipped_max_x = view_max_x.min(dst_max_x);
    let clipped_max_y = view_max_y.min(dst_max_y);
    if clipped_max_x <= clipped_min_x || clipped_max_y <= clipped_min_y {
        return None;
    }

    let dst_width = dst_max_x - dst_min_x;
    let dst_height = dst_max_y - dst_min_y;
    if dst_width <= 0.0 || dst_height <= 0.0 {
        return None;
    }

    let scale_x = image_width as f32 / dst_width;
    let scale_y = image_height as f32 / dst_height;
    let image_h = image_height as f32;

    let x0 = (clipped_min_x - dst_min_x) * scale_x;
    let x1 = (clipped_max_x - dst_min_x) * scale_x;
    let y0_from_bottom = (clipped_min_y - dst_min_y) * scale_y;
    let y1_from_bottom = (clipped_max_y - dst_min_y) * scale_y;
    let y0 = image_h - y1_from_bottom;
    let y1 = image_h - y0_from_bottom;
    if x1 <= x0 || y1 <= y0 {
        return None;
    }

    Some(F32Rect {
        x: x0,
        y: y0,
        width: x1 - x0,
        height: y1 - y0,
    })
}

pub fn image_rect_to_view_rect(
    image_rect: F32Rect,
    destination_rect: F32Rect,
    image_width: u32,
    image_height: u32,
) -> Option<F32Rect> {
    if image_width == 0 || image_height == 0 {
        return None;
    }

    let (img_min_x, img_min_y, img_max_x, img_max_y) = standardize_rect(image_rect)?;
    let (dst_min_x, dst_min_y, dst_max_x, dst_max_y) = standardize_rect(destination_rect)?;

    let dst_width = dst_max_x - dst_min_x;
    let dst_height = dst_max_y - dst_min_y;
    if dst_width <= 0.0 || dst_height <= 0.0 {
        return None;
    }

    let scale_x = dst_width / image_width as f32;
    let scale_y = dst_height / image_height as f32;
    if scale_x <= 0.0 || scale_y <= 0.0 {
        return None;
    }

    let image_h = image_height as f32;
    let x0 = dst_min_x + img_min_x * scale_x;
    let x1 = dst_min_x + img_max_x * scale_x;
    let y_top = dst_min_y + (image_h - img_min_y) * scale_y;
    let y_bottom = dst_min_y + (image_h - img_max_y) * scale_y;
    let min_x = x0.min(x1);
    let max_x = x0.max(x1);
    let min_y = y_bottom.min(y_top);
    let max_y = y_bottom.max(y_top);
    if max_x <= min_x || max_y <= min_y {
        return None;
    }

    Some(F32Rect {
        x: min_x,
        y: min_y,
        width: max_x - min_x,
        height: max_y - min_y,
    })
}

pub fn view_delta_to_image_delta(
    delta_x: f32,
    delta_y: f32,
    destination_rect: F32Rect,
    image_width: u32,
    image_height: u32,
) -> Option<F32Point> {
    if !delta_x.is_finite() || !delta_y.is_finite() || image_width == 0 || image_height == 0 {
        return None;
    }
    let (dst_min_x, dst_min_y, dst_max_x, dst_max_y) = standardize_rect(destination_rect)?;
    let dst_width = dst_max_x - dst_min_x;
    let dst_height = dst_max_y - dst_min_y;
    if dst_width <= 0.0 || dst_height <= 0.0 {
        return None;
    }

    let scale_x = image_width as f32 / dst_width;
    let scale_y = image_height as f32 / dst_height;
    if scale_x <= 0.0 || scale_y <= 0.0 {
        return None;
    }

    Some(F32Point {
        x: delta_x * scale_x,
        y: -delta_y * scale_y,
    })
}

pub fn image_delta_to_view_delta(
    delta_x: f32,
    delta_y: f32,
    destination_rect: F32Rect,
    image_width: u32,
    image_height: u32,
) -> Option<F32Point> {
    if !delta_x.is_finite() || !delta_y.is_finite() || image_width == 0 || image_height == 0 {
        return None;
    }
    let (dst_min_x, dst_min_y, dst_max_x, dst_max_y) = standardize_rect(destination_rect)?;
    let dst_width = dst_max_x - dst_min_x;
    let dst_height = dst_max_y - dst_min_y;
    if dst_width <= 0.0 || dst_height <= 0.0 {
        return None;
    }

    let scale_x = image_width as f32 / dst_width;
    let scale_y = image_height as f32 / dst_height;
    if scale_x <= 0.0 || scale_y <= 0.0 {
        return None;
    }

    Some(F32Point {
        x: delta_x / scale_x,
        y: -delta_y / scale_y,
    })
}

#[allow(clippy::too_many_arguments)]
pub fn viewport_clamp_pan_offset(
    bounds_width: f32,
    bounds_height: f32,
    image_width: u32,
    image_height: u32,
    zoom_scale: f32,
    overscroll: f32,
    candidate_x: f32,
    candidate_y: f32,
) -> Option<F32Point> {
    if image_width == 0
        || image_height == 0
        || !bounds_width.is_finite()
        || !bounds_height.is_finite()
        || !zoom_scale.is_finite()
        || !overscroll.is_finite()
        || !candidate_x.is_finite()
        || !candidate_y.is_finite()
    {
        return None;
    }
    if bounds_width <= 0.0 || bounds_height <= 0.0 || zoom_scale <= 0.0 {
        return None;
    }

    let image_width_f = image_width as f32;
    let image_height_f = image_height as f32;
    let fit_scale = (bounds_width / image_width_f).min(bounds_height / image_height_f);
    let draw_scale = fit_scale * zoom_scale;
    let draw_width = image_width_f * draw_scale;
    let draw_height = image_height_f * draw_scale;
    let max_x = ((draw_width - bounds_width) * 0.5 + overscroll).max(0.0);
    let max_y = ((draw_height - bounds_height) * 0.5 + overscroll).max(0.0);

    Some(F32Point {
        x: clamp_f32(candidate_x, -max_x, max_x),
        y: clamp_f32(candidate_y, -max_y, max_y),
    })
}

pub fn selection_move_rect(
    current: F32Rect,
    bounds: F32Rect,
    delta_x: f32,
    delta_y: f32,
) -> Option<(F32Rect, bool)> {
    if !delta_x.is_finite() || !delta_y.is_finite() {
        return None;
    }

    let (current_min_x, current_min_y, current_max_x, current_max_y) = standardize_rect(current)?;
    let (bounds_min_x, bounds_min_y, bounds_max_x, bounds_max_y) = standardize_rect(bounds)?;

    let width = current_max_x - current_min_x;
    let height = current_max_y - current_min_y;
    let bounds_width = bounds_max_x - bounds_min_x;
    let bounds_height = bounds_max_y - bounds_min_y;
    if width <= 0.0 || height <= 0.0 || width > bounds_width || height > bounds_height {
        return None;
    }

    let candidate_x = clamp_f32(current_min_x + delta_x, bounds_min_x, bounds_max_x - width);
    let candidate_y = clamp_f32(current_min_y + delta_y, bounds_min_y, bounds_max_y - height);
    let moved =
        (candidate_x - current_min_x).abs() > 0.01 || (candidate_y - current_min_y).abs() > 0.01;

    Some((
        F32Rect {
            x: candidate_x,
            y: candidate_y,
            width,
            height,
        },
        moved,
    ))
}

pub fn selection_resize_rect(
    start: F32Rect,
    bounds: F32Rect,
    corner: ResizeCorner,
    delta_x: f32,
    delta_y: f32,
    min_width: f32,
    min_height: f32,
) -> Option<F32Rect> {
    if !delta_x.is_finite()
        || !delta_y.is_finite()
        || !min_width.is_finite()
        || !min_height.is_finite()
        || min_width <= 0.0
        || min_height <= 0.0
    {
        return None;
    }

    let (start_min_x, start_min_y, start_max_x, start_max_y) = standardize_rect(start)?;
    let (bounds_min_x, bounds_min_y, bounds_max_x, bounds_max_y) = standardize_rect(bounds)?;

    let mut min_x = start_min_x;
    let mut max_x = start_max_x;
    let mut min_y = start_min_y;
    let mut max_y = start_max_y;

    match corner {
        ResizeCorner::TopLeft => {
            min_x += delta_x;
            max_y += delta_y;
        }
        ResizeCorner::Top => {
            max_y += delta_y;
        }
        ResizeCorner::TopRight => {
            max_x += delta_x;
            max_y += delta_y;
        }
        ResizeCorner::Right => {
            max_x += delta_x;
        }
        ResizeCorner::Bottom => {
            min_y += delta_y;
        }
        ResizeCorner::Left => {
            min_x += delta_x;
        }
        ResizeCorner::BottomLeft => {
            min_x += delta_x;
            min_y += delta_y;
        }
        ResizeCorner::BottomRight => {
            max_x += delta_x;
            min_y += delta_y;
        }
    }

    match corner {
        ResizeCorner::TopLeft => {
            min_x = min_x.min(max_x - min_width);
            max_y = max_y.max(min_y + min_height);
        }
        ResizeCorner::Top => {
            max_y = max_y.max(min_y + min_height);
        }
        ResizeCorner::TopRight => {
            max_x = max_x.max(min_x + min_width);
            max_y = max_y.max(min_y + min_height);
        }
        ResizeCorner::Right => {
            max_x = max_x.max(min_x + min_width);
        }
        ResizeCorner::Bottom => {
            min_y = min_y.min(max_y - min_height);
        }
        ResizeCorner::Left => {
            min_x = min_x.min(max_x - min_width);
        }
        ResizeCorner::BottomLeft => {
            min_x = min_x.min(max_x - min_width);
            min_y = min_y.min(max_y - min_height);
        }
        ResizeCorner::BottomRight => {
            max_x = max_x.max(min_x + min_width);
            min_y = min_y.min(max_y - min_height);
        }
    }

    min_x = min_x.max(bounds_min_x);
    max_x = max_x.min(bounds_max_x);
    min_y = min_y.max(bounds_min_y);
    max_y = max_y.min(bounds_max_y);

    let width = max_x - min_x;
    let height = max_y - min_y;
    if width < min_width || height < min_height {
        return None;
    }

    Some(F32Rect {
        x: min_x,
        y: min_y,
        width,
        height,
    })
}

pub fn quantize_image_rect(image_width: u32, image_height: u32, rect: F32Rect) -> Option<I32Rect> {
    if image_width == 0 || image_height == 0 {
        return None;
    }
    let (min_x, min_y, max_x, max_y) = standardize_rect(rect)?;

    let mut x = min_x.floor() as i32;
    let mut y = min_y.floor() as i32;
    let mut width = (max_x - min_x).ceil() as i32;
    let mut height = (max_y - min_y).ceil() as i32;
    if width <= 0 || height <= 0 {
        return None;
    }

    let max_w = image_width as i32;
    let max_h = image_height as i32;
    x = x.clamp(0, max_w - 1);
    y = y.clamp(0, max_h - 1);
    width = width.clamp(1, max_w - x);
    height = height.clamp(1, max_h - y);

    Some(I32Rect {
        x,
        y,
        width,
        height,
    })
}

pub fn quantize_image_point(
    image_width: u32,
    image_height: u32,
    x: f32,
    y: f32,
) -> Option<(i32, i32)> {
    if image_width == 0 || image_height == 0 || !x.is_finite() || !y.is_finite() {
        return None;
    }

    let max_x = image_width as i32 - 1;
    let max_y = image_height as i32 - 1;
    let px = (x.round() as i32).clamp(0, max_x);
    let py = (y.round() as i32).clamp(0, max_y);
    Some((px, py))
}

pub fn quantize_rgba(r: f32, g: f32, b: f32, a: f32) -> Option<Rgba8> {
    if !r.is_finite() || !g.is_finite() || !b.is_finite() || !a.is_finite() {
        return None;
    }

    let to_u8 = |v: f32| -> u8 { (v.clamp(0.0, 1.0) * 255.0).round() as u8 };
    Some(Rgba8 {
        r: to_u8(r),
        g: to_u8(g),
        b: to_u8(b),
        a: to_u8(a),
    })
}
