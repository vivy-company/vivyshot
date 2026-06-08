use std::collections::HashSet;
use std::ffi::c_void;
use std::fs;
use std::path::PathBuf;
use std::process;
use std::ptr::NonNull;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

use screencapturekit::audio_devices::AudioInputDevice;
use screencapturekit::cg::CGRect;
use screencapturekit::cm::CMSampleBuffer;
use screencapturekit::recording_output::{
    RecordingCallbacks, SCRecordingOutput, SCRecordingOutputCodec, SCRecordingOutputConfiguration,
    SCRecordingOutputFileType,
};
use screencapturekit::screenshot_manager::{CGImageExt, SCScreenshotManager};
use screencapturekit::shareable_content::{
    SCDisplay, SCRunningApplication, SCShareableContent, SCWindow,
};
use screencapturekit::stream::configuration::{
    PixelFormat, SCCaptureDynamicRange, SCStreamConfiguration,
};
use screencapturekit::stream::content_filter::SCContentFilter;
use screencapturekit::stream::delegate_trait::StreamCallbacks;
use screencapturekit::stream::output_trait::SCStreamOutputTrait;
use screencapturekit::stream::output_type::SCStreamOutputType;
use screencapturekit::stream::SCStream;

use crate::{
    CaptureCapabilities, CaptureDevice, CaptureDeviceKind, CaptureError, CaptureErrorKind,
    CaptureRect, CapturedImage, RecordingCodec, RecordingConfig, RecordingContainer,
    RecordingEncoder, RecordingOutput, DEVICE_CAPABILITY_DISPLAY_RECORDING,
    DEVICE_CAPABILITY_MICROPHONE_AUDIO, DEVICE_CAPABILITY_REGION_RECORDING,
    DEVICE_CAPABILITY_SCREENSHOT_CAPTURE, PIXEL_FORMAT_BGRA8_PREMULTIPLIED_FIRST,
};

pub struct Backend;

pub struct RecordingSession {
    stream: SCStream,
    recording_output: Option<SCRecordingOutput>,
    software_writer: Option<Arc<SoftwareH264Writer>>,
    output: RecordingOutput,
    latest_error: Arc<Mutex<Option<CaptureError>>>,
}

impl Backend {
    pub fn new() -> Self {
        Self
    }

    pub fn capabilities(&self) -> CaptureCapabilities {
        CaptureCapabilities {
            region_recording: true,
            window_recording: false,
            display_recording: true,
            system_audio: true,
            microphone_audio: true,
            cursor_capture: true,
            mouse_click_visualization: true,
            direct_to_file_recording: true,
            h264: true,
            hevc: true,
            software_h264: true,
            screenshot_capture: true,
            overlay_window_exceptions: true,
        }
    }

    pub fn start_recording(
        &self,
        config: RecordingConfig,
    ) -> Result<RecordingSession, CaptureError> {
        start_recording(config)
    }

    pub fn devices(&self, kind: CaptureDeviceKind) -> Result<Vec<CaptureDevice>, CaptureError> {
        match kind {
            CaptureDeviceKind::Display => display_devices(),
            CaptureDeviceKind::Microphone => Ok(microphone_devices()),
        }
    }

    pub fn capture_screenshot(
        &self,
        rect_screen: CaptureRect,
    ) -> Result<CapturedImage, CaptureError> {
        capture_screenshot(rect_screen)
    }
}

impl Default for Backend {
    fn default() -> Self {
        Self::new()
    }
}

