//! C ABI adapter for VivyShot portable core logic.
//!
//! This crate owns `extern "C"` interop, pointer validation, and memory
//! ownership across the FFI boundary. Portable policy/state machines should
//! live in `vivyshot-core` and be called from this adapter.
#![allow(clippy::manual_clamp)]
#![allow(clippy::missing_safety_doc)]
#![allow(clippy::too_many_arguments)]
#![allow(clippy::unnecessary_cast)]
#![allow(clippy::wrong_self_convention)]

use font8x8::UnicodeFonts;
use fontdue::layout::{CoordinateSystem, Layout, LayoutSettings, TextStyle};
use image::codecs::jpeg::JpegEncoder;
use image::codecs::png::PngEncoder;
use image::{ColorType, ImageEncoder};
use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use std::ffi::c_void;
use std::fs;
use std::os::raw::c_char;
use std::slice;
use std::sync::{Mutex, OnceLock};
use vivyshot_domain::{
    bgra_view_to_owned as domain_bgra_view_to_owned,
    build_gif_export_plan as domain_build_gif_export_plan,
    click_event_is_duplicate as domain_click_event_is_duplicate,
    derive_video_export_decision as domain_derive_video_export_decision,
    gif_frame_time_ms as domain_gif_frame_time_ms,
    normalize_click_point as domain_normalize_click_point,
    normalize_trim_range as domain_normalize_trim_range,
    quantize_image_point as domain_quantize_image_point,
    quantize_image_rect as domain_quantize_image_rect, quantize_rgba as domain_quantize_rgba,
    stitch_autoscroll_reset as domain_stitch_autoscroll_reset,
    stitch_autoscroll_update as domain_stitch_autoscroll_update,
    stitch_crop_frame as domain_stitch_crop_frame,
    stitch_extract_strip as domain_stitch_extract_strip,
    stitch_merge_frames as domain_stitch_merge_frames,
    stitch_resize_width_nearest as domain_stitch_resize_width_nearest,
    timeline_clamp_clip_end as domain_timeline_clamp_clip_end,
    timeline_full_duration_end as domain_timeline_full_duration_end,
    timeline_normalize_text_clip_range as domain_timeline_normalize_text_clip_range,
    BgraImageOwned as DomainBgraImageOwned, BgraImageView as DomainBgraImageView,
    STITCH_SIDE_BOTTOM as DOMAIN_STITCH_SIDE_BOTTOM, STITCH_SIDE_TOP as DOMAIN_STITCH_SIDE_TOP,
};

#[cfg(test)]
use vivyshot_domain::VIDEO_PLAN_MODE_COMPOSITE_MP4 as DOMAIN_VIDEO_PLAN_MODE_COMPOSITE_MP4;

mod ffi;

use ffi::document as ffi_document;
use ffi::domain::{
    to_domain_f32_rect, to_domain_gif_plan, to_domain_stitch_autoscroll_state,
    to_domain_trim_handle, to_domain_video_export_plan, to_ffi_gif_plan, to_ffi_i32_rect,
    to_ffi_rgba8, to_ffi_stitch_autoscroll_state, to_ffi_video_export_decision,
};
use ffi::encode as ffi_encode;
use ffi::geometry as ffi_geometry;
use ffi::stitch as ffi_stitch;
use ffi::timeline as ffi_timeline;
use ffi::video as ffi_video;

static VERSION: &[u8] = b"0.1.0\0";
static SYSTEM_FONTS: OnceLock<Vec<fontdue::Font>> = OnceLock::new();
static DOCUMENT_HANDLES: OnceLock<Mutex<HashSet<usize>>> = OnceLock::new();
static VIDEO_SESSION_HANDLES: OnceLock<Mutex<HashSet<usize>>> = OnceLock::new();
static STITCH_SESSION_HANDLES: OnceLock<Mutex<HashSet<usize>>> = OnceLock::new();
static TIMELINE_HANDLES: OnceLock<Mutex<HashSet<usize>>> = OnceLock::new();

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

#[derive(Clone, Serialize, Deserialize)]
struct VsVideoKeyEvent {
    timestamp_ns: u64,
    token: String,
}

#[derive(Clone, Copy, Serialize, Deserialize)]
struct VsVideoClickEvent {
    timestamp_ns: u64,
    normalized_x: f32,
    normalized_y: f32,
    button: u32,
}

#[repr(C)]
struct vs_video_session {
    config: vs_video_session_config,
    key_events: Vec<VsVideoKeyEvent>,
    click_events: Vec<VsVideoClickEvent>,
    trim_start_ms: u32,
    trim_end_ms: u32,
    source_has_audio: bool,
    source_has_webcam_asset: bool,
    audio_track_visible: bool,
    webcam_track_visible: bool,
    text_overlay_count: u32,
}

#[derive(Serialize, Deserialize)]
struct VsVideoSessionSnapshot {
    version: u32,
    config: vs_video_session_config,
    key_events: Vec<VsVideoKeyEvent>,
    click_events: Vec<VsVideoClickEvent>,
    trim_start_ms: u32,
    trim_end_ms: u32,
    source_has_audio: bool,
    source_has_webcam_asset: bool,
    audio_track_visible: bool,
    webcam_track_visible: bool,
    text_overlay_count: u32,
}

fn register_handle(registry: &OnceLock<Mutex<HashSet<usize>>>, handle: *mut c_void) {
    if handle.is_null() {
        return;
    }
    let lock = registry.get_or_init(|| Mutex::new(HashSet::new()));
    let mut guard = match lock.lock() {
        Ok(v) => v,
        Err(poisoned) => poisoned.into_inner(),
    };
    guard.insert(handle as usize);
}

fn unregister_handle(registry: &OnceLock<Mutex<HashSet<usize>>>, handle: *mut c_void) -> bool {
    if handle.is_null() {
        return false;
    }
    let Some(lock) = registry.get() else {
        return false;
    };
    let mut guard = match lock.lock() {
        Ok(v) => v,
        Err(poisoned) => poisoned.into_inner(),
    };
    guard.remove(&(handle as usize))
}

fn validate_handle(
    registry: &OnceLock<Mutex<HashSet<usize>>>,
    handle: *const c_void,
) -> Result<(), i32> {
    if handle.is_null() {
        return Err(VS_STATUS_NULL_POINTER);
    }
    let Some(lock) = registry.get() else {
        return Err(VS_STATUS_INVALID_ARGUMENT);
    };
    let guard = match lock.lock() {
        Ok(v) => v,
        Err(poisoned) => poisoned.into_inner(),
    };
    if guard.contains(&(handle as usize)) {
        Ok(())
    } else {
        Err(VS_STATUS_INVALID_ARGUMENT)
    }
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

unsafe fn video_session_from_handle_mut<'a>(
    session: *mut c_void,
) -> Result<&'a mut vs_video_session, i32> {
    validate_handle(&VIDEO_SESSION_HANDLES, session)?;
    // SAFETY: pointer was validated by registry and originates from Box::into_raw.
    Ok(unsafe { &mut *session.cast::<vs_video_session>() })
}

unsafe fn video_session_from_handle<'a>(
    session: *const c_void,
) -> Result<&'a vs_video_session, i32> {
    validate_handle(&VIDEO_SESSION_HANDLES, session)?;
    // SAFETY: pointer was validated by registry and originates from Box::into_raw.
    Ok(unsafe { &*session.cast::<vs_video_session>() })
}

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

unsafe fn timeline_from_handle_mut<'a>(handle: *mut c_void) -> Result<&'a mut VsTimeline, i32> {
    validate_handle(&TIMELINE_HANDLES, handle)?;
    // SAFETY: pointer was validated by registry and originates from Box::into_raw.
    Ok(unsafe { &mut *handle.cast::<VsTimeline>() })
}

