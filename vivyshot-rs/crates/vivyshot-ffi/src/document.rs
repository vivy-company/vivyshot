use super::*;
use vivyshot_domain::{
    Document as CoreDocument, DocumentArrowCommand, DocumentBlurRectCommand,
    DocumentCommand as CoreCommand, DocumentEllipseCommand, DocumentLineCommand, DocumentPathStyle,
    DocumentPixelateRectCommand, DocumentRectCommand, DocumentTextCommand, I32Point as CorePoint,
    I32Rect as CoreRect,
};

type VsCommand = CoreCommand;
type VsDocument = CoreDocument;

impl From<vs_rect_command> for DocumentRectCommand {
    fn from(value: vs_rect_command) -> Self {
        Self {
            x: value.x,
            y: value.y,
            width: value.width,
            height: value.height,
            stroke_width: value.stroke_width,
            r: value.r,
            g: value.g,
            b: value.b,
            a: value.a,
        }
    }
}

impl From<DocumentRectCommand> for vs_rect_command {
    fn from(value: DocumentRectCommand) -> Self {
        Self {
            x: value.x,
            y: value.y,
            width: value.width,
            height: value.height,
            stroke_width: value.stroke_width,
            r: value.r,
            g: value.g,
            b: value.b,
            a: value.a,
        }
    }
}

impl From<vs_ellipse_command> for DocumentEllipseCommand {
    fn from(value: vs_ellipse_command) -> Self {
        Self {
            x: value.x,
            y: value.y,
            width: value.width,
            height: value.height,
            stroke_width: value.stroke_width,
            r: value.r,
            g: value.g,
            b: value.b,
            a: value.a,
        }
    }
}

impl From<DocumentEllipseCommand> for vs_ellipse_command {
    fn from(value: DocumentEllipseCommand) -> Self {
        Self {
            x: value.x,
            y: value.y,
            width: value.width,
            height: value.height,
            stroke_width: value.stroke_width,
            r: value.r,
            g: value.g,
            b: value.b,
            a: value.a,
        }
    }
}

impl From<vs_line_command> for DocumentLineCommand {
    fn from(value: vs_line_command) -> Self {
        Self {
            x0: value.x0,
            y0: value.y0,
            x1: value.x1,
            y1: value.y1,
            stroke_width: value.stroke_width,
            r: value.r,
            g: value.g,
            b: value.b,
            a: value.a,
        }
    }
}

impl From<DocumentLineCommand> for vs_line_command {
    fn from(value: DocumentLineCommand) -> Self {
        Self {
            x0: value.x0,
            y0: value.y0,
            x1: value.x1,
            y1: value.y1,
            stroke_width: value.stroke_width,
            r: value.r,
            g: value.g,
            b: value.b,
            a: value.a,
        }
    }
}

impl From<vs_arrow_command> for DocumentArrowCommand {
    fn from(value: vs_arrow_command) -> Self {
        Self {
            x0: value.x0,
            y0: value.y0,
            x1: value.x1,
            y1: value.y1,
            stroke_width: value.stroke_width,
            r: value.r,
            g: value.g,
            b: value.b,
            a: value.a,
        }
    }
}

impl From<DocumentArrowCommand> for vs_arrow_command {
    fn from(value: DocumentArrowCommand) -> Self {
        Self {
            x0: value.x0,
            y0: value.y0,
            x1: value.x1,
            y1: value.y1,
            stroke_width: value.stroke_width,
            r: value.r,
            g: value.g,
            b: value.b,
            a: value.a,
        }
    }
}

impl From<vs_text_command> for DocumentTextCommand {
    fn from(value: vs_text_command) -> Self {
        Self {
            x: value.x,
            y: value.y,
            font_px: value.font_px,
            r: value.r,
            g: value.g,
            b: value.b,
            a: value.a,
        }
    }
}

impl From<DocumentTextCommand> for vs_text_command {
    fn from(value: DocumentTextCommand) -> Self {
        Self {
            x: value.x,
            y: value.y,
            font_px: value.font_px,
            r: value.r,
            g: value.g,
            b: value.b,
            a: value.a,
        }
    }
}

impl From<vs_pixelate_rect_command> for DocumentPixelateRectCommand {
    fn from(value: vs_pixelate_rect_command) -> Self {
        Self {
            x: value.x,
            y: value.y,
            width: value.width,
            height: value.height,
            block_size: value.block_size,
        }
    }
}

impl From<DocumentPixelateRectCommand> for vs_pixelate_rect_command {
    fn from(value: DocumentPixelateRectCommand) -> Self {
        Self {
            x: value.x,
            y: value.y,
            width: value.width,
            height: value.height,
            block_size: value.block_size,
        }
    }
}