impl RecordingSession {
    pub fn stop(self) -> Result<RecordingOutput, CaptureError> {
        if let Err(error) = self.stream.stop_capture() {
            if let Some(writer) = &self.software_writer {
                writer.cancel();
            }
            return Err(CaptureError::new(
                CaptureErrorKind::StreamStoppedWithError,
                error.to_string(),
            ));
        }

        drop(self.recording_output);
        thread::sleep(Duration::from_millis(220));

        if let Some(error) = take_latest_error(&self.latest_error) {
            if let Some(writer) = &self.software_writer {
                writer.cancel();
            }
            return Err(error);
        }

        if let Some(writer) = &self.software_writer {
            writer.finish()?;
        }

        if !self.output.output_path.exists() {
            return Err(CaptureError::new(
                CaptureErrorKind::OutputFileUnavailable,
                format!(
                    "recording output does not exist: {}",
                    self.output.output_path.display()
                ),
            ));
        }

        Ok(self.output)
    }

    pub fn cancel(self) {
        let _ = self.stream.stop_capture();
        if let Some(writer) = &self.software_writer {
            writer.cancel();
        }
        let _ = fs::remove_file(&self.output.output_path);
    }
}

fn start_recording(config: RecordingConfig) -> Result<RecordingSession, CaptureError> {
    remove_existing_output(&config.output_path)?;

    let content = SCShareableContent::get().map_err(|error| {
        CaptureError::new(CaptureErrorKind::PermissionDenied, error.to_string())
    })?;
    let display = display_for_selection(&content, config.selection_rect_screen)?;
    let overlay_windows = resolve_overlay_windows(&config, &content)?;
    let excluded_apps = if config.exclude_current_process {
        excluded_current_process_apps(&content)
    } else {
        Vec::new()
    };

    let source_rect = source_rect_for_selection(config.selection_rect_screen, &display)?;
    let scale = display_scale(&display);
    let width = output_dimension(source_rect.size.width * scale);
    let height = output_dimension(source_rect.size.height * scale);

    let filter = build_filter(&display, &excluded_apps, &overlay_windows)?;
    let stream_config = SCStreamConfiguration::new()
        .with_source_rect(source_rect)
        .with_width(width)
        .with_height(height)
        .with_fps(config.frame_rate.max(1))
        .with_pixel_format(PixelFormat::BGRA)
        .with_queue_depth(5)
        .with_shows_cursor(config.show_cursor)
        .with_shows_mouse_clicks(config.highlight_mouse_clicks)
        .with_captures_audio(config.capture_system_audio)
        .with_captures_microphone(config.capture_microphone)
        .with_excludes_current_process_audio(false)
        .with_capture_dynamic_range(SCCaptureDynamicRange::SDR);

    if config.encoder == RecordingEncoder::SoftwareH264 {
        return start_software_recording(config, filter, stream_config, width, height);
    }

    let recording_config = build_recording_config(&config)?;
    let output = RecordingOutput {
        output_path: config.output_path.clone(),
        width,
        height,
        frame_rate: config.frame_rate.max(1),
        codec: codec_from_recording_config(&recording_config),
        container: container_from_recording_config(&recording_config),
    };

    let latest_error = Arc::new(Mutex::new(None));
    let stream_errors = latest_error.clone();
    let stream_delegate = StreamCallbacks::new().on_error(move |error| {
        store_latest_error(
            &stream_errors,
            CaptureError::new(CaptureErrorKind::StreamStoppedWithError, error.to_string()),
        );
    });

    let recording_errors = latest_error.clone();
    let recording_delegate = RecordingCallbacks::new().on_fail(move |error| {
        store_latest_error(
            &recording_errors,
            CaptureError::new(CaptureErrorKind::RecordingOutputFailed, error),
        );
    });

    let stream = SCStream::new_with_delegate(&filter, &stream_config, stream_delegate);
    let recording_output =
        SCRecordingOutput::new_with_delegate(&recording_config, recording_delegate).ok_or_else(
            || {
                CaptureError::new(
                    CaptureErrorKind::UnsupportedOsVersion,
                    "SCRecordingOutput requires macOS 15.0 or newer",
                )
            },
        )?;

    stream
        .add_recording_output(&recording_output)
        .map_err(|error| {
            CaptureError::new(CaptureErrorKind::RecordingOutputFailed, error.to_string())
        })?;
    stream.start_capture().map_err(|error| {
        CaptureError::new(CaptureErrorKind::StreamStartFailed, error.to_string())
    })?;

    Ok(RecordingSession {
        stream,
        recording_output: Some(recording_output),
        software_writer: None,
        output,
        latest_error,
    })
}

