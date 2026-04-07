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
    capture_statistics_daily_buckets as domain_capture_statistics_daily_buckets,
    capture_statistics_ingest_event as domain_capture_statistics_ingest_event,
    capture_statistics_recent_daily_buckets as domain_capture_statistics_recent_daily_buckets,
    capture_statistics_reset as domain_capture_statistics_reset,
    capture_statistics_summary as domain_capture_statistics_summary,
    click_event_is_duplicate as domain_click_event_is_duplicate,
    derive_video_export_decision as domain_derive_video_export_decision,
    gif_frame_time_ms as domain_gif_frame_time_ms,
    normalize_click_point as domain_normalize_click_point,
    normalize_trim_range as domain_normalize_trim_range,
    quantize_image_point as domain_quantize_image_point,
    quantize_image_rect as domain_quantize_image_rect, quantize_rgba as domain_quantize_rgba,
    stitch_autoscroll_reset as domain_stitch_autoscroll_reset,
    stitch_autoscroll_update as domain_stitch_autoscroll_update,
    stitch_extract_strip as domain_stitch_extract_strip,
    stitch_merge_frames as domain_stitch_merge_frames,
    stitch_resize_width_nearest as domain_stitch_resize_width_nearest,
    timeline_clamp_clip_end as domain_timeline_clamp_clip_end,
    timeline_full_duration_end as domain_timeline_full_duration_end,
    timeline_normalize_text_clip_range as domain_timeline_normalize_text_clip_range,
    timeline_validate_split as domain_timeline_validate_split,
    BgraImageOwned as DomainBgraImageOwned, BgraImageView as DomainBgraImageView,
    CaptureStatisticsEvent as DomainCaptureStatisticsEvent,
    CaptureStatisticsEventType as DomainCaptureStatisticsEventType,
    CaptureStatisticsState as DomainCaptureStatisticsState,
    CaptureStatisticsSummary,
    DailyCaptureStats,
    StatsDayKey as DomainStatsDayKey,
    STATS_EVENT_RECORDING_COMPLETED as DOMAIN_STATS_EVENT_RECORDING_COMPLETED,
    STATS_EVENT_SCREENSHOT_CAPTURED as DOMAIN_STATS_EVENT_SCREENSHOT_CAPTURED,
    STATS_EVENT_SCREENSHOT_SESSION_COMPLETED as DOMAIN_STATS_EVENT_SCREENSHOT_SESSION_COMPLETED,
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

mod abi;
mod common;
pub(crate) use common::{register_handle, unregister_handle, validate_handle};
mod document;
mod video;
mod stats;
mod stitch;
pub(crate) use stitch::{bgra_view_slice, zero_bgra_owned_image};
mod geometry;
mod encode;
mod timeline;

#[cfg(test)]
mod tests;

pub use abi::*;
pub use common::{vs_core_abi_version, vs_core_version};
pub use document::*;
pub use encode::*;
pub use geometry::*;
pub use stats::*;
pub use stitch::*;
pub use timeline::*;
pub use video::*;

static VERSION: &[u8] = b"0.1.0\0";
static SYSTEM_FONTS: OnceLock<Vec<fontdue::Font>> = OnceLock::new();
static DOCUMENT_HANDLES: OnceLock<Mutex<HashSet<usize>>> = OnceLock::new();
static VIDEO_SESSION_HANDLES: OnceLock<Mutex<HashSet<usize>>> = OnceLock::new();
static STITCH_SESSION_HANDLES: OnceLock<Mutex<HashSet<usize>>> = OnceLock::new();
static TIMELINE_HANDLES: OnceLock<Mutex<HashSet<usize>>> = OnceLock::new();
static STATS_SESSION_HANDLES: OnceLock<Mutex<HashSet<usize>>> = OnceLock::new();

#[cfg(test)]
pub(crate) fn live_handle_counts() -> (usize, usize, usize, usize, usize) {
    (
        common::handle_count(&DOCUMENT_HANDLES),
        common::handle_count(&VIDEO_SESSION_HANDLES),
        common::handle_count(&STITCH_SESSION_HANDLES),
        common::handle_count(&TIMELINE_HANDLES),
        common::handle_count(&STATS_SESSION_HANDLES),
    )
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
pub const VS_STATS_EVENT_SCREENSHOT_CAPTURED: u8 = DOMAIN_STATS_EVENT_SCREENSHOT_CAPTURED;
pub const VS_STATS_EVENT_SCREENSHOT_SESSION_COMPLETED: u8 =
    DOMAIN_STATS_EVENT_SCREENSHOT_SESSION_COMPLETED;
pub const VS_STATS_EVENT_RECORDING_COMPLETED: u8 = DOMAIN_STATS_EVENT_RECORDING_COMPLETED;

pub const VS_CORE_ABI_VERSION_MAJOR: u32 = 1;
pub const VS_CORE_ABI_VERSION_MINOR: u32 = 1;
pub const VS_CORE_ABI_VERSION_PATCH: u32 = 0;
const VS_VIDEO_SESSION_SNAPSHOT_VERSION: u32 = 1;
const VS_STATS_SESSION_SNAPSHOT_VERSION: u32 = 1;
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