unsafe fn timeline_from_handle<'a>(handle: *const c_void) -> Result<&'a VsTimeline, i32> {
    validate_handle(&TIMELINE_HANDLES, handle)?;
    // SAFETY: pointer was validated by registry and originates from Box::into_raw.
    Ok(unsafe { &*handle.cast::<VsTimeline>() })
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
pub extern "C" fn vs_core_version() -> *const c_char {
    VERSION.as_ptr().cast()
}

#[no_mangle]
pub unsafe extern "C" fn vs_core_abi_version(
    out_major: *mut u32,
    out_minor: *mut u32,
    out_patch: *mut u32,
) -> i32 {
    if out_major.is_null() || out_minor.is_null() || out_patch.is_null() {
        return VS_STATUS_NULL_POINTER;
    }

    unsafe {
        *out_major = VS_CORE_ABI_VERSION_MAJOR;
        *out_minor = VS_CORE_ABI_VERSION_MINOR;
        *out_patch = VS_CORE_ABI_VERSION_PATCH;
    }
    VS_STATUS_OK
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
pub extern "C" fn vs_video_session_create(config: vs_video_session_config) -> *mut c_void {
    let session = vs_video_session {
        config,
        key_events: Vec::new(),
        click_events: Vec::new(),
        trim_start_ms: 0,
        trim_end_ms: 0,
        source_has_audio: false,
        source_has_webcam_asset: false,
        audio_track_visible: true,
        webcam_track_visible: true,
        text_overlay_count: 0,
    };

    let handle = Box::into_raw(Box::new(session)).cast();
    register_handle(&VIDEO_SESSION_HANDLES, handle);
    handle
}

#[no_mangle]
pub unsafe extern "C" fn vs_video_session_add_key_event(
    session: *mut c_void,
    event: vs_video_key_event,
) -> i32 {
    let session_ref = match unsafe { video_session_from_handle_mut(session) } {
        Ok(v) => v,
        Err(code) => return code,
    };

    if event.token_ptr.is_null() || event.token_len == 0 || event.token_len > 128 {
        return -2;
    }

    // SAFETY: `token_ptr` is validated non-null and bounded by `token_len`.
    let token_bytes = unsafe { slice::from_raw_parts(event.token_ptr, event.token_len) };
    let token = match std::str::from_utf8(token_bytes) {
        Ok(value) => value.trim(),
        Err(_) => return -3,
    };

    if token.is_empty() {
        return -4;
    }

    session_ref.key_events.push(VsVideoKeyEvent {
        timestamp_ns: event.timestamp_ns,
        token: token.to_string(),
    });
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_video_session_add_click_event(
    session: *mut c_void,
    event: vs_video_click_event,
) -> i32 {
    let session_ref = match unsafe { video_session_from_handle_mut(session) } {
        Ok(v) => v,
        Err(code) => return code,
    };

    if !event.normalized_x.is_finite() || !event.normalized_y.is_finite() {
        return -2;
    }

    session_ref.click_events.push(VsVideoClickEvent {
        timestamp_ns: event.timestamp_ns,
        normalized_x: event.normalized_x.clamp(0.0, 1.0),
        normalized_y: event.normalized_y.clamp(0.0, 1.0),
        button: event.button,
    });
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_video_session_set_trim(
    session: *mut c_void,
    start_ms: u32,
    end_ms: u32,
) -> i32 {
    let session_ref = match unsafe { video_session_from_handle_mut(session) } {
        Ok(v) => v,
        Err(code) => return code,
    };

    if end_ms < start_ms {
        return -2;
    }

    session_ref.trim_start_ms = start_ms;
    session_ref.trim_end_ms = end_ms;
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_video_session_set_export_context(
    session: *mut c_void,
    context: vs_video_export_context,
) -> i32 {
    let session_ref = match unsafe { video_session_from_handle_mut(session) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    session_ref.source_has_audio = context.source_has_audio;
    session_ref.source_has_webcam_asset = context.source_has_webcam_asset;
    session_ref.audio_track_visible = context.audio_track_visible;
    session_ref.webcam_track_visible = context.webcam_track_visible;
    session_ref.text_overlay_count = context.text_overlay_count;
    0
}

fn compute_video_export_plan(
    trim_start_ms: u32,
    trim_end_ms: u32,
    key_event_count: u32,
    click_event_count: u32,
    context: vs_video_export_context,
) -> Option<vs_video_export_plan> {
    ffi_video::compute_export_plan(
        trim_start_ms,
        trim_end_ms,
        key_event_count,
        click_event_count,
        context,
    )
}

#[no_mangle]
pub unsafe extern "C" fn vs_video_compute_export_plan(
    trim_start_ms: u32,
    trim_end_ms: u32,
    key_event_count: u32,
    click_event_count: u32,
    context: vs_video_export_context,
    out_plan: *mut vs_video_export_plan,
) -> i32 {
    if out_plan.is_null() {
        return -1;
    }

    let Some(plan) = compute_video_export_plan(
        trim_start_ms,
        trim_end_ms,
        key_event_count,
        click_event_count,
        context,
    ) else {
        return -2;
    };

    // SAFETY: `out_plan` is validated non-null above.
    unsafe {
        *out_plan = plan;
    }
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_video_derive_export_decision(
    target: u8,
    plan: vs_video_export_plan,
    out_decision: *mut vs_video_export_decision,
) -> i32 {
    if out_decision.is_null() {
        return VS_STATUS_NULL_POINTER;
    }

    let target = match target {
        VS_VIDEO_EXPORT_TARGET_MP4 | VS_VIDEO_EXPORT_TARGET_GIF => target,
        _ => return VS_STATUS_INVALID_ARGUMENT,
    };

    let Some(decision) =
        domain_derive_video_export_decision(target, to_domain_video_export_plan(plan))
    else {
        return VS_STATUS_INVALID_ARGUMENT;
    };

    unsafe {
        *out_decision = to_ffi_video_export_decision(decision);
    }
    VS_STATUS_OK
}

#[no_mangle]
pub unsafe extern "C" fn vs_video_key_overlay_label_layout(
    render_width: f32,
    render_height: f32,
    char_count: u32,
    out_layout: *mut vs_video_overlay_label_layout,
) -> i32 {
    if out_layout.is_null() {
        return VS_STATUS_NULL_POINTER;
    }
    let Some(layout) = ffi_video::key_overlay_label_layout(render_width, render_height, char_count)
    else {
        return VS_STATUS_INVALID_ARGUMENT;
    };
    unsafe {
        *out_layout = layout;
    }
    VS_STATUS_OK
}

#[no_mangle]
pub unsafe extern "C" fn vs_video_text_overlay_label_layout(
    render_width: f32,
    render_height: f32,
    char_count: u32,
    out_layout: *mut vs_video_overlay_label_layout,
) -> i32 {
    if out_layout.is_null() {
        return VS_STATUS_NULL_POINTER;
    }
    let Some(layout) =
        ffi_video::text_overlay_label_layout(render_width, render_height, char_count)
    else {
        return VS_STATUS_INVALID_ARGUMENT;
    };
    unsafe {
        *out_layout = layout;
    }
    VS_STATUS_OK
}

#[no_mangle]
pub unsafe extern "C" fn vs_video_compute_overlay_clip_window(
    clip_start_seconds: f64,
    clip_end_seconds: f64,
    trim_start_seconds: f64,
    min_visible_seconds: f64,
    out_window: *mut vs_video_overlay_clip_window,
) -> i32 {
    if out_window.is_null() {
        return VS_STATUS_NULL_POINTER;
    }
    let Some(window) = ffi_video::overlay_clip_window(
        clip_start_seconds,
        clip_end_seconds,
        trim_start_seconds,
        min_visible_seconds,
    ) else {
        return VS_STATUS_INVALID_ARGUMENT;
    };
    unsafe {
        *out_window = window;
    }
    VS_STATUS_OK
}

#[no_mangle]
pub unsafe extern "C" fn vs_video_session_get_export_plan(
    session: *mut c_void,
    out_plan: *mut vs_video_export_plan,
) -> i32 {
    if out_plan.is_null() {
        return -1;
    }
    let session_ref = match unsafe { video_session_from_handle(session) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    let key_count = session_ref.key_events.len().min(u32::MAX as usize) as u32;
    let click_count = session_ref.click_events.len().min(u32::MAX as usize) as u32;
    let _config_snapshot = (
        session_ref.config.frame_rate,
        session_ref.config.capture_system_audio,
        session_ref.config.capture_microphone,
        session_ref.config.show_webcam,
        session_ref.config.highlight_mouse_clicks,
        session_ref.config.highlight_keystrokes,
    );
    let _latest_key_timestamp_ns = session_ref
        .key_events
        .last()
        .map(|event| event.timestamp_ns)
        .unwrap_or(0);
    let _latest_click_timestamp_ns = session_ref
        .click_events
        .last()
        .map(|event| event.timestamp_ns)
        .unwrap_or(0);
    let _total_key_token_bytes: usize = session_ref
        .key_events
        .iter()
        .map(|event| event.token.len())
        .sum();
    let _click_checksum: f32 = session_ref
        .click_events
        .iter()
        .map(|event| event.normalized_x + event.normalized_y + event.button as f32)
        .sum();

    let context = vs_video_export_context {
        source_has_audio: session_ref.source_has_audio,
        source_has_webcam_asset: session_ref.source_has_webcam_asset,
        audio_track_visible: session_ref.audio_track_visible,
        webcam_track_visible: session_ref.webcam_track_visible,
        text_overlay_count: session_ref.text_overlay_count,
    };
    let Some(plan) = compute_video_export_plan(
        session_ref.trim_start_ms,
        session_ref.trim_end_ms,
        key_count,
        click_count,
        context,
    ) else {
        return -2;
    };

    // SAFETY: `out_plan` is validated non-null and points to writable memory owned by caller.
    unsafe {
        *out_plan = plan;
    }
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_video_session_destroy(session: *mut c_void) {
    if !unregister_handle(&VIDEO_SESSION_HANDLES, session) {
        return;
    }

    // SAFETY: `session` came from `Box::into_raw` in `vs_video_session_create`.
    unsafe {
        drop(Box::from_raw(session.cast::<vs_video_session>()));
    }
}

unsafe fn write_bytes_to_output(
    bytes: &[u8],
    out_ptr: *mut u8,
    out_cap: u32,
    out_written: *mut u32,
) -> i32 {
    if out_written.is_null() {
        return -1;
    }

    let total_len = bytes.len();
    let total_u32 = if total_len > u32::MAX as usize {
        u32::MAX
    } else {
        total_len as u32
    };

    // SAFETY: caller provided non-null pointer to writable memory for `out_written`.
    unsafe {
        *out_written = total_u32;
    }

    if out_ptr.is_null() || out_cap == 0 || total_len == 0 {
        return 0;
    }

    let copy_len = total_len.min(out_cap as usize);
    // SAFETY: pointers are validated and destination capacity is bounded by `copy_len`.
    unsafe {
        std::ptr::copy_nonoverlapping(bytes.as_ptr(), out_ptr, copy_len);
    }
    0
}

fn fallback_key_label(key_code: u16) -> &'static str {
    match key_code as i32 {
        36 => "Return",
        48 => "Tab",
        49 => "Space",
        51 => "Delete",
        53 => "Esc",
        123 => "←",
        124 => "→",
        125 => "↓",
        126 => "↑",
        122 => "F1",
        120 => "F2",
        99 => "F3",
        118 => "F4",
        96 => "F5",
        97 => "F6",
        98 => "F7",
        100 => "F8",
        101 => "F9",
        109 => "F10",
        103 => "F11",
        111 => "F12",
        _ => "Key",
    }
}

fn normalize_key_token_inner(key_code: u16, modifiers: u32, chars: Option<&str>) -> String {
    let mut token = String::new();
    if modifiers & VS_KEY_MOD_COMMAND != 0 {
        token.push('⌘');
    }
    if modifiers & VS_KEY_MOD_SHIFT != 0 {
        token.push('⇧');
    }
    if modifiers & VS_KEY_MOD_OPTION != 0 {
        token.push('⌥');
    }
    if modifiers & VS_KEY_MOD_CONTROL != 0 {
        token.push('⌃');
    }

    let key_label = match chars {
        Some(raw) => {
            let trimmed = raw.trim();
            if !trimmed.is_empty() && trimmed.chars().count() == 1 {
                trimmed.to_uppercase()
            } else {
                fallback_key_label(key_code).to_string()
            }
        }
        None => fallback_key_label(key_code).to_string(),
    };
    token.push_str(&key_label);

    token.chars().take(24).collect()
}

#[no_mangle]
pub unsafe extern "C" fn vs_normalize_key_token(
    key_code: u16,
    modifiers: u32,
    chars_ptr: *const u8,
    chars_len: u32,
    out_ptr: *mut u8,
    out_cap: u32,
    out_written: *mut u32,
) -> i32 {
    let chars = if chars_len > 0 {
        if chars_ptr.is_null() {
            return -1;
        }
        // SAFETY: pointer and length validated above.
        let bytes = unsafe { slice::from_raw_parts(chars_ptr, chars_len as usize) };
        std::str::from_utf8(bytes).ok()
    } else {
        None
    };

    let token = normalize_key_token_inner(key_code, modifiers, chars);
    // SAFETY: delegates to helper that validates output pointers.
    unsafe { write_bytes_to_output(token.as_bytes(), out_ptr, out_cap, out_written) }
}

#[no_mangle]
pub unsafe extern "C" fn vs_key_event_is_duplicate(
    last_timestamp_ns: u64,
    last_token_ptr: *const u8,
    last_token_len: u32,
    timestamp_ns: u64,
    token_ptr: *const u8,
    token_len: u32,
) -> bool {
    if last_timestamp_ns != timestamp_ns || last_token_len != token_len || token_len == 0 {
        return false;
    }
    if last_token_ptr.is_null() || token_ptr.is_null() {
        return false;
    }

    // SAFETY: pointers are non-null and sizes are bounded by caller.
    let last = unsafe { slice::from_raw_parts(last_token_ptr, last_token_len as usize) };
    // SAFETY: pointers are non-null and sizes are bounded by caller.
    let curr = unsafe { slice::from_raw_parts(token_ptr, token_len as usize) };
    last == curr
}

#[no_mangle]
pub unsafe extern "C" fn vs_normalize_click_point(
    normalized_x: f32,
    normalized_y: f32,
    out_x: *mut f32,
    out_y: *mut f32,
) -> i32 {
    if out_x.is_null() || out_y.is_null() {
        return -1;
    }

    let Some((x, y)) = domain_normalize_click_point(normalized_x, normalized_y) else {
        return -1;
    };

    // SAFETY: output pointers are validated non-null above.
    unsafe {
        *out_x = x;
        *out_y = y;
    }
    0
}

#[no_mangle]
pub extern "C" fn vs_click_event_is_duplicate(
    last_timestamp_ns: u64,
    last_button: u32,
    last_x: f32,
    last_y: f32,
    timestamp_ns: u64,
    button: u32,
    x: f32,
    y: f32,
    epsilon: f32,
) -> bool {
    domain_click_event_is_duplicate(
        last_timestamp_ns,
        last_button,
        last_x,
        last_y,
        timestamp_ns,
        button,
        x,
        y,
        epsilon,
    )
}

#[no_mangle]
pub unsafe extern "C" fn vs_video_session_serialize_json(
    session: *const c_void,
    out_ptr: *mut u8,
    out_cap: u32,
    out_written: *mut u32,
) -> i32 {
    let session_ref = match unsafe { video_session_from_handle(session) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    let snapshot = VsVideoSessionSnapshot {
        version: VS_VIDEO_SESSION_SNAPSHOT_VERSION,
        config: session_ref.config,
        key_events: session_ref.key_events.clone(),
        click_events: session_ref.click_events.clone(),
        trim_start_ms: session_ref.trim_start_ms,
        trim_end_ms: session_ref.trim_end_ms,
        source_has_audio: session_ref.source_has_audio,
        source_has_webcam_asset: session_ref.source_has_webcam_asset,
        audio_track_visible: session_ref.audio_track_visible,
        webcam_track_visible: session_ref.webcam_track_visible,
        text_overlay_count: session_ref.text_overlay_count,
    };

    let json_bytes = match serde_json::to_vec(&snapshot) {
        Ok(v) => v,
        Err(_) => return -2,
    };

    unsafe { write_bytes_to_output(&json_bytes, out_ptr, out_cap, out_written) }
}

#[no_mangle]
pub unsafe extern "C" fn vs_video_session_deserialize_json(
    json_ptr: *const u8,
    json_len: u32,
) -> *mut c_void {
    if json_ptr.is_null() || json_len == 0 {
        return std::ptr::null_mut();
    }

    // SAFETY: caller provides valid pointer/len for call duration.
    let json_bytes = unsafe { slice::from_raw_parts(json_ptr, json_len as usize) };
    let snapshot: VsVideoSessionSnapshot = match serde_json::from_slice(json_bytes) {
        Ok(v) => v,
        Err(_) => return std::ptr::null_mut(),
    };

    if snapshot.version != VS_VIDEO_SESSION_SNAPSHOT_VERSION {
        return std::ptr::null_mut();
    }

    if snapshot.trim_end_ms < snapshot.trim_start_ms {
        return std::ptr::null_mut();
    }

    let session = vs_video_session {
        config: snapshot.config,
        key_events: snapshot.key_events,
        click_events: snapshot.click_events,
        trim_start_ms: snapshot.trim_start_ms,
        trim_end_ms: snapshot.trim_end_ms,
        source_has_audio: snapshot.source_has_audio,
        source_has_webcam_asset: snapshot.source_has_webcam_asset,
        audio_track_visible: snapshot.audio_track_visible,
        webcam_track_visible: snapshot.webcam_track_visible,
        text_overlay_count: snapshot.text_overlay_count,
    };

    let handle = Box::into_raw(Box::new(session)).cast();
    register_handle(&VIDEO_SESSION_HANDLES, handle);
    handle
}

#[cfg(test)]
const VS_VIDEO_PLAN_MODE_COMPOSITE_MP4: u8 = DOMAIN_VIDEO_PLAN_MODE_COMPOSITE_MP4;
const VS_IMAGE_ENCODE_PNG: u8 = 0;
const VS_IMAGE_ENCODE_JPEG: u8 = 1;

const VS_STITCH_SIDE_TOP: u8 = DOMAIN_STITCH_SIDE_TOP;
const VS_STITCH_SIDE_BOTTOM: u8 = DOMAIN_STITCH_SIDE_BOTTOM;
const VS_RESIZE_CORNER_TOP_LEFT: u8 = 0;
const VS_RESIZE_CORNER_TOP: u8 = 1;
const VS_RESIZE_CORNER_TOP_RIGHT: u8 = 2;
const VS_RESIZE_CORNER_RIGHT: u8 = 3;
const VS_RESIZE_CORNER_BOTTOM: u8 = 4;
const VS_RESIZE_CORNER_LEFT: u8 = 5;
const VS_RESIZE_CORNER_BOTTOM_LEFT: u8 = 6;
const VS_RESIZE_CORNER_BOTTOM_RIGHT: u8 = 7;

const VS_KEY_MOD_COMMAND: u32 = 1 << 0;
const VS_KEY_MOD_SHIFT: u32 = 1 << 1;
const VS_KEY_MOD_OPTION: u32 = 1 << 2;
const VS_KEY_MOD_CONTROL: u32 = 1 << 3;

const VS_TRIM_HANDLE_UNKNOWN: u8 = 0;
const VS_TRIM_HANDLE_START: u8 = 1;
const VS_TRIM_HANDLE_END: u8 = 2;
pub const VS_VIDEO_EXPORT_TARGET_MP4: u8 = 0;
pub const VS_VIDEO_EXPORT_TARGET_GIF: u8 = 1;

pub const VS_CORE_ABI_VERSION_MAJOR: u32 = 1;
pub const VS_CORE_ABI_VERSION_MINOR: u32 = 0;
pub const VS_CORE_ABI_VERSION_PATCH: u32 = 0;
const VS_VIDEO_SESSION_SNAPSHOT_VERSION: u32 = 1;
pub const VS_VIDEO_TEXT_MIN_VISIBLE_SECONDS: f64 = 0.05;
pub const VS_VIDEO_TEXT_MIN_FADE_DURATION_SECONDS: f64 = 0.10;
pub const VS_VIDEO_KEY_FADE_DURATION_SECONDS: f32 = 0.95;
pub const VS_VIDEO_KEY_FADE_IN_KEYTIME: f32 = 0.10;
pub const VS_VIDEO_KEY_FADE_HOLD_KEYTIME: f32 = 0.78;
pub const VS_VIDEO_TEXT_FADE_IN_KEYTIME: f32 = 0.08;
pub const VS_VIDEO_TEXT_FADE_HOLD_KEYTIME: f32 = 0.92;

pub const VS_STATUS_OK: i32 = 0;
pub const VS_STATUS_NO_CHANGE: i32 = 1;
pub const VS_STATUS_NULL_POINTER: i32 = -1;
pub const VS_STATUS_INVALID_ARGUMENT: i32 = -2;
pub const VS_STATUS_REJECTED: i32 = -3;
pub const VS_STATUS_BUFFER_TOO_SMALL: i32 = -4;
pub const VS_STATUS_NOT_FOUND: i32 = -5;

unsafe fn bgra_view_slice<'a>(view: vs_bgra_image_view) -> Option<(&'a [u8], usize, usize, usize)> {
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

fn crop_bgra_frame(
    frame: &OwnedBgraFrame,
    x: u32,
    y: u32,
    width: u32,
    height: u32,
) -> Option<OwnedBgraFrame> {
    domain_stitch_crop_frame(&frame.to_domain_owned(), x, y, width, height)
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

fn zero_bgra_owned_image(image: &mut vs_bgra_owned_image) {
    image.width = 0;
    image.height = 0;
    image.stride = 0;
    image.ptr = std::ptr::null_mut();
    image.len = 0;
}

fn zero_encoded_bytes(bytes: &mut vs_encoded_bytes) {
    bytes.ptr = std::ptr::null_mut();
    bytes.len = 0;
}

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

    let source_owned = match copy_bgra_view_to_owned(source) {
        Some(v) => v,
        None => return -2,
    };
    let cropped = match crop_bgra_frame(&source_owned, x, y, width, height) {
        Some(v) => v,
        None => return -2,
    };

    // SAFETY: `out_image` is validated non-null above and points to writable memory from caller.
    unsafe {
        *out_image = cropped.to_owned_image();
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

fn bgra_to_rgba(bytes: &[u8], width: usize, height: usize, stride: usize) -> Option<Vec<u8>> {
    let row_bytes = width.checked_mul(4)?;
    if stride < row_bytes {
        return None;
    }

    let mut rgba = vec![0u8; row_bytes.checked_mul(height)?];
    for y in 0..height {
        let src_row = &bytes[y * stride..y * stride + row_bytes];
        let dst_row = &mut rgba[y * row_bytes..(y + 1) * row_bytes];
        for x in 0..width {
            let si = x * 4;
            let di = si;
            dst_row[di] = src_row[si + 2];
            dst_row[di + 1] = src_row[si + 1];
            dst_row[di + 2] = src_row[si];
            dst_row[di + 3] = src_row[si + 3];
        }
    }
    Some(rgba)
}

fn rgba_to_rgb(rgba: &[u8]) -> Vec<u8> {
    let mut rgb = Vec::with_capacity(rgba.len() / 4 * 3);
    for chunk in rgba.chunks_exact(4) {
        rgb.push(chunk[0]);
        rgb.push(chunk[1]);
        rgb.push(chunk[2]);
    }
    rgb
}

#[no_mangle]
pub unsafe extern "C" fn vs_encode_bgra_image(
    source: vs_bgra_image_view,
    format: u8,
    jpeg_quality: u8,
    out_bytes: *mut vs_encoded_bytes,
) -> i32 {
    if out_bytes.is_null() {
        return -1;
    }

    // SAFETY: caller provides writable pointer.
    let out_bytes_ref = unsafe { &mut *out_bytes };
    zero_encoded_bytes(out_bytes_ref);

    // SAFETY: validates pointer/len invariants before returning bytes.
    let (bytes, width, height, stride) = match unsafe { bgra_view_slice(source) } {
        Some(v) => v,
        None => return -2,
    };
    let rgba = match bgra_to_rgba(bytes, width, height, stride) {
        Some(v) => v,
        None => return -2,
    };
    if !ffi_encode::supports_image_format(format, VS_IMAGE_ENCODE_PNG, VS_IMAGE_ENCODE_JPEG) {
        return -2;
    }

    let encoded = match format {
        VS_IMAGE_ENCODE_PNG => {
            let mut out = Vec::<u8>::new();
            let encoder = PngEncoder::new(&mut out);
            if encoder
                .write_image(&rgba, width as u32, height as u32, ColorType::Rgba8.into())
                .is_err()
            {
                return -3;
            }
            out
        }
        VS_IMAGE_ENCODE_JPEG => {
            let quality = ffi_encode::normalized_jpeg_quality(jpeg_quality);
            let rgb = rgba_to_rgb(&rgba);
            let mut out = Vec::<u8>::new();
            let encoder = JpegEncoder::new_with_quality(&mut out, quality);
            if encoder
                .write_image(&rgb, width as u32, height as u32, ColorType::Rgb8.into())
                .is_err()
            {
                return -3;
            }
            out
        }
        _ => unreachable!("format validated above"),
    };

    let mut owned = encoded;
    out_bytes_ref.ptr = owned.as_mut_ptr();
    out_bytes_ref.len = owned.len();
    std::mem::forget(owned);
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_encoded_bytes_destroy(bytes: *mut vs_encoded_bytes) {
    if bytes.is_null() {
        return;
    }

    let bytes_ref = unsafe { &mut *bytes };
    if !bytes_ref.ptr.is_null() && bytes_ref.len > 0 {
        // SAFETY: pointer/len came from Vec allocation in `vs_encode_bgra_image`.
        unsafe {
            drop(Vec::from_raw_parts(
                bytes_ref.ptr,
                bytes_ref.len,
                bytes_ref.len,
            ));
        }
    }
    zero_encoded_bytes(bytes_ref);
}

#[no_mangle]
pub unsafe extern "C" fn vs_bgra_owned_image_destroy(image: *mut vs_bgra_owned_image) {
    if image.is_null() {
        return;
    }

    let image = unsafe { &mut *image };
    if !image.ptr.is_null() && image.len > 0 {
        // SAFETY: pointer/len came from Vec allocation in `vs_stitch_merge_bgra`.
        unsafe {
            drop(Vec::from_raw_parts(image.ptr, image.len, image.len));
        }
    }

    image.width = 0;
    image.height = 0;
    image.stride = 0;
    image.ptr = std::ptr::null_mut();
    image.len = 0;
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

// ---------------------------------------------------------------------------
// Timeline editor core model
// ---------------------------------------------------------------------------

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
pub struct vs_timeline_text_export_clip_info {
    pub track_index: u32,
    pub clip_id: u32,
    pub start_ms: u32,
    pub end_ms: u32,
}

#[derive(Clone, Copy, Default)]
struct TimelineTextClipExportRef {
    track_index: u32,
    clip_id: u32,
    start_ms: u32,
    end_ms: u32,
}

#[derive(Clone, Copy)]
struct ClipTransform {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    rotation: f32,
    opacity: f32,
}

impl ClipTransform {
    fn default_full() -> Self {
        ClipTransform {
            x: 0.0,
            y: 0.0,
            width: 1.0,
            height: 1.0,
            rotation: 0.0,
            opacity: 1.0,
        }
    }

    fn to_ffi(&self) -> vs_clip_transform {
        vs_clip_transform {
            x: self.x,
            y: self.y,
            width: self.width,
            height: self.height,
            rotation: self.rotation,
            opacity: self.opacity,
        }
    }

    fn from_ffi(t: &vs_clip_transform) -> Self {
        ClipTransform {
            x: t.x,
            y: t.y,
            width: t.width,
            height: t.height,
            rotation: t.rotation,
            opacity: t.opacity,
        }
    }
}

#[derive(Clone)]
enum ClipData {
    Video,
    Webcam,
    Audio,
    Text {
        text: String,
        font_size: f32,
        color: u32,
        bg_color: u32,
    },
    Shape {
        fill: u32,
        border: u32,
        border_width: f32,
        corner_radius: f32,
    },
    Cursor,
    Zoom {
        scale: f32,
    },
}

#[derive(Clone)]
struct TimelineClip {
    id: u32,
    start_ms: u32,
    end_ms: u32,
    transform: ClipTransform,
    data: ClipData,
}

#[derive(Clone)]
struct TimelineTrack {
    kind: u8,
    visible: bool,
    clips: Vec<TimelineClip>,
}

#[derive(Clone)]
enum TimelineAction {
    AddClip {
        track_index: usize,
        clip: TimelineClip,
    },
    RemoveClip {
        track_index: usize,
        clip: TimelineClip,
    },
    MoveClip {
        track_index: usize,
        clip_id: u32,
        old_start: u32,
        new_start: u32,
    },
    ResizeClip {
        track_index: usize,
        clip_id: u32,
        old_start: u32,
        old_end: u32,
        new_start: u32,
        new_end: u32,
    },
    UpdateTransform {
        track_index: usize,
        clip_id: u32,
        old_transform: ClipTransform,
        new_transform: ClipTransform,
    },
    SetTrackVisible {
        track_index: usize,
        old_visible: bool,
        new_visible: bool,
    },
    AddTrack {
        kind: u8,
    },
    RemoveTrack {
        track_index: usize,
        track: TimelineTrack,
    },
    ReorderTrack {
        from: usize,
        to: usize,
    },
    UpdateClipText {
        track_index: usize,
        clip_id: u32,
        old_text: String,
        new_text: String,
    },
    UpdateClipTextStyle {
        track_index: usize,
        clip_id: u32,
        old_font_size: f32,
        old_color: u32,
        old_bg_color: u32,
        new_font_size: f32,
        new_color: u32,
        new_bg_color: u32,
    },
    UpdateClipShapeStyle {
        track_index: usize,
        clip_id: u32,
        old_fill: u32,
        old_border: u32,
        old_border_width: f32,
        old_corner_radius: f32,
        new_fill: u32,
        new_border: u32,
        new_border_width: f32,
        new_corner_radius: f32,
    },
}

struct VsTimeline {
    video_duration_ms: u32,
    width: u32,
    height: u32,
    tracks: Vec<TimelineTrack>,
    next_clip_id: u32,
    history: Vec<TimelineAction>,
    history_cursor: usize,
}

impl VsTimeline {
    fn find_clip_mut(&mut self, track_index: usize, clip_id: u32) -> Option<&mut TimelineClip> {
        let track = self.tracks.get_mut(track_index)?;
        track.clips.iter_mut().find(|c| c.id == clip_id)
    }

    fn find_clip(&self, track_index: usize, clip_id: u32) -> Option<&TimelineClip> {
        let track = self.tracks.get(track_index)?;
        track.clips.iter().find(|c| c.id == clip_id)
    }

    fn push_action(&mut self, action: TimelineAction) {
        self.history.truncate(self.history_cursor);
        self.history.push(action);
        self.history_cursor = self.history.len();
    }

    fn apply_action(&mut self, action: &TimelineAction) {
        match action {
            TimelineAction::AddClip { track_index, clip } => {
                if let Some(track) = self.tracks.get_mut(*track_index) {
                    track.clips.push(clip.clone());
                }
            }
            TimelineAction::RemoveClip { track_index, clip } => {
                if let Some(track) = self.tracks.get_mut(*track_index) {
                    track.clips.retain(|c| c.id != clip.id);
                }
            }
            TimelineAction::MoveClip {
                track_index,
                clip_id,
                new_start,
                ..
            } => {
                if let Some(clip) = self.find_clip_mut(*track_index, *clip_id) {
                    let duration = clip.end_ms.saturating_sub(clip.start_ms);
                    clip.start_ms = *new_start;
                    clip.end_ms = new_start.saturating_add(duration);
                }
            }
            TimelineAction::ResizeClip {
                track_index,
                clip_id,
                new_start,
                new_end,
                ..
            } => {
                if let Some(clip) = self.find_clip_mut(*track_index, *clip_id) {
                    clip.start_ms = *new_start;
                    clip.end_ms = *new_end;
                }
            }
            TimelineAction::UpdateTransform {
                track_index,
                clip_id,
                new_transform,
                ..
            } => {
                if let Some(clip) = self.find_clip_mut(*track_index, *clip_id) {
                    clip.transform = *new_transform;
                }
            }
            TimelineAction::SetTrackVisible {
                track_index,
                new_visible,
                ..
            } => {
                if let Some(track) = self.tracks.get_mut(*track_index) {
                    track.visible = *new_visible;
                }
            }
            TimelineAction::AddTrack { kind } => {
                self.tracks.push(TimelineTrack {
                    kind: *kind,
                    visible: true,
                    clips: Vec::new(),
                });
            }
            TimelineAction::RemoveTrack { track_index, .. } => {
                if *track_index < self.tracks.len() {
                    self.tracks.remove(*track_index);
                }
            }
            TimelineAction::ReorderTrack { from, to } => {
                if *from < self.tracks.len() && *to < self.tracks.len() {
                    let track = self.tracks.remove(*from);
                    self.tracks.insert(*to, track);
                }
            }
            TimelineAction::UpdateClipText {
                track_index,
                clip_id,
                new_text,
                ..
            } => {
                if let Some(clip) = self.find_clip_mut(*track_index, *clip_id) {
                    if let ClipData::Text { ref mut text, .. } = clip.data {
                        *text = new_text.clone();
                    }
                }
            }
            TimelineAction::UpdateClipTextStyle {
                track_index,
                clip_id,
                new_font_size,
                new_color,
                new_bg_color,
                ..
            } => {
                if let Some(clip) = self.find_clip_mut(*track_index, *clip_id) {
                    if let ClipData::Text {
                        ref mut font_size,
                        ref mut color,
                        ref mut bg_color,
                        ..
                    } = clip.data
                    {
                        *font_size = *new_font_size;
                        *color = *new_color;
                        *bg_color = *new_bg_color;
                    }
                }
            }
            TimelineAction::UpdateClipShapeStyle {
                track_index,
                clip_id,
                new_fill,
                new_border,
                new_border_width,
                new_corner_radius,
                ..
            } => {
                if let Some(clip) = self.find_clip_mut(*track_index, *clip_id) {
                    if let ClipData::Shape {
                        ref mut fill,
                        ref mut border,
                        ref mut border_width,
                        ref mut corner_radius,
                    } = clip.data
                    {
                        *fill = *new_fill;
                        *border = *new_border;
                        *border_width = *new_border_width;
                        *corner_radius = *new_corner_radius;
                    }
                }
            }
        }
    }

    fn reverse_action(&mut self, action: &TimelineAction) {
        match action {
            TimelineAction::AddClip { track_index, clip } => {
                if let Some(track) = self.tracks.get_mut(*track_index) {
                    track.clips.retain(|c| c.id != clip.id);
                }
            }
            TimelineAction::RemoveClip { track_index, clip } => {
                if let Some(track) = self.tracks.get_mut(*track_index) {
                    track.clips.push(clip.clone());
                }
            }
            TimelineAction::MoveClip {
                track_index,
                clip_id,
                old_start,
                ..
            } => {
                if let Some(clip) = self.find_clip_mut(*track_index, *clip_id) {
                    let duration = clip.end_ms.saturating_sub(clip.start_ms);
                    clip.start_ms = *old_start;
                    clip.end_ms = old_start.saturating_add(duration);
                }
            }
            TimelineAction::ResizeClip {
                track_index,
                clip_id,
                old_start,
                old_end,
                ..
            } => {
                if let Some(clip) = self.find_clip_mut(*track_index, *clip_id) {
                    clip.start_ms = *old_start;
                    clip.end_ms = *old_end;
                }
            }
            TimelineAction::UpdateTransform {
                track_index,
                clip_id,
                old_transform,
                ..
            } => {
                if let Some(clip) = self.find_clip_mut(*track_index, *clip_id) {
                    clip.transform = *old_transform;
                }
            }
            TimelineAction::SetTrackVisible {
                track_index,
                old_visible,
                ..
            } => {
                if let Some(track) = self.tracks.get_mut(*track_index) {
                    track.visible = *old_visible;
                }
            }
            TimelineAction::AddTrack { .. } => {
                if !self.tracks.is_empty() {
                    self.tracks.pop();
                }
            }
            TimelineAction::RemoveTrack { track_index, track } => {
                if *track_index <= self.tracks.len() {
                    self.tracks.insert(*track_index, track.clone());
                }
            }
            TimelineAction::ReorderTrack { from, to } => {
                if *to < self.tracks.len() && *from <= self.tracks.len() {
                    let track = self.tracks.remove(*to);
                    self.tracks.insert(*from, track);
                }
            }
            TimelineAction::UpdateClipText {
                track_index,
                clip_id,
                old_text,
                ..
            } => {
                if let Some(clip) = self.find_clip_mut(*track_index, *clip_id) {
                    if let ClipData::Text { ref mut text, .. } = clip.data {
                        *text = old_text.clone();
                    }
                }
            }
            TimelineAction::UpdateClipTextStyle {
                track_index,
                clip_id,
                old_font_size,
                old_color,
                old_bg_color,
                ..
            } => {
                if let Some(clip) = self.find_clip_mut(*track_index, *clip_id) {
                    if let ClipData::Text {
                        ref mut font_size,
                        ref mut color,
                        ref mut bg_color,
                        ..
                    } = clip.data
                    {
                        *font_size = *old_font_size;
                        *color = *old_color;
                        *bg_color = *old_bg_color;
                    }
                }
            }
            TimelineAction::UpdateClipShapeStyle {
                track_index,
                clip_id,
                old_fill,
                old_border,
                old_border_width,
                old_corner_radius,
                ..
            } => {
                if let Some(clip) = self.find_clip_mut(*track_index, *clip_id) {
                    if let ClipData::Shape {
                        ref mut fill,
                        ref mut border,
                        ref mut border_width,
                        ref mut corner_radius,
                    } = clip.data
                    {
                        *fill = *old_fill;
                        *border = *old_border;
                        *border_width = *old_border_width;
                        *corner_radius = *old_corner_radius;
                    }
                }
            }
        }
    }
}

fn clip_data_for_kind(kind: u8) -> Option<ClipData> {
    match kind {
        0 => Some(ClipData::Video),
        1 => Some(ClipData::Webcam),
        2 => Some(ClipData::Audio),
        3 => Some(ClipData::Text {
            text: String::new(),
            font_size: 16.0,
            color: 0xFFFFFFFF,
            bg_color: 0x00000000,
        }),
        4 => Some(ClipData::Shape {
            fill: 0xFFFFFFFF,
            border: 0xFF000000,
            border_width: 2.0,
            corner_radius: 0.0,
        }),
        5 => Some(ClipData::Cursor),
        6 => Some(ClipData::Zoom { scale: 2.0 }),
        _ => None,
    }
}

fn track_kind_for_clip(data: &ClipData) -> u8 {
    match data {
        ClipData::Video => 0,
        ClipData::Webcam => 1,
        ClipData::Audio => 2,
        ClipData::Text { .. } => 3,
        ClipData::Shape { .. } => 4,
        ClipData::Cursor => 5,
        ClipData::Zoom { .. } => 6,
    }
}

fn timeline_next_clip(
    tl: &mut VsTimeline,
    start_ms: u32,
    end_ms: u32,
    data: ClipData,
) -> TimelineClip {
    let clip_id = tl.next_clip_id;
    tl.next_clip_id = tl.next_clip_id.wrapping_add(1);
    TimelineClip {
        id: clip_id,
        start_ms,
        end_ms,
        transform: ClipTransform::default_full(),
        data,
    }
}

fn timeline_full_duration_end(tl: &VsTimeline) -> u32 {
    domain_timeline_full_duration_end(tl.video_duration_ms)
}

// ---------------------------------------------------------------------------
// Timeline FFI: lifecycle
// ---------------------------------------------------------------------------

#[no_mangle]
pub extern "C" fn vs_timeline_create(duration_ms: u32, width: u32, height: u32) -> *mut c_void {
    if width == 0 || height == 0 {
        return std::ptr::null_mut();
    }

    let tl = VsTimeline {
        video_duration_ms: duration_ms,
        width,
        height,
        tracks: Vec::new(),
        next_clip_id: 1,
        history: Vec::new(),
        history_cursor: 0,
    };

    let handle = Box::into_raw(Box::new(tl)).cast();
    register_handle(&TIMELINE_HANDLES, handle);
    handle
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_destroy(handle: *mut c_void) {
    if !unregister_handle(&TIMELINE_HANDLES, handle) {
        return;
    }

    unsafe {
        drop(Box::from_raw(handle.cast::<VsTimeline>()));
    }
}

// ---------------------------------------------------------------------------
// Timeline FFI: tracks
// ---------------------------------------------------------------------------

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_add_track(handle: *mut c_void, kind: u8) -> i32 {
    if kind > 6 {
        return -2;
    }

    let tl = match unsafe { timeline_from_handle_mut(handle) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    let action = TimelineAction::AddTrack { kind };
    tl.apply_action(&action);
    tl.push_action(action);
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_remove_track(handle: *mut c_void, track_index: u32) -> i32 {
    let tl = match unsafe { timeline_from_handle_mut(handle) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    let idx = track_index as usize;
    if idx >= tl.tracks.len() {
        return -2;
    }

    let track = tl.tracks[idx].clone();
    let action = TimelineAction::RemoveTrack {
        track_index: idx,
        track,
    };
    tl.apply_action(&action);
    tl.push_action(action);
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_reorder_track(
    handle: *mut c_void,
    from_index: u32,
    to_index: u32,
) -> i32 {
    let tl = match unsafe { timeline_from_handle_mut(handle) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    let from = from_index as usize;
    let to = to_index as usize;
    if from >= tl.tracks.len() || to >= tl.tracks.len() {
        return -2;
    }

    if from == to {
        return 0;
    }

    let action = TimelineAction::ReorderTrack { from, to };
    tl.apply_action(&action);
    tl.push_action(action);
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_set_track_visible(
    handle: *mut c_void,
    track_index: u32,
    visible: bool,
) -> i32 {
    let tl = match unsafe { timeline_from_handle_mut(handle) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    let idx = track_index as usize;
    if idx >= tl.tracks.len() {
        return -2;
    }

    let old_visible = tl.tracks[idx].visible;
    if old_visible == visible {
        return 0;
    }

    let action = TimelineAction::SetTrackVisible {
        track_index: idx,
        old_visible,
        new_visible: visible,
    };
    tl.apply_action(&action);
    tl.push_action(action);
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_get_tracks(
    handle: *mut c_void,
    out_ptr: *mut vs_timeline_track_info,
    out_cap: u32,
    out_written: *mut u32,
) -> i32 {
    if out_written.is_null() {
        return -1;
    }

    if out_cap > 0 && out_ptr.is_null() {
        return -2;
    }

    let tl = match unsafe { timeline_from_handle(handle) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    let total = tl.tracks.len().min(u32::MAX as usize) as u32;
    let write_count = (out_cap as usize).min(total as usize);

    for i in 0..write_count {
        let track = &tl.tracks[i];
        unsafe {
            *out_ptr.add(i) = vs_timeline_track_info {
                kind: track.kind,
                visible: track.visible,
                clip_count: track.clips.len() as u32,
            };
        }
    }

    unsafe {
        *out_written = total;
    }
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_derive_export_context(
    handle: *const c_void,
    source_has_audio: bool,
    source_has_webcam_asset: bool,
    out_context: *mut vs_video_export_context,
) -> i32 {
    if out_context.is_null() {
        return -1;
    }

    let tl = match unsafe { timeline_from_handle(handle) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    let context =
        ffi_timeline::derive_export_context(source_has_audio, source_has_webcam_asset, &tl.tracks);

    unsafe {
        *out_context = context;
    }
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_is_webcam_track_visible_for_export(
    handle: *const c_void,
    out_visible: *mut bool,
) -> i32 {
    if out_visible.is_null() {
        return -1;
    }

    let tl = match unsafe { timeline_from_handle(handle) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    let visible = ffi_timeline::webcam_visible_for_export(&tl.tracks);
    unsafe {
        *out_visible = visible;
    }
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_get_text_export_clips(
    handle: *const c_void,
    out_ptr: *mut vs_timeline_text_export_clip_info,
    out_cap: u32,
    out_written: *mut u32,
) -> i32 {
    if out_written.is_null() {
        return -1;
    }
    if out_cap > 0 && out_ptr.is_null() {
        return -2;
    }

    let tl = match unsafe { timeline_from_handle(handle) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    let refs = ffi_timeline::text_export_clip_refs(&tl.tracks);
    if out_cap > 0 {
        ffi_timeline::write_text_export_clip_refs(&refs, out_ptr, out_cap);
    }
    unsafe {
        *out_written = refs.len().min(u32::MAX as usize) as u32;
    }
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_bootstrap_capture_tracks(
    handle: *mut c_void,
    source_has_audio: bool,
    source_has_webcam_asset: bool,
) -> i32 {
    let tl = match unsafe { timeline_from_handle_mut(handle) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    let full_end = timeline_full_duration_end(tl);
    let mut tracks: Vec<TimelineTrack> = Vec::new();

    let video_clip = timeline_next_clip(tl, 0, full_end, ClipData::Video);
    tracks.push(TimelineTrack {
        kind: 0,
        visible: true,
        clips: vec![video_clip],
    });

    if source_has_audio {
        let audio_clip = timeline_next_clip(tl, 0, full_end, ClipData::Audio);
        tracks.push(TimelineTrack {
            kind: 2,
            visible: true,
            clips: vec![audio_clip],
        });
    }

    if source_has_webcam_asset {
        let webcam_clip = timeline_next_clip(tl, 0, full_end, ClipData::Webcam);
        tracks.push(TimelineTrack {
            kind: 1,
            visible: true,
            clips: vec![webcam_clip],
        });
    }

    tl.tracks = tracks;
    tl.history.clear();
    tl.history_cursor = 0;
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_add_text_clip_auto_track(
    handle: *mut c_void,
    start_ms: u32,
    end_ms: u32,
    text_ptr: *const u8,
    text_len: u32,
    out_clip_id: *mut u32,
) -> i32 {
    if text_ptr.is_null() || text_len == 0 {
        return -1;
    }

    // SAFETY: pointer + len are validated above.
    let text_bytes = unsafe { slice::from_raw_parts(text_ptr, text_len as usize) };
    let raw_text = match std::str::from_utf8(text_bytes) {
        Ok(v) => v,
        Err(_) => return -2,
    };
    let trimmed = raw_text.trim();
    if trimmed.is_empty() {
        return -2;
    }

    let tl = match unsafe { timeline_from_handle_mut(handle) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    let (clamped_start, clamped_end) =
        domain_timeline_normalize_text_clip_range(tl.video_duration_ms, start_ms, end_ms);

    let track_index = match tl.tracks.iter().position(|track| track.kind == 3) {
        Some(idx) => idx,
        None => {
            tl.tracks.push(TimelineTrack {
                kind: 3,
                visible: true,
                clips: Vec::new(),
            });
            tl.tracks.len() - 1
        }
    };

    let clip = timeline_next_clip(
        tl,
        clamped_start,
        clamped_end,
        ClipData::Text {
            text: trimmed.to_string(),
            font_size: 16.0,
            color: 0xFFFFFFFF,
            bg_color: 0x00000000,
        },
    );
    let clip_id = clip.id;
    tl.tracks[track_index].clips.push(clip);

    if !out_clip_id.is_null() {
        unsafe {
            *out_clip_id = clip_id;
        }
    }
    0
}

// ---------------------------------------------------------------------------
// Timeline FFI: clips
// ---------------------------------------------------------------------------

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_add_clip(
    handle: *mut c_void,
    track_index: u32,
    start_ms: u32,
    end_ms: u32,
    kind: u8,
    out_clip_id: *mut u32,
) -> i32 {
    if end_ms <= start_ms {
        return -2;
    }

    let Some(data) = clip_data_for_kind(kind) else {
        return -2;
    };

    let tl = match unsafe { timeline_from_handle_mut(handle) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    let idx = track_index as usize;
    if idx >= tl.tracks.len() {
        return -2;
    }

    let clamped_end = domain_timeline_clamp_clip_end(tl.video_duration_ms, start_ms, end_ms);

    let clip_id = tl.next_clip_id;
    tl.next_clip_id = tl.next_clip_id.wrapping_add(1);

    let clip = TimelineClip {
        id: clip_id,
        start_ms,
        end_ms: clamped_end,
        transform: ClipTransform::default_full(),
        data,
    };

    let action = TimelineAction::AddClip {
        track_index: idx,
        clip,
    };
    tl.apply_action(&action);
    tl.push_action(action);

    if !out_clip_id.is_null() {
        unsafe {
            *out_clip_id = clip_id;
        }
    }

    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_remove_clip(
    handle: *mut c_void,
    track_index: u32,
    clip_id: u32,
) -> i32 {
    let tl = match unsafe { timeline_from_handle_mut(handle) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    let idx = track_index as usize;

    let clip = match tl.find_clip(idx, clip_id) {
        Some(c) => c.clone(),
        None => return -2,
    };

    let action = TimelineAction::RemoveClip {
        track_index: idx,
        clip,
    };
    tl.apply_action(&action);
    tl.push_action(action);
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_move_clip(
    handle: *mut c_void,
    track_index: u32,
    clip_id: u32,
    new_start_ms: u32,
) -> i32 {
    let tl = match unsafe { timeline_from_handle_mut(handle) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    let idx = track_index as usize;

    let (old_start, duration) = match tl.find_clip(idx, clip_id) {
        Some(c) => (c.start_ms, c.end_ms.saturating_sub(c.start_ms)),
        None => return -2,
    };

    let clamped_start = if tl.video_duration_ms > 0 && duration > 0 {
        new_start_ms.min(tl.video_duration_ms.saturating_sub(duration))
    } else {
        new_start_ms
    };

    if old_start == clamped_start {
        return 0;
    }

    let action = TimelineAction::MoveClip {
        track_index: idx,
        clip_id,
        old_start,
        new_start: clamped_start,
    };
    tl.apply_action(&action);
    tl.push_action(action);
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_resize_clip(
    handle: *mut c_void,
    track_index: u32,
    clip_id: u32,
    new_start_ms: u32,
    new_end_ms: u32,
) -> i32 {
    if new_end_ms <= new_start_ms {
        return -2;
    }

    let tl = match unsafe { timeline_from_handle_mut(handle) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    let idx = track_index as usize;

    let clamped_end = if tl.video_duration_ms > 0 {
        new_end_ms.min(tl.video_duration_ms)
    } else {
        new_end_ms
    };
    let clamped_end = clamped_end.max(new_start_ms + 1);

    let (old_start, old_end) = match tl.find_clip(idx, clip_id) {
        Some(c) => (c.start_ms, c.end_ms),
        None => return -2,
    };

    if old_start == new_start_ms && old_end == clamped_end {
        return 0;
    }

    let action = TimelineAction::ResizeClip {
        track_index: idx,
        clip_id,
        old_start,
        old_end,
        new_start: new_start_ms,
        new_end: clamped_end,
    };
    tl.apply_action(&action);
    tl.push_action(action);
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_update_clip_transform(
    handle: *mut c_void,
    track_index: u32,
    clip_id: u32,
    transform: vs_clip_transform,
) -> i32 {
    if !transform.x.is_finite()
        || !transform.y.is_finite()
        || !transform.width.is_finite()
        || !transform.height.is_finite()
        || !transform.rotation.is_finite()
        || !transform.opacity.is_finite()
    {
        return -2;
    }

    let tl = match unsafe { timeline_from_handle_mut(handle) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    let idx = track_index as usize;

    let old_transform = match tl.find_clip(idx, clip_id) {
        Some(c) => c.transform,
        None => return -2,
    };

    let new_transform = ClipTransform::from_ffi(&transform);

    let action = TimelineAction::UpdateTransform {
        track_index: idx,
        clip_id,
        old_transform,
        new_transform,
    };
    tl.apply_action(&action);
    tl.push_action(action);
    0
}

// ---------------------------------------------------------------------------
// Timeline FFI: clip data
// ---------------------------------------------------------------------------

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_set_clip_text(
    handle: *mut c_void,
    track_index: u32,
    clip_id: u32,
    text_ptr: *const u8,
    text_len: u32,
) -> i32 {
    if text_ptr.is_null() || text_len == 0 {
        return -2;
    }

    let text_bytes = unsafe { slice::from_raw_parts(text_ptr, text_len as usize) };
    let new_text = match std::str::from_utf8(text_bytes) {
        Ok(v) => v.to_string(),
        Err(_) => return -2,
    };

    let tl = match unsafe { timeline_from_handle_mut(handle) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    let idx = track_index as usize;

    let old_text = match tl.find_clip(idx, clip_id) {
        Some(c) => {
            if let ClipData::Text { ref text, .. } = c.data {
                text.clone()
            } else {
                return -2;
            }
        }
        None => return -2,
    };

    let action = TimelineAction::UpdateClipText {
        track_index: idx,
        clip_id,
        old_text,
        new_text,
    };
    tl.apply_action(&action);
    tl.push_action(action);
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_set_clip_text_style(
    handle: *mut c_void,
    track_index: u32,
    clip_id: u32,
    font_size: f32,
    color: u32,
    bg_color: u32,
) -> i32 {
    if !font_size.is_finite() || font_size <= 0.0 {
        return -2;
    }

    let tl = match unsafe { timeline_from_handle_mut(handle) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    let idx = track_index as usize;

    let (old_font_size, old_color, old_bg_color) = match tl.find_clip(idx, clip_id) {
        Some(c) => {
            if let ClipData::Text {
                font_size: fs,
                color: co,
                bg_color: bg,
                ..
            } = &c.data
            {
                (*fs, *co, *bg)
            } else {
                return -2;
            }
        }
        None => return -2,
    };

    let action = TimelineAction::UpdateClipTextStyle {
        track_index: idx,
        clip_id,
        old_font_size,
        old_color,
        old_bg_color,
        new_font_size: font_size,
        new_color: color,
        new_bg_color: bg_color,
    };
    tl.apply_action(&action);
    tl.push_action(action);
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_set_clip_shape_style(
    handle: *mut c_void,
    track_index: u32,
    clip_id: u32,
    fill: u32,
    border: u32,
    border_width: f32,
    corner_radius: f32,
) -> i32 {
    if !border_width.is_finite() || !corner_radius.is_finite() {
        return -2;
    }

    let tl = match unsafe { timeline_from_handle_mut(handle) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    let idx = track_index as usize;

    let (old_fill, old_border, old_border_width, old_corner_radius) =
        match tl.find_clip(idx, clip_id) {
            Some(c) => {
                if let ClipData::Shape {
                    fill: f,
                    border: b,
                    border_width: bw,
                    corner_radius: cr,
                } = &c.data
                {
                    (*f, *b, *bw, *cr)
                } else {
                    return -2;
                }
            }
            None => return -2,
        };

    let action = TimelineAction::UpdateClipShapeStyle {
        track_index: idx,
        clip_id,
        old_fill,
        old_border,
        old_border_width,
        old_corner_radius,
        new_fill: fill,
        new_border: border,
        new_border_width: border_width,
        new_corner_radius: corner_radius,
    };
    tl.apply_action(&action);
    tl.push_action(action);
    0
}

// ---------------------------------------------------------------------------
// Timeline FFI: queries
// ---------------------------------------------------------------------------

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_get_clips(
    handle: *mut c_void,
    track_index: u32,
    out_ptr: *mut vs_timeline_clip_info,
    out_cap: u32,
    out_written: *mut u32,
) -> i32 {
    if out_written.is_null() {
        return -1;
    }

    if out_cap > 0 && out_ptr.is_null() {
        return -2;
    }

    let tl = match unsafe { timeline_from_handle(handle) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    let idx = track_index as usize;
    if idx >= tl.tracks.len() {
        return -2;
    }

    let track = &tl.tracks[idx];
    let total = track.clips.len().min(u32::MAX as usize) as u32;
    let write_count = (out_cap as usize).min(total as usize);

    for i in 0..write_count {
        let clip = &track.clips[i];
        unsafe {
            *out_ptr.add(i) = vs_timeline_clip_info {
                id: clip.id,
                track_index,
                start_ms: clip.start_ms,
                end_ms: clip.end_ms,
                kind: track_kind_for_clip(&clip.data),
                transform: clip.transform.to_ffi(),
            };
        }
    }

    unsafe {
        *out_written = total;
    }
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_get_visible_clips_at(
    handle: *mut c_void,
    time_ms: u32,
    out_ptr: *mut vs_timeline_clip_info,
    out_cap: u32,
    out_written: *mut u32,
) -> i32 {
    if out_written.is_null() {
        return -1;
    }

    if out_cap > 0 && out_ptr.is_null() {
        return -2;
    }

    let tl = match unsafe { timeline_from_handle(handle) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    let mut written: u32 = 0;

    for (track_idx, track) in tl.tracks.iter().enumerate() {
        if !track.visible {
            continue;
        }

        for clip in &track.clips {
            if time_ms >= clip.start_ms && time_ms < clip.end_ms {
                if written < out_cap {
                    unsafe {
                        *out_ptr.add(written as usize) = vs_timeline_clip_info {
                            id: clip.id,
                            track_index: track_idx as u32,
                            start_ms: clip.start_ms,
                            end_ms: clip.end_ms,
                            kind: track.kind,
                            transform: clip.transform.to_ffi(),
                        };
                    }
                }
                written += 1;
            }
        }
    }

    unsafe {
        *out_written = written;
    }
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_get_clip_text(
    handle: *mut c_void,
    track_index: u32,
    clip_id: u32,
    out_ptr: *mut u8,
    out_cap: u32,
    out_written: *mut u32,
) -> i32 {
    if out_written.is_null() {
        return -1;
    }

    if out_cap > 0 && out_ptr.is_null() {
        return -2;
    }

    let tl = match unsafe { timeline_from_handle(handle) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    let idx = track_index as usize;

    let clip = match tl.find_clip(idx, clip_id) {
        Some(c) => c,
        None => return -2,
    };

    let text = match &clip.data {
        ClipData::Text { text, .. } => text,
        _ => return -2,
    };

    let bytes = text.as_bytes();
    let copy_len = bytes.len().min(out_cap as usize);

    if copy_len > 0 {
        unsafe {
            std::ptr::copy_nonoverlapping(bytes.as_ptr(), out_ptr, copy_len);
        }
    }

    unsafe {
        *out_written = bytes.len() as u32;
    }
    0
}

// ---------------------------------------------------------------------------
// Timeline FFI: undo/redo
// ---------------------------------------------------------------------------

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_undo(handle: *mut c_void) -> i32 {
    let tl = match unsafe { timeline_from_handle_mut(handle) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    if tl.history_cursor == 0 {
        return 1;
    }

    tl.history_cursor -= 1;
    let action = tl.history[tl.history_cursor].clone();
    tl.reverse_action(&action);
    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_redo(handle: *mut c_void) -> i32 {
    let tl = match unsafe { timeline_from_handle_mut(handle) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    if tl.history_cursor >= tl.history.len() {
        return 1;
    }

    let action = tl.history[tl.history_cursor].clone();
    tl.apply_action(&action);
    tl.history_cursor += 1;
    0
}

// ---------------------------------------------------------------------------
// Timeline FFI: info and zoom scale
// ---------------------------------------------------------------------------

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_get_video_info(
    handle: *mut c_void,
    out_duration_ms: *mut u32,
    out_width: *mut u32,
    out_height: *mut u32,
) -> i32 {
    let tl = match unsafe { timeline_from_handle(handle) } {
        Ok(v) => v,
        Err(code) => return code,
    };

    if !out_duration_ms.is_null() {
        unsafe {
            *out_duration_ms = tl.video_duration_ms;
        }
    }
    if !out_width.is_null() {
        unsafe {
            *out_width = tl.width;
        }
    }
    if !out_height.is_null() {
        unsafe {
            *out_height = tl.height;
        }
    }

    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_set_clip_zoom_scale(
    handle: *mut c_void,
    track_index: u32,
    clip_id: u32,
    scale: f32,
) -> i32 {
    if !scale.is_finite() || scale <= 0.0 {
        return -2;
    }

    let tl = match unsafe { timeline_from_handle_mut(handle) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    let idx = track_index as usize;

    let clip = match tl.find_clip(idx, clip_id) {
        Some(c) => c,
        None => return -2,
    };

    let old_scale = match &clip.data {
        ClipData::Zoom { scale } => *scale,
        _ => return -2,
    };

    if (old_scale - scale).abs() < f32::EPSILON {
        return 0;
    }

    let clip = match tl.find_clip_mut(idx, clip_id) {
        Some(c) => c,
        None => return -2,
    };
    if let ClipData::Zoom {
        scale: ref mut value,
    } = clip.data
    {
        *value = scale;
    } else {
        return -2;
    }

    0
}

#[no_mangle]
pub unsafe extern "C" fn vs_timeline_get_clip_zoom_scale(
    handle: *mut c_void,
    track_index: u32,
    clip_id: u32,
    out_scale: *mut f32,
) -> i32 {
    if out_scale.is_null() {
        return -1;
    }

    let tl = match unsafe { timeline_from_handle(handle) } {
        Ok(v) => v,
        Err(code) => return code,
    };
    let idx = track_index as usize;

    let clip = match tl.find_clip(idx, clip_id) {
        Some(c) => c,
        None => return -2,
    };

    match &clip.data {
        ClipData::Zoom { scale } => {
            unsafe {
                *out_scale = *scale;
            }
            0
        }
        _ => -2,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_base(width: usize, height: usize) -> Vec<u8> {
        let mut data = vec![0u8; width * height * 4];
        for i in (3..data.len()).step_by(4) {
            data[i] = 255;
        }
        data
    }

    unsafe fn make_doc(width: usize, height: usize) -> *mut c_void {
        let base = make_base(width, height);
        // SAFETY: buffer is alive for call duration.
        unsafe {
            vs_create_document_from_bgra(
                width as u32,
                height as u32,
                (width * 4) as u32,
                base.as_ptr(),
                base.len(),
            )
        }
    }

    fn zero_transform() -> vs_clip_transform {
        vs_clip_transform {
            x: 0.0,
            y: 0.0,
            width: 0.0,
            height: 0.0,
            rotation: 0.0,
            opacity: 0.0,
        }
    }

    fn zero_clip_info() -> vs_timeline_clip_info {
        vs_timeline_clip_info {
            id: 0,
            track_index: 0,
            start_ms: 0,
            end_ms: 0,
            kind: 0,
            transform: zero_transform(),
        }
    }

    fn solid_bgra(width: usize, height: usize, b: u8, g: u8, r: u8, a: u8) -> Vec<u8> {
        let mut pixels = vec![0u8; width * height * 4];
        for y in 0..height {
            for x in 0..width {
                let idx = y * width * 4 + x * 4;
                pixels[idx] = b;
                pixels[idx + 1] = g;
                pixels[idx + 2] = r;
                pixels[idx + 3] = a;
            }
        }
        pixels
    }

    fn pixel_bgra(pixels: &[u8], stride: usize, x: usize, y: usize) -> (u8, u8, u8, u8) {
        let idx = y * stride + x * 4;
        (
            pixels[idx],
            pixels[idx + 1],
            pixels[idx + 2],
            pixels[idx + 3],
        )
    }

    fn approx_eq(lhs: f32, rhs: f32, epsilon: f32) -> bool {
        (lhs - rhs).abs() <= epsilon
    }

    #[test]
    fn undo_and_redo_affect_rendered_pixels() {
        // SAFETY: FFI pointers are managed and freed in this test.
        unsafe {
            let doc = make_doc(32, 24);
            assert!(!doc.is_null());

            let cmd = vs_rect_command {
                x: 4,
                y: 4,
                width: 10,
                height: 8,
                stroke_width: 2,
                r: 255,
                g: 0,
                b: 0,
                a: 255,
            };

            assert_eq!(vs_add_rect(doc, cmd), 0);

            let mut rendered = vec![0u8; 32 * 24 * 4];
            assert_eq!(
                vs_render_full(doc, rendered.as_mut_ptr(), rendered.len()),
                0
            );

            let idx = 4 * (32 * 4) + 4 * 4;
            assert_eq!(rendered[idx + 2], 255);

            assert_eq!(vs_undo(doc), 0);
            assert_eq!(
                vs_render_full(doc, rendered.as_mut_ptr(), rendered.len()),
                0
            );
            assert_eq!(rendered[idx + 2], 0);

            assert_eq!(vs_redo(doc), 0);
            assert_eq!(
                vs_render_full(doc, rendered.as_mut_ptr(), rendered.len()),
                0
            );
            assert_eq!(rendered[idx + 2], 255);

            vs_destroy_document(doc);
        }
    }

    #[test]
    fn render_dirty_returns_changed_rect() {
        // SAFETY: FFI pointers are managed and freed in this test.
        unsafe {
            let doc = make_doc(64, 64);
            assert!(!doc.is_null());

            let mut out = make_base(64, 64);
            assert_eq!(vs_render_full(doc, out.as_mut_ptr(), out.len()), 0);

            let cmd = vs_rect_command {
                x: 10,
                y: 12,
                width: 20,
                height: 18,
                stroke_width: 3,
                r: 0,
                g: 255,
                b: 0,
                a: 255,
            };
            assert_eq!(vs_add_rect(doc, cmd), 0);

            let mut dirty = vs_dirty_rect {
                x: 0,
                y: 0,
                width: 0,
                height: 0,
            };
            let mut written = 0usize;

            assert_eq!(
                vs_render_dirty(
                    doc,
                    out.as_mut_ptr(),
                    out.len(),
                    &mut dirty,
                    1,
                    &mut written,
                ),
                0
            );

            assert_eq!(written, 1);
            assert_eq!(dirty.x, 10);
            assert_eq!(dirty.y, 12);
            assert_eq!(dirty.width, 20);
            assert_eq!(dirty.height, 18);

            let idx = 12 * (64 * 4) + 10 * 4;
            assert_eq!(out[idx + 1], 255);

            assert_eq!(
                vs_render_dirty(
                    doc,
                    out.as_mut_ptr(),
                    out.len(),
                    &mut dirty,
                    1,
                    &mut written,
                ),
                0
            );
            assert_eq!(written, 0);

            vs_destroy_document(doc);
        }
    }

    #[test]
    fn remove_annotation_clears_rendered_pixels() {
        // SAFETY: FFI pointers are managed and freed in this test.
        unsafe {
            let doc = make_doc(48, 36);
            assert!(!doc.is_null());

            let cmd = vs_rect_command {
                x: 8,
                y: 6,
                width: 18,
                height: 12,
                stroke_width: 3,
                r: 255,
                g: 64,
                b: 0,
                a: 255,
            };
            assert_eq!(vs_add_rect(doc, cmd), 0);

            let mut out = make_base(48, 36);
            assert_eq!(vs_render_full(doc, out.as_mut_ptr(), out.len()), 0);

            let probe_idx = 6 * (48 * 4) + 8 * 4;
            assert_eq!(out[probe_idx + 2], 255);
            assert_eq!(out[probe_idx + 1], 64);

            assert_eq!(vs_remove_annotation(doc, 0), 0);

            let mut dirty = vs_dirty_rect {
                x: 0,
                y: 0,
                width: 0,
                height: 0,
            };
            let mut written = 0usize;
            assert_eq!(
                vs_render_dirty(
                    doc,
                    out.as_mut_ptr(),
                    out.len(),
                    &mut dirty,
                    1,
                    &mut written,
                ),
                0
            );
            assert_eq!(written, 1);
            assert_eq!(dirty.x, 8);
            assert_eq!(dirty.y, 6);
            assert_eq!(dirty.width, 18);
            assert_eq!(dirty.height, 12);

            assert_eq!(out[probe_idx + 2], 0);
            assert_eq!(out[probe_idx + 1], 0);

            vs_destroy_document(doc);
        }
    }

    #[test]
    fn video_session_export_plan_tracks_counts_and_trim() {
        let config = vs_video_session_config {
            frame_rate: 60,
            capture_system_audio: true,
            capture_microphone: false,
            show_webcam: true,
            highlight_mouse_clicks: true,
            highlight_keystrokes: true,
        };
        let session = vs_video_session_create(config);
        assert!(!session.is_null());

        let key_a = b"CmdK";
        let key_b = b"Esc";

        // SAFETY: pointers remain valid for call duration and session handle is valid.
        unsafe {
            assert_eq!(
                vs_video_session_add_key_event(
                    session,
                    vs_video_key_event {
                        timestamp_ns: 10,
                        token_ptr: key_a.as_ptr(),
                        token_len: key_a.len(),
                    },
                ),
                0
            );
            assert_eq!(
                vs_video_session_add_key_event(
                    session,
                    vs_video_key_event {
                        timestamp_ns: 20,
                        token_ptr: key_b.as_ptr(),
                        token_len: key_b.len(),
                    },
                ),
                0
            );
            assert_eq!(
                vs_video_session_add_click_event(
                    session,
                    vs_video_click_event {
                        timestamp_ns: 30,
                        normalized_x: 0.35,
                        normalized_y: 0.82,
                        button: 0,
                    },
                ),
                0
            );
            assert_eq!(vs_video_session_set_trim(session, 120, 980), 0);

            let mut plan = vs_video_export_plan {
                trim_start_ms: 0,
                trim_end_ms: 0,
                key_event_count: 0,
                click_event_count: 0,
                plan_mode: 0,
                include_audio: false,
                include_webcam: false,
                text_overlay_count: 0,
                overlay_item_count: 0,
                requires_intermediate_for_gif: false,
                needs_custom_compositor: false,
            };
            assert_eq!(vs_video_session_get_export_plan(session, &mut plan), 0);
            assert_eq!(plan.trim_start_ms, 120);
            assert_eq!(plan.trim_end_ms, 980);
            assert_eq!(plan.key_event_count, 2);
            assert_eq!(plan.click_event_count, 1);
            assert_eq!(plan.plan_mode, VS_VIDEO_PLAN_MODE_COMPOSITE_MP4);
            assert_eq!(plan.overlay_item_count, 2);
            assert!(plan.requires_intermediate_for_gif);
            assert_eq!(
                vs_video_session_set_export_context(
                    session,
                    vs_video_export_context {
                        source_has_audio: true,
                        source_has_webcam_asset: true,
                        audio_track_visible: false,
                        webcam_track_visible: true,
                        text_overlay_count: 3,
                    },
                ),
                0
            );
            assert_eq!(vs_video_session_get_export_plan(session, &mut plan), 0);
            assert!(!plan.include_audio);
            assert!(plan.include_webcam);
            assert_eq!(plan.text_overlay_count, 3);
            assert_eq!(plan.overlay_item_count, 5);
            assert_eq!(plan.plan_mode, VS_VIDEO_PLAN_MODE_COMPOSITE_MP4);
            assert!(plan.requires_intermediate_for_gif);
            assert!(plan.needs_custom_compositor);

            vs_video_session_destroy(session);
        }
    }

    #[test]
    fn stitch_estimate_detects_bottom_delta_for_shifted_frames() {
        let width = 80usize;
        let height = 56usize;
        let shift = 7usize;
        let stride = width * 4;

        let mut previous = vec![0u8; stride * height];
        for y in 0..height {
            for x in 0..width {
                let idx = y * stride + x * 4;
                previous[idx] = ((x * 3 + y * 5) % 251) as u8;
                previous[idx + 1] = ((x * 11 + y * 7) % 251) as u8;
                previous[idx + 2] = ((x * 13 + y * 17) % 251) as u8;
                previous[idx + 3] = 255;
            }
        }

        let mut current = vec![0u8; stride * height];
        for y in 0..(height - shift) {
            let src = (y + shift) * stride;
            let dst = y * stride;
            current[dst..dst + stride].copy_from_slice(&previous[src..src + stride]);
        }
        for y in (height - shift)..height {
            for x in 0..width {
                let idx = y * stride + x * 4;
                current[idx] = ((x * 19 + y * 23 + 29) % 251) as u8;
                current[idx + 1] = ((x * 31 + y * 7 + 41) % 251) as u8;
                current[idx + 2] = ((x * 5 + y * 37 + 53) % 251) as u8;
                current[idx + 3] = 255;
            }
        }

        let prev_view = vs_bgra_image_view {
            width: width as u32,
            height: height as u32,
            stride: stride as u32,
            ptr: previous.as_ptr(),
            len: previous.len(),
        };
        let curr_view = vs_bgra_image_view {
            width: width as u32,
            height: height as u32,
            stride: stride as u32,
            ptr: current.as_ptr(),
            len: current.len(),
        };
        let mut delta = vs_stitch_delta::default();

        // SAFETY: views point to valid slices for the full duration of the call.
        let status = unsafe {
            vs_stitch_estimate_delta_bgra(
                prev_view,
                curr_view,
                -1,
                shift as u32,
                true,
                false,
                &mut delta,
            )
        };
        assert_eq!(status, 0);
        assert_eq!(delta.rows, shift as u32);
        assert_eq!(delta.side, VS_STITCH_SIDE_BOTTOM);
    }

    #[test]
    fn stitch_merge_places_segment_on_requested_side() {
        let width = 16usize;
        let base_height = 10usize;
        let segment_height = 3usize;
        let stride = width * 4;
        let base = solid_bgra(width, base_height, 10, 20, 30, 255);
        let segment = solid_bgra(width, segment_height, 200, 150, 100, 255);

        let base_view = vs_bgra_image_view {
            width: width as u32,
            height: base_height as u32,
            stride: stride as u32,
            ptr: base.as_ptr(),
            len: base.len(),
        };
        let segment_view = vs_bgra_image_view {
            width: width as u32,
            height: segment_height as u32,
            stride: stride as u32,
            ptr: segment.as_ptr(),
            len: segment.len(),
        };

        let mut merged_bottom = vs_bgra_owned_image {
            width: 0,
            height: 0,
            stride: 0,
            ptr: std::ptr::null_mut(),
            len: 0,
        };
        let mut merged_top = merged_bottom;

        // SAFETY: views reference valid memory; owned output is destroyed before test returns.
        unsafe {
            assert_eq!(
                vs_stitch_merge_bgra(
                    base_view,
                    segment_view,
                    VS_STITCH_SIDE_BOTTOM,
                    &mut merged_bottom
                ),
                0
            );
            assert_eq!(
                vs_stitch_merge_bgra(base_view, segment_view, VS_STITCH_SIDE_TOP, &mut merged_top),
                0
            );

            let bottom_pixels = std::slice::from_raw_parts(merged_bottom.ptr, merged_bottom.len);
            assert_eq!(merged_bottom.height as usize, base_height + segment_height);
            assert_eq!(
                pixel_bgra(bottom_pixels, merged_bottom.stride as usize, 0, 0),
                (10, 20, 30, 255)
            );
            assert_eq!(
                pixel_bgra(bottom_pixels, merged_bottom.stride as usize, 0, base_height),
                (200, 150, 100, 255)
            );

            let top_pixels = std::slice::from_raw_parts(merged_top.ptr, merged_top.len);
            assert_eq!(merged_top.height as usize, base_height + segment_height);
            assert_eq!(
                pixel_bgra(top_pixels, merged_top.stride as usize, 0, 0),
                (200, 150, 100, 255)
            );
            assert_eq!(
                pixel_bgra(top_pixels, merged_top.stride as usize, 0, segment_height),
                (10, 20, 30, 255)
            );

            vs_bgra_owned_image_destroy(&mut merged_bottom);
            vs_bgra_owned_image_destroy(&mut merged_top);
        }
    }

    #[test]
    fn bgra_crop_extracts_expected_region() {
        let width = 8usize;
        let height = 6usize;
        let stride = width * 4;
        let mut pixels = vec![0u8; stride * height];

        for y in 0..height {
            for x in 0..width {
                let idx = y * stride + x * 4;
                pixels[idx] = (x as u8).wrapping_mul(10);
                pixels[idx + 1] = (y as u8).wrapping_mul(20);
                pixels[idx + 2] = 140;
                pixels[idx + 3] = 255;
            }
        }

        let source_view = vs_bgra_image_view {
            width: width as u32,
            height: height as u32,
            stride: stride as u32,
            ptr: pixels.as_ptr(),
            len: pixels.len(),
        };
        let mut cropped = vs_bgra_owned_image {
            width: 0,
            height: 0,
            stride: 0,
            ptr: std::ptr::null_mut(),
            len: 0,
        };

        // SAFETY: view references valid source bytes and owned image is released below.
        unsafe {
            assert_eq!(vs_bgra_crop(source_view, 2, 1, 3, 4, &mut cropped), 0);
            assert_eq!(cropped.width, 3);
            assert_eq!(cropped.height, 4);
            let cropped_pixels = std::slice::from_raw_parts(cropped.ptr, cropped.len);
            assert_eq!(
                pixel_bgra(cropped_pixels, cropped.stride as usize, 0, 0),
                (20, 20, 140, 255)
            );
            assert_eq!(
                pixel_bgra(cropped_pixels, cropped.stride as usize, 2, 3),
                (40, 80, 140, 255)
            );
            vs_bgra_owned_image_destroy(&mut cropped);
        }
    }

    #[test]
    fn selection_move_rect_clamps_to_bounds() {
        let current = vs_f32_rect {
            x: 50.0,
            y: 40.0,
            width: 120.0,
            height: 80.0,
        };
        let bounds = vs_f32_rect {
            x: 0.0,
            y: 0.0,
            width: 200.0,
            height: 160.0,
        };
        let mut out = vs_f32_rect::default();

        // SAFETY: out pointer is valid.
        let status = unsafe { vs_selection_move_rect(current, bounds, 200.0, -100.0, &mut out) };
        assert_eq!(status, 0);
        assert_eq!(out.x, 80.0);
        assert_eq!(out.y, 0.0);
        assert_eq!(out.width, 120.0);
        assert_eq!(out.height, 80.0);
    }

    #[test]
    fn selection_resize_rect_applies_corner_and_minimums() {
        let start = vs_f32_rect {
            x: 60.0,
            y: 30.0,
            width: 120.0,
            height: 100.0,
        };
        let bounds = vs_f32_rect {
            x: 0.0,
            y: 0.0,
            width: 300.0,
            height: 200.0,
        };
        let mut out = vs_f32_rect::default();

        // SAFETY: out pointer is valid.
        let status = unsafe {
            vs_selection_resize_rect(
                start,
                bounds,
                VS_RESIZE_CORNER_TOP_LEFT,
                200.0,
                -90.0,
                80.0,
                60.0,
                &mut out,
            )
        };
        assert_eq!(status, 0);
        assert_eq!(out.width, 80.0);
        assert_eq!(out.height, 60.0);
        assert!(out.x >= 0.0);
        assert!(out.y >= 0.0);
    }

    #[test]
    fn encode_bgra_image_outputs_png_and_jpeg_bytes() {
        let width = 5usize;
        let height = 4usize;
        let stride = width * 4;
        let pixels = solid_bgra(width, height, 12, 34, 56, 255);
        let source = vs_bgra_image_view {
            width: width as u32,
            height: height as u32,
            stride: stride as u32,
            ptr: pixels.as_ptr(),
            len: pixels.len(),
        };
        let mut png = vs_encoded_bytes {
            ptr: std::ptr::null_mut(),
            len: 0,
        };
        let mut jpeg = png;

        // SAFETY: source view is valid and owned buffers are released below.
        unsafe {
            assert_eq!(
                vs_encode_bgra_image(source, VS_IMAGE_ENCODE_PNG, 0, &mut png),
                0
            );
            assert!(png.len > 8);
            let png_bytes = std::slice::from_raw_parts(png.ptr, png.len);
            assert_eq!(png_bytes[0], 0x89);
            assert_eq!(png_bytes[1], b'P');
            assert_eq!(png_bytes[2], b'N');
            assert_eq!(png_bytes[3], b'G');

            assert_eq!(
                vs_encode_bgra_image(source, VS_IMAGE_ENCODE_JPEG, 90, &mut jpeg),
                0
            );
            assert!(jpeg.len > 4);
            let jpeg_bytes = std::slice::from_raw_parts(jpeg.ptr, jpeg.len);
            assert_eq!(jpeg_bytes[0], 0xFF);
            assert_eq!(jpeg_bytes[1], 0xD8);

            vs_encoded_bytes_destroy(&mut png);
            vs_encoded_bytes_destroy(&mut jpeg);
        }
    }

    #[test]
    fn stitch_session_push_frame_and_merge_accumulates_segments() {
        let width = 96usize;
        let height = 68usize;
        let shift = 9usize;
        let stride = width * 4;

        let mut frame_a = vec![0u8; stride * height];
        for y in 0..height {
            for x in 0..width {
                let idx = y * stride + x * 4;
                frame_a[idx] = ((x * 5 + y * 13) % 251) as u8;
                frame_a[idx + 1] = ((x * 17 + y * 3) % 251) as u8;
                frame_a[idx + 2] = ((x * 7 + y * 11) % 251) as u8;
                frame_a[idx + 3] = 255;
            }
        }

        let mut frame_b = vec![0u8; stride * height];
        for y in 0..(height - shift) {
            let src = (y + shift) * stride;
            let dst = y * stride;
            frame_b[dst..dst + stride].copy_from_slice(&frame_a[src..src + stride]);
        }
        for y in (height - shift)..height {
            for x in 0..width {
                let idx = y * stride + x * 4;
                frame_b[idx] = ((x * 19 + y * 23 + 31) % 251) as u8;
                frame_b[idx + 1] = ((x * 29 + y * 7 + 41) % 251) as u8;
                frame_b[idx + 2] = ((x * 3 + y * 37 + 53) % 251) as u8;
                frame_b[idx + 3] = 255;
            }
        }

        let base_view = vs_bgra_image_view {
            width: width as u32,
            height: height as u32,
            stride: stride as u32,
            ptr: frame_a.as_ptr(),
            len: frame_a.len(),
        };
        let first_view = base_view;
        let second_view = vs_bgra_image_view {
            width: width as u32,
            height: height as u32,
            stride: stride as u32,
            ptr: frame_b.as_ptr(),
            len: frame_b.len(),
        };

        let session = vs_stitch_session_create();
        assert!(!session.is_null());

        let mut first_result = vs_stitch_session_result::default();
        let mut first_merged = vs_bgra_owned_image {
            width: 0,
            height: 0,
            stride: 0,
            ptr: std::ptr::null_mut(),
            len: 0,
        };
        let mut second_result = first_result;
        let mut second_merged = first_merged;

        // SAFETY: pointers and handle are valid for call duration; owned output is destroyed below.
        unsafe {
            assert_eq!(vs_stitch_session_set_base_bgra(session, base_view, 1), 0);
            assert_eq!(
                vs_stitch_session_push_frame_and_merge_bgra(
                    session,
                    first_view,
                    &mut first_result,
                    &mut first_merged
                ),
                0
            );
            assert!(!first_result.accepted);
            assert!(first_merged.ptr.is_null());

            assert_eq!(
                vs_stitch_session_push_frame_and_merge_bgra(
                    session,
                    second_view,
                    &mut second_result,
                    &mut second_merged
                ),
                0
            );
            assert!(second_result.accepted);
            assert_eq!(second_result.side, VS_STITCH_SIDE_BOTTOM);
            assert_eq!(second_result.rows, shift as u32);
            assert_eq!(second_result.segment_count, 2);
            assert_eq!(second_merged.width as usize, width);
            assert_eq!(second_merged.height as usize, height + shift);

            vs_bgra_owned_image_destroy(&mut second_merged);
            vs_stitch_session_destroy(session);
        }
    }

    #[test]
    fn timeline_visible_clips_reports_total_when_output_capacity_is_small() {
        let tl = vs_timeline_create(10_000, 1920, 1080);
        assert!(!tl.is_null());

        // SAFETY: timeline handle is valid and destroyed at end of test.
        unsafe {
            assert_eq!(vs_timeline_add_track(tl, 0), 0);

            let mut clip_ids = [0u32; 3];
            for (idx, start) in [0u32, 1_000, 2_000].iter().enumerate() {
                assert_eq!(
                    vs_timeline_add_clip(tl, 0, *start, *start + 5_000, 0, &mut clip_ids[idx]),
                    0
                );
            }

            let mut out = [zero_clip_info(); 1];
            let mut written = 0u32;
            assert_eq!(
                vs_timeline_get_visible_clips_at(
                    tl,
                    2_500,
                    out.as_mut_ptr(),
                    out.len() as u32,
                    &mut written
                ),
                0
            );
            assert_eq!(written, 3);
            assert_eq!(out[0].id, clip_ids[0]);

            vs_timeline_destroy(tl);
        }
    }

    #[test]
    fn timeline_get_clip_text_reports_full_length_with_small_buffer() {
        let tl = vs_timeline_create(8_000, 1280, 720);
        assert!(!tl.is_null());

        // SAFETY: timeline handle is valid and destroyed at end of test.
        unsafe {
            assert_eq!(vs_timeline_add_track(tl, 3), 0);
            let mut clip_id = 0u32;
            assert_eq!(vs_timeline_add_clip(tl, 0, 0, 6_000, 3, &mut clip_id), 0);

            let text = "A".repeat(8_192);
            let bytes = text.as_bytes();
            assert_eq!(
                vs_timeline_set_clip_text(tl, 0, clip_id, bytes.as_ptr(), bytes.len() as u32),
                0
            );

            let mut buffer = vec![0u8; 16];
            let mut written = 0u32;
            assert_eq!(
                vs_timeline_get_clip_text(
                    tl,
                    0,
                    clip_id,
                    buffer.as_mut_ptr(),
                    buffer.len() as u32,
                    &mut written
                ),
                0
            );
            assert_eq!(written as usize, bytes.len());
            assert_eq!(&buffer[..], &bytes[..buffer.len()]);

            vs_timeline_destroy(tl);
        }
    }

    #[test]
    fn timeline_derive_export_context_counts_only_visible_tracks() {
        let tl = vs_timeline_create(9_000, 1280, 720);
        assert!(!tl.is_null());

        // SAFETY: handle is valid and destroyed at end of test.
        unsafe {
            assert_eq!(vs_timeline_add_track(tl, 0), 0); // video
            assert_eq!(vs_timeline_add_track(tl, 2), 0); // audio
            assert_eq!(vs_timeline_add_track(tl, 1), 0); // webcam
            assert_eq!(vs_timeline_add_track(tl, 3), 0); // text

            let mut clip_id = 0u32;
            assert_eq!(vs_timeline_add_clip(tl, 1, 0, 8_000, 2, &mut clip_id), 0);
            assert_eq!(vs_timeline_add_clip(tl, 2, 0, 8_000, 1, &mut clip_id), 0);
            assert_eq!(vs_timeline_add_clip(tl, 3, 0, 2_000, 3, &mut clip_id), 0);
            assert_eq!(
                vs_timeline_add_clip(tl, 3, 3_000, 5_000, 3, &mut clip_id),
                0
            );
            assert_eq!(vs_timeline_set_track_visible(tl, 2, false), 0); // webcam hidden

            let mut context = vs_video_export_context {
                source_has_audio: false,
                source_has_webcam_asset: false,
                audio_track_visible: false,
                webcam_track_visible: false,
                text_overlay_count: 0,
            };
            assert_eq!(
                vs_timeline_derive_export_context(tl, true, true, &mut context),
                0
            );
            assert!(context.source_has_audio);
            assert!(context.source_has_webcam_asset);
            assert!(context.audio_track_visible);
            assert!(!context.webcam_track_visible);
            assert_eq!(context.text_overlay_count, 2);

            vs_timeline_destroy(tl);
        }
    }

    #[test]
    fn timeline_export_text_clip_refs_are_filtered_and_sorted() {
        let tl = vs_timeline_create(9_000, 1280, 720);
        assert!(!tl.is_null());

        // SAFETY: handle is valid and destroyed at end of test.
        unsafe {
            assert_eq!(vs_timeline_add_track(tl, 0), 0); // video
            assert_eq!(vs_timeline_add_track(tl, 1), 0); // webcam
            assert_eq!(vs_timeline_add_track(tl, 3), 0); // text

            let mut clip_id = 0u32;
            assert_eq!(vs_timeline_add_clip(tl, 1, 0, 8_000, 1, &mut clip_id), 0);
            assert_eq!(
                vs_timeline_add_clip(tl, 2, 3_000, 4_000, 3, &mut clip_id),
                0
            );
            assert_eq!(
                vs_timeline_add_clip(tl, 2, 1_000, 2_000, 3, &mut clip_id),
                0
            );

            let mut webcam_visible = false;
            assert_eq!(
                vs_timeline_is_webcam_track_visible_for_export(tl, &mut webcam_visible),
                0
            );
            assert!(webcam_visible);

            let mut written = 0u32;
            assert_eq!(
                vs_timeline_get_text_export_clips(tl, std::ptr::null_mut(), 0, &mut written),
                0
            );
            assert_eq!(written, 2);

            let mut clips = vec![vs_timeline_text_export_clip_info::default(); written as usize];
            assert_eq!(
                vs_timeline_get_text_export_clips(
                    tl,
                    clips.as_mut_ptr(),
                    clips.len() as u32,
                    &mut written
                ),
                0
            );
            assert_eq!(written, 2);
            assert_eq!(clips[0].start_ms, 1_000);
            assert_eq!(clips[1].start_ms, 3_000);

            assert_eq!(vs_timeline_set_track_visible(tl, 1, false), 0);
            webcam_visible = true;
            assert_eq!(
                vs_timeline_is_webcam_track_visible_for_export(tl, &mut webcam_visible),
                0
            );
            assert!(!webcam_visible);

            vs_timeline_destroy(tl);
        }
    }

    #[test]
    fn video_compute_export_plan_respects_context_and_trim() {
        let context = vs_video_export_context {
            source_has_audio: true,
            source_has_webcam_asset: true,
            audio_track_visible: false,
            webcam_track_visible: true,
            text_overlay_count: 2,
        };
        let mut plan = vs_video_export_plan {
            trim_start_ms: 0,
            trim_end_ms: 0,
            key_event_count: 0,
            click_event_count: 0,
            plan_mode: 0,
            include_audio: false,
            include_webcam: false,
            text_overlay_count: 0,
            overlay_item_count: 0,
            requires_intermediate_for_gif: false,
            needs_custom_compositor: false,
        };

        // SAFETY: output pointer is valid for the duration of call.
        let status = unsafe { vs_video_compute_export_plan(120, 880, 3, 1, context, &mut plan) };
        assert_eq!(status, 0);
        assert_eq!(plan.trim_start_ms, 120);
        assert_eq!(plan.trim_end_ms, 880);
        assert_eq!(plan.key_event_count, 3);
        assert_eq!(plan.click_event_count, 1);
        assert!(!plan.include_audio);
        assert!(plan.include_webcam);
        assert_eq!(plan.text_overlay_count, 2);
        assert_eq!(plan.overlay_item_count, 5);
        assert_eq!(plan.plan_mode, VS_VIDEO_PLAN_MODE_COMPOSITE_MP4);
        assert!(plan.requires_intermediate_for_gif);
        assert!(plan.needs_custom_compositor);
    }

    #[test]
    fn input_normalization_helpers_are_deterministic() {
        let mut token_bytes = [0u8; 64];
        let mut written = 0u32;
        let chars = b"k";

        // SAFETY: pointers are valid for the duration of each FFI call.
        unsafe {
            assert_eq!(
                vs_normalize_key_token(
                    40,
                    VS_KEY_MOD_COMMAND | VS_KEY_MOD_SHIFT,
                    chars.as_ptr(),
                    chars.len() as u32,
                    token_bytes.as_mut_ptr(),
                    token_bytes.len() as u32,
                    &mut written,
                ),
                0
            );
        }
        let token = std::str::from_utf8(&token_bytes[..written as usize]).unwrap();
        assert_eq!(token, "⌘⇧K");

        // SAFETY: pointers are valid and lengths are bounded by local buffers.
        let duplicate = unsafe {
            vs_key_event_is_duplicate(
                7,
                token_bytes.as_ptr(),
                written,
                7,
                token_bytes.as_ptr(),
                written,
            )
        };
        assert!(duplicate);

        let mut out_x = 0.0f32;
        let mut out_y = 0.0f32;
        // SAFETY: output pointers are valid.
        unsafe {
            assert_eq!(
                vs_normalize_click_point(-0.25, 1.25, &mut out_x, &mut out_y),
                0
            );
        }
        assert!(approx_eq(out_x, 0.0, 0.0001));
        assert!(approx_eq(out_y, 1.0, 0.0001));

        assert!(vs_click_event_is_duplicate(
            11, 0, 0.42, 0.58, 11, 0, 0.42005, 0.57995, 0.001,
        ));
    }

    #[test]
    fn geometry_helpers_round_trip_rects_and_deltas() {
        let destination = vs_f32_rect {
            x: 100.0,
            y: 200.0,
            width: 640.0,
            height: 360.0,
        };
        let view_rect = vs_f32_rect {
            x: 180.0,
            y: 250.0,
            width: 220.0,
            height: 90.0,
        };
        let mut image_rect = vs_f32_rect::default();

        // SAFETY: output pointer is valid.
        unsafe {
            assert_eq!(
                vs_view_rect_to_image_rect(view_rect, destination, 1920, 1080, &mut image_rect),
                0
            );
        }
        assert!(image_rect.width > 0.0);
        assert!(image_rect.height > 0.0);

        let mut round_trip = vs_f32_rect::default();
        // SAFETY: output pointer is valid.
        unsafe {
            assert_eq!(
                vs_image_rect_to_view_rect(image_rect, destination, 1920, 1080, &mut round_trip),
                0
            );
        }

        assert!(approx_eq(round_trip.x, view_rect.x, 1.0));
        assert!(approx_eq(round_trip.y, view_rect.y, 1.0));
        assert!(approx_eq(round_trip.width, view_rect.width, 1.0));
        assert!(approx_eq(round_trip.height, view_rect.height, 1.0));

        let mut delta_image = vs_f32_point::default();
        let mut delta_view = vs_f32_point::default();
        // SAFETY: output pointers are valid.
        unsafe {
            assert_eq!(
                vs_view_delta_to_image_delta(12.0, -8.0, destination, 1920, 1080, &mut delta_image),
                0
            );
            assert_eq!(
                vs_image_delta_to_view_delta(
                    delta_image.x,
                    delta_image.y,
                    destination,
                    1920,
                    1080,
                    &mut delta_view
                ),
                0
            );
        }
        assert!(approx_eq(delta_view.x, 12.0, 0.01));
        assert!(approx_eq(delta_view.y, -8.0, 0.01));
    }

    #[test]
    fn trim_and_gif_policy_helpers_apply_limits() {
        let mut start = 0u32;
        let mut end = 0u32;
        // SAFETY: output pointers are valid.
        unsafe {
            assert_eq!(
                vs_normalize_trim_range(
                    1_000,
                    950,
                    960,
                    100,
                    VS_TRIM_HANDLE_END,
                    &mut start,
                    &mut end
                ),
                0
            );
        }
        assert_eq!(start, 860);
        assert_eq!(end, 960);

        let mut plan = vs_gif_export_plan::default();
        // SAFETY: output pointer is valid.
        unsafe {
            assert_eq!(
                vs_build_gif_export_plan(0, 1_000, 12.0, 9_999, &mut plan),
                0
            );
        }
        assert_eq!(plan.start_ms, 0);
        assert_eq!(plan.end_ms, 1_000);
        assert_eq!(plan.frame_count, 12);
        assert_eq!(plan.max_dimension, 2_048);
        assert_eq!(plan.frame_delay_ms, 83);

        let mut first_t = 0u32;
        let mut last_t = 0u32;
        // SAFETY: output pointers are valid.
        unsafe {
            assert_eq!(vs_gif_frame_time_ms(plan, 0, &mut first_t), 0);
            assert_eq!(
                vs_gif_frame_time_ms(plan, plan.frame_count - 1, &mut last_t),
                0
            );
        }
        assert_eq!(first_t, plan.start_ms);
        assert_eq!(last_t, plan.end_ms);
    }

    #[test]
    fn stitch_autoscroll_policy_flips_once_after_threshold() {
        let mut state = vs_stitch_autoscroll_state::default();
        // SAFETY: output pointer is valid.
        unsafe {
            assert_eq!(vs_stitch_autoscroll_reset(&mut state), 0);
        }
        assert_eq!(state.direction_sign, -1);
        assert_eq!(state.no_motion_ticks, 0);
        assert!(!state.did_flip_direction);

        for _ in 0..4 {
            let mut next = vs_stitch_autoscroll_state::default();
            // SAFETY: output pointer is valid.
            unsafe {
                assert_eq!(
                    vs_stitch_autoscroll_update(true, false, false, 4, state, &mut next),
                    0
                );
            }
            state = next;
        }
        assert_eq!(state.direction_sign, 1);
        assert_eq!(state.no_motion_ticks, 0);
        assert!(state.did_flip_direction);
    }

    #[test]
    fn timeline_bootstrap_and_auto_text_track_import_work() {
        let tl = vs_timeline_create(7_500, 1280, 720);
        assert!(!tl.is_null());

        // SAFETY: handle is valid and destroyed at end of test.
        unsafe {
            assert_eq!(vs_timeline_bootstrap_capture_tracks(tl, true, true), 0);

            let mut tracks = [vs_timeline_track_info {
                kind: 0,
                visible: false,
                clip_count: 0,
            }; 6];
            let mut track_written = 0u32;
            assert_eq!(
                vs_timeline_get_tracks(
                    tl,
                    tracks.as_mut_ptr(),
                    tracks.len() as u32,
                    &mut track_written
                ),
                0
            );
            assert_eq!(track_written, 3);
            assert_eq!(tracks[0].kind, 0);
            assert_eq!(tracks[1].kind, 2);
            assert_eq!(tracks[2].kind, 1);
            assert_eq!(tracks[0].clip_count, 1);

            let text = "  Hello Rust  ";
            let mut clip_id = 0u32;
            assert_eq!(
                vs_timeline_add_text_clip_auto_track(
                    tl,
                    500,
                    1_800,
                    text.as_ptr(),
                    text.len() as u32,
                    &mut clip_id,
                ),
                0
            );
            assert!(clip_id > 0);

            track_written = 0;
            assert_eq!(
                vs_timeline_get_tracks(
                    tl,
                    tracks.as_mut_ptr(),
                    tracks.len() as u32,
                    &mut track_written
                ),
                0
            );
            let text_track_idx = tracks
                .iter()
                .take(track_written as usize)
                .position(|track| track.kind == 3)
                .unwrap() as u32;

            let mut clip_written = 0u32;
            let mut clips = [zero_clip_info(); 4];
            assert_eq!(
                vs_timeline_get_clips(
                    tl,
                    text_track_idx,
                    clips.as_mut_ptr(),
                    clips.len() as u32,
                    &mut clip_written
                ),
                0
            );
            assert_eq!(clip_written, 1);
            assert_eq!(clips[0].id, clip_id);
            assert_eq!(clips[0].start_ms, 500);
            assert_eq!(clips[0].end_ms, 1_800);

            let mut text_buffer = [0u8; 32];
            let mut text_written = 0u32;
            assert_eq!(
                vs_timeline_get_clip_text(
                    tl,
                    text_track_idx,
                    clip_id,
                    text_buffer.as_mut_ptr(),
                    text_buffer.len() as u32,
                    &mut text_written,
                ),
                0
            );
            let restored_text = std::str::from_utf8(&text_buffer[..text_written as usize]).unwrap();
            assert_eq!(restored_text, "Hello Rust");

            vs_timeline_destroy(tl);
        }
    }
}