fn start_software_recording(
    config: RecordingConfig,
    filter: SCContentFilter,
    stream_config: SCStreamConfiguration,
    width: u32,
    height: u32,
) -> Result<RecordingSession, CaptureError> {
    let output = RecordingOutput {
        output_path: config.output_path.clone(),
        width,
        height,
        frame_rate: config.frame_rate.max(1),
        codec: RecordingCodec::H264,
        container: RecordingContainer::Mp4,
    };

    let writer = Arc::new(SoftwareH264Writer::new(
        &config.output_path,
        config.frame_rate.max(1),
        config.capture_system_audio,
        config.capture_microphone,
    )?);
    writer.configure_video_size(width, height)?;
    writer.prepare()?;

    let latest_error = Arc::new(Mutex::new(None));
    let stream_errors = latest_error.clone();
    let stream_delegate = StreamCallbacks::new().on_error(move |error| {
        store_latest_error(
            &stream_errors,
            CaptureError::new(CaptureErrorKind::StreamStoppedWithError, error.to_string()),
        );
    });

    let mut stream = SCStream::new_with_delegate(&filter, &stream_config, stream_delegate);
    add_software_output_handler(&mut stream, writer.clone(), SCStreamOutputType::Screen)?;
    if config.capture_system_audio {
        add_software_output_handler(&mut stream, writer.clone(), SCStreamOutputType::Audio)?;
    }
    if config.capture_microphone {
        add_software_output_handler(&mut stream, writer.clone(), SCStreamOutputType::Microphone)?;
    }

    if let Err(error) = stream.start_capture() {
        writer.cancel();
        return Err(CaptureError::new(
            CaptureErrorKind::StreamStartFailed,
            error.to_string(),
        ));
    }

    Ok(RecordingSession {
        stream,
        recording_output: None,
        software_writer: Some(writer),
        output,
        latest_error,
    })
}

fn add_software_output_handler(
    stream: &mut SCStream,
    writer: Arc<SoftwareH264Writer>,
    output_type: SCStreamOutputType,
) -> Result<(), CaptureError> {
    stream
        .add_output_handler(SoftwareH264SampleHandler { writer }, output_type)
        .map(|_| ())
        .ok_or_else(|| {
            CaptureError::new(
                CaptureErrorKind::RecordingOutputFailed,
                format!("failed to add software H.264 {output_type} stream output"),
            )
        })
}

fn display_devices() -> Result<Vec<CaptureDevice>, CaptureError> {
    let content = SCShareableContent::get().map_err(|error| {
        CaptureError::new(CaptureErrorKind::PermissionDenied, error.to_string())
    })?;
    Ok(content
        .displays()
        .into_iter()
        .map(|display| CaptureDevice {
            stable_id: display.display_id().to_string(),
            display_name: format!(
                "Display {} ({}x{})",
                display.display_id(),
                display.width(),
                display.height()
            ),
            capability_mask: DEVICE_CAPABILITY_DISPLAY_RECORDING
                | DEVICE_CAPABILITY_REGION_RECORDING
                | DEVICE_CAPABILITY_SCREENSHOT_CAPTURE,
            is_available: true,
        })
        .collect())
}

fn microphone_devices() -> Vec<CaptureDevice> {
    AudioInputDevice::list()
        .into_iter()
        .map(|device| CaptureDevice {
            stable_id: device.id,
            display_name: device.name,
            capability_mask: DEVICE_CAPABILITY_MICROPHONE_AUDIO,
            is_available: true,
        })
        .collect()
}

