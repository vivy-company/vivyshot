pub enum TrimHandle {
    Unknown,
    Start,
    End,
}

pub const VIDEO_PLAN_MODE_PASSTHROUGH: u8 = 0;
pub const VIDEO_PLAN_MODE_COMPOSITE_MP4: u8 = 1;
pub const VIDEO_EXPORT_TARGET_MP4: u8 = 0;
pub const VIDEO_EXPORT_TARGET_GIF: u8 = 1;
pub const VIDEO_KEY_OVERLAY_FADE_DURATION_SECONDS: f32 = 0.95;
pub const VIDEO_KEY_OVERLAY_FADE_IN_KEYTIME: f32 = 0.10;
pub const VIDEO_KEY_OVERLAY_FADE_HOLD_KEYTIME: f32 = 0.78;
pub const VIDEO_TEXT_OVERLAY_FADE_IN_KEYTIME: f32 = 0.08;
pub const VIDEO_TEXT_OVERLAY_FADE_HOLD_KEYTIME: f32 = 0.92;
pub const VIDEO_TEXT_OVERLAY_MIN_VISIBLE_SECONDS: f64 = 0.05;
pub const VIDEO_TEXT_OVERLAY_MIN_FADE_DURATION_SECONDS: f64 = 0.10;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct VideoExportContext {
    pub source_has_audio: bool,
    pub source_has_webcam_asset: bool,
    pub audio_track_visible: bool,
    pub webcam_track_visible: bool,
    pub text_overlay_count: u32,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct VideoExportPlan {
    pub trim_start_ms: u32,
    pub trim_end_ms: u32,
    pub key_event_count: u32,
    pub click_event_count: u32,
    pub plan_mode: u8,
    pub include_audio: bool,
    pub include_webcam: bool,
    pub text_overlay_count: u32,
    pub overlay_item_count: u32,
    pub requires_intermediate_for_gif: bool,
    pub needs_custom_compositor: bool,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct VideoExportDecision {
    pub use_custom_compositor: bool,
    pub requires_intermediate_for_gif: bool,
    pub include_audio: bool,
    pub include_webcam: bool,
}

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct VideoOverlayLabelLayout {
    pub width: f32,
    pub height: f32,
    pub y: f32,
    pub font_size: f32,
}

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct VideoOverlayClipWindow {
    pub start_seconds: f64,
    pub end_seconds: f64,
}

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct GifExportPlan {
    pub start_ms: u32,
    pub end_ms: u32,
    pub frame_rate: f32,
    pub frame_count: u32,
    pub max_dimension: u32,
    pub frame_delay_ms: u32,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct StitchAutoscrollState {
    pub direction_sign: i32,
    pub no_motion_ticks: u32,
    pub did_flip_direction: bool,
}

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct F32Rect {
    pub x: f32,
    pub y: f32,
    pub width: f32,
    pub height: f32,
}

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct F32Point {
    pub x: f32,
    pub y: f32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ResizeCorner {
    TopLeft,
    Top,
    TopRight,
    Right,
    Bottom,
    Left,
    BottomLeft,
    BottomRight,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct TimelineTrackSummary {
    pub kind: u8,
    pub visible: bool,
    pub clip_count: u32,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct TimelineTextClipExportInput {
    pub track_index: u32,
    pub track_order: u32,
    pub clip_id: u32,
    pub start_ms: u32,
    pub end_ms: u32,
    pub track_visible: bool,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct TimelineTextClipExportRef {
    pub track_index: u32,
    pub clip_id: u32,
    pub start_ms: u32,
    pub end_ms: u32,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct I32Rect {
    pub x: i32,
    pub y: i32,
    pub width: i32,
    pub height: i32,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Rgba8 {
    pub r: u8,
    pub g: u8,
    pub b: u8,
    pub a: u8,
}

pub const STITCH_SIDE_TOP: u8 = 0;
pub const STITCH_SIDE_BOTTOM: u8 = 1;

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct StitchDelta {
    pub rows: u32,
    pub side: u8,
    pub score: f32,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct BgraImageOwned {
    pub width: u32,
    pub height: u32,
    pub stride: u32,
    pub pixels: Vec<u8>,
}

#[derive(Clone, Copy, Debug)]
pub struct BgraImageView<'a> {
    pub width: u32,
    pub height: u32,
    pub stride: u32,
    pub pixels: &'a [u8],
}

