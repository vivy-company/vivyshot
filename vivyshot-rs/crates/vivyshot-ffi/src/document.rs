use super::*;

#[derive(Clone)]
enum VsCommand {
    Rect(vs_rect_command),
    FilledRect(vs_rect_command),
    Ellipse(vs_ellipse_command),
    FilledEllipse(vs_ellipse_command),
    Line(vs_line_command),
    Arrow(vs_arrow_command),
    Path {
        points: Vec<vs_point_i32>,
        style: vs_path_style,
    },
    Text {
        text: String,
        cmd: vs_text_command,
    },
    Pixelate(vs_pixelate_rect_command),
    Blur(vs_blur_rect_command),
}

unsafe fn document_from_handle_mut<'a>(doc: *mut c_void) -> Result<&'a mut vs_document, i32> {
    validate_handle(&DOCUMENT_HANDLES, doc)?;
    // SAFETY: pointer was validated by registry and originates from Box::into_raw.
    Ok(unsafe { &mut *doc.cast::<vs_document>() })
}

unsafe fn document_from_handle<'a>(doc: *const c_void) -> Result<&'a vs_document, i32> {
    validate_handle(&DOCUMENT_HANDLES, doc)?;
    // SAFETY: pointer was validated by registry and originates from Box::into_raw.
    Ok(unsafe { &*doc.cast::<vs_document>() })
}


#[derive(Clone, Copy)]
struct RectI {
    x0: i32,
    y0: i32,
    x1: i32,
    y1: i32,
}

impl RectI {
    fn width(self) -> i32 {
        self.x1.saturating_sub(self.x0)
    }

    fn height(self) -> i32 {
        self.y1.saturating_sub(self.y0)
    }

    fn is_empty(self) -> bool {
        self.x0 >= self.x1 || self.y0 >= self.y1
    }

    fn intersect(self, other: RectI) -> Option<RectI> {
        let rect = RectI {
            x0: self.x0.max(other.x0),
            y0: self.y0.max(other.y0),
            x1: self.x1.min(other.x1),
            y1: self.y1.min(other.y1),
        };
        if rect.is_empty() {
            None
        } else {
            Some(rect)
        }
    }

    fn union(self, other: RectI) -> RectI {
        RectI {
            x0: self.x0.min(other.x0),
            y0: self.y0.min(other.y0),
            x1: self.x1.max(other.x1),
            y1: self.y1.max(other.y1),
        }
    }

    fn clamp_to_image(self, width: i32, height: i32) -> Option<RectI> {
        self.intersect(RectI {
            x0: 0,
            y0: 0,
            x1: width,
            y1: height,
        })
    }

    fn to_ffi(self) -> vs_dirty_rect {
        vs_dirty_rect {
            x: self.x0,
            y: self.y0,
            width: self.width(),
            height: self.height(),
        }
    }
}

#[repr(C)]
pub struct vs_document {
    width: u32,
    height: u32,
    stride: u32,
    base: Vec<u8>,
    commands: Vec<VsCommand>,
    cursor: usize,
    pending_dirty: Option<RectI>,
}

impl vs_document {
    fn expected_len(&self) -> Option<usize> {
        (self.stride as usize).checked_mul(self.height as usize)
    }

    fn image_width_i32(&self) -> i32 {
        self.width as i32
    }

    fn image_height_i32(&self) -> i32 {
        self.height as i32
    }

    fn full_image_rect(&self) -> RectI {
        RectI {
            x0: 0,
            y0: 0,
            x1: self.image_width_i32(),
            y1: self.image_height_i32(),
        }
    }

    fn applied_commands(&self) -> &[VsCommand] {
        let end = self.cursor.min(self.commands.len());
        &self.commands[..end]
    }

    fn has_global_effect_command(&self) -> bool {
        self.applied_commands().iter().any(is_global_effect_command)
    }

    fn add_dirty_full(&mut self) {
        let full = self.full_image_rect();
        self.pending_dirty = Some(match self.pending_dirty {
            Some(prev) => prev.union(full),
            None => full,
        });
    }

