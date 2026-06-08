use std::path::PathBuf;

#[cfg(target_os = "macos")]
mod macos;
#[cfg(not(target_os = "macos"))]
mod unsupported;

#[cfg(target_os = "macos")]
pub use macos::{Backend, RecordingSession, WebcamRecordingSession};
#[cfg(not(target_os = "macos"))]
pub use unsupported::{Backend, RecordingSession, WebcamRecordingSession};

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct CaptureRect {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
}

impl CaptureRect {
    pub fn standardized(self) -> Self {
        let (x, width) = if self.width < 0.0 {
            (self.x + self.width, -self.width)
        } else {
            (self.x, self.width)
        };
        let (y, height) = if self.height < 0.0 {
            (self.y + self.height, -self.height)
        } else {
            (self.y, self.height)
        };
        Self {
            x,
            y,
            width,
            height,
        }
    }

    pub fn center(self) -> (f64, f64) {
        (self.x + self.width / 2.0, self.y + self.height / 2.0)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RecordingEncoder {
    StandardH264,
    SmallerFileHevc,
    SoftwareH264,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RecordingCodec {
    H264,
    Hevc,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RecordingContainer {
    Mp4,
    Mov,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct CaptureCapabilities {
    pub region_recording: bool,
    pub window_recording: bool,
    pub display_recording: bool,
    pub system_audio: bool,
    pub microphone_audio: bool,
    pub cursor_capture: bool,
    pub mouse_click_visualization: bool,
    pub direct_to_file_recording: bool,
    pub h264: bool,
    pub hevc: bool,
    pub software_h264: bool,
    pub screenshot_capture: bool,
    pub overlay_window_exceptions: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CaptureDeviceKind {
    Display,
    Microphone,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CaptureDevice {
    pub stable_id: String,
    pub display_name: String,
    pub capability_mask: u32,
    pub is_available: bool,
}

pub const DEVICE_CAPABILITY_DISPLAY_RECORDING: u32 = 1 << 0;
pub const DEVICE_CAPABILITY_REGION_RECORDING: u32 = 1 << 1;
pub const DEVICE_CAPABILITY_SCREENSHOT_CAPTURE: u32 = 1 << 2;
pub const DEVICE_CAPABILITY_MICROPHONE_AUDIO: u32 = 1 << 3;
pub const DEVICE_CAPABILITY_WEBCAM_RECORDING: u32 = 1 << 4;

pub const PIXEL_FORMAT_BGRA8_PREMULTIPLIED_FIRST: u8 = 0;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CapturedImage {
    pub width: u32,
    pub height: u32,
    pub bytes_per_row: u32,
    pub pixel_format: u8,
    pub data: Vec<u8>,
}

impl CaptureCapabilities {
    pub const fn unsupported() -> Self {
        Self {
            region_recording: false,
            window_recording: false,
            display_recording: false,
            system_audio: false,
            microphone_audio: false,
            cursor_capture: false,
            mouse_click_visualization: false,
            direct_to_file_recording: false,
            h264: false,
            hevc: false,
            software_h264: false,
            screenshot_capture: false,
            overlay_window_exceptions: false,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct RecordingConfig {
    pub selection_rect_screen: CaptureRect,
    pub output_path: PathBuf,
    pub frame_rate: u32,
    pub encoder: RecordingEncoder,
    pub capture_system_audio: bool,
    pub capture_microphone: bool,
    pub show_cursor: bool,
    pub highlight_mouse_clicks: bool,
    pub include_window_ids: Vec<u32>,
    pub exclude_current_process: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub struct RecordingOutput {
    pub output_path: PathBuf,
    pub width: u32,
    pub height: u32,
    pub frame_rate: u32,
    pub codec: RecordingCodec,
    pub container: RecordingContainer,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WebcamDevice {
    pub stable_id: String,
    pub display_name: String,
    pub capability_mask: u32,
    pub is_available: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub struct WebcamRecordingConfig {
    pub output_path: PathBuf,
    pub preferred_device_id: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct WebcamRecordingOutput {
    pub output_path: PathBuf,
    pub recording_start_uptime_seconds: f64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CaptureErrorKind {
    PermissionDenied,
    PermissionNotDetermined,
    UnsupportedOsVersion,
    NoDisplayForSelection,
    SelectionTooSmall,
    UnsupportedCodec,
    UnsupportedContainer,
    StreamStartFailed,
    StreamStoppedWithError,
    RecordingOutputFailed,
    NoFramesCaptured,
    OutputFileUnavailable,
    Cancelled,
    InternalPlatformError,
    UnsupportedPlatform,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CaptureError {
    pub kind: CaptureErrorKind,
    pub diagnostic: String,
}

impl CaptureError {
    pub fn new(kind: CaptureErrorKind, diagnostic: impl Into<String>) -> Self {
        Self {
            kind,
            diagnostic: diagnostic.into(),
        }
    }
}

impl std::fmt::Display for CaptureError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        if self.diagnostic.is_empty() {
            write!(f, "{:?}", self.kind)
        } else {
            write!(f, "{:?}: {}", self.kind, self.diagnostic)
        }
    }
}

impl std::error::Error for CaptureError {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rect_standardization_preserves_visible_area() {
        let rect = CaptureRect {
            x: 10.0,
            y: 20.0,
            width: -4.0,
            height: -8.0,
        }
        .standardized();

        assert_eq!(
            rect,
            CaptureRect {
                x: 6.0,
                y: 12.0,
                width: 4.0,
                height: 8.0
            }
        );
    }

    #[test]
    fn unsupported_capabilities_are_empty() {
        let capabilities = CaptureCapabilities::unsupported();
        assert!(!capabilities.region_recording);
        assert!(!capabilities.direct_to_file_recording);
        assert!(!capabilities.overlay_window_exceptions);
    }

    #[test]
    fn device_capability_bits_do_not_overlap() {
        assert_eq!(
            DEVICE_CAPABILITY_DISPLAY_RECORDING
                | DEVICE_CAPABILITY_REGION_RECORDING
                | DEVICE_CAPABILITY_SCREENSHOT_CAPTURE
                | DEVICE_CAPABILITY_MICROPHONE_AUDIO,
            0b1111
        );
    }
}
