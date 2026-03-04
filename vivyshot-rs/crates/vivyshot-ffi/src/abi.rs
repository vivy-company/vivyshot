use super::*;

#[repr(C)]
#[derive(Clone, Copy)]
pub struct vs_rect_command {
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

#[repr(C)]
#[derive(Clone, Copy)]
pub struct vs_ellipse_command {
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

#[repr(C)]
#[derive(Clone, Copy)]
pub struct vs_line_command {
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

#[repr(C)]
#[derive(Clone, Copy)]
pub struct vs_arrow_command {
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

#[repr(C)]
#[derive(Clone, Copy)]
pub struct vs_text_command {
    pub x: i32,
    pub y: i32,
    pub font_px: u32,
    pub r: u8,
    pub g: u8,
    pub b: u8,
    pub a: u8,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct vs_pixelate_rect_command {
    pub x: i32,
    pub y: i32,
    pub width: i32,
    pub height: i32,
    pub block_size: u32,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct vs_blur_rect_command {
    pub x: i32,
    pub y: i32,
    pub width: i32,
    pub height: i32,
    pub radius: u32,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct vs_path_style {
    pub stroke_width: u32,
    pub r: u8,
    pub g: u8,
    pub b: u8,
    pub a: u8,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct vs_point_i32 {
    pub x: i32,
    pub y: i32,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct vs_dirty_rect {
    pub x: i32,
    pub y: i32,
    pub width: i32,
    pub height: i32,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct vs_annotation_info {
    pub index: u32,
    pub kind: u32,
    pub x: i32,
    pub y: i32,
    pub width: i32,
    pub height: i32,
}

#[repr(C)]
#[derive(Clone, Copy, Serialize, Deserialize)]
pub struct vs_video_session_config {
    pub frame_rate: u32,
    pub capture_system_audio: bool,
    pub capture_microphone: bool,
    pub show_webcam: bool,
    pub highlight_mouse_clicks: bool,
    pub highlight_keystrokes: bool,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct vs_video_key_event {
    pub timestamp_ns: u64,
    pub token_ptr: *const u8,
    pub token_len: usize,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct vs_video_click_event {
    pub timestamp_ns: u64,
    pub normalized_x: f32,
    pub normalized_y: f32,
    pub button: u32,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct vs_video_export_plan {
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

#[repr(C)]
#[derive(Clone, Copy)]
pub struct vs_video_export_decision {
    pub use_custom_compositor: bool,
    pub requires_intermediate_for_gif: bool,
    pub include_audio: bool,
    pub include_webcam: bool,
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct vs_video_overlay_label_layout {
    pub width: f32,
    pub height: f32,
    pub y: f32,
    pub font_size: f32,
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct vs_video_overlay_clip_window {
    pub start_seconds: f64,
    pub end_seconds: f64,
    pub fade_duration_seconds: f64,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct vs_video_export_context {
    pub source_has_audio: bool,
    pub source_has_webcam_asset: bool,
    pub audio_track_visible: bool,
    pub webcam_track_visible: bool,
    pub text_overlay_count: u32,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct vs_bgra_image_view {
    pub width: u32,
    pub height: u32,
    pub stride: u32,
    pub ptr: *const u8,
    pub len: usize,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct vs_bgra_owned_image {
    pub width: u32,
    pub height: u32,
    pub stride: u32,
    pub ptr: *mut u8,
    pub len: usize,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct vs_encoded_bytes {
    pub ptr: *mut u8,
    pub len: usize,
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct vs_stitch_delta {
    pub rows: u32,
    pub side: u8,
    pub score: f32,
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct vs_stitch_session_result {
    pub accepted: bool,
    pub rows: u32,
    pub side: u8,
    pub score: f32,
    pub direction_locked: bool,
    pub expected_rows: u32,
    pub segment_count: u32,
    pub scroll_direction_sign: i32,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct vs_overlay_key_event_input {
    pub timestamp_ns: u64,
    pub token_len: u32,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct vs_overlay_text_clip_input {
    pub start_ms: u32,
    pub end_ms: u32,
    pub text_len: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct vs_overlay_plan_item {
    pub kind: u8,
    pub source_index: u32,
    pub start_ms: u32,
    pub duration_ms: u32,
    pub x_norm: f32,
    pub y_norm: f32,
    pub width_norm: f32,
    pub height_norm: f32,
    pub font_size_px: f32,
    pub corner_radius_norm: f32,
    pub fade_in_frac: f32,
    pub hold_frac: f32,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct vs_clip_transform {
    pub x: f32,
    pub y: f32,
    pub width: f32,
    pub height: f32,
    pub rotation: f32,
    pub opacity: f32,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct vs_timeline_track_info {
    pub kind: u8,
    pub visible: bool,
    pub clip_count: u32,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct vs_timeline_clip_info {
    pub id: u32,
    pub track_index: u32,
    pub start_ms: u32,
    pub end_ms: u32,
    pub kind: u8,
    pub transform: vs_clip_transform,
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct vs_f32_rect {
    pub x: f32,
    pub y: f32,
    pub width: f32,
    pub height: f32,
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct vs_f32_point {
    pub x: f32,
    pub y: f32,
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct vs_i32_rect {
    pub x: i32,
    pub y: i32,
    pub width: i32,
    pub height: i32,
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct vs_rgba8 {
    pub r: u8,
    pub g: u8,
    pub b: u8,
    pub a: u8,
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct vs_gif_export_plan {
    pub start_ms: u32,
    pub end_ms: u32,
    pub frame_rate: f32,
    pub frame_count: u32,
    pub max_dimension: u32,
    pub frame_delay_ms: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct vs_stitch_autoscroll_state {
    pub direction_sign: i32,
    pub no_motion_ticks: u32,
    pub did_flip_direction: bool,
}