fn capture_screenshot(rect_screen: CaptureRect) -> Result<CapturedImage, CaptureError> {
    let rect_screen = rect_screen.standardized();
    if rect_screen.width < 1.0 || rect_screen.height < 1.0 {
        return Err(CaptureError::new(
            CaptureErrorKind::SelectionTooSmall,
            "selected region is too small to capture",
        ));
    }

    let image = SCScreenshotManager::capture_image_in_rect(CGRect::new(
        rect_screen.x.round(),
        rect_screen.y.round(),
        rect_screen.width.round(),
        rect_screen.height.round(),
    ))
    .map_err(|error| {
        CaptureError::new(CaptureErrorKind::InternalPlatformError, error.to_string())
    })?;

    let width = u32::try_from(image.width()).map_err(|_| {
        CaptureError::new(
            CaptureErrorKind::InternalPlatformError,
            "captured image width exceeds FFI limits",
        )
    })?;
    let height = u32::try_from(image.height()).map_err(|_| {
        CaptureError::new(
            CaptureErrorKind::InternalPlatformError,
            "captured image height exceeds FFI limits",
        )
    })?;
    let bytes_per_row = width.checked_mul(4).ok_or_else(|| {
        CaptureError::new(
            CaptureErrorKind::InternalPlatformError,
            "captured image row size overflows u32",
        )
    })?;
    let data = image.bgra_data().map_err(|error| {
        CaptureError::new(CaptureErrorKind::InternalPlatformError, error.to_string())
    })?;
    if data.len() > u32::MAX as usize {
        return Err(CaptureError::new(
            CaptureErrorKind::InternalPlatformError,
            "captured image data exceeds FFI limits",
        ));
    }

    Ok(CapturedImage {
        width,
        height,
        bytes_per_row,
        pixel_format: PIXEL_FORMAT_BGRA8_PREMULTIPLIED_FIRST,
        data,
    })
}

fn remove_existing_output(path: &PathBuf) -> Result<(), CaptureError> {
    if path.exists() {
        fs::remove_file(path).map_err(|error| {
            CaptureError::new(
                CaptureErrorKind::OutputFileUnavailable,
                format!("failed to remove existing output: {error}"),
            )
        })?;
    }
    Ok(())
}

fn display_for_selection(
    content: &SCShareableContent,
    selection: CaptureRect,
) -> Result<SCDisplay, CaptureError> {
    let selection = selection.standardized();
    let (center_x, center_y) = selection.center();
    content
        .displays()
        .into_iter()
        .find(|display| rect_contains(display.frame(), center_x, center_y))
        .or_else(|| content.displays().into_iter().next())
        .ok_or_else(|| {
            CaptureError::new(
                CaptureErrorKind::NoDisplayForSelection,
                "no compatible display found for selected area",
            )
        })
}

fn resolve_overlay_windows(
    config: &RecordingConfig,
    initial_content: &SCShareableContent,
) -> Result<Vec<SCWindow>, CaptureError> {
    if config.include_window_ids.is_empty() {
        return Ok(Vec::new());
    }

    let requested_ids: HashSet<u32> = config.include_window_ids.iter().copied().collect();
    for attempt in 0..5 {
        let content = if attempt == 0 {
            initial_content.windows()
        } else {
            SCShareableContent::get()
                .map_err(|error| {
                    CaptureError::new(CaptureErrorKind::InternalPlatformError, error.to_string())
                })?
                .windows()
        };
        let windows: Vec<SCWindow> = content
            .into_iter()
            .filter(|window| requested_ids.contains(&window.window_id()))
            .collect();
        if windows.len() == requested_ids.len() {
            return Ok(windows);
        }

        if attempt < 4 {
            thread::sleep(Duration::from_millis(80));
        }
    }

    Err(CaptureError::new(
        CaptureErrorKind::InternalPlatformError,
        "recording overlay window was not available to capture",
    ))
}

fn excluded_current_process_apps(content: &SCShareableContent) -> Vec<SCRunningApplication> {
    let pid = process::id() as i32;
    content
        .applications()
        .into_iter()
        .filter(|application| application.process_id() == pid)
        .collect()
}

