/// Encoder used by the live recording pipeline.
enum RecordingEncoder: Int, CaseIterable, Identifiable {
  case standardH264 = 0
  case smallerFileHEVC = 1
  case cpuH264 = 2

  var id: Int { rawValue }
}

/// Capture frame-rate preset stored in settings and applied to ScreenCaptureKit.
enum RecordingFrameRate: Int, CaseIterable, Identifiable {
  case fps30 = 30
  case fps60 = 60
  case fps120 = 120

  var id: Int { rawValue }
}

/// Countdown delay shown before recording begins.
enum RecordingCountdown: Int, CaseIterable, Identifiable {
  case off = 0
  case three = 3
  case five = 5

  var id: Int { rawValue }
}

/// Mouse click visualization used while recording or rendered by VivyShot after recording.
enum MouseClickHighlightStyle: Int, CaseIterable, Identifiable {
  case system = 1
  case ripple = 2
  case pulse = 3
  case spotlight = 4

  var id: Int { rawValue }
}
