use std::ffi::{c_char, c_void};

pub const SOFTWARE_WRITER_STATUS_OK: i32 = 0;
pub const SOFTWARE_WRITER_STATUS_INVALID_ARGUMENT: i32 = -1;
pub const SOFTWARE_WRITER_STATUS_NO_FRAMES: i32 = -7;
pub const SOFTWARE_WRITER_STATUS_FINISH_FAILED: i32 = -8;
pub const SOFTWARE_WRITER_STATUS_CANCELLED: i32 = -9;
pub const SOFTWARE_WRITER_STATUS_INCOMPLETE: i32 = -10;

pub const WEBCAM_STATUS_OK: i32 = 0;
pub const WEBCAM_STATUS_INVALID_ARGUMENT: i32 = -1;
pub const WEBCAM_STATUS_NO_DEVICE: i32 = -2;
pub const WEBCAM_STATUS_INPUT_UNAVAILABLE: i32 = -3;
pub const WEBCAM_STATUS_OUTPUT_UNAVAILABLE: i32 = -4;
pub const WEBCAM_STATUS_START_FAILED: i32 = -5;
pub const WEBCAM_STATUS_STOP_FAILED: i32 = -6;
pub const WEBCAM_STATUS_OUTPUT_FILE_UNAVAILABLE: i32 = -7;
pub const WEBCAM_STATUS_CANCELLED: i32 = -8;

#[repr(C)]
pub struct WebcamDevice {
    pub stable_id: *const c_char,
    pub display_name: *const c_char,
}

extern "C" {
    pub fn sck_software_h264_writer_create(
        path_utf8: *const u8,
        path_len: u32,
        frame_rate: u32,
        include_system_audio: bool,
        include_microphone_audio: bool,
    ) -> *mut c_void;
    pub fn sck_software_h264_writer_configure_video_size(
        writer: *mut c_void,
        width: u32,
        height: u32,
    ) -> i32;
    pub fn sck_software_h264_writer_prepare(writer: *mut c_void) -> i32;
    pub fn sck_software_h264_writer_append(
        writer: *mut c_void,
        sample_buffer: *mut c_void,
        output_type: i32,
    );
    pub fn sck_software_h264_writer_finish(writer: *mut c_void) -> i32;
    pub fn sck_software_h264_writer_cancel(writer: *mut c_void);
    pub fn sck_software_h264_writer_destroy(writer: *mut c_void);

    pub fn sck_webcam_recorder_create(
        output_path_utf8: *const u8,
        output_path_len: u32,
        device_id_utf8: *const u8,
        device_id_len: u32,
    ) -> *mut c_void;
    pub fn sck_webcam_recorder_preview_session(recorder: *mut c_void) -> *mut c_void;
    pub fn sck_webcam_recorder_start(recorder: *mut c_void) -> i32;
    pub fn sck_webcam_recorder_stop(recorder: *mut c_void) -> i32;
    pub fn sck_webcam_recorder_cancel(recorder: *mut c_void);
    pub fn sck_webcam_recorder_start_uptime_seconds(recorder: *mut c_void) -> f64;
    pub fn sck_webcam_recorder_destroy(recorder: *mut c_void);
    pub fn sck_webcam_copy_devices(devices: *mut *mut WebcamDevice, count: *mut u32) -> i32;
    pub fn sck_webcam_devices_free(devices: *mut WebcamDevice, count: u32);
}
