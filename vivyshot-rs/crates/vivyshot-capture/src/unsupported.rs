use crate::{
    CaptureCapabilities, CaptureDevice, CaptureDeviceKind, CaptureError, CaptureErrorKind,
    CaptureRect, CapturedImage, RecordingConfig, RecordingOutput, WebcamDevice,
    WebcamRecordingConfig, WebcamRecordingOutput,
};

pub struct Backend;

pub struct RecordingSession;

pub struct WebcamRecordingSession;

impl Backend {
    pub fn new() -> Self {
        Self
    }

    pub fn capabilities(&self) -> CaptureCapabilities {
        CaptureCapabilities::unsupported()
    }

    pub fn start_recording(
        &self,
        _config: RecordingConfig,
    ) -> Result<RecordingSession, CaptureError> {
        Err(CaptureError::new(
            CaptureErrorKind::UnsupportedPlatform,
            "capture backend is not available on this platform",
        ))
    }

    pub fn devices(&self, _kind: CaptureDeviceKind) -> Result<Vec<CaptureDevice>, CaptureError> {
        Ok(Vec::new())
    }

    pub fn capture_screenshot(
        &self,
        _rect_screen: CaptureRect,
    ) -> Result<CapturedImage, CaptureError> {
        Err(CaptureError::new(
            CaptureErrorKind::UnsupportedPlatform,
            "capture backend is not available on this platform",
        ))
    }

    pub fn webcam_devices(&self) -> Result<Vec<WebcamDevice>, CaptureError> {
        Ok(Vec::new())
    }

    pub fn start_webcam_recording(
        &self,
        _config: WebcamRecordingConfig,
    ) -> Result<WebcamRecordingSession, CaptureError> {
        Err(CaptureError::new(
            CaptureErrorKind::UnsupportedPlatform,
            "webcam recording backend is not available on this platform",
        ))
    }
}

impl Default for Backend {
    fn default() -> Self {
        Self::new()
    }
}

impl RecordingSession {
    pub fn stop(self) -> Result<RecordingOutput, CaptureError> {
        Err(CaptureError::new(
            CaptureErrorKind::UnsupportedPlatform,
            "capture backend is not available on this platform",
        ))
    }

    pub fn cancel(self) {}
}

impl WebcamRecordingSession {
    pub fn preview_session_ptr(&self) -> *mut std::ffi::c_void {
        std::ptr::null_mut()
    }

    pub fn start(&self) -> Result<(), CaptureError> {
        Err(CaptureError::new(
            CaptureErrorKind::UnsupportedPlatform,
            "webcam recording backend is not available on this platform",
        ))
    }

    pub fn stop(self) -> Result<WebcamRecordingOutput, CaptureError> {
        Err(CaptureError::new(
            CaptureErrorKind::UnsupportedPlatform,
            "webcam recording backend is not available on this platform",
        ))
    }

    pub fn cancel(self) {}
}
