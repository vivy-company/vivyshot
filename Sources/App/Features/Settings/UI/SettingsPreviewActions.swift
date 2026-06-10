import Foundation

@MainActor
struct SettingsPreviewActions {
  let previewCaptureTransition: () -> Void
  let showRecordingOverlayPreview: (
    RecordingOverlaySettingsPreviewKind,
    AppSettings,
    @escaping (RecordingOverlaySettingsPreviewKind) -> Void
  ) -> Void
  let closeRecordingOverlayPreview: (RecordingOverlaySettingsPreviewKind) -> Void
  let closeAllRecordingOverlayPreviews: () -> Void
}