fn build_filter(
    display: &SCDisplay,
    excluded_apps: &[SCRunningApplication],
    overlay_windows: &[SCWindow],
) -> Result<SCContentFilter, CaptureError> {
    let app_refs: Vec<&SCRunningApplication> = excluded_apps.iter().collect();
    let window_refs: Vec<&SCWindow> = overlay_windows.iter().collect();
    SCContentFilter::create()
        .with_display(display)
        .with_excluding_applications(&app_refs, &window_refs)
        .try_build()
        .map_err(|error| {
            CaptureError::new(CaptureErrorKind::InternalPlatformError, error.to_string())
        })
}

fn source_rect_for_selection(
    selection: CaptureRect,
    display: &SCDisplay,
) -> Result<CGRect, CaptureError> {
    let selection = selection.standardized();
    let selection_rect = CaptureRect {
        x: selection.x,
        y: selection.y,
        width: selection.width,
        height: selection.height,
    };
    let display_rect = display.frame();
    let intersection = intersect_rects(selection_rect, capture_rect_from_cg(display_rect))
        .ok_or_else(|| {
            CaptureError::new(
                CaptureErrorKind::SelectionTooSmall,
                "selected region does not intersect the active display",
            )
        })?;
    if intersection.width < 2.0 || intersection.height < 2.0 {
        return Err(CaptureError::new(
            CaptureErrorKind::SelectionTooSmall,
            "selected region is too small to record",
        ));
    }

    Ok(CGRect::new(
        (intersection.x - display_rect.origin.x).round(),
        (intersection.y - display_rect.origin.y).round(),
        intersection.width.round(),
        intersection.height.round(),
    ))
}

fn build_recording_config(
    config: &RecordingConfig,
) -> Result<SCRecordingOutputConfiguration, CaptureError> {
    let base = SCRecordingOutputConfiguration::new().with_output_url(&config.output_path);
    let available_codecs = base.available_video_codecs();
    let preferred_codec = match config.encoder {
        RecordingEncoder::StandardH264 => SCRecordingOutputCodec::H264,
        RecordingEncoder::SmallerFileHevc => {
            if available_codecs.contains(&SCRecordingOutputCodec::HEVC) {
                SCRecordingOutputCodec::HEVC
            } else {
                SCRecordingOutputCodec::H264
            }
        }
        RecordingEncoder::SoftwareH264 => SCRecordingOutputCodec::H264,
    };
    if !available_codecs.is_empty() && !available_codecs.contains(&preferred_codec) {
        return Err(CaptureError::new(
            CaptureErrorKind::UnsupportedCodec,
            "requested recording codec is not available",
        ));
    }

    let available_containers = base.available_output_file_types();
    let container = if available_containers.contains(&SCRecordingOutputFileType::MP4) {
        SCRecordingOutputFileType::MP4
    } else if let Some(first) = available_containers.first().copied() {
        first
    } else {
        return Err(CaptureError::new(
            CaptureErrorKind::UnsupportedContainer,
            "no recording output container is available",
        ));
    };

    Ok(base
        .with_video_codec(preferred_codec)
        .with_output_file_type(container))
}

fn codec_from_recording_config(config: &SCRecordingOutputConfiguration) -> RecordingCodec {
    match config.video_codec() {
        SCRecordingOutputCodec::HEVC => RecordingCodec::Hevc,
        SCRecordingOutputCodec::H264 => RecordingCodec::H264,
    }
}

fn container_from_recording_config(config: &SCRecordingOutputConfiguration) -> RecordingContainer {
    match config.output_file_type() {
        SCRecordingOutputFileType::MOV => RecordingContainer::Mov,
        SCRecordingOutputFileType::MP4 => RecordingContainer::Mp4,
    }
}

fn output_dimension(points: f64) -> u32 {
    (points.round().max(2.0)) as u32
}

fn display_scale(display: &SCDisplay) -> f64 {
    let frame = display.frame();
    if frame.size.width <= 0.0 {
        return 1.0;
    }
    (f64::from(display.width()) / frame.size.width).max(1.0)
}

