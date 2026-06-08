use crate::{
    CaptureCapabilities, CaptureDevice, CaptureDeviceKind, CaptureError, CaptureErrorKind,
    CaptureRect, CapturedImage, RecordingConfig, RecordingOutput,
};

pub struct Backend;

pub struct RecordingSession;

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
