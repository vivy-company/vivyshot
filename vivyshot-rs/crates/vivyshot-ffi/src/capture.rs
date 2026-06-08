#![allow(non_camel_case_types)]

use std::ffi::c_void;
use std::path::PathBuf;
use std::slice;
use std::sync::Mutex;
use std::thread;

use vivyshot_capture::{
    Backend as CaptureBackend, CaptureCapabilities, CaptureDevice, CaptureDeviceKind, CaptureError,
    CaptureErrorKind, CaptureRect, CapturedImage, RecordingCodec, RecordingConfig,
    RecordingContainer, RecordingEncoder, RecordingOutput, RecordingSession,
};

use super::*;

#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct vs_capture_rect {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct vs_capture_path {
    pub path_utf8: *const u8,
    pub path_len: u32,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct vs_capture_recording_config {
    pub selection_rect_screen: vs_capture_rect,
    pub output_path: vs_capture_path,
    pub frame_rate: u32,
    pub encoder: u8,
    pub capture_system_audio: bool,
    pub capture_microphone: bool,
    pub show_cursor: bool,
    pub highlight_mouse_clicks: bool,
    pub include_window_ids: *const u32,
    pub include_window_id_count: u32,
    pub exclude_current_process: bool,
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct vs_capture_recording_output {
    pub output_path: vs_capture_path,
    pub width: u32,
    pub height: u32,
    pub frame_rate: u32,
    pub codec: u8,
    pub container: u8,
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct vs_capture_capabilities {
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

#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct vs_capture_device {
    pub stable_id_utf8: *const u8,
    pub stable_id_len: u32,
    pub display_name_utf8: *const u8,
    pub display_name_len: u32,
    pub capability_mask: u32,
    pub is_available: bool,
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct vs_capture_captured_image {
    pub width: u32,
    pub height: u32,
    pub bytes_per_row: u32,
    pub pixel_format: u8,
    pub data: *const u8,
    pub data_len: u32,
}

pub struct vs_capture_recording_session {
    inner: Mutex<Option<RecordingSession>>,
}

pub type vs_capture_recording_start_callback =
    Option<extern "C" fn(*mut c_void, i32, *mut vs_capture_recording_session)>;

pub type vs_capture_recording_stop_callback =
    Option<extern "C" fn(*mut c_void, i32, vs_capture_recording_output)>;

pub type vs_capture_screenshot_callback =
    Option<extern "C" fn(*mut c_void, i32, vs_capture_captured_image)>;

fn capture_status(error: &CaptureError) -> i32 {
    match error.kind {
        CaptureErrorKind::PermissionDenied => VS_CAPTURE_STATUS_PERMISSION_DENIED,
        CaptureErrorKind::PermissionNotDetermined => VS_CAPTURE_STATUS_PERMISSION_NOT_DETERMINED,
        CaptureErrorKind::UnsupportedOsVersion => VS_CAPTURE_STATUS_UNSUPPORTED_OS_VERSION,
        CaptureErrorKind::NoDisplayForSelection => VS_CAPTURE_STATUS_NO_DISPLAY_FOR_SELECTION,
        CaptureErrorKind::SelectionTooSmall => VS_CAPTURE_STATUS_SELECTION_TOO_SMALL,
        CaptureErrorKind::UnsupportedCodec => VS_CAPTURE_STATUS_UNSUPPORTED_CODEC,
        CaptureErrorKind::UnsupportedContainer => VS_CAPTURE_STATUS_UNSUPPORTED_CONTAINER,
        CaptureErrorKind::StreamStartFailed => VS_CAPTURE_STATUS_STREAM_START_FAILED,
        CaptureErrorKind::StreamStoppedWithError => VS_CAPTURE_STATUS_STREAM_STOPPED_WITH_ERROR,
        CaptureErrorKind::RecordingOutputFailed => VS_CAPTURE_STATUS_RECORDING_OUTPUT_FAILED,
        CaptureErrorKind::NoFramesCaptured => VS_CAPTURE_STATUS_NO_FRAMES_CAPTURED,
        CaptureErrorKind::OutputFileUnavailable => VS_CAPTURE_STATUS_OUTPUT_FILE_UNAVAILABLE,
        CaptureErrorKind::Cancelled => VS_CAPTURE_STATUS_CANCELLED,
        CaptureErrorKind::InternalPlatformError => VS_CAPTURE_STATUS_INTERNAL_PLATFORM_ERROR,
        CaptureErrorKind::UnsupportedPlatform => VS_CAPTURE_STATUS_UNSUPPORTED_PLATFORM,
    }
}

unsafe fn read_path(path: vs_capture_path) -> Result<PathBuf, i32> {
    if path.path_utf8.is_null() {
        return Err(VS_CAPTURE_STATUS_NULL_POINTER);
    }
    let len = usize::try_from(path.path_len).map_err(|_| VS_CAPTURE_STATUS_INVALID_ARGUMENT)?;
    let bytes = unsafe { slice::from_raw_parts(path.path_utf8, len) };
    let path = std::str::from_utf8(bytes).map_err(|_| VS_CAPTURE_STATUS_INVALID_ARGUMENT)?;
    if path.is_empty() {
        return Err(VS_CAPTURE_STATUS_INVALID_ARGUMENT);
    }
    Ok(PathBuf::from(path))
}

unsafe fn read_window_ids(config: &vs_capture_recording_config) -> Result<Vec<u32>, i32> {
    if config.include_window_id_count == 0 {
        return Ok(Vec::new());
    }
    if config.include_window_ids.is_null() {
        return Err(VS_CAPTURE_STATUS_NULL_POINTER);
    }
    let len = usize::try_from(config.include_window_id_count)
        .map_err(|_| VS_CAPTURE_STATUS_INVALID_ARGUMENT)?;
    Ok(unsafe { slice::from_raw_parts(config.include_window_ids, len) }.to_vec())
}

unsafe fn to_capture_config(
    config: *const vs_capture_recording_config,
) -> Result<RecordingConfig, i32> {
    if config.is_null() {
        return Err(VS_CAPTURE_STATUS_NULL_POINTER);
    }
    let config = unsafe { &*config };
    let encoder = match config.encoder {
        VS_CAPTURE_ENCODER_STANDARD_H264 => RecordingEncoder::StandardH264,
        VS_CAPTURE_ENCODER_SMALLER_FILE_HEVC => RecordingEncoder::SmallerFileHevc,
        VS_CAPTURE_ENCODER_SOFTWARE_H264 => RecordingEncoder::SoftwareH264,
        _ => return Err(VS_CAPTURE_STATUS_INVALID_ARGUMENT),
    };
    Ok(RecordingConfig {
        selection_rect_screen: CaptureRect {
            x: config.selection_rect_screen.x,
            y: config.selection_rect_screen.y,
            width: config.selection_rect_screen.width,
            height: config.selection_rect_screen.height,
        },
        output_path: unsafe { read_path(config.output_path)? },
        frame_rate: config.frame_rate.max(1),
        encoder,
        capture_system_audio: config.capture_system_audio,
        capture_microphone: config.capture_microphone,
        show_cursor: config.show_cursor,
        highlight_mouse_clicks: config.highlight_mouse_clicks,
        include_window_ids: unsafe { read_window_ids(config)? },
        exclude_current_process: config.exclude_current_process,
    })
}

fn to_capture_rect(rect: vs_capture_rect) -> Result<CaptureRect, i32> {
    if !rect.x.is_finite()
        || !rect.y.is_finite()
        || !rect.width.is_finite()
        || !rect.height.is_finite()
    {
        return Err(VS_CAPTURE_STATUS_INVALID_ARGUMENT);
    }
    Ok(CaptureRect {
        x: rect.x,
        y: rect.y,
        width: rect.width,
        height: rect.height,
    })
}

fn path_to_ffi(path: PathBuf) -> vs_capture_path {
    let bytes = path.to_string_lossy().into_owned().into_bytes();
    let len = bytes.len().min(u32::MAX as usize) as u32;
    let ptr = Box::leak(bytes.into_boxed_slice()).as_ptr();
    vs_capture_path {
        path_utf8: ptr,
        path_len: len,
    }
}

fn output_to_ffi(output: RecordingOutput) -> vs_capture_recording_output {
    vs_capture_recording_output {
        output_path: path_to_ffi(output.output_path),
        width: output.width,
        height: output.height,
        frame_rate: output.frame_rate,
        codec: match output.codec {
            RecordingCodec::H264 => VS_CAPTURE_CODEC_H264,
            RecordingCodec::Hevc => VS_CAPTURE_CODEC_HEVC,
        },
        container: match output.container {
            RecordingContainer::Mp4 => VS_CAPTURE_CONTAINER_MP4,
            RecordingContainer::Mov => VS_CAPTURE_CONTAINER_MOV,
        },
    }
}

fn capabilities_to_ffi(capabilities: CaptureCapabilities) -> vs_capture_capabilities {
    vs_capture_capabilities {
        region_recording: capabilities.region_recording,
        window_recording: capabilities.window_recording,
        display_recording: capabilities.display_recording,
        system_audio: capabilities.system_audio,
        microphone_audio: capabilities.microphone_audio,
        cursor_capture: capabilities.cursor_capture,
        mouse_click_visualization: capabilities.mouse_click_visualization,
        direct_to_file_recording: capabilities.direct_to_file_recording,
        h264: capabilities.h264,
        hevc: capabilities.hevc,
        software_h264: capabilities.software_h264,
        screenshot_capture: capabilities.screenshot_capture,
        overlay_window_exceptions: capabilities.overlay_window_exceptions,
    }
}

fn capture_device_kind(kind: u8) -> Result<CaptureDeviceKind, i32> {
    match kind {
        VS_CAPTURE_DEVICE_KIND_DISPLAY => Ok(CaptureDeviceKind::Display),
        VS_CAPTURE_DEVICE_KIND_MICROPHONE => Ok(CaptureDeviceKind::Microphone),
        _ => Err(VS_CAPTURE_STATUS_INVALID_ARGUMENT),
    }
}

fn string_to_ffi_bytes(value: String) -> (*const u8, u32) {
    if value.is_empty() {
        return (std::ptr::null(), 0);
    }
    let bytes = value.into_bytes();
    let len = bytes.len().min(u32::MAX as usize) as u32;
    let ptr = Box::leak(bytes.into_boxed_slice()).as_ptr();
    (ptr, len)
}

fn device_to_ffi(device: CaptureDevice) -> vs_capture_device {
    let (stable_id_utf8, stable_id_len) = string_to_ffi_bytes(device.stable_id);
    let (display_name_utf8, display_name_len) = string_to_ffi_bytes(device.display_name);
    vs_capture_device {
        stable_id_utf8,
        stable_id_len,
        display_name_utf8,
        display_name_len,
        capability_mask: device.capability_mask,
        is_available: device.is_available,
    }
}

fn captured_image_to_ffi(image: CapturedImage) -> vs_capture_captured_image {
    let CapturedImage {
        width,
        height,
        bytes_per_row,
        pixel_format,
        data,
    } = image;
    let data_len = data.len().min(u32::MAX as usize) as u32;
    let data = if data.is_empty() {
        std::ptr::null()
    } else {
        Box::leak(data.into_boxed_slice()).as_ptr()
    };
    vs_capture_captured_image {
        width,
        height,
        bytes_per_row,
        pixel_format,
        data,
        data_len,
    }
}

unsafe fn free_ffi_bytes(ptr: *const u8, len: u32) {
    if ptr.is_null() || len == 0 {
        return;
    }
    let slice = std::ptr::slice_from_raw_parts_mut(ptr as *mut u8, len as usize);
    unsafe {
        drop(Box::from_raw(slice));
    }
}

#[no_mangle]
pub unsafe extern "C" fn vs_capture_screenshot(
    rect_screen: vs_capture_rect,
    user_data: *mut c_void,
    callback: vs_capture_screenshot_callback,
) {
    let Some(callback) = callback else {
        return;
    };
    let user_data = user_data as usize;
    let rect = to_capture_rect(rect_screen);
    thread::spawn(move || {
        let user_data = user_data as *mut c_void;
        let rect = match rect {
            Ok(rect) => rect,
            Err(status) => {
                callback(user_data, status, vs_capture_captured_image::default());
                return;
            }
        };
        match CaptureBackend::new().capture_screenshot(rect) {
            Ok(image) => callback(
                user_data,
                VS_CAPTURE_STATUS_OK,
                captured_image_to_ffi(image),
            ),
            Err(error) => callback(
                user_data,
                capture_status(&error),
                vs_capture_captured_image::default(),
            ),
        }
    });
}

#[no_mangle]
pub unsafe extern "C" fn vs_capture_captured_image_free(image: vs_capture_captured_image) {
    unsafe {
        free_ffi_bytes(image.data, image.data_len);
    }
}

#[no_mangle]
pub unsafe extern "C" fn vs_capture_copy_capabilities(
    out_capabilities: *mut vs_capture_capabilities,
) -> i32 {
    if out_capabilities.is_null() {
        return VS_CAPTURE_STATUS_NULL_POINTER;
    }
    unsafe {
        *out_capabilities = capabilities_to_ffi(CaptureBackend::new().capabilities());
    }
    VS_CAPTURE_STATUS_OK
}

#[no_mangle]
pub unsafe extern "C" fn vs_capture_copy_devices(
    device_kind: u8,
    out_devices: *mut vs_capture_device,
    capacity: u32,
    out_count: *mut u32,
) -> i32 {
    if out_count.is_null() {
        return VS_CAPTURE_STATUS_NULL_POINTER;
    }
    let kind = match capture_device_kind(device_kind) {
        Ok(kind) => kind,
        Err(status) => return status,
    };
    let devices = match CaptureBackend::new().devices(kind) {
        Ok(devices) => devices,
        Err(error) => return capture_status(&error),
    };
    let count = devices.len().min(u32::MAX as usize) as u32;
    unsafe {
        *out_count = count;
    }
    if capacity == 0 {
        return VS_CAPTURE_STATUS_OK;
    }
    if out_devices.is_null() {
        return VS_CAPTURE_STATUS_NULL_POINTER;
    }
    if capacity < count {
        return VS_CAPTURE_STATUS_BUFFER_TOO_SMALL;
    }
    for (index, device) in devices.into_iter().enumerate() {
        unsafe {
            out_devices.add(index).write(device_to_ffi(device));
        }
    }
    VS_CAPTURE_STATUS_OK
}

#[no_mangle]
pub unsafe extern "C" fn vs_capture_devices_free(devices: *mut vs_capture_device, count: u32) {
    if devices.is_null() || count == 0 {
        return;
    }
    for index in 0..count as usize {
        let device = unsafe { devices.add(index).read() };
        unsafe {
            free_ffi_bytes(device.stable_id_utf8, device.stable_id_len);
            free_ffi_bytes(device.display_name_utf8, device.display_name_len);
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn vs_capture_recording_start(
    config: *const vs_capture_recording_config,
    user_data: *mut c_void,
    callback: vs_capture_recording_start_callback,
) {
    let Some(callback) = callback else {
        return;
    };
    let user_data = user_data as usize;
    let config = unsafe { to_capture_config(config) };
    thread::spawn(move || {
        let user_data = user_data as *mut c_void;
        let config = match config {
            Ok(config) => config,
            Err(status) => {
                callback(user_data, status, std::ptr::null_mut());
                return;
            }
        };
        match CaptureBackend::new().start_recording(config) {
            Ok(session) => {
                let handle = Box::into_raw(Box::new(vs_capture_recording_session {
                    inner: Mutex::new(Some(session)),
                }));
                register_handle(&CAPTURE_RECORDING_SESSION_HANDLES, handle.cast());
                callback(user_data, VS_CAPTURE_STATUS_OK, handle);
            }
            Err(error) => {
                callback(user_data, capture_status(&error), std::ptr::null_mut());
            }
        }
    });
}

#[no_mangle]
pub unsafe extern "C" fn vs_capture_recording_stop(
    session: *mut vs_capture_recording_session,
    user_data: *mut c_void,
    callback: vs_capture_recording_stop_callback,
) {
    let Some(callback) = callback else {
        return;
    };
    if let Err(status) = validate_handle(&CAPTURE_RECORDING_SESSION_HANDLES, session.cast()) {
        callback(user_data, status, vs_capture_recording_output::default());
        return;
    }
    let user_data = user_data as usize;
    let session = session as usize;
    thread::spawn(move || {
        let user_data = user_data as *mut c_void;
        let session = session as *mut vs_capture_recording_session;
        let session_ref = unsafe { &*session };
        let active_session = {
            let mut guard = session_ref
                .inner
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            guard.take()
        };
        let Some(active_session) = active_session else {
            callback(
                user_data,
                VS_CAPTURE_STATUS_INVALID_ARGUMENT,
                vs_capture_recording_output::default(),
            );
            return;
        };
        let result = active_session.stop();
        unregister_handle(&CAPTURE_RECORDING_SESSION_HANDLES, session.cast());
        unsafe {
            drop(Box::from_raw(session));
        }
        match result {
            Ok(output) => callback(user_data, VS_CAPTURE_STATUS_OK, output_to_ffi(output)),
            Err(error) => callback(
                user_data,
                capture_status(&error),
                vs_capture_recording_output::default(),
            ),
        }
    });
}

#[no_mangle]
pub unsafe extern "C" fn vs_capture_recording_cancel(session: *mut vs_capture_recording_session) {
    if validate_handle(&CAPTURE_RECORDING_SESSION_HANDLES, session.cast()).is_err() {
        return;
    }
    let session_ref = unsafe { &*session };
    let active_session = {
        let mut guard = session_ref
            .inner
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        guard.take()
    };
    if let Some(active_session) = active_session {
        active_session.cancel();
    }
    unregister_handle(&CAPTURE_RECORDING_SESSION_HANDLES, session.cast());
    unsafe {
        drop(Box::from_raw(session));
    }
}

#[no_mangle]
pub unsafe extern "C" fn vs_capture_recording_output_free(output: vs_capture_recording_output) {
    if output.output_path.path_utf8.is_null() || output.output_path.path_len == 0 {
        return;
    }
    let len = output.output_path.path_len as usize;
    let slice = std::ptr::slice_from_raw_parts_mut(output.output_path.path_utf8 as *mut u8, len);
    unsafe {
        drop(Box::from_raw(slice));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn capture_status_maps_structured_errors() {
        let error = CaptureError::new(CaptureErrorKind::UnsupportedCodec, "bad codec");
        assert_eq!(capture_status(&error), VS_CAPTURE_STATUS_UNSUPPORTED_CODEC);
    }

    #[test]
    fn ffi_config_rejects_unknown_encoder() {
        let path = b"/tmp/vivyshot-test.mp4";
        let config = vs_capture_recording_config {
            selection_rect_screen: vs_capture_rect {
                x: 0.0,
                y: 0.0,
                width: 20.0,
                height: 20.0,
            },
            output_path: vs_capture_path {
                path_utf8: path.as_ptr(),
                path_len: path.len() as u32,
            },
            frame_rate: 30,
            encoder: 255,
            capture_system_audio: false,
            capture_microphone: false,
            show_cursor: true,
            highlight_mouse_clicks: false,
            include_window_ids: std::ptr::null(),
            include_window_id_count: 0,
            exclude_current_process: true,
        };

        let status = unsafe { to_capture_config(&config).unwrap_err() };
        assert_eq!(status, VS_CAPTURE_STATUS_INVALID_ARGUMENT);
    }

    #[test]
    fn ffi_device_kind_rejects_unknown_kind() {
        assert_eq!(
            capture_device_kind(255).unwrap_err(),
            VS_CAPTURE_STATUS_INVALID_ARGUMENT
        );
    }

    #[test]
    fn ffi_capabilities_reports_backend_shape() {
        let mut capabilities = vs_capture_capabilities::default();
        let status = unsafe { vs_capture_copy_capabilities(&mut capabilities) };
        assert_eq!(status, VS_CAPTURE_STATUS_OK);
        assert_eq!(
            capabilities.direct_to_file_recording,
            CaptureBackend::new()
                .capabilities()
                .direct_to_file_recording
        );
    }

    #[test]
    fn ffi_rect_rejects_nonfinite_values() {
        let status = to_capture_rect(vs_capture_rect {
            x: f64::NAN,
            y: 0.0,
            width: 10.0,
            height: 10.0,
        })
        .unwrap_err();
        assert_eq!(status, VS_CAPTURE_STATUS_INVALID_ARGUMENT);
    }
}
