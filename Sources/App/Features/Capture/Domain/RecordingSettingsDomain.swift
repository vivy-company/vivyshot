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

/// User-facing capture color profile applied as one coordinated capture pipeline choice.
enum RecordingColorProfile: Int, CaseIterable, Identifiable {
  case automatic = 0
  case sdr = 1
  case wideColor = 2
  case hdrExperimental = 3

  var id: Int { rawValue }

  var requiresHEVC: Bool {
    switch self {
    case .automatic, .sdr:
      return false
    case .wideColor, .hdrExperimental:
      return true
    }
  }
}

/// Output resolution applied to the live ScreenCaptureKit stream before encoding.
enum RecordingCaptureResolution: Int, CaseIterable, Identifiable {
  case native = 100
  case percent75 = 75
  case percent50 = 50

  var id: Int { rawValue }

  var scale: Double {
    Double(rawValue) / 100.0
  }
}

/// ScreenCaptureKit frame queue preset. Higher values can smooth capture at the cost of memory and latency.
enum RecordingCaptureBuffering: Int, CaseIterable, Identifiable {
  case lowLatency = 3
  case balanced = 5
  case smoother = 8

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