impl From<vs_blur_rect_command> for DocumentBlurRectCommand {
    fn from(value: vs_blur_rect_command) -> Self {
        Self {
            x: value.x,
            y: value.y,
            width: value.width,
            height: value.height,
            radius: value.radius,
        }
    }
}

impl From<DocumentBlurRectCommand> for vs_blur_rect_command {
    fn from(value: DocumentBlurRectCommand) -> Self {
        Self {
            x: value.x,
            y: value.y,
            width: value.width,
            height: value.height,
            radius: value.radius,
        }
    }
}

impl From<vs_path_style> for DocumentPathStyle {
    fn from(value: vs_path_style) -> Self {
        Self {
            stroke_width: value.stroke_width,
            r: value.r,
            g: value.g,
            b: value.b,
            a: value.a,
        }
    }
}

impl From<DocumentPathStyle> for vs_path_style {
    fn from(value: DocumentPathStyle) -> Self {
        Self {
            stroke_width: value.stroke_width,
            r: value.r,
            g: value.g,
            b: value.b,
            a: value.a,
        }
    }
}

impl From<vs_point_i32> for CorePoint {
    fn from(value: vs_point_i32) -> Self {
        Self {
            x: value.x,
            y: value.y,
        }
    }
}

impl From<CorePoint> for vs_point_i32 {
    fn from(value: CorePoint) -> Self {
        Self {
            x: value.x,
            y: value.y,
        }
    }
}

unsafe fn document_from_handle_mut<'a>(doc: *mut c_void) -> Result<&'a mut VsDocument, i32> {
    validate_handle(&DOCUMENT_HANDLES, doc)?;
    // SAFETY: pointer was validated by registry and originates from Box::into_raw.
    Ok(unsafe { &mut *doc.cast::<VsDocument>() })
}