fn rect_contains(rect: CGRect, x: f64, y: f64) -> bool {
    x >= rect.origin.x
        && y >= rect.origin.y
        && x < rect.origin.x + rect.size.width
        && y < rect.origin.y + rect.size.height
}

fn capture_rect_from_cg(rect: CGRect) -> CaptureRect {
    CaptureRect {
        x: rect.origin.x,
        y: rect.origin.y,
        width: rect.size.width,
        height: rect.size.height,
    }
}

fn intersect_rects(a: CaptureRect, b: CaptureRect) -> Option<CaptureRect> {
    let min_x = a.x.max(b.x);
    let min_y = a.y.max(b.y);
    let max_x = (a.x + a.width).min(b.x + b.width);
    let max_y = (a.y + a.height).min(b.y + b.height);
    if max_x <= min_x || max_y <= min_y {
        return None;
    }
    Some(CaptureRect {
        x: min_x,
        y: min_y,
        width: max_x - min_x,
        height: max_y - min_y,
    })
}

struct SoftwareH264Writer {
    ptr: NonNull<c_void>,
}

unsafe impl Send for SoftwareH264Writer {}
unsafe impl Sync for SoftwareH264Writer {}

impl SoftwareH264Writer {
    fn new(
        output_path: &PathBuf,
        frame_rate: u32,
        include_system_audio: bool,
        include_microphone_audio: bool,
    ) -> Result<Self, CaptureError> {
        let path = output_path.to_string_lossy();
        let path_len = u32::try_from(path.len()).map_err(|_| {
            CaptureError::new(
                CaptureErrorKind::InternalPlatformError,
                "software H.264 output path exceeds platform limits",
            )
        })?;
        let ptr = unsafe {
            sck_software_h264_writer_create(
                path.as_ptr(),
                path_len,
                frame_rate.max(1),
                include_system_audio,
                include_microphone_audio,
            )
        };
        let ptr = NonNull::new(ptr).ok_or_else(|| {
            CaptureError::new(
                CaptureErrorKind::RecordingOutputFailed,
                "failed to create software H.264 writer",
            )
        })?;
        Ok(Self { ptr })
    }

    fn configure_video_size(&self, width: u32, height: u32) -> Result<(), CaptureError> {
        software_writer_status(unsafe {
            sck_software_h264_writer_configure_video_size(self.ptr.as_ptr(), width, height)
        })
    }

    fn prepare(&self) -> Result<(), CaptureError> {
        software_writer_status(unsafe { sck_software_h264_writer_prepare(self.ptr.as_ptr()) })
    }

    fn append_sample(&self, sample_buffer: CMSampleBuffer, output_type: SCStreamOutputType) {
        let output_type = match output_type {
            SCStreamOutputType::Screen => 0,
            SCStreamOutputType::Audio => 1,
            SCStreamOutputType::Microphone => 2,
        };
        unsafe {
            sck_software_h264_writer_append(self.ptr.as_ptr(), sample_buffer.as_ptr(), output_type);
        }
    }

    fn finish(&self) -> Result<(), CaptureError> {
        software_writer_status(unsafe { sck_software_h264_writer_finish(self.ptr.as_ptr()) })
    }

    fn cancel(&self) {
        unsafe {
            sck_software_h264_writer_cancel(self.ptr.as_ptr());
        }
    }
}

impl Drop for SoftwareH264Writer {
    fn drop(&mut self) {
        unsafe {
            sck_software_h264_writer_destroy(self.ptr.as_ptr());
        }
    }
}

struct SoftwareH264SampleHandler {
    writer: Arc<SoftwareH264Writer>,
}

impl SCStreamOutputTrait for SoftwareH264SampleHandler {
    fn did_output_sample_buffer(&self, sample_buffer: CMSampleBuffer, of_type: SCStreamOutputType) {
        self.writer.append_sample(sample_buffer, of_type);
    }
}