    fn add_dirty(&mut self, rect: Option<RectI>) {
        let Some(rect) = rect else {
            return;
        };

        let Some(clamped) = rect.clamp_to_image(self.image_width_i32(), self.image_height_i32())
        else {
            return;
        };

        let merged = match self.pending_dirty {
            Some(prev) => prev.union(clamped),
            None => clamped,
        };

        self.pending_dirty = Some(merged);

        if self.has_global_effect_command() {
            self.pending_dirty = Some(self.full_image_rect());
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn vs_create_document_from_bgra(
    width: u32,
    height: u32,
    stride: u32,
    ptr: *const u8,
    len: usize,
) -> *mut c_void {
    if width == 0 || height == 0 {
        return std::ptr::null_mut();
    }

    let min_stride = width.saturating_mul(4);
    if stride < min_stride {
        return std::ptr::null_mut();
    }

    if ptr.is_null() {
        return std::ptr::null_mut();
    }

    let expected_len = match (stride as usize).checked_mul(height as usize) {
        Some(v) => v,
        None => return std::ptr::null_mut(),
    };

    if len < expected_len {
        return std::ptr::null_mut();
    }

    // SAFETY: `ptr` is non-null and `len >= expected_len` has been validated above.
    let src = unsafe { slice::from_raw_parts(ptr, expected_len) };
    let doc = vs_document {
        width,
        height,
        stride,
        base: src.to_vec(),
        commands: Vec::new(),
        cursor: 0,
        pending_dirty: None,
    };

    let handle = Box::into_raw(Box::new(doc)).cast();
    register_handle(&DOCUMENT_HANDLES, handle);
    handle
}

#[no_mangle]
pub unsafe extern "C" fn vs_destroy_document(doc: *mut c_void) {
    if !unregister_handle(&DOCUMENT_HANDLES, doc) {
        return;
    }

    // SAFETY: `doc` came from `Box::into_raw` in `vs_create_document_from_bgra`.
    unsafe {
        drop(Box::from_raw(doc.cast::<vs_document>()));
    }
}

#[no_mangle]
pub unsafe extern "C" fn vs_add_rect(doc: *mut c_void, cmd: vs_rect_command) -> i32 {
    let doc = match unsafe { document_from_handle_mut(doc) } {
        Ok(v) => v,
        Err(code) => return code,
    };

    let Some(bounds) = rect_command_bounds(cmd) else {
        return -2;
    };

    if doc.cursor < doc.commands.len() {
        doc.commands.truncate(doc.cursor);
    }

    doc.commands.push(VsCommand::Rect(cmd));
    doc.cursor = doc.commands.len();
    doc.add_dirty(Some(bounds));

    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_add_filled_rect(doc: *mut c_void, cmd: vs_rect_command) -> i32 {
    let doc = match unsafe { document_from_handle_mut(doc) } {
        Ok(v) => v,
        Err(code) => return code,
    };

    let Some(bounds) = rect_command_bounds(cmd) else {
        return -2;
    };

    if doc.cursor < doc.commands.len() {
        doc.commands.truncate(doc.cursor);
    }

    doc.commands.push(VsCommand::FilledRect(cmd));
    doc.cursor = doc.commands.len();
    doc.add_dirty(Some(bounds));
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_add_ellipse(doc: *mut c_void, cmd: vs_ellipse_command) -> i32 {
    let doc = match unsafe { document_from_handle_mut(doc) } {
        Ok(v) => v,
        Err(code) => return code,
    };

    let Some(bounds) = ellipse_command_bounds(cmd) else {
        return -2;
    };

    if doc.cursor < doc.commands.len() {
        doc.commands.truncate(doc.cursor);
    }

    doc.commands.push(VsCommand::Ellipse(cmd));
    doc.cursor = doc.commands.len();
    doc.add_dirty(Some(bounds));
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_add_filled_ellipse(doc: *mut c_void, cmd: vs_ellipse_command) -> i32 {
    let doc = match unsafe { document_from_handle_mut(doc) } {
        Ok(v) => v,
        Err(code) => return code,
    };

    let Some(bounds) = ellipse_command_bounds(cmd) else {
        return -2;
    };

    if doc.cursor < doc.commands.len() {
        doc.commands.truncate(doc.cursor);
    }

    doc.commands.push(VsCommand::FilledEllipse(cmd));
    doc.cursor = doc.commands.len();
    doc.add_dirty(Some(bounds));
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_add_line(doc: *mut c_void, cmd: vs_line_command) -> i32 {
    let doc = match unsafe { document_from_handle_mut(doc) } {
        Ok(v) => v,
        Err(code) => return code,
    };

    let Some(bounds) = line_command_bounds(cmd) else {
        return -2;
    };

    if doc.cursor < doc.commands.len() {
        doc.commands.truncate(doc.cursor);
    }

    doc.commands.push(VsCommand::Line(cmd));
    doc.cursor = doc.commands.len();
    doc.add_dirty(Some(bounds));
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_add_path(
    doc: *mut c_void,
    points_ptr: *const vs_point_i32,
    points_len: usize,
    style: vs_path_style,
) -> i32 {
    let doc = match unsafe { document_from_handle_mut(doc) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    if points_ptr.is_null() || points_len == 0 {
        return -2;
    }

    // SAFETY: pointer and length validated above.
    let points = unsafe { slice::from_raw_parts(points_ptr, points_len) };
    let Some(bounds) = path_command_bounds(points, style) else {
        return -3;
    };

    if doc.cursor < doc.commands.len() {
        doc.commands.truncate(doc.cursor);
    }

    doc.commands.push(VsCommand::Path {
        points: points.to_vec(),
        style,
    });
    doc.cursor = doc.commands.len();
    doc.add_dirty(Some(bounds));
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_add_arrow(doc: *mut c_void, cmd: vs_arrow_command) -> i32 {
    let doc = match unsafe { document_from_handle_mut(doc) } {
        Ok(v) => v,
        Err(code) => return code,
    };

    let Some(bounds) = arrow_command_bounds(cmd) else {
        return -2;
    };

    if doc.cursor < doc.commands.len() {
        doc.commands.truncate(doc.cursor);
    }

    doc.commands.push(VsCommand::Arrow(cmd));
    doc.cursor = doc.commands.len();
    doc.add_dirty(Some(bounds));
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_add_text(
    doc: *mut c_void,
    text_ptr: *const u8,
    text_len: usize,
    cmd: vs_text_command,
) -> i32 {
    let doc = match unsafe { document_from_handle_mut(doc) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    if text_ptr.is_null() || text_len == 0 {
        return -2;
    }

    // SAFETY: pointer and length validated above.
    let text_bytes = unsafe { slice::from_raw_parts(text_ptr, text_len) };
    let text = match std::str::from_utf8(text_bytes) {
        Ok(v) => v.trim().to_string(),
        Err(_) => return -3,
    };

    if text.is_empty() {
        return -4;
    }

    let Some(bounds) = text_command_bounds(&text, cmd) else {
        return -5;
    };

    if doc.cursor < doc.commands.len() {
        doc.commands.truncate(doc.cursor);
    }

    doc.commands.push(VsCommand::Text { text, cmd });
    doc.cursor = doc.commands.len();
    doc.add_dirty(Some(bounds));
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_add_pixelate_rect(
    doc: *mut c_void,
    cmd: vs_pixelate_rect_command,
) -> i32 {
    let doc = match unsafe { document_from_handle_mut(doc) } {
        Ok(v) => v,
        Err(code) => return code,
    };

    let Some(bounds) = effect_rect_bounds(cmd.x, cmd.y, cmd.width, cmd.height) else {
        return -2;
    };

    if doc.cursor < doc.commands.len() {
        doc.commands.truncate(doc.cursor);
    }

    doc.commands.push(VsCommand::Pixelate(cmd));
    doc.cursor = doc.commands.len();
    doc.add_dirty(Some(bounds));
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_add_blur_rect(doc: *mut c_void, cmd: vs_blur_rect_command) -> i32 {
    let doc = match unsafe { document_from_handle_mut(doc) } {
        Ok(v) => v,
        Err(code) => return code,
    };

    let Some(bounds) = effect_rect_bounds(cmd.x, cmd.y, cmd.width, cmd.height) else {
        return -2;
    };

    if doc.cursor < doc.commands.len() {
        doc.commands.truncate(doc.cursor);
    }

    doc.commands.push(VsCommand::Blur(cmd));
    doc.cursor = doc.commands.len();
    doc.add_dirty(Some(bounds));
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_undo(doc: *mut c_void) -> i32 {
    let doc = match unsafe { document_from_handle_mut(doc) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    if doc.cursor == 0 {
        return 1;
    }

    let (undone_global, undone_bounds) = {
        let cmd = &doc.commands[doc.cursor - 1];
        (is_global_effect_command(cmd), command_bounds(cmd))
    };
    doc.cursor -= 1;
    if undone_global {
        doc.add_dirty_full();
    } else {
        doc.add_dirty(undone_bounds);
    }
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_redo(doc: *mut c_void) -> i32 {
    let doc = match unsafe { document_from_handle_mut(doc) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    if doc.cursor >= doc.commands.len() {
        return 1;
    }

    let (redone_global, redone_bounds) = {
        let cmd = &doc.commands[doc.cursor];
        (is_global_effect_command(cmd), command_bounds(cmd))
    };
    doc.cursor += 1;
    if redone_global {
        doc.add_dirty_full();
    } else {
        doc.add_dirty(redone_bounds);
    }
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_list_annotations(
    doc: *mut c_void,
    out_ptr: *mut vs_annotation_info,
    out_cap: usize,
    out_written_ptr: *mut usize,
) -> i32 {
    if out_written_ptr.is_null() {
        return -1;
    }

    if out_cap > 0 && out_ptr.is_null() {
        return -2;
    }

    let doc = match unsafe { document_from_handle(doc) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    let image_w = doc.image_width_i32();
    let image_h = doc.image_height_i32();

    let mut total: usize = 0;
    let mut written: usize = 0;
    for (index, cmd) in doc.applied_commands().iter().enumerate() {
        let Some(bounds) = command_bounds(cmd) else {
            continue;
        };
        let Some(clamped) = bounds.clamp_to_image(image_w, image_h) else {
            continue;
        };

        if written < out_cap {
            // SAFETY: `out_ptr` is non-null if `out_cap > 0`, guaranteed above.
            unsafe {
                *out_ptr.add(written) = vs_annotation_info {
                    index: index as u32,
                    kind: annotation_kind(cmd),
                    x: clamped.x0,
                    y: clamped.y0,
                    width: clamped.width(),
                    height: clamped.height(),
                };
            }
            written += 1;
        }

        total += 1;
    }

    // SAFETY: `out_written_ptr` nullability checked above.
    unsafe {
        *out_written_ptr = total;
    }
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_move_annotation(doc: *mut c_void, index: u32, dx: i32, dy: i32) -> i32 {
    if dx == 0 && dy == 0 {
        return 1;
    }

    let doc = match unsafe { document_from_handle_mut(doc) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    let Some(idx) = ffi_document::validate_annotation_index(index, doc.commands.len()) else {
        return -2;
    };
    if idx >= doc.cursor {
        return -2;
    }

    let (was_global, old_bounds) = {
        let cmd = &doc.commands[idx];
        (is_global_effect_command(cmd), command_bounds(cmd))
    };

    {
        let cmd = &mut doc.commands[idx];
        translate_command(cmd, dx, dy);
    }

    let new_bounds = {
        let cmd = &doc.commands[idx];
        command_bounds(cmd)
    };

    if was_global {
        doc.add_dirty_full();
    } else {
        doc.add_dirty(old_bounds);
        doc.add_dirty(new_bounds);
    }

    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_remove_annotation(doc: *mut c_void, index: u32) -> i32 {
    let doc = match unsafe { document_from_handle_mut(doc) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    let Some(idx) = ffi_document::validate_annotation_index(index, doc.commands.len()) else {
        return -2;
    };
    if idx >= doc.cursor {
        return -2;
    }

    let (was_global, old_bounds) = {
        let cmd = &doc.commands[idx];
        (is_global_effect_command(cmd), command_bounds(cmd))
    };

    doc.commands.remove(idx);
    doc.cursor = doc.cursor.saturating_sub(1);

    if was_global {
        doc.add_dirty_full();
    } else {
        doc.add_dirty(old_bounds);
    }

    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_resize_annotation(
    doc: *mut c_void,
    index: u32,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
) -> i32 {
    if width <= 0 || height <= 0 {
        return -2;
    }

    let target = RectI {
        x0: x,
        y0: y,
        x1: x.saturating_add(width),
        y1: y.saturating_add(height),
    };
    if target.is_empty() {
        return -2;
    }

    let doc = match unsafe { document_from_handle_mut(doc) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    let Some(idx) = ffi_document::validate_annotation_index(index, doc.commands.len()) else {
        return -3;
    };
    if idx >= doc.cursor {
        return -3;
    }

    let (was_global, old_bounds) = {
        let cmd = &doc.commands[idx];
        (is_global_effect_command(cmd), command_bounds(cmd))
    };
    let Some(old_bounds) = old_bounds else {
        return -4;
    };

    let changed = {
        let cmd = &mut doc.commands[idx];
        resize_command(cmd, old_bounds, target)
    };
    if !changed {
        return 1;
    }

    let new_bounds = {
        let cmd = &doc.commands[idx];
        command_bounds(cmd)
    };

    if was_global {
        doc.add_dirty_full();
    } else {
        doc.add_dirty(Some(old_bounds));
        doc.add_dirty(new_bounds);
    }

    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_copy_annotations_affine(
    dst_doc: *mut c_void,
    src_doc: *const c_void,
    scale_x: f32,
    scale_y: f32,
    translate_x: f32,
    translate_y: f32,
) -> i32 {
    if !scale_x.is_finite()
        || !scale_y.is_finite()
        || !translate_x.is_finite()
        || !translate_y.is_finite()
        || scale_x.abs() < f32::EPSILON
        || scale_y.abs() < f32::EPSILON
    {
        return -2;
    }

    if std::ptr::eq(dst_doc.cast::<c_void>(), src_doc) {
        return -3;
    }

    let src = match unsafe { document_from_handle(src_doc) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    let dst = match unsafe { document_from_handle_mut(dst_doc) } {
        Ok(v) => v,
        Err(code) => return code,
    };

    if dst.cursor < dst.commands.len() {
        dst.commands.truncate(dst.cursor);
    }
    dst.commands.clear();
    dst.cursor = 0;

    if src.applied_commands().is_empty() {
        return 0;
    }

    let mut copied = Vec::with_capacity(src.applied_commands().len());
    for cmd in src.applied_commands() {
        let mut next = cmd.clone();
        transform_command_affine(&mut next, scale_x, scale_y, translate_x, translate_y);
        copied.push(next);
    }

    dst.commands = copied;
    dst.cursor = dst.commands.len();
    dst.add_dirty_full();
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_render_full(doc: *mut c_void, out_ptr: *mut u8, out_len: usize) -> i32 {
    if out_ptr.is_null() {
        return -1;
    }

    let doc = match unsafe { document_from_handle_mut(doc) } {
        Ok(v) => v,
        Err(code) => return code,
    };

    let Some(expected_len) = doc.expected_len() else {
        return -2;
    };

    if out_len < expected_len {
        return -3;
    }

    // SAFETY: `out_ptr` is non-null and `out_len >= expected_len` has been validated above.
    let out = unsafe { slice::from_raw_parts_mut(out_ptr, expected_len) };
    out.copy_from_slice(&doc.base);

    for cmd in doc.applied_commands() {
        draw_command(
            out,
            doc.image_width_i32(),
            doc.image_height_i32(),
            doc.stride as usize,
            cmd,
            None,
        );
    }

    doc.pending_dirty = None;
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_render_dirty(
    doc: *mut c_void,
    out_ptr: *mut u8,
    out_len: usize,
    dirty_rects_ptr: *mut vs_dirty_rect,
    dirty_rects_cap: usize,
    dirty_rects_written_ptr: *mut usize,
) -> i32 {
    if out_ptr.is_null() || dirty_rects_written_ptr.is_null() {
        return -1;
    }

    if dirty_rects_cap > 0 && dirty_rects_ptr.is_null() {
        return -2;
    }

    let doc = match unsafe { document_from_handle_mut(doc) } {
        Ok(v) => v,
        Err(code) => return code,
    };

    // SAFETY: `dirty_rects_written_ptr` nullability is checked above.
    unsafe {
        *dirty_rects_written_ptr = 0;
    }

    let Some(expected_len) = doc.expected_len() else {
        return -3;
    };

    if out_len < expected_len {
        return -4;
    }

    let Some(dirty) = doc.pending_dirty else {
        return 0;
    };

    // SAFETY: `out_ptr` is non-null and `out_len >= expected_len` has been validated above.
    let out = unsafe { slice::from_raw_parts_mut(out_ptr, expected_len) };

    restore_region(&doc.base, out, doc.stride as usize, dirty);

    for cmd in doc.applied_commands() {
        if let Some(bounds) = command_bounds(cmd) {
            if bounds.intersect(dirty).is_none() {
                continue;
            }
        }

        draw_command(
            out,
            doc.image_width_i32(),
            doc.image_height_i32(),
            doc.stride as usize,
            cmd,
            Some(dirty),
        );
    }

    if dirty_rects_cap > 0 {
        // SAFETY: pointers and capacity validated above.
        unsafe {
            *dirty_rects_ptr = dirty.to_ffi();
            *dirty_rects_written_ptr = 1;
        }
    }

    doc.pending_dirty = None;
    0
}

fn draw_command(
    buf: &mut [u8],
    image_width: i32,
    image_height: i32,
    stride: usize,
    cmd: &VsCommand,
    clip: Option<RectI>,
) {
    match cmd {
        VsCommand::Rect(rect) => {
            draw_rect(buf, image_width, image_height, stride, *rect, false, clip)
        }
        VsCommand::FilledRect(rect) => {
            draw_rect(buf, image_width, image_height, stride, *rect, true, clip)
        }
        VsCommand::Ellipse(cmd) => {
            draw_ellipse(buf, image_width, image_height, stride, *cmd, false, clip)
        }
        VsCommand::FilledEllipse(cmd) => {
            draw_ellipse(buf, image_width, image_height, stride, *cmd, true, clip)
        }
        VsCommand::Line(line) => draw_line(buf, image_width, image_height, stride, *line, clip),
        VsCommand::Arrow(arrow) => draw_arrow(buf, image_width, image_height, stride, *arrow, clip),
        VsCommand::Path { points, style } => {
            draw_path(buf, image_width, image_height, stride, points, *style, clip)
        }
        VsCommand::Text { text, cmd } => {
            draw_text(buf, image_width, image_height, stride, text, *cmd, clip)
        }
        VsCommand::Pixelate(cmd) => {
            draw_pixelate(buf, image_width, image_height, stride, *cmd, clip)
        }
        VsCommand::Blur(cmd) => draw_blur(buf, image_width, image_height, stride, *cmd, clip),
    }
}

fn command_bounds(cmd: &VsCommand) -> Option<RectI> {
    match cmd {
        VsCommand::Rect(rect) => rect_command_bounds(*rect),
        VsCommand::FilledRect(rect) => rect_command_bounds(*rect),
        VsCommand::Ellipse(cmd) => ellipse_command_bounds(*cmd),
        VsCommand::FilledEllipse(cmd) => ellipse_command_bounds(*cmd),
        VsCommand::Line(line) => line_command_bounds(*line),
        VsCommand::Arrow(arrow) => arrow_command_bounds(*arrow),
        VsCommand::Path { points, style } => path_command_bounds(points, *style),
        VsCommand::Text { text, cmd } => text_command_bounds(text, *cmd),
        VsCommand::Pixelate(cmd) => effect_rect_bounds(cmd.x, cmd.y, cmd.width, cmd.height),
        VsCommand::Blur(cmd) => effect_rect_bounds(cmd.x, cmd.y, cmd.width, cmd.height),
    }
}

fn annotation_kind(cmd: &VsCommand) -> u32 {
    match cmd {
        VsCommand::Rect(_) => 1,
        VsCommand::FilledRect(_) => 2,
        VsCommand::Ellipse(_) => 3,
        VsCommand::FilledEllipse(_) => 4,
        VsCommand::Line(_) => 5,
        VsCommand::Arrow(_) => 6,
        VsCommand::Path { .. } => 7,
        VsCommand::Text { .. } => 8,
        VsCommand::Pixelate(_) => 9,
        VsCommand::Blur(_) => 10,
    }
}

fn translate_command(cmd: &mut VsCommand, dx: i32, dy: i32) {
    match cmd {
        VsCommand::Rect(rect) => {
            rect.x = rect.x.saturating_add(dx);
            rect.y = rect.y.saturating_add(dy);
        }
        VsCommand::FilledRect(rect) => {
            rect.x = rect.x.saturating_add(dx);
            rect.y = rect.y.saturating_add(dy);
        }
        VsCommand::Ellipse(ellipse) => {
            ellipse.x = ellipse.x.saturating_add(dx);
            ellipse.y = ellipse.y.saturating_add(dy);
        }
        VsCommand::FilledEllipse(ellipse) => {
            ellipse.x = ellipse.x.saturating_add(dx);
            ellipse.y = ellipse.y.saturating_add(dy);
        }
        VsCommand::Line(line) => {
            line.x0 = line.x0.saturating_add(dx);
            line.y0 = line.y0.saturating_add(dy);
            line.x1 = line.x1.saturating_add(dx);
            line.y1 = line.y1.saturating_add(dy);
        }
        VsCommand::Arrow(arrow) => {
            arrow.x0 = arrow.x0.saturating_add(dx);
            arrow.y0 = arrow.y0.saturating_add(dy);
            arrow.x1 = arrow.x1.saturating_add(dx);
            arrow.y1 = arrow.y1.saturating_add(dy);
        }
        VsCommand::Path { points, .. } => {
            for point in points.iter_mut() {
                point.x = point.x.saturating_add(dx);
                point.y = point.y.saturating_add(dy);
            }
        }
        VsCommand::Text { cmd, .. } => {
            cmd.x = cmd.x.saturating_add(dx);
            cmd.y = cmd.y.saturating_add(dy);
        }
        VsCommand::Pixelate(pixelate) => {
            pixelate.x = pixelate.x.saturating_add(dx);
            pixelate.y = pixelate.y.saturating_add(dy);
        }
        VsCommand::Blur(blur) => {
            blur.x = blur.x.saturating_add(dx);
            blur.y = blur.y.saturating_add(dy);
        }
    }
}

fn round_to_i32(value: f32) -> i32 {
    if !value.is_finite() {
        return 0;
    }

    if value >= i32::MAX as f32 {
        i32::MAX
    } else if value <= i32::MIN as f32 {
        i32::MIN
    } else {
        value.round() as i32
    }
}

fn transform_rect_affine(
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    scale_x: f32,
    scale_y: f32,
    translate_x: f32,
    translate_y: f32,
) -> (i32, i32, i32, i32) {
    let x0 = x as f32 * scale_x + translate_x;
    let y0 = y as f32 * scale_y + translate_y;
    let x1 = x.saturating_add(width) as f32 * scale_x + translate_x;
    let y1 = y.saturating_add(height) as f32 * scale_y + translate_y;

    let left = round_to_i32(x0.min(x1));
    let top = round_to_i32(y0.min(y1));
    let right = round_to_i32(x0.max(x1));
    let bottom = round_to_i32(y0.max(y1));

    let next_width = right.saturating_sub(left).max(1);
    let next_height = bottom.saturating_sub(top).max(1);
    (left, top, next_width, next_height)
}

fn transform_point_affine(
    x: i32,
    y: i32,
    scale_x: f32,
    scale_y: f32,
    translate_x: f32,
    translate_y: f32,
) -> (i32, i32) {
    (
        round_to_i32(x as f32 * scale_x + translate_x),
        round_to_i32(y as f32 * scale_y + translate_y),
    )
}

fn transform_command_affine(
    cmd: &mut VsCommand,
    scale_x: f32,
    scale_y: f32,
    translate_x: f32,
    translate_y: f32,
) {
    match cmd {
        VsCommand::Rect(rect) | VsCommand::FilledRect(rect) => {
            let (x, y, width, height) = transform_rect_affine(
                rect.x,
                rect.y,
                rect.width,
                rect.height,
                scale_x,
                scale_y,
                translate_x,
                translate_y,
            );
            rect.x = x;
            rect.y = y;
            rect.width = width;
            rect.height = height;
        }
        VsCommand::Ellipse(ellipse) | VsCommand::FilledEllipse(ellipse) => {
            let (x, y, width, height) = transform_rect_affine(
                ellipse.x,
                ellipse.y,
                ellipse.width,
                ellipse.height,
                scale_x,
                scale_y,
                translate_x,
                translate_y,
            );
            ellipse.x = x;
            ellipse.y = y;
            ellipse.width = width;
            ellipse.height = height;
        }
        VsCommand::Line(line) => {
            let (x0, y0) = transform_point_affine(
                line.x0,
                line.y0,
                scale_x,
                scale_y,
                translate_x,
                translate_y,
            );
            let (x1, y1) = transform_point_affine(
                line.x1,
                line.y1,
                scale_x,
                scale_y,
                translate_x,
                translate_y,
            );
            line.x0 = x0;
            line.y0 = y0;
            line.x1 = x1;
            line.y1 = y1;
        }
        VsCommand::Arrow(arrow) => {
            let (x0, y0) = transform_point_affine(
                arrow.x0,
                arrow.y0,
                scale_x,
                scale_y,
                translate_x,
                translate_y,
            );
            let (x1, y1) = transform_point_affine(
                arrow.x1,
                arrow.y1,
                scale_x,
                scale_y,
                translate_x,
                translate_y,
            );
            arrow.x0 = x0;
            arrow.y0 = y0;
            arrow.x1 = x1;
            arrow.y1 = y1;
        }
        VsCommand::Path { points, .. } => {
            for point in points.iter_mut() {
                let (x, y) = transform_point_affine(
                    point.x,
                    point.y,
                    scale_x,
                    scale_y,
                    translate_x,
                    translate_y,
                );
                point.x = x;
                point.y = y;
            }
        }
        VsCommand::Text { cmd: text_cmd, .. } => {
            let (x, y) = transform_point_affine(
                text_cmd.x,
                text_cmd.y,
                scale_x,
                scale_y,
                translate_x,
                translate_y,
            );
            text_cmd.x = x;
            text_cmd.y = y;

            let avg_scale = ((scale_x.abs() + scale_y.abs()) * 0.5).clamp(0.25, 8.0);
            text_cmd.font_px = ((text_cmd.font_px as f32) * avg_scale)
                .round()
                .clamp(8.0, 256.0) as u32;
        }
        VsCommand::Pixelate(pixelate) => {
            let (x, y, width, height) = transform_rect_affine(
                pixelate.x,
                pixelate.y,
                pixelate.width,
                pixelate.height,
                scale_x,
                scale_y,
                translate_x,
                translate_y,
            );
            pixelate.x = x;
            pixelate.y = y;
            pixelate.width = width;
            pixelate.height = height;
        }
        VsCommand::Blur(blur) => {
            let (x, y, width, height) = transform_rect_affine(
                blur.x,
                blur.y,
                blur.width,
                blur.height,
                scale_x,
                scale_y,
                translate_x,
                translate_y,
            );
            blur.x = x;
            blur.y = y;
            blur.width = width;
            blur.height = height;
        }
    }
}

fn resize_command(cmd: &mut VsCommand, from: RectI, to: RectI) -> bool {
    if from.is_empty() || to.is_empty() {
        return false;
    }

    match cmd {
        VsCommand::Rect(rect) | VsCommand::FilledRect(rect) => {
            let next = rect_from_bounds(*rect, to);
            if rect_equals(*rect, next) {
                return false;
            }
            *rect = next;
            true
        }
        VsCommand::Ellipse(ellipse) | VsCommand::FilledEllipse(ellipse) => {
            let next = ellipse_from_bounds(*ellipse, to);
            if ellipse_equals(*ellipse, next) {
                return false;
            }
            *ellipse = next;
            true
        }
        VsCommand::Line(line) => {
            let (x0, y0) = scale_point_between_rects(line.x0, line.y0, from, to);
            let (x1, y1) = scale_point_between_rects(line.x1, line.y1, from, to);
            if line.x0 == x0 && line.y0 == y0 && line.x1 == x1 && line.y1 == y1 {
                return false;
            }
            line.x0 = x0;
            line.y0 = y0;
            line.x1 = x1;
            line.y1 = y1;
            true
        }
        VsCommand::Arrow(arrow) => {
            let (x0, y0) = scale_point_between_rects(arrow.x0, arrow.y0, from, to);
            let (x1, y1) = scale_point_between_rects(arrow.x1, arrow.y1, from, to);
            if arrow.x0 == x0 && arrow.y0 == y0 && arrow.x1 == x1 && arrow.y1 == y1 {
                return false;
            }
            arrow.x0 = x0;
            arrow.y0 = y0;
            arrow.x1 = x1;
            arrow.y1 = y1;
            true
        }
        VsCommand::Path { points, .. } => {
            if points.is_empty() {
                return false;
            }

            let mut changed = false;
            for point in points.iter_mut() {
                let (nx, ny) = scale_point_between_rects(point.x, point.y, from, to);
                if point.x != nx || point.y != ny {
                    point.x = nx;
                    point.y = ny;
                    changed = true;
                }
            }
            changed
        }
        VsCommand::Text { cmd: text_cmd, .. } => {
            let old_w = from.width().max(1) as f32;
            let old_h = from.height().max(1) as f32;
            let new_w = to.width().max(1) as f32;
            let new_h = to.height().max(1) as f32;
            let scale = ((new_w / old_w) + (new_h / old_h)) * 0.5;
            let font_px = ((text_cmd.font_px as f32) * scale)
                .round()
                .clamp(8.0, 256.0) as u32;

            if text_cmd.x == to.x0 && text_cmd.y == to.y0 && text_cmd.font_px == font_px {
                return false;
            }

            text_cmd.x = to.x0;
            text_cmd.y = to.y0;
            text_cmd.font_px = font_px;
            true
        }
        VsCommand::Pixelate(pixelate) => {
            let width = to.width().max(1);
            let height = to.height().max(1);
            if pixelate.x == to.x0
                && pixelate.y == to.y0
                && pixelate.width == width
                && pixelate.height == height
            {
                return false;
            }
            pixelate.x = to.x0;
            pixelate.y = to.y0;
            pixelate.width = width;
            pixelate.height = height;
            true
        }
        VsCommand::Blur(blur) => {
            let width = to.width().max(1);
            let height = to.height().max(1);
            if blur.x == to.x0 && blur.y == to.y0 && blur.width == width && blur.height == height {
                return false;
            }
            blur.x = to.x0;
            blur.y = to.y0;
            blur.width = width;
            blur.height = height;
            true
        }
    }
}

fn rect_from_bounds(prev: vs_rect_command, bounds: RectI) -> vs_rect_command {
    let width = bounds.width().max(1);
    let height = bounds.height().max(1);
    vs_rect_command {
        x: bounds.x0,
        y: bounds.y0,
        width,
        height,
        ..prev
    }
}

fn ellipse_from_bounds(prev: vs_ellipse_command, bounds: RectI) -> vs_ellipse_command {
    let width = bounds.width().max(1);
    let height = bounds.height().max(1);
    vs_ellipse_command {
        x: bounds.x0,
        y: bounds.y0,
        width,
        height,
        ..prev
    }
}

fn rect_equals(lhs: vs_rect_command, rhs: vs_rect_command) -> bool {
    lhs.x == rhs.x && lhs.y == rhs.y && lhs.width == rhs.width && lhs.height == rhs.height
}

fn ellipse_equals(lhs: vs_ellipse_command, rhs: vs_ellipse_command) -> bool {
    lhs.x == rhs.x && lhs.y == rhs.y && lhs.width == rhs.width && lhs.height == rhs.height
}

fn scale_point_between_rects(px: i32, py: i32, from: RectI, to: RectI) -> (i32, i32) {
    let from_w = from.width().max(1) as f32;
    let from_h = from.height().max(1) as f32;
    let to_w = to.width().max(1) as f32;
    let to_h = to.height().max(1) as f32;

    let nx = (px.saturating_sub(from.x0) as f32) / from_w;
    let ny = (py.saturating_sub(from.y0) as f32) / from_h;

    let x = to.x0 as f32 + nx * to_w;
    let y = to.y0 as f32 + ny * to_h;
    (x.round() as i32, y.round() as i32)
}

fn is_global_effect_command(cmd: &VsCommand) -> bool {
    matches!(cmd, VsCommand::Pixelate(_) | VsCommand::Blur(_))
}

fn rect_command_bounds(cmd: vs_rect_command) -> Option<RectI> {
    if cmd.width <= 0 || cmd.height <= 0 {
        return None;
    }

    Some(RectI {
        x0: cmd.x,
        y0: cmd.y,
        x1: cmd.x.saturating_add(cmd.width),
        y1: cmd.y.saturating_add(cmd.height),
    })
}

fn ellipse_command_bounds(cmd: vs_ellipse_command) -> Option<RectI> {
    if cmd.width <= 0 || cmd.height <= 0 {
        return None;
    }

    Some(RectI {
        x0: cmd.x,
        y0: cmd.y,
        x1: cmd.x.saturating_add(cmd.width),
        y1: cmd.y.saturating_add(cmd.height),
    })
}

fn line_command_bounds(cmd: vs_line_command) -> Option<RectI> {
    if cmd.x0 == cmd.x1 && cmd.y0 == cmd.y1 {
        return None;
    }

    let pad = ((cmd.stroke_width as i32).max(1) + 1) / 2 + 1;
    Some(RectI {
        x0: cmd.x0.min(cmd.x1).saturating_sub(pad),
        y0: cmd.y0.min(cmd.y1).saturating_sub(pad),
        x1: cmd.x0.max(cmd.x1).saturating_add(pad + 1),
        y1: cmd.y0.max(cmd.y1).saturating_add(pad + 1),
    })
}

fn path_command_bounds(points: &[vs_point_i32], style: vs_path_style) -> Option<RectI> {
    let first = points.first()?;

    let mut min_x = first.x;
    let mut min_y = first.y;
    let mut max_x = first.x;
    let mut max_y = first.y;

    for point in &points[1..] {
        min_x = min_x.min(point.x);
        min_y = min_y.min(point.y);
        max_x = max_x.max(point.x);
        max_y = max_y.max(point.y);
    }

    let pad = ((style.stroke_width as i32).max(1) + 1) / 2 + 2;
    Some(RectI {
        x0: min_x.saturating_sub(pad),
        y0: min_y.saturating_sub(pad),
        x1: max_x.saturating_add(pad + 1),
        y1: max_y.saturating_add(pad + 1),
    })
}

fn arrow_command_bounds(cmd: vs_arrow_command) -> Option<RectI> {
    if cmd.x0 == cmd.x1 && cmd.y0 == cmd.y1 {
        return None;
    }

    let stroke = (cmd.stroke_width as i32).max(1);
    let head_len = (stroke * 6).max(16);
    let pad = head_len + stroke;
    Some(RectI {
        x0: cmd.x0.min(cmd.x1).saturating_sub(pad),
        y0: cmd.y0.min(cmd.y1).saturating_sub(pad),
        x1: cmd.x0.max(cmd.x1).saturating_add(pad + 1),
        y1: cmd.y0.max(cmd.y1).saturating_add(pad + 1),
    })
}

fn effect_rect_bounds(x: i32, y: i32, width: i32, height: i32) -> Option<RectI> {
    if width <= 0 || height <= 0 {
        return None;
    }
    Some(RectI {
        x0: x,
        y0: y,
        x1: x.saturating_add(width),
        y1: y.saturating_add(height),
    })
}

fn system_fonts() -> Option<&'static Vec<fontdue::Font>> {
    let fonts = SYSTEM_FONTS.get_or_init(load_system_fonts);
    if fonts.is_empty() {
        None
    } else {
        Some(fonts)
    }
}

fn load_system_fonts() -> Vec<fontdue::Font> {
    const DEFAULT_MAX_FONT_BYTES: u64 = 8 * 1024 * 1024;
    const DEFAULT_MAX_FONTS: usize = 1;

    let max_font_bytes = std::env::var("VIVYSHOT_MAX_SYSTEM_FONT_BYTES")
        .ok()
        .and_then(|value| value.parse::<u64>().ok())
        .filter(|value| *value > 0)
        .unwrap_or(DEFAULT_MAX_FONT_BYTES);
    let max_fonts = std::env::var("VIVYSHOT_MAX_SYSTEM_FONTS")
        .ok()
        .and_then(|value| value.parse::<usize>().ok())
        .filter(|value| *value > 0)
        .unwrap_or(DEFAULT_MAX_FONTS);

    let candidates: [(&str, u32); 15] = [
        // macOS
        ("/System/Library/Fonts/Supplemental/Arial.ttf", 0),
        ("/System/Library/Fonts/Supplemental/Arial Unicode.ttf", 0),
        ("/System/Library/Fonts/PingFang.ttc", 0),
        ("/System/Library/Fonts/Hiragino Sans GB.ttc", 0),
        ("/System/Library/Fonts/AppleSDGothicNeo.ttc", 0),
        // Windows
        ("C:\\Windows\\Fonts\\arial.ttf", 0),
        ("C:\\Windows\\Fonts\\segoeui.ttf", 0),
        ("C:\\Windows\\Fonts\\msyh.ttc", 0),
        ("C:\\Windows\\Fonts\\meiryo.ttc", 0),
        ("C:\\Windows\\Fonts\\malgun.ttf", 0),
        // Linux
        ("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 0),
        ("/usr/share/fonts/dejavu/DejaVuSans.ttf", 0),
        ("/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf", 0),
        ("/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc", 0),
        ("/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc", 0),
    ];

    let mut fonts: Vec<fontdue::Font> = Vec::new();
    let mut seen_hashes: HashSet<usize> = HashSet::new();

    for (path, collection_index) in candidates {
        if fonts.len() >= max_fonts {
            break;
        }

        // Avoid loading large TTC collections that can dominate RSS for the process.
        let Ok(metadata) = fs::metadata(path) else {
            continue;
        };
        if metadata.len() == 0 || metadata.len() > max_font_bytes {
            continue;
        }

        let Ok(bytes) = fs::read(path) else {
            continue;
        };

        let settings = fontdue::FontSettings {
            collection_index,
            ..fontdue::FontSettings::default()
        };

        let Ok(font) = fontdue::Font::from_bytes(bytes, settings) else {
            continue;
        };

        let hash = font.file_hash();
        if seen_hashes.insert(hash) {
            fonts.push(font);
        }
    }

    fonts
}

fn font_index_for_char(ch: char, fonts: &[fontdue::Font]) -> usize {
    if fonts.len() <= 1 || ch.is_ascii_control() || ch.is_ascii_whitespace() {
        return 0;
    }

    if fonts[0].lookup_glyph_index(ch) != 0 {
        return 0;
    }

    for (index, font) in fonts.iter().enumerate().skip(1) {
        if font.lookup_glyph_index(ch) != 0 {
            return index;
        }
    }

    0
}

fn build_text_layout(text: &str, cmd: vs_text_command, fonts: &[fontdue::Font]) -> Layout {
    let mut layout = Layout::new(CoordinateSystem::PositiveYDown);
    let px = (cmd.font_px.max(8).min(144)) as f32;
    layout.reset(&LayoutSettings {
        x: cmd.x as f32,
        y: cmd.y as f32,
        ..LayoutSettings::default()
    });

    if fonts.is_empty() || text.is_empty() {
        return layout;
    }

    let mut run = String::new();
    let mut run_font_index: Option<usize> = None;

    for ch in text.chars() {
        let index = font_index_for_char(ch, fonts);
        match run_font_index {
            Some(current) if current != index => {
                if !run.is_empty() {
                    layout.append(fonts, &TextStyle::new(&run, px, current));
                    run.clear();
                }
                run_font_index = Some(index);
            }
            None => {
                run_font_index = Some(index);
            }
            _ => {}
        }
        run.push(ch);
    }

    if let Some(index) = run_font_index {
        if !run.is_empty() {
            layout.append(fonts, &TextStyle::new(&run, px, index));
        }
    }

    layout
}

fn text_command_bounds(text: &str, cmd: vs_text_command) -> Option<RectI> {
    if text.is_empty() {
        return None;
    }

    if let Some(fonts) = system_fonts() {
        let layout = build_text_layout(text, cmd, fonts);
        let mut min_x = i32::MAX;
        let mut min_y = i32::MAX;
        let mut max_x = i32::MIN;
        let mut max_y = i32::MIN;
        let mut seen = false;

        for glyph in layout.glyphs() {
            if glyph.width == 0 || glyph.height == 0 {
                continue;
            }

            let gx0 = glyph.x.floor() as i32;
            let gy0 = glyph.y.floor() as i32;
            let gx1 = (glyph.x + glyph.width as f32).ceil() as i32;
            let gy1 = (glyph.y + glyph.height as f32).ceil() as i32;

            min_x = min_x.min(gx0);
            min_y = min_y.min(gy0);
            max_x = max_x.max(gx1);
            max_y = max_y.max(gy1);
            seen = true;
        }

        if seen {
            return Some(RectI {
                x0: min_x,
                y0: min_y,
                x1: max_x,
                y1: max_y,
            });
        }
    }

    let scale = (cmd.font_px as i32 / 8).max(1);
    let glyph_w = 8 * scale;
    let glyph_h = 8 * scale;
    let line_h = glyph_h + scale;

    let mut max_chars = 0i32;
    let mut lines = 0i32;
    for line in text.lines() {
        lines += 1;
        let count = line.chars().count() as i32;
        if count > max_chars {
            max_chars = count;
        }
    }

    if lines == 0 {
        lines = 1;
    }

    let width = (max_chars.max(1)).saturating_mul(glyph_w);
    let height = lines.saturating_mul(line_h);

    Some(RectI {
        x0: cmd.x,
        y0: cmd.y,
        x1: cmd.x.saturating_add(width),
        y1: cmd.y.saturating_add(height),
    })
}

fn draw_rect(
    buf: &mut [u8],
    image_width: i32,
    image_height: i32,
    stride: usize,
    cmd: vs_rect_command,
    filled: bool,
    clip: Option<RectI>,
) {
    let Some(rect_bounds) = rect_command_bounds(cmd) else {
        return;
    };

    let Some(clamped_to_image) = rect_bounds.clamp_to_image(image_width, image_height) else {
        return;
    };

    let draw_rect = match clip {
        Some(clip_rect) => match clamped_to_image.intersect(clip_rect) {
            Some(intersection) => intersection,
            None => return,
        },
        None => clamped_to_image,
    };

    let stroke = (cmd.stroke_width as i32).max(1);

    for y in draw_rect.y0..draw_rect.y1 {
        for x in draw_rect.x0..draw_rect.x1 {
            if !filled {
                let is_border = x < clamped_to_image.x0 + stroke
                    || x >= clamped_to_image.x1 - stroke
                    || y < clamped_to_image.y0 + stroke
                    || y >= clamped_to_image.y1 - stroke;
                if !is_border {
                    continue;
                }
            }

            let idx = y as usize * stride + x as usize * 4;
            if idx + 3 >= buf.len() {
                continue;
            }
            blend_pixel_bgra(&mut buf[idx..idx + 4], cmd.b, cmd.g, cmd.r, cmd.a);
        }
    }
}

fn draw_ellipse(
    buf: &mut [u8],
    image_width: i32,
    image_height: i32,
    stride: usize,
    cmd: vs_ellipse_command,
    filled: bool,
    clip: Option<RectI>,
) {
    let Some(ellipse_bounds) = ellipse_command_bounds(cmd) else {
        return;
    };

    let Some(clamped_to_image) = ellipse_bounds.clamp_to_image(image_width, image_height) else {
        return;
    };

    let draw_rect = match clip {
        Some(clip_rect) => match clamped_to_image.intersect(clip_rect) {
            Some(intersection) => intersection,
            None => return,
        },
        None => clamped_to_image,
    };

    let rx = (cmd.width as f32).max(1.0) * 0.5;
    let ry = (cmd.height as f32).max(1.0) * 0.5;
    let cx = cmd.x as f32 + rx;
    let cy = cmd.y as f32 + ry;
    let stroke = (cmd.stroke_width as f32).max(1.0);
    let inner_rx = (rx - stroke).max(0.5);
    let inner_ry = (ry - stroke).max(0.5);
    let fully_filled_by_stroke = stroke >= rx || stroke >= ry;

    for y in draw_rect.y0..draw_rect.y1 {
        for x in draw_rect.x0..draw_rect.x1 {
            let px = x as f32 + 0.5;
            let py = y as f32 + 0.5;
            let nx = (px - cx) / rx;
            let ny = (py - cy) / ry;
            let outer = nx * nx + ny * ny;
            if outer > 1.0 {
                continue;
            }

            if !filled && !fully_filled_by_stroke {
                let inx = (px - cx) / inner_rx;
                let iny = (py - cy) / inner_ry;
                let inner = inx * inx + iny * iny;
                if inner < 1.0 {
                    continue;
                }
            }

            blend_pixel_at(buf, stride, x, y, cmd.b, cmd.g, cmd.r, cmd.a);
        }
    }
}

fn draw_line(
    buf: &mut [u8],
    image_width: i32,
    image_height: i32,
    stride: usize,
    cmd: vs_line_command,
    clip: Option<RectI>,
) {
    let Some(mut bounds) = line_command_bounds(cmd) else {
        return;
    };

    bounds = match bounds.clamp_to_image(image_width, image_height) {
        Some(v) => v,
        None => return,
    };

    let draw_rect = match clip {
        Some(clip_rect) => match bounds.intersect(clip_rect) {
            Some(v) => v,
            None => return,
        },
        None => bounds,
    };

    let stroke = (cmd.stroke_width as f32).max(1.0);
    let half_stroke = stroke * 0.5;
    let x0 = cmd.x0 as f32;
    let y0 = cmd.y0 as f32;
    let x1 = cmd.x1 as f32;
    let y1 = cmd.y1 as f32;
    let dx = x1 - x0;
    let dy = y1 - y0;
    let len_sq = dx * dx + dy * dy;
    if len_sq <= f32::EPSILON {
        return;
    }

    for y in draw_rect.y0..draw_rect.y1 {
        for x in draw_rect.x0..draw_rect.x1 {
            let px = x as f32 + 0.5;
            let py = y as f32 + 0.5;
            let t = (((px - x0) * dx + (py - y0) * dy) / len_sq).clamp(0.0, 1.0);
            let cx = x0 + t * dx;
            let cy = y0 + t * dy;
            let dist = ((px - cx).powi(2) + (py - cy).powi(2)).sqrt();
            if dist > half_stroke {
                continue;
            }

            let idx = y as usize * stride + x as usize * 4;
            if idx + 3 >= buf.len() {
                continue;
            }
            blend_pixel_bgra(&mut buf[idx..idx + 4], cmd.b, cmd.g, cmd.r, cmd.a);
        }
    }
}

fn draw_path(
    buf: &mut [u8],
    image_width: i32,
    image_height: i32,
    stride: usize,
    points: &[vs_point_i32],
    style: vs_path_style,
    clip: Option<RectI>,
) {
    if points.is_empty() {
        return;
    }

    let stroke_width = style.stroke_width.max(1);

    if points.len() == 1 {
        let point = points[0];
        draw_disc(
            buf,
            image_width,
            image_height,
            stride,
            point.x,
            point.y,
            stroke_width as f32 * 0.5,
            style.b,
            style.g,
            style.r,
            style.a,
            clip,
        );
        return;
    }

    for segment in points.windows(2) {
        let p0 = segment[0];
        let p1 = segment[1];
        let line = vs_line_command {
            x0: p0.x,
            y0: p0.y,
            x1: p1.x,
            y1: p1.y,
            stroke_width,
            r: style.r,
            g: style.g,
            b: style.b,
            a: style.a,
        };
        draw_line(buf, image_width, image_height, stride, line, clip);
    }
}

#[allow(clippy::too_many_arguments)]
fn draw_disc(
    buf: &mut [u8],
    image_width: i32,
    image_height: i32,
    stride: usize,
    cx: i32,
    cy: i32,
    radius: f32,
    b: u8,
    g: u8,
    r: u8,
    a: u8,
    clip: Option<RectI>,
) {
    let radius = radius.max(0.75);
    let pad = radius.ceil() as i32 + 1;
    let bounds = RectI {
        x0: cx.saturating_sub(pad),
        y0: cy.saturating_sub(pad),
        x1: cx.saturating_add(pad + 1),
        y1: cy.saturating_add(pad + 1),
    };
    let Some(clamped) = bounds.clamp_to_image(image_width, image_height) else {
        return;
    };

    let draw_rect = match clip {
        Some(c) => match clamped.intersect(c) {
            Some(v) => v,
            None => return,
        },
        None => clamped,
    };

    let cx = cx as f32;
    let cy = cy as f32;
    let radius_sq = radius * radius;
    for y in draw_rect.y0..draw_rect.y1 {
        for x in draw_rect.x0..draw_rect.x1 {
            let dx = x as f32 + 0.5 - cx;
            let dy = y as f32 + 0.5 - cy;
            if dx * dx + dy * dy > radius_sq {
                continue;
            }
            blend_pixel_at(buf, stride, x, y, b, g, r, a);
        }
    }
}

fn draw_arrow(
    buf: &mut [u8],
    image_width: i32,
    image_height: i32,
    stride: usize,
    cmd: vs_arrow_command,
    clip: Option<RectI>,
) {
    let shaft = vs_line_command {
        x0: cmd.x0,
        y0: cmd.y0,
        x1: cmd.x1,
        y1: cmd.y1,
        stroke_width: cmd.stroke_width,
        r: cmd.r,
        g: cmd.g,
        b: cmd.b,
        a: cmd.a,
    };
    draw_line(buf, image_width, image_height, stride, shaft, clip);

    let dx = (cmd.x1 - cmd.x0) as f32;
    let dy = (cmd.y1 - cmd.y0) as f32;
    let len = (dx * dx + dy * dy).sqrt();
    if len <= f32::EPSILON {
        return;
    }

    let ux = dx / len;
    let uy = dy / len;
    let stroke = (cmd.stroke_width as f32).max(1.0);
    let head_len = (stroke * 6.0).max(16.0);
    let theta = 30.0f32.to_radians();
    let cos_t = theta.cos();
    let sin_t = theta.sin();

    let rx1 = ux * cos_t - uy * sin_t;
    let ry1 = ux * sin_t + uy * cos_t;
    let rx2 = ux * cos_t + uy * sin_t;
    let ry2 = -ux * sin_t + uy * cos_t;

    let hx0 = cmd.x1 as f32 - rx1 * head_len;
    let hy0 = cmd.y1 as f32 - ry1 * head_len;
    let hx1 = cmd.x1 as f32 - rx2 * head_len;
    let hy1 = cmd.y1 as f32 - ry2 * head_len;

    let left_head = vs_line_command {
        x0: cmd.x1,
        y0: cmd.y1,
        x1: hx0.round() as i32,
        y1: hy0.round() as i32,
        stroke_width: cmd.stroke_width,
        r: cmd.r,
        g: cmd.g,
        b: cmd.b,
        a: cmd.a,
    };
    let right_head = vs_line_command {
        x0: cmd.x1,
        y0: cmd.y1,
        x1: hx1.round() as i32,
        y1: hy1.round() as i32,
        stroke_width: cmd.stroke_width,
        r: cmd.r,
        g: cmd.g,
        b: cmd.b,
        a: cmd.a,
    };

    draw_line(buf, image_width, image_height, stride, left_head, clip);
    draw_line(buf, image_width, image_height, stride, right_head, clip);
}

fn draw_text(
    buf: &mut [u8],
    image_width: i32,
    image_height: i32,
    stride: usize,
    text: &str,
    cmd: vs_text_command,
    clip: Option<RectI>,
) {
    let Some(bounds) = text_command_bounds(text, cmd) else {
        return;
    };

    let Some(clamped_to_image) = bounds.clamp_to_image(image_width, image_height) else {
        return;
    };

    let draw_rect = match clip {
        Some(clip_rect) => match clamped_to_image.intersect(clip_rect) {
            Some(intersection) => intersection,
            None => return,
        },
        None => clamped_to_image,
    };

    if let Some(fonts) = system_fonts() {
        draw_text_with_system_fonts(buf, stride, draw_rect, text, cmd, fonts);
        return;
    }

    draw_text_bitmap(buf, stride, draw_rect, text, cmd);
}

fn draw_text_with_system_fonts(
    buf: &mut [u8],
    stride: usize,
    clip: RectI,
    text: &str,
    cmd: vs_text_command,
    fonts: &[fontdue::Font],
) {
    let layout = build_text_layout(text, cmd, fonts);
    for glyph in layout.glyphs() {
        if glyph.width == 0 || glyph.height == 0 {
            continue;
        }

        let Some(font) = fonts.get(glyph.font_index) else {
            continue;
        };

        let (metrics, bitmap) = font.rasterize_config(glyph.key);
        if metrics.width == 0 || metrics.height == 0 || bitmap.is_empty() {
            continue;
        }

        let gx0 = glyph.x.floor() as i32;
        let gy0 = glyph.y.floor() as i32;
        let gx1 = gx0.saturating_add(metrics.width as i32);
        let gy1 = gy0.saturating_add(metrics.height as i32);

        let glyph_rect = RectI {
            x0: gx0,
            y0: gy0,
            x1: gx1,
            y1: gy1,
        };

        let Some(draw_span) = glyph_rect.intersect(clip) else {
            continue;
        };

        for yy in draw_span.y0..draw_span.y1 {
            let sy = (yy - gy0) as usize;
            for xx in draw_span.x0..draw_span.x1 {
                let sx = (xx - gx0) as usize;
                let coverage = bitmap[sy * metrics.width + sx];
                if coverage == 0 {
                    continue;
                }

                let alpha = ((coverage as u32 * cmd.a as u32 + 127) / 255) as u8;
                blend_pixel_at(buf, stride, xx, yy, cmd.b, cmd.g, cmd.r, alpha);
            }
        }
    }
}

fn draw_text_bitmap(
    buf: &mut [u8],
    stride: usize,
    draw_rect: RectI,
    text: &str,
    cmd: vs_text_command,
) {
    let scale = (cmd.font_px as i32 / 8).max(1);
    let glyph_w = 8 * scale;
    let glyph_h = 8 * scale;
    let line_h = glyph_h + scale;
    let fallback = font8x8::BASIC_FONTS.get('?').unwrap_or([0u8; 8]);

    let mut pen_y = cmd.y;
    for line in text.lines() {
        let mut pen_x = cmd.x;
        for ch in line.chars() {
            let glyph = font8x8::BASIC_FONTS.get(ch).unwrap_or(fallback);
            draw_bitmap_glyph(
                buf, stride, draw_rect, pen_x, pen_y, scale, glyph, cmd.b, cmd.g, cmd.r, cmd.a,
            );
            pen_x = pen_x.saturating_add(glyph_w);
        }
        pen_y = pen_y.saturating_add(line_h);
    }
}

fn draw_bitmap_glyph(
    buf: &mut [u8],
    stride: usize,
    clip: RectI,
    x: i32,
    y: i32,
    scale: i32,
    glyph: [u8; 8],
    b: u8,
    g: u8,
    r: u8,
    a: u8,
) {
    for (row, row_bits) in glyph.iter().enumerate() {
        for col in 0..8 {
            if (row_bits >> col) & 1 == 0 {
                continue;
            }

            let px0 = x.saturating_add((col as i32).saturating_mul(scale));
            let py0 = y.saturating_add((row as i32).saturating_mul(scale));
            let px1 = px0.saturating_add(scale);
            let py1 = py0.saturating_add(scale);

            let span = RectI {
                x0: px0,
                y0: py0,
                x1: px1,
                y1: py1,
            };
            let Some(draw_span) = span.intersect(clip) else {
                continue;
            };

            for yy in draw_span.y0..draw_span.y1 {
                for xx in draw_span.x0..draw_span.x1 {
                    blend_pixel_at(buf, stride, xx, yy, b, g, r, a);
                }
            }
        }
    }
}

fn draw_pixelate(
    buf: &mut [u8],
    image_width: i32,
    image_height: i32,
    stride: usize,
    cmd: vs_pixelate_rect_command,
    clip: Option<RectI>,
) {
    let Some(rect) = effect_rect_bounds(cmd.x, cmd.y, cmd.width, cmd.height) else {
        return;
    };
    let Some(clamped) = rect.clamp_to_image(image_width, image_height) else {
        return;
    };
    let region = match clip {
        Some(c) => match clamped.intersect(c) {
            Some(v) => v,
            None => return,
        },
        None => clamped,
    };

    let block = (cmd.block_size as i32).max(2);
    let mut by = region.y0;
    while by < region.y1 {
        let mut bx = region.x0;
        while bx < region.x1 {
            let x1 = (bx + block).min(region.x1);
            let y1 = (by + block).min(region.y1);
            let bx_u = bx as usize;
            let x1_u = x1 as usize;

            let mut sum_b: u32 = 0;
            let mut sum_g: u32 = 0;
            let mut sum_r: u32 = 0;
            let mut sum_a: u32 = 0;
            let mut count: u32 = 0;

            for y in by..y1 {
                let mut idx = y as usize * stride + bx_u * 4;
                for _x in bx_u..x1_u {
                    sum_b += buf[idx] as u32;
                    sum_g += buf[idx + 1] as u32;
                    sum_r += buf[idx + 2] as u32;
                    sum_a += buf[idx + 3] as u32;
                    count += 1;
                    idx += 4;
                }
            }

            if count > 0 {
                let avg_b = (sum_b / count) as u8;
                let avg_g = (sum_g / count) as u8;
                let avg_r = (sum_r / count) as u8;
                let avg_a = (sum_a / count) as u8;
                for y in by..y1 {
                    let mut idx = y as usize * stride + bx_u * 4;
                    for _x in bx_u..x1_u {
                        buf[idx] = avg_b;
                        buf[idx + 1] = avg_g;
                        buf[idx + 2] = avg_r;
                        buf[idx + 3] = avg_a;
                        idx += 4;
                    }
                }
            }

            bx += block;
        }
        by += block;
    }
}

fn draw_blur(
    buf: &mut [u8],
    image_width: i32,
    image_height: i32,
    stride: usize,
    cmd: vs_blur_rect_command,
    clip: Option<RectI>,
) {
    let Some(rect) = effect_rect_bounds(cmd.x, cmd.y, cmd.width, cmd.height) else {
        return;
    };
    let Some(clamped) = rect.clamp_to_image(image_width, image_height) else {
        return;
    };
    let region = match clip {
        Some(c) => match clamped.intersect(c) {
            Some(v) => v,
            None => return,
        },
        None => clamped,
    };

    let radius = (cmd.radius as i32).clamp(1, 24);
    let sample = RectI {
        x0: region.x0.saturating_sub(radius),
        y0: region.y0.saturating_sub(radius),
        x1: region.x1.saturating_add(radius),
        y1: region.y1.saturating_add(radius),
    };
    let Some(sample) = sample.clamp_to_image(image_width, image_height) else {
        return;
    };

    let sample_w = sample.width() as usize;
    let sample_h = sample.height() as usize;
    if sample_w == 0 || sample_h == 0 {
        return;
    }

    let sample_stride = sample_w * 4;
    let mut src = vec![0u8; sample_h * sample_stride];
    let sample_x = sample.x0 as usize;
    let sample_y = sample.y0 as usize;
    for row in 0..sample_h {
        let src_row = (sample_y + row) * stride;
        let src_start = src_row + sample_x * 4;
        let src_end = src_start + sample_stride;
        let dst_start = row * sample_stride;
        src[dst_start..dst_start + sample_stride].copy_from_slice(&buf[src_start..src_end]);
    }

    let rx0 = (region.x0 - sample.x0) as usize;
    let rx1 = (region.x1 - sample.x0) as usize;
    let ry0 = (region.y0 - sample.y0) as usize;
    let ry1 = (region.y1 - sample.y0) as usize;
    let region_w = rx1.saturating_sub(rx0);
    let region_h = ry1.saturating_sub(ry0);
    if region_w == 0 || region_h == 0 {
        return;
    }

    let radius = radius as usize;
    let window_size = radius * 2 + 1;
    let window_size_u32 = window_size as u32;

    // Horizontal pass computes only the x-range that will be written back.
    let tmp_stride = region_w * 4;
    let mut tmp = vec![0u8; sample_h * tmp_stride];
    for y in 0..sample_h {
        let src_row = &src[y * sample_stride..(y + 1) * sample_stride];
        let tmp_row = &mut tmp[y * tmp_stride..(y + 1) * tmp_stride];

        let mut sum_b: u32 = 0;
        let mut sum_g: u32 = 0;
        let mut sum_r: u32 = 0;
        let mut sum_a: u32 = 0;
        for k in 0..window_size {
            let sx = clamp_index(rx0 as isize + k as isize - radius as isize, sample_w);
            let idx = sx * 4;
            sum_b += src_row[idx] as u32;
            sum_g += src_row[idx + 1] as u32;
            sum_r += src_row[idx + 2] as u32;
            sum_a += src_row[idx + 3] as u32;
        }

        let mut sx = rx0;
        for out_x in 0..region_w {
            let dst_idx = out_x * 4;
            tmp_row[dst_idx] = (sum_b / window_size_u32) as u8;
            tmp_row[dst_idx + 1] = (sum_g / window_size_u32) as u8;
            tmp_row[dst_idx + 2] = (sum_r / window_size_u32) as u8;
            tmp_row[dst_idx + 3] = (sum_a / window_size_u32) as u8;

            let remove_x = clamp_index(sx as isize - radius as isize, sample_w);
            let add_x = clamp_index(sx as isize + radius as isize + 1, sample_w);
            let remove_idx = remove_x * 4;
            let add_idx = add_x * 4;
            sum_b = sum_b + src_row[add_idx] as u32 - src_row[remove_idx] as u32;
            sum_g = sum_g + src_row[add_idx + 1] as u32 - src_row[remove_idx + 1] as u32;
            sum_r = sum_r + src_row[add_idx + 2] as u32 - src_row[remove_idx + 2] as u32;
            sum_a = sum_a + src_row[add_idx + 3] as u32 - src_row[remove_idx + 3] as u32;
            sx += 1;
        }
    }

    // Vertical pass writes directly into the destination buffer for the region.
    for x in 0..region_w {
        let mut sum_b: u32 = 0;
        let mut sum_g: u32 = 0;
        let mut sum_r: u32 = 0;
        let mut sum_a: u32 = 0;
        for k in 0..window_size {
            let sy = clamp_index(ry0 as isize + k as isize - radius as isize, sample_h);
            let idx = sy * tmp_stride + x * 4;
            sum_b += tmp[idx] as u32;
            sum_g += tmp[idx + 1] as u32;
            sum_r += tmp[idx + 2] as u32;
            sum_a += tmp[idx + 3] as u32;
        }

        let mut sy = ry0;
        for out_y in 0..region_h {
            let dst_y = sample_y + ry0 + out_y;
            let dst_x = sample_x + rx0 + x;
            let dst_idx = dst_y * stride + dst_x * 4;
            buf[dst_idx] = (sum_b / window_size_u32) as u8;
            buf[dst_idx + 1] = (sum_g / window_size_u32) as u8;
            buf[dst_idx + 2] = (sum_r / window_size_u32) as u8;
            buf[dst_idx + 3] = (sum_a / window_size_u32) as u8;

            let remove_y = clamp_index(sy as isize - radius as isize, sample_h);
            let add_y = clamp_index(sy as isize + radius as isize + 1, sample_h);
            let remove_idx = remove_y * tmp_stride + x * 4;
            let add_idx = add_y * tmp_stride + x * 4;
            sum_b = sum_b + tmp[add_idx] as u32 - tmp[remove_idx] as u32;
            sum_g = sum_g + tmp[add_idx + 1] as u32 - tmp[remove_idx + 1] as u32;
            sum_r = sum_r + tmp[add_idx + 2] as u32 - tmp[remove_idx + 2] as u32;
            sum_a = sum_a + tmp[add_idx + 3] as u32 - tmp[remove_idx + 3] as u32;
            sy += 1;
        }
    }
}

fn clamp_index(value: isize, len: usize) -> usize {
    if len == 0 {
        return 0;
    }
    value.clamp(0, len as isize - 1) as usize
}

fn blend_pixel_at(buf: &mut [u8], stride: usize, x: i32, y: i32, b: u8, g: u8, r: u8, a: u8) {
    if x < 0 || y < 0 {
        return;
    }
    let idx = y as usize * stride + x as usize * 4;
    if idx + 3 >= buf.len() {
        return;
    }
    blend_pixel_bgra(&mut buf[idx..idx + 4], b, g, r, a);
}

fn restore_region(base: &[u8], out: &mut [u8], stride: usize, dirty: RectI) {
    let x0 = dirty.x0.max(0) as usize;
    let x1 = dirty.x1.max(0) as usize;

    if x0 >= x1 {
        return;
    }

    for y in dirty.y0.max(0) as usize..dirty.y1.max(0) as usize {
        let row_start = y * stride;
        let src_start = row_start + x0 * 4;
        let src_end = row_start + x1 * 4;

        if src_end > base.len() || src_end > out.len() {
            continue;
        }

        out[src_start..src_end].copy_from_slice(&base[src_start..src_end]);
    }
}

fn blend_pixel_bgra(pixel: &mut [u8], b: u8, g: u8, r: u8, a: u8) {
    let alpha = a as u16;
    let inv = 255u16.saturating_sub(alpha);

    pixel[0] = ((pixel[0] as u16 * inv + b as u16 * alpha) / 255) as u8;
    pixel[1] = ((pixel[1] as u16 * inv + g as u16 * alpha) / 255) as u8;
    pixel[2] = ((pixel[2] as u16 * inv + r as u16 * alpha) / 255) as u8;
    pixel[3] = 255;
}