unsafe fn document_from_handle<'a>(doc: *const c_void) -> Result<&'a VsDocument, i32> {
    validate_handle(&DOCUMENT_HANDLES, doc)?;
    // SAFETY: pointer was validated by registry and originates from Box::into_raw.
    Ok(unsafe { &*doc.cast::<VsDocument>() })
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

impl From<RectI> for CoreRect {
    fn from(value: RectI) -> Self {
        Self {
            x: value.x0,
            y: value.y0,
            width: value.width(),
            height: value.height(),
        }
    }
}

impl From<CoreRect> for RectI {
    fn from(value: CoreRect) -> Self {
        RectI {
            x0: value.x,
            y0: value.y,
            x1: value.x.saturating_add(value.width),
            y1: value.y.saturating_add(value.height),
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
    let Some(doc) = CoreDocument::new(width, height, stride, src.to_vec()) else {
        return std::ptr::null_mut();
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
        drop(Box::from_raw(doc.cast::<VsDocument>()));
    }
}

#[no_mangle]
pub unsafe extern "C" fn vs_add_rect(doc: *mut c_void, cmd: vs_rect_command) -> i32 {
    let doc = match unsafe { document_from_handle_mut(doc) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    match doc.add_rect(cmd.into()) {
        Ok(()) => 0,
        Err(code) => code.code(),
    }
}

#[no_mangle]
pub unsafe extern "C" fn vs_add_filled_rect(doc: *mut c_void, cmd: vs_rect_command) -> i32 {
    let doc = match unsafe { document_from_handle_mut(doc) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    match doc.add_filled_rect(cmd.into()) {
        Ok(()) => 0,
        Err(code) => code.code(),
    }
}

#[no_mangle]
pub unsafe extern "C" fn vs_add_ellipse(doc: *mut c_void, cmd: vs_ellipse_command) -> i32 {
    let doc = match unsafe { document_from_handle_mut(doc) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    match doc.add_ellipse(cmd.into()) {
        Ok(()) => 0,
        Err(code) => code.code(),
    }
}

#[no_mangle]
pub unsafe extern "C" fn vs_add_filled_ellipse(doc: *mut c_void, cmd: vs_ellipse_command) -> i32 {
    let doc = match unsafe { document_from_handle_mut(doc) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    match doc.add_filled_ellipse(cmd.into()) {
        Ok(()) => 0,
        Err(code) => code.code(),
    }
}

#[no_mangle]
pub unsafe extern "C" fn vs_add_line(doc: *mut c_void, cmd: vs_line_command) -> i32 {
    let doc = match unsafe { document_from_handle_mut(doc) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    match doc.add_line(cmd.into()) {
        Ok(()) => 0,
        Err(code) => code.code(),
    }
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
    let points = points.iter().copied().map(Into::into).collect();
    match doc.add_path(points, style.into()) {
        Ok(()) => 0,
        Err(code) => code.code(),
    }
}

#[no_mangle]
pub unsafe extern "C" fn vs_add_arrow(doc: *mut c_void, cmd: vs_arrow_command) -> i32 {
    let doc = match unsafe { document_from_handle_mut(doc) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    match doc.add_arrow(cmd.into()) {
        Ok(()) => 0,
        Err(code) => code.code(),
    }
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

    match doc.add_text(text, cmd.into()) {
        Ok(()) => 0,
        Err(code) => code.code(),
    }
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
    match doc.add_pixelate(cmd.into()) {
        Ok(()) => 0,
        Err(code) => code.code(),
    }
}

#[no_mangle]
pub unsafe extern "C" fn vs_add_blur_rect(doc: *mut c_void, cmd: vs_blur_rect_command) -> i32 {
    let doc = match unsafe { document_from_handle_mut(doc) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    match doc.add_blur(cmd.into()) {
        Ok(()) => 0,
        Err(code) => code.code(),
    }
}

#[no_mangle]
pub unsafe extern "C" fn vs_undo(doc: *mut c_void) -> i32 {
    let doc = match unsafe { document_from_handle_mut(doc) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    match doc.undo() {
        Ok(true) => 0,
        Ok(false) => 1,
        Err(code) => code.code(),
    }
}

#[no_mangle]
pub unsafe extern "C" fn vs_redo(doc: *mut c_void) -> i32 {
    let doc = match unsafe { document_from_handle_mut(doc) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    match doc.redo() {
        Ok(true) => 0,
        Ok(false) => 1,
        Err(code) => code.code(),
    }
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
    let annotations = doc.list_annotations();
    let total = annotations.len();

    for (index, annotation) in annotations.iter().take(out_cap).enumerate() {
        unsafe {
            *out_ptr.add(index) = vs_annotation_info {
                index: annotation.index,
                kind: annotation.kind,
                x: annotation.x,
                y: annotation.y,
                width: annotation.width,
                height: annotation.height,
            };
        }
    }

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

    match doc.move_annotation(idx, dx, dy) {
        Ok(true) => 0,
        Ok(false) => 1,
        Err(code) => code.code(),
    }
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

    match doc.remove_annotation(idx) {
        Ok(()) => 0,
        Err(code) => code.code(),
    }
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

    match doc.resize_annotation(idx, target.into()) {
        Ok(true) => 0,
        Ok(false) => 1,
        Err(code) => code.code(),
    }
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

    match dst.copy_annotations_affine(src, scale_x, scale_y, translate_x, translate_y) {
        Ok(()) => 0,
        Err(code) => code.code(),
    }
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

    doc.clear_dirty();
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

    let Some(dirty) = doc.pending_dirty.map(RectI::from) else {
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

    doc.clear_dirty();
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
        VsCommand::Rect(rect) => draw_rect(
            buf,
            image_width,
            image_height,
            stride,
            (*rect).into(),
            false,
            clip,
        ),
        VsCommand::FilledRect(rect) => draw_rect(
            buf,
            image_width,
            image_height,
            stride,
            (*rect).into(),
            true,
            clip,
        ),
        VsCommand::Ellipse(cmd) => draw_ellipse(
            buf,
            image_width,
            image_height,
            stride,
            (*cmd).into(),
            false,
            clip,
        ),
        VsCommand::FilledEllipse(cmd) => draw_ellipse(
            buf,
            image_width,
            image_height,
            stride,
            (*cmd).into(),
            true,
            clip,
        ),
        VsCommand::Line(line) => {
            draw_line(buf, image_width, image_height, stride, (*line).into(), clip)
        }
        VsCommand::Arrow(arrow) => draw_arrow(
            buf,
            image_width,
            image_height,
            stride,
            (*arrow).into(),
            clip,
        ),
        VsCommand::Path { points, style } => {
            draw_path(buf, image_width, image_height, stride, points, *style, clip)
        }
        VsCommand::Text { text, cmd } => draw_text(
            buf,
            image_width,
            image_height,
            stride,
            text,
            (*cmd).into(),
            clip,
        ),
        VsCommand::Pixelate(cmd) => {
            draw_pixelate(buf, image_width, image_height, stride, (*cmd).into(), clip)
        }
        VsCommand::Blur(cmd) => {
            draw_blur(buf, image_width, image_height, stride, (*cmd).into(), clip)
        }
    }
}

fn command_bounds(cmd: &VsCommand) -> Option<RectI> {
    cmd.bounds().map(RectI::from)
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
    points: &[CorePoint],
    style: DocumentPathStyle,
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