fn software_writer_status(status: i32) -> Result<(), CaptureError> {
    if status == SCK_SOFTWARE_WRITER_STATUS_OK {
        return Ok(());
    }
    let (kind, diagnostic) = match status {
        SCK_SOFTWARE_WRITER_STATUS_INVALID_ARGUMENT => (
            CaptureErrorKind::InternalPlatformError,
            "software H.264 writer received an invalid request",
        ),
        SCK_SOFTWARE_WRITER_STATUS_NO_FRAMES => (
            CaptureErrorKind::NoFramesCaptured,
            "no video frames were captured for software H.264 recording",
        ),
        SCK_SOFTWARE_WRITER_STATUS_CANCELLED => (
            CaptureErrorKind::Cancelled,
            "software H.264 writer was cancelled",
        ),
        SCK_SOFTWARE_WRITER_STATUS_FINISH_FAILED => (
            CaptureErrorKind::RecordingOutputFailed,
            "software H.264 writer failed to finish",
        ),
        SCK_SOFTWARE_WRITER_STATUS_INCOMPLETE => (
            CaptureErrorKind::RecordingOutputFailed,
            "software H.264 writer did not complete",
        ),
        _ => (
            CaptureErrorKind::RecordingOutputFailed,
            "software H.264 writer setup failed",
        ),
    };
    Err(CaptureError::new(kind, diagnostic))
}

const SCK_SOFTWARE_WRITER_STATUS_OK: i32 = 0;
const SCK_SOFTWARE_WRITER_STATUS_INVALID_ARGUMENT: i32 = -1;
const SCK_SOFTWARE_WRITER_STATUS_NO_FRAMES: i32 = -7;
const SCK_SOFTWARE_WRITER_STATUS_FINISH_FAILED: i32 = -8;
const SCK_SOFTWARE_WRITER_STATUS_CANCELLED: i32 = -9;
const SCK_SOFTWARE_WRITER_STATUS_INCOMPLETE: i32 = -10;

extern "C" {
    fn sck_software_h264_writer_create(
        path_utf8: *const u8,
        path_len: u32,
        frame_rate: u32,
        include_system_audio: bool,
        include_microphone_audio: bool,
    ) -> *mut c_void;
    fn sck_software_h264_writer_configure_video_size(
        writer: *mut c_void,
        width: u32,
        height: u32,
    ) -> i32;
    fn sck_software_h264_writer_prepare(writer: *mut c_void) -> i32;
    fn sck_software_h264_writer_append(
        writer: *mut c_void,
        sample_buffer: *mut c_void,
        output_type: i32,
    );
    fn sck_software_h264_writer_finish(writer: *mut c_void) -> i32;
    fn sck_software_h264_writer_cancel(writer: *mut c_void);
    fn sck_software_h264_writer_destroy(writer: *mut c_void);
}

fn store_latest_error(lock: &Arc<Mutex<Option<CaptureError>>>, error: CaptureError) {
    let mut guard = lock
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    *guard = Some(error);
}

fn take_latest_error(lock: &Arc<Mutex<Option<CaptureError>>>) -> Option<CaptureError> {
    let mut guard = lock
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    guard.take()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn intersect_rects_returns_overlap() {
        let overlap = intersect_rects(
            CaptureRect {
                x: 10.0,
                y: 10.0,
                width: 20.0,
                height: 20.0,
            },
            CaptureRect {
                x: 20.0,
                y: 0.0,
                width: 10.0,
                height: 40.0,
            },
        );

        assert_eq!(
            overlap,
            Some(CaptureRect {
                x: 20.0,
                y: 10.0,
                width: 10.0,
                height: 20.0
            })
        );
    }

    #[test]
    fn output_dimension_has_screen_capture_minimum() {
        assert_eq!(output_dimension(0.5), 2);
        assert_eq!(output_dimension(12.4), 12);
        assert_eq!(output_dimension(12.6), 13);
    }
}
