/// Paid capability gate used across settings, recording, export, and store presentation.
enum PaidFeature: CaseIterable {
  case captureTransitions
  case microphoneAudioExport
  case webcamOverlay
  case keystrokeOverlay
  case gifExport
  case hevcExport
  case sixtyFPSExport
  case highQualityExport
  case highBitrateExport
  case statistics
}
