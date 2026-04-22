pub enum TrimHandle {
    Unknown,
    Start,
    End,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum VideoExportCodec {
    H264,
    Hevc,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum VideoExportFrameRate {
    Fps30,
    Fps60,
    Fps120,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum VideoExportQuality {
    Standard,
    High,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum VideoExportScale {
    Full,
    Percent75,
    Percent50,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum VideoExportBitratePreset {
    Standard,
    High,
    VeryHigh,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum VideoExportContainer {
    Mp4,
    Mov,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum VideoExportPreset {
    HighestQuality,
    Resolution1920x1080,
    Resolution1280x720,
    MediumQuality,
    HevcResolution1920x1080,
    HevcHighestQuality,
}

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct AffineTransform {
    pub a: f32,
    pub b: f32,
    pub c: f32,
    pub d: f32,
    pub tx: f32,
    pub ty: f32,
}

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct VideoPostRecordingCompositionPlan {
    pub render_width: u32,
    pub render_height: u32,
    pub transform: AffineTransform,
}

pub const VIDEO_PLAN_MODE_PASSTHROUGH: u8 = 0;
pub const VIDEO_PLAN_MODE_COMPOSITE_MP4: u8 = 1;
pub const VIDEO_EXPORT_TARGET_MP4: u8 = 0;
pub const VIDEO_EXPORT_TARGET_GIF: u8 = 1;
pub const VIDEO_EXPORT_CONTAINER_MP4: u8 = 0;
pub const VIDEO_EXPORT_CONTAINER_MOV: u8 = 1;
pub const VIDEO_EXPORT_PRESET_HIGHEST_QUALITY: u8 = 0;
pub const VIDEO_EXPORT_PRESET_1920X1080: u8 = 1;
pub const VIDEO_EXPORT_PRESET_1280X720: u8 = 2;
pub const VIDEO_EXPORT_PRESET_MEDIUM_QUALITY: u8 = 3;
pub const VIDEO_EXPORT_PRESET_HEVC_1920X1080: u8 = 4;
pub const VIDEO_EXPORT_PRESET_HEVC_HIGHEST_QUALITY: u8 = 5;
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

impl VideoExportCodec {
    pub fn compression_multiplier(self) -> f64 {
        match self {
            Self::H264 => 1.0,
            Self::Hevc => 0.78,
        }
    }
}

impl VideoExportFrameRate {
    pub fn multiplier(self) -> f64 {
        match self {
            Self::Fps30 => 1.0,
            Self::Fps60 => 1.35,
            Self::Fps120 => 1.8,
        }
    }
}

impl VideoExportQuality {
    pub fn multiplier(self) -> f64 {
        match self {
            Self::Standard => 1.0,
            Self::High => 1.2,
        }
    }
}

impl VideoExportScale {
    pub fn factor(self) -> f64 {
        match self {
            Self::Full => 1.0,
            Self::Percent75 => 0.75,
            Self::Percent50 => 0.5,
        }
    }

    pub fn multiplier(self) -> f64 {
        match self {
            Self::Full => 1.0,
            Self::Percent75 => 0.72,
            Self::Percent50 => 0.55,
        }
    }
}

impl VideoExportBitratePreset {
    pub fn base_bits_per_second(self) -> f64 {
        match self {
            Self::Standard => 8_000_000.0,
            Self::High => 14_000_000.0,
            Self::VeryHigh => 22_000_000.0,
        }
    }
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

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct I32Point {
    pub x: i32,
    pub y: i32,
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

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct TimelineClipTransform {
    pub x: f32,
    pub y: f32,
    pub width: f32,
    pub height: f32,
    pub rotation: f32,
    pub opacity: f32,
}

impl Default for TimelineClipTransform {
    fn default() -> Self {
        Self {
            x: 0.0,
            y: 0.0,
            width: 1.0,
            height: 1.0,
            rotation: 0.0,
            opacity: 1.0,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct TimelineTextStyle {
    pub font_size: f32,
    pub color: u32,
    pub bg_color: u32,
}

impl Default for TimelineTextStyle {
    fn default() -> Self {
        Self {
            font_size: 16.0,
            color: 0xFFFFFFFF,
            bg_color: 0x00000000,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct TimelineShapeStyle {
    pub fill: u32,
    pub border: u32,
    pub border_width: f32,
    pub corner_radius: f32,
}

impl Default for TimelineShapeStyle {
    fn default() -> Self {
        Self {
            fill: 0xFFFFFFFF,
            border: 0xFF000000,
            border_width: 2.0,
            corner_radius: 0.0,
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub enum TimelineClipData {
    Video,
    Webcam,
    Audio,
    Text {
        text: String,
        style: TimelineTextStyle,
    },
    Shape {
        style: TimelineShapeStyle,
    },
    Cursor,
    Zoom {
        scale: f32,
    },
}

impl TimelineClipData {
    pub fn from_kind(kind: u8) -> Option<Self> {
        match kind {
            0 => Some(Self::Video),
            1 => Some(Self::Webcam),
            2 => Some(Self::Audio),
            3 => Some(Self::Text {
                text: String::new(),
                style: TimelineTextStyle::default(),
            }),
            4 => Some(Self::Shape {
                style: TimelineShapeStyle::default(),
            }),
            5 => Some(Self::Cursor),
            6 => Some(Self::Zoom { scale: 2.0 }),
            _ => None,
        }
    }

    pub fn kind(&self) -> u8 {
        match self {
            Self::Video => 0,
            Self::Webcam => 1,
            Self::Audio => 2,
            Self::Text { .. } => 3,
            Self::Shape { .. } => 4,
            Self::Cursor => 5,
            Self::Zoom { .. } => 6,
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct TimelineClip {
    pub id: u32,
    pub start_ms: u32,
    pub end_ms: u32,
    pub transform: TimelineClipTransform,
    pub data: TimelineClipData,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct TimelineTrack {
    pub kind: u8,
    pub visible: bool,
    pub clips: Vec<TimelineClip>,
}

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct TimelineClipSnapshot {
    pub id: u32,
    pub track_index: u32,
    pub start_ms: u32,
    pub end_ms: u32,
    pub kind: u8,
    pub transform: TimelineClipTransform,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct I32Rect {
    pub x: i32,
    pub y: i32,
    pub width: i32,
    pub height: i32,
}

impl I32Rect {
    pub fn width(self) -> i32 {
        self.width
    }

    pub fn height(self) -> i32 {
        self.height
    }

    pub fn is_empty(self) -> bool {
        self.width <= 0 || self.height <= 0
    }

    pub fn intersect(self, other: I32Rect) -> Option<I32Rect> {
        let x0 = self.x.max(other.x);
        let y0 = self.y.max(other.y);
        let x1 = (self.x.saturating_add(self.width)).min(other.x.saturating_add(other.width));
        let y1 = (self.y.saturating_add(self.height)).min(other.y.saturating_add(other.height));
        let rect = I32Rect {
            x: x0,
            y: y0,
            width: x1.saturating_sub(x0),
            height: y1.saturating_sub(y0),
        };
        if rect.is_empty() {
            None
        } else {
            Some(rect)
        }
    }

    pub fn union(self, other: I32Rect) -> I32Rect {
        let x0 = self.x.min(other.x);
        let y0 = self.y.min(other.y);
        let x1 = self
            .x
            .saturating_add(self.width)
            .max(other.x.saturating_add(other.width));
        let y1 = self
            .y
            .saturating_add(self.height)
            .max(other.y.saturating_add(other.height));
        I32Rect {
            x: x0,
            y: y0,
            width: x1.saturating_sub(x0),
            height: y1.saturating_sub(y0),
        }
    }

    pub fn clamp_to_image(self, width: i32, height: i32) -> Option<I32Rect> {
        self.intersect(I32Rect {
            x: 0,
            y: 0,
            width,
            height,
        })
    }
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
