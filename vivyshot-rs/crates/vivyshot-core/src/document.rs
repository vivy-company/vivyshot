use crate::types::{I32Point, I32Rect};

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct DocumentRectCommand {
    pub x: i32,
    pub y: i32,
    pub width: i32,
    pub height: i32,
    pub stroke_width: u32,
    pub r: u8,
    pub g: u8,
    pub b: u8,
    pub a: u8,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct DocumentEllipseCommand {
    pub x: i32,
    pub y: i32,
    pub width: i32,
    pub height: i32,
    pub stroke_width: u32,
    pub r: u8,
    pub g: u8,
    pub b: u8,
    pub a: u8,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct DocumentLineCommand {
    pub x0: i32,
    pub y0: i32,
    pub x1: i32,
    pub y1: i32,
    pub stroke_width: u32,
    pub r: u8,
    pub g: u8,
    pub b: u8,
    pub a: u8,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct DocumentArrowCommand {
    pub x0: i32,
    pub y0: i32,
    pub x1: i32,
    pub y1: i32,
    pub stroke_width: u32,
    pub r: u8,
    pub g: u8,
    pub b: u8,
    pub a: u8,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct DocumentTextCommand {
    pub x: i32,
    pub y: i32,
    pub font_px: u32,
    pub r: u8,
    pub g: u8,
    pub b: u8,
    pub a: u8,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct DocumentPixelateRectCommand {
    pub x: i32,
    pub y: i32,
    pub width: i32,
    pub height: i32,
    pub block_size: u32,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct DocumentBlurRectCommand {
    pub x: i32,
    pub y: i32,
    pub width: i32,
    pub height: i32,
    pub radius: u32,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct DocumentPathStyle {
    pub stroke_width: u32,
    pub r: u8,
    pub g: u8,
    pub b: u8,
    pub a: u8,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum DocumentCommand {
    Rect(DocumentRectCommand),
    FilledRect(DocumentRectCommand),
    Ellipse(DocumentEllipseCommand),
    FilledEllipse(DocumentEllipseCommand),
    Line(DocumentLineCommand),
    Arrow(DocumentArrowCommand),
    Path {
        points: Vec<I32Point>,
        style: DocumentPathStyle,
    },
    Text {
        text: String,
        cmd: DocumentTextCommand,
    },
    Pixelate(DocumentPixelateRectCommand),
    Blur(DocumentBlurRectCommand),
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct DocumentAnnotationInfo {
    pub index: u32,
    pub kind: u32,
    pub x: i32,
    pub y: i32,
    pub width: i32,
    pub height: i32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum DocumentError {
    InvalidArgument,
    InvalidIndex,
    NoOp,
    NothingToUndo,
    NothingToRedo,
}

impl DocumentError {
    pub fn code(self) -> i32 {
        match self {
            Self::InvalidArgument | Self::InvalidIndex => -2,
            Self::NoOp | Self::NothingToUndo | Self::NothingToRedo => 1,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct DocRect {
    x: i32,
    y: i32,
    width: i32,
    height: i32,
}

impl DocRect {
    fn to_ffi(self) -> I32Rect {
        I32Rect {
            x: self.x,
            y: self.y,
            width: self.width,
            height: self.height,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Document {
    pub width: u32,
    pub height: u32,
    pub stride: u32,
    pub base: Vec<u8>,
    pub commands: Vec<DocumentCommand>,
    pub cursor: usize,
    pub pending_dirty: Option<I32Rect>,
}

impl Document {
    pub fn new(width: u32, height: u32, stride: u32, base: Vec<u8>) -> Option<Self> {
        if width == 0 || height == 0 {
            return None;
        }
        if stride < width.saturating_mul(4) {
            return None;
        }
        let expected_len = (stride as usize).checked_mul(height as usize)?;
        if base.len() != expected_len {
            return None;
        }
        Some(Self {
            width,
            height,
            stride,
            base,
            commands: Vec::new(),
            cursor: 0,
            pending_dirty: None,
        })
    }

    pub fn expected_len(&self) -> Option<usize> {
        (self.stride as usize).checked_mul(self.height as usize)
    }

    pub fn image_width_i32(&self) -> i32 {
        self.width as i32
    }

    pub fn image_height_i32(&self) -> i32 {
        self.height as i32
    }

    pub fn full_image_rect(&self) -> I32Rect {
        I32Rect {
            x: 0,
            y: 0,
            width: self.image_width_i32(),
            height: self.image_height_i32(),
        }
    }

    pub fn applied_commands(&self) -> &[DocumentCommand] {
        let end = self.cursor.min(self.commands.len());
        &self.commands[..end]
    }

    pub fn command(&self, index: usize) -> Option<&DocumentCommand> {
        self.commands.get(index)
    }

    pub fn command_mut(&mut self, index: usize) -> Option<&mut DocumentCommand> {
        self.commands.get_mut(index)
    }

    pub fn has_global_effect_command(&self) -> bool {
        self.applied_commands()
            .iter()
            .any(DocumentCommand::is_global_effect)
    }

    pub fn add_dirty_full(&mut self) {
        self.pending_dirty = Some(self.full_image_rect());
    }

    pub fn add_dirty(&mut self, rect: Option<I32Rect>) {
        let Some(rect) = rect else {
            return;
        };
        let Some(clamped) = rect.clamp_to_image(self.image_width_i32(), self.image_height_i32())
        else {
            return;
        };

        self.pending_dirty = Some(match self.pending_dirty {
            Some(prev) => prev.union(clamped),
            None => clamped,
        });

        if self.has_global_effect_command() {
            self.add_dirty_full();
        }
    }

    pub fn clear_dirty(&mut self) {
        self.pending_dirty = None;
    }

    pub fn undo(&mut self) -> Result<bool, DocumentError> {
        if self.cursor == 0 {
            return Ok(false);
        }

        let command = &self.commands[self.cursor - 1];
        self.cursor -= 1;
        if command.is_global_effect() {
            self.add_dirty_full();
        } else {
            self.add_dirty(command.bounds());
        }
        Ok(true)
    }

    pub fn redo(&mut self) -> Result<bool, DocumentError> {
        if self.cursor >= self.commands.len() {
            return Ok(false);
        }

        let command = &self.commands[self.cursor];
        self.cursor += 1;
        if command.is_global_effect() {
            self.add_dirty_full();
        } else {
            self.add_dirty(command.bounds());
        }
        Ok(true)
    }

    pub fn add_rect(&mut self, cmd: DocumentRectCommand) -> Result<(), DocumentError> {
        let bounds = rect_command_bounds(cmd).ok_or(DocumentError::InvalidArgument)?;
        self.push_command(DocumentCommand::Rect(cmd), Some(bounds));
        Ok(())
    }

    pub fn add_filled_rect(&mut self, cmd: DocumentRectCommand) -> Result<(), DocumentError> {
        let bounds = rect_command_bounds(cmd).ok_or(DocumentError::InvalidArgument)?;
        self.push_command(DocumentCommand::FilledRect(cmd), Some(bounds));
        Ok(())
    }

    pub fn add_ellipse(&mut self, cmd: DocumentEllipseCommand) -> Result<(), DocumentError> {
        let bounds = ellipse_command_bounds(cmd).ok_or(DocumentError::InvalidArgument)?;
        self.push_command(DocumentCommand::Ellipse(cmd), Some(bounds));
        Ok(())
    }

    pub fn add_filled_ellipse(&mut self, cmd: DocumentEllipseCommand) -> Result<(), DocumentError> {
        let bounds = ellipse_command_bounds(cmd).ok_or(DocumentError::InvalidArgument)?;
        self.push_command(DocumentCommand::FilledEllipse(cmd), Some(bounds));
        Ok(())
    }

    pub fn add_line(&mut self, cmd: DocumentLineCommand) -> Result<(), DocumentError> {
        let bounds = line_command_bounds(cmd).ok_or(DocumentError::InvalidArgument)?;
        self.push_command(DocumentCommand::Line(cmd), Some(bounds));
        Ok(())
    }

    pub fn add_arrow(&mut self, cmd: DocumentArrowCommand) -> Result<(), DocumentError> {
        let bounds = arrow_command_bounds(cmd).ok_or(DocumentError::InvalidArgument)?;
        self.push_command(DocumentCommand::Arrow(cmd), Some(bounds));
        Ok(())
    }

    pub fn add_path(
        &mut self,
        points: Vec<I32Point>,
        style: DocumentPathStyle,
    ) -> Result<(), DocumentError> {
        let bounds = path_command_bounds(&points, style).ok_or(DocumentError::InvalidArgument)?;
        self.push_command(DocumentCommand::Path { points, style }, Some(bounds));
        Ok(())
    }

    pub fn add_text(
        &mut self,
        text: String,
        cmd: DocumentTextCommand,
    ) -> Result<(), DocumentError> {
        let bounds = text_command_bounds(&text, cmd).ok_or(DocumentError::InvalidArgument)?;
        self.push_command(DocumentCommand::Text { text, cmd }, Some(bounds));
        Ok(())
    }

    pub fn add_pixelate(&mut self, cmd: DocumentPixelateRectCommand) -> Result<(), DocumentError> {
        let bounds = effect_rect_bounds(cmd.x, cmd.y, cmd.width, cmd.height)
            .ok_or(DocumentError::InvalidArgument)?;
        self.push_command(DocumentCommand::Pixelate(cmd), Some(bounds));
        Ok(())
    }

    pub fn add_blur(&mut self, cmd: DocumentBlurRectCommand) -> Result<(), DocumentError> {
        let bounds = effect_rect_bounds(cmd.x, cmd.y, cmd.width, cmd.height)
            .ok_or(DocumentError::InvalidArgument)?;
        self.push_command(DocumentCommand::Blur(cmd), Some(bounds));
        Ok(())
    }

    pub fn remove_annotation(&mut self, index: usize) -> Result<(), DocumentError> {
        if index >= self.cursor || index >= self.commands.len() {
            return Err(DocumentError::InvalidIndex);
        }
        let removed = self.commands.remove(index);
        self.cursor = self.cursor.saturating_sub(1);
        if removed.is_global_effect() {
            self.add_dirty_full();
        } else {
            self.add_dirty(removed.bounds());
        }
        Ok(())
    }

    pub fn move_annotation(
        &mut self,
        index: usize,
        dx: i32,
        dy: i32,
    ) -> Result<bool, DocumentError> {
        if dx == 0 && dy == 0 {
            return Ok(false);
        }
        if index >= self.cursor {
            return Err(DocumentError::InvalidIndex);
        }

        let old_bounds = self
            .commands
            .get(index)
            .and_then(DocumentCommand::bounds)
            .ok_or(DocumentError::InvalidArgument)?;
        self.commands
            .get_mut(index)
            .ok_or(DocumentError::InvalidIndex)?
            .translate_by(dx, dy);
        let new_bounds = self.commands.get(index).and_then(DocumentCommand::bounds);
        self.add_dirty(Some(old_bounds));
        self.add_dirty(new_bounds);
        Ok(true)
    }

    pub fn resize_annotation(
        &mut self,
        index: usize,
        target: I32Rect,
    ) -> Result<bool, DocumentError> {
        if target.width <= 0 || target.height <= 0 {
            return Err(DocumentError::InvalidArgument);
        }
        if index >= self.cursor {
            return Err(DocumentError::InvalidIndex);
        }

        let old_bounds = self
            .commands
            .get(index)
            .and_then(DocumentCommand::bounds)
            .ok_or(DocumentError::InvalidArgument)?;
        let changed = self
            .commands
            .get_mut(index)
            .ok_or(DocumentError::InvalidIndex)?
            .resize_to(old_bounds, target);
        if !changed {
            return Ok(false);
        }
        let new_bounds = self.commands.get(index).and_then(DocumentCommand::bounds);
        self.add_dirty(Some(old_bounds));
        self.add_dirty(new_bounds);
        Ok(true)
    }

    pub fn copy_annotations_affine(
        &mut self,
        src: &Document,
        scale_x: f32,
        scale_y: f32,
        translate_x: f32,
        translate_y: f32,
    ) -> Result<(), DocumentError> {
        if !scale_x.is_finite()
            || !scale_y.is_finite()
            || !translate_x.is_finite()
            || !translate_y.is_finite()
            || scale_x.abs() < f32::EPSILON
            || scale_y.abs() < f32::EPSILON
        {
            return Err(DocumentError::InvalidArgument);
        }

        self.commands.clear();
        self.cursor = 0;

        if src.applied_commands().is_empty() {
            return Ok(());
        }

        let mut copied = Vec::with_capacity(src.applied_commands().len());
        for command in src.applied_commands() {
            let mut next = command.clone();
            next.transform_affine(scale_x, scale_y, translate_x, translate_y);
            copied.push(next);
        }

        self.commands = copied;
        self.cursor = self.commands.len();
        self.add_dirty_full();
        Ok(())
    }

    pub fn list_annotations(&self) -> Vec<DocumentAnnotationInfo> {
        self.applied_commands()
            .iter()
            .enumerate()
            .filter_map(|(index, command)| {
                let bounds = command.bounds()?;
                Some(DocumentAnnotationInfo {
                    index: index as u32,
                    kind: command.annotation_kind(),
                    x: bounds.x,
                    y: bounds.y,
                    width: bounds.width,
                    height: bounds.height,
                })
            })
            .collect()
    }

    fn push_command(&mut self, command: DocumentCommand, bounds: Option<DocRect>) {
        if self.cursor < self.commands.len() {
            self.commands.truncate(self.cursor);
        }
        self.commands.push(command);
        self.cursor = self.commands.len();
        if let Some(bounds) = bounds {
            self.add_dirty(Some(bounds.to_ffi()));
        }
    }
}

impl DocumentCommand {
    pub fn annotation_kind(&self) -> u32 {
        match self {
            Self::Rect(_) => 1,
            Self::FilledRect(_) => 2,
            Self::Ellipse(_) => 3,
            Self::FilledEllipse(_) => 4,
            Self::Line(_) => 5,
            Self::Arrow(_) => 6,
            Self::Path { .. } => 7,
            Self::Text { .. } => 8,
            Self::Pixelate(_) => 9,
            Self::Blur(_) => 10,
        }
    }

    pub fn is_global_effect(&self) -> bool {
        matches!(self, Self::Pixelate(_) | Self::Blur(_))
    }

    pub fn bounds(&self) -> Option<I32Rect> {
        match self {
            Self::Rect(cmd) | Self::FilledRect(cmd) => {
                rect_command_bounds(*cmd).map(DocRect::to_ffi)
            }
            Self::Ellipse(cmd) | Self::FilledEllipse(cmd) => {
                ellipse_command_bounds(*cmd).map(DocRect::to_ffi)
            }
            Self::Line(cmd) => line_command_bounds(*cmd).map(DocRect::to_ffi),
            Self::Arrow(cmd) => arrow_command_bounds(*cmd).map(DocRect::to_ffi),
            Self::Path { points, style } => {
                path_command_bounds(points, *style).map(DocRect::to_ffi)
            }
            Self::Text { text, cmd } => text_command_bounds(text, *cmd).map(DocRect::to_ffi),
            Self::Pixelate(cmd) => {
                effect_rect_bounds(cmd.x, cmd.y, cmd.width, cmd.height).map(DocRect::to_ffi)
            }
            Self::Blur(cmd) => {
                effect_rect_bounds(cmd.x, cmd.y, cmd.width, cmd.height).map(DocRect::to_ffi)
            }
        }
    }

    fn translate_by(&mut self, dx: i32, dy: i32) {
        match self {
            Self::Rect(rect) | Self::FilledRect(rect) => {
                rect.x = rect.x.saturating_add(dx);
                rect.y = rect.y.saturating_add(dy);
            }
            Self::Ellipse(ellipse) | Self::FilledEllipse(ellipse) => {
                ellipse.x = ellipse.x.saturating_add(dx);
                ellipse.y = ellipse.y.saturating_add(dy);
            }
            Self::Line(line) => {
                line.x0 = line.x0.saturating_add(dx);
                line.y0 = line.y0.saturating_add(dy);
                line.x1 = line.x1.saturating_add(dx);
                line.y1 = line.y1.saturating_add(dy);
            }
            Self::Arrow(arrow) => {
                arrow.x0 = arrow.x0.saturating_add(dx);
                arrow.y0 = arrow.y0.saturating_add(dy);
                arrow.x1 = arrow.x1.saturating_add(dx);
                arrow.y1 = arrow.y1.saturating_add(dy);
            }
            Self::Path { points, .. } => {
                for point in points.iter_mut() {
                    point.x = point.x.saturating_add(dx);
                    point.y = point.y.saturating_add(dy);
                }
            }
            Self::Text { cmd, .. } => {
                cmd.x = cmd.x.saturating_add(dx);
                cmd.y = cmd.y.saturating_add(dy);
            }
            Self::Pixelate(pixelate) => {
                pixelate.x = pixelate.x.saturating_add(dx);
                pixelate.y = pixelate.y.saturating_add(dy);
            }
            Self::Blur(blur) => {
                blur.x = blur.x.saturating_add(dx);
                blur.y = blur.y.saturating_add(dy);
            }
        }
    }

    fn transform_affine(&mut self, scale_x: f32, scale_y: f32, translate_x: f32, translate_y: f32) {
        let transform = AffineTransform {
            scale_x,
            scale_y,
            translate_x,
            translate_y,
        };
        match self {
            Self::Rect(rect) | Self::FilledRect(rect) => {
                let (x, y, width, height) =
                    transform_rect_affine(rect.x, rect.y, rect.width, rect.height, transform);
                rect.x = x;
                rect.y = y;
                rect.width = width;
                rect.height = height;
            }
            Self::Ellipse(ellipse) | Self::FilledEllipse(ellipse) => {
                let (x, y, width, height) = transform_rect_affine(
                    ellipse.x,
                    ellipse.y,
                    ellipse.width,
                    ellipse.height,
                    transform,
                );
                ellipse.x = x;
                ellipse.y = y;
                ellipse.width = width;
                ellipse.height = height;
            }
            Self::Line(line) => {
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
            Self::Arrow(arrow) => {
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
            Self::Path { points, .. } => {
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
            Self::Text { cmd, .. } => {
                let (x, y) = transform_point_affine(
                    cmd.x,
                    cmd.y,
                    scale_x,
                    scale_y,
                    translate_x,
                    translate_y,
                );
                cmd.x = x;
                cmd.y = y;
                let avg_scale = ((scale_x.abs() + scale_y.abs()) * 0.5).clamp(0.25, 8.0);
                cmd.font_px = ((cmd.font_px as f32) * avg_scale).round().clamp(8.0, 256.0) as u32;
            }
            Self::Pixelate(pixelate) => {
                let (x, y, width, height) = transform_rect_affine(
                    pixelate.x,
                    pixelate.y,
                    pixelate.width,
                    pixelate.height,
                    transform,
                );
                pixelate.x = x;
                pixelate.y = y;
                pixelate.width = width;
                pixelate.height = height;
            }
            Self::Blur(blur) => {
                let (x, y, width, height) =
                    transform_rect_affine(blur.x, blur.y, blur.width, blur.height, transform);
                blur.x = x;
                blur.y = y;
                blur.width = width;
                blur.height = height;
            }
        }
    }

    fn resize_to(&mut self, from: I32Rect, to: I32Rect) -> bool {
        if from.width <= 0 || from.height <= 0 || to.width <= 0 || to.height <= 0 {
            return false;
        }

        match self {
            Self::Rect(rect) | Self::FilledRect(rect) => {
                let next = rect_from_bounds(*rect, to);
                if rect_equals(*rect, next) {
                    return false;
                }
                *rect = next;
                true
            }
            Self::Ellipse(ellipse) | Self::FilledEllipse(ellipse) => {
                let next = ellipse_from_bounds(*ellipse, to);
                if ellipse_equals(*ellipse, next) {
                    return false;
                }
                *ellipse = next;
                true
            }
            Self::Line(line) => {
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
            Self::Arrow(arrow) => {
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
            Self::Path { points, .. } => {
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
            Self::Text { cmd, .. } => {
                let old_w = from.width.max(1) as f32;
                let old_h = from.height.max(1) as f32;
                let new_w = to.width.max(1) as f32;
                let new_h = to.height.max(1) as f32;
                let scale = ((new_w / old_w) + (new_h / old_h)) * 0.5;
                let font_px = ((cmd.font_px as f32) * scale).round().clamp(8.0, 256.0) as u32;
                if cmd.x == to.x && cmd.y == to.y && cmd.font_px == font_px {
                    return false;
                }
                cmd.x = to.x;
                cmd.y = to.y;
                cmd.font_px = font_px;
                true
            }
            Self::Pixelate(pixelate) => {
                let width = to.width.max(1);
                let height = to.height.max(1);
                if pixelate.x == to.x
                    && pixelate.y == to.y
                    && pixelate.width == width
                    && pixelate.height == height
                {
                    return false;
                }
                pixelate.x = to.x;
                pixelate.y = to.y;
                pixelate.width = width;
                pixelate.height = height;
                true
            }
            Self::Blur(blur) => {
                let width = to.width.max(1);
                let height = to.height.max(1);
                if blur.x == to.x && blur.y == to.y && blur.width == width && blur.height == height
                {
                    return false;
                }
                blur.x = to.x;
                blur.y = to.y;
                blur.width = width;
                blur.height = height;
                true
            }
        }
    }
}

fn rect_command_bounds(cmd: DocumentRectCommand) -> Option<DocRect> {
    if cmd.width <= 0 || cmd.height <= 0 {
        return None;
    }
    Some(DocRect {
        x: cmd.x,
        y: cmd.y,
        width: cmd.width,
        height: cmd.height,
    })
}

fn ellipse_command_bounds(cmd: DocumentEllipseCommand) -> Option<DocRect> {
    if cmd.width <= 0 || cmd.height <= 0 {
        return None;
    }
    Some(DocRect {
        x: cmd.x,
        y: cmd.y,
        width: cmd.width,
        height: cmd.height,
    })
}

fn line_command_bounds(cmd: DocumentLineCommand) -> Option<DocRect> {
    if cmd.x0 == cmd.x1 && cmd.y0 == cmd.y1 {
        return None;
    }
    let pad = ((cmd.stroke_width as i32).max(1) + 1) / 2 + 1;
    Some(DocRect {
        x: cmd.x0.min(cmd.x1).saturating_sub(pad),
        y: cmd.y0.min(cmd.y1).saturating_sub(pad),
        width: cmd
            .x0
            .max(cmd.x1)
            .saturating_sub(cmd.x0.min(cmd.x1))
            .saturating_add(pad * 2 + 1),
        height: cmd
            .y0
            .max(cmd.y1)
            .saturating_sub(cmd.y0.min(cmd.y1))
            .saturating_add(pad * 2 + 1),
    })
}

fn path_command_bounds(points: &[I32Point], style: DocumentPathStyle) -> Option<DocRect> {
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
    Some(DocRect {
        x: min_x.saturating_sub(pad),
        y: min_y.saturating_sub(pad),
        width: max_x.saturating_sub(min_x).saturating_add(pad * 2 + 1),
        height: max_y.saturating_sub(min_y).saturating_add(pad * 2 + 1),
    })
}

fn arrow_command_bounds(cmd: DocumentArrowCommand) -> Option<DocRect> {
    if cmd.x0 == cmd.x1 && cmd.y0 == cmd.y1 {
        return None;
    }
    let stroke = (cmd.stroke_width as i32).max(1);
    let head_len = (stroke * 6).max(16);
    let pad = head_len + stroke;
    Some(DocRect {
        x: cmd.x0.min(cmd.x1).saturating_sub(pad),
        y: cmd.y0.min(cmd.y1).saturating_sub(pad),
        width: cmd
            .x0
            .max(cmd.x1)
            .saturating_sub(cmd.x0.min(cmd.x1))
            .saturating_add(pad * 2 + 1),
        height: cmd
            .y0
            .max(cmd.y1)
            .saturating_sub(cmd.y0.min(cmd.y1))
            .saturating_add(pad * 2 + 1),
    })
}

fn effect_rect_bounds(x: i32, y: i32, width: i32, height: i32) -> Option<DocRect> {
    if width <= 0 || height <= 0 {
        return None;
    }
    Some(DocRect {
        x,
        y,
        width,
        height,
    })
}

fn text_command_bounds(text: &str, cmd: DocumentTextCommand) -> Option<DocRect> {
    if text.is_empty() {
        return None;
    }
    let px = cmd.font_px.clamp(8, 144) as i32;
    let glyph_w = (px * 5) / 4;
    let line_h = (px * 3) / 2;
    let mut max_chars = 0i32;
    let mut lines = 0i32;
    for line in text.lines() {
        lines += 1;
        max_chars = max_chars.max(line.chars().count() as i32);
    }
    if lines == 0 {
        lines = 1;
    }
    Some(DocRect {
        x: cmd.x,
        y: cmd.y,
        width: max_chars.max(1).saturating_mul(glyph_w).max(px),
        height: lines.saturating_mul(line_h).max(px),
    })
}

fn rect_from_bounds(prev: DocumentRectCommand, bounds: I32Rect) -> DocumentRectCommand {
    DocumentRectCommand {
        x: bounds.x,
        y: bounds.y,
        width: bounds.width.max(1),
        height: bounds.height.max(1),
        ..prev
    }
}

fn ellipse_from_bounds(prev: DocumentEllipseCommand, bounds: I32Rect) -> DocumentEllipseCommand {
    DocumentEllipseCommand {
        x: bounds.x,
        y: bounds.y,
        width: bounds.width.max(1),
        height: bounds.height.max(1),
        ..prev
    }
}

fn rect_equals(lhs: DocumentRectCommand, rhs: DocumentRectCommand) -> bool {
    lhs.x == rhs.x && lhs.y == rhs.y && lhs.width == rhs.width && lhs.height == rhs.height
}

fn ellipse_equals(lhs: DocumentEllipseCommand, rhs: DocumentEllipseCommand) -> bool {
    lhs.x == rhs.x && lhs.y == rhs.y && lhs.width == rhs.width && lhs.height == rhs.height
}

fn scale_point_between_rects(px: i32, py: i32, from: I32Rect, to: I32Rect) -> (i32, i32) {
    let from_w = from.width.max(1) as f32;
    let from_h = from.height.max(1) as f32;
    let to_w = to.width.max(1) as f32;
    let to_h = to.height.max(1) as f32;
    let nx = (px.saturating_sub(from.x) as f32) / from_w;
    let ny = (py.saturating_sub(from.y) as f32) / from_h;
    let x = to.x as f32 + nx * to_w;
    let y = to.y as f32 + ny * to_h;
    (x.round() as i32, y.round() as i32)
}

#[derive(Clone, Copy)]
struct AffineTransform {
    scale_x: f32,
    scale_y: f32,
    translate_x: f32,
    translate_y: f32,
}

fn transform_rect_affine(
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    transform: AffineTransform,
) -> (i32, i32, i32, i32) {
    let x0 = x as f32 * transform.scale_x + transform.translate_x;
    let y0 = y as f32 * transform.scale_y + transform.translate_y;
    let x1 = x.saturating_add(width) as f32 * transform.scale_x + transform.translate_x;
    let y1 = y.saturating_add(height) as f32 * transform.scale_y + transform.translate_y;
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
