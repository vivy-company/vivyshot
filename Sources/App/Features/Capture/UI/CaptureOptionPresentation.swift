import Foundation

extension CaptureMode {
  var symbolName: String {
    switch self {
    case .screen:
      return "rectangle"
    case .window:
      return "macwindow"
    case .selection:
      return "rectangle.dashed"
    }
  }
}

extension CaptureContentType {
  var title: String {
    switch self {
    case .screenshot:
      return String(localized: "Screenshot", bundle: AppLocalizer.shared.bundle)
    case .video:
      return String(localized: "Video", bundle: AppLocalizer.shared.bundle)
    }
  }

  var symbolName: String {
    switch self {
    case .screenshot:
      return "camera"
    case .video:
      return "record.circle"
    }
  }
}

extension RecordingTool {
  var title: String {
    switch self {
    case .systemAudio:
      return String(localized: "System Audio", bundle: AppLocalizer.shared.bundle)
    case .microphone:
      return String(localized: "Microphone", bundle: AppLocalizer.shared.bundle)
    case .webcam:
      return String(localized: "Webcam Overlay", bundle: AppLocalizer.shared.bundle)
    case .mouseClicks:
      return String(localized: "Mouse Click Highlights", bundle: AppLocalizer.shared.bundle)
    case .keystrokes:
      return String(localized: "Keystroke Highlights", bundle: AppLocalizer.shared.bundle)
    case .countdown:
      return String(localized: "Countdown", bundle: AppLocalizer.shared.bundle)
    }
  }

  var symbolName: String {
    switch self {
    case .systemAudio:
      return "speaker.wave.2.fill"
    case .microphone:
      return "mic.fill"
    case .webcam:
      return "video.fill"
    case .mouseClicks:
      return "cursorarrow.rays"
    case .keystrokes:
      return "keyboard"
    case .countdown:
      return "timer"
    }
  }
}

extension RecordingSourceOption {
  static let systemDefault = RecordingSourceOption(
    id: "",
    name: String(localized: "System Default", bundle: AppLocalizer.shared.bundle)
  )
}

extension ScreenshotMainAction {
  var title: String {
    switch self {
    case .copy:
      return String(localized: "Copy", bundle: AppLocalizer.shared.bundle)
    case .save:
      return String(localized: "Save", bundle: AppLocalizer.shared.bundle)
    }
  }

  var symbolName: String {
    switch self {
    case .copy:
      return "doc.on.doc"
    case .save:
      return "square.and.arrow.down"
    }
  }
}

extension ScreenshotWindowCaptureStyle {
  var title: String {
    switch self {
    case .nativeWithShadow:
      return String(localized: "Native Window with Shadow", bundle: AppLocalizer.shared.bundle)
    case .nativeWithoutShadow:
      return String(localized: "Native Window", bundle: AppLocalizer.shared.bundle)
    case .visibleAreaRectangle:
      return String(localized: "Visible Area Rectangle", bundle: AppLocalizer.shared.bundle)
    }
  }
}

extension RecordingEncoder {
  var title: String {
    switch self {
    case .standardH264:
      return String(localized: "Standard (H.264)", bundle: AppLocalizer.shared.bundle)
    case .smallerFileHEVC:
      return String(localized: "Smaller File (HEVC)", bundle: AppLocalizer.shared.bundle)
    case .cpuH264:
      return String(localized: "CPU Recording (H.264)", bundle: AppLocalizer.shared.bundle)
    }
  }
}

extension RecordingFrameRate {
  var title: String {
    "\(rawValue) fps"
  }
}

extension RecordingCountdown {
  var title: String {
    switch self {
    case .off:
      return String(localized: "Off", bundle: AppLocalizer.shared.bundle)
    case .three:
      return "3s"
    case .five:
      return "5s"
    }
  }
}

extension RecordingColorProfile {
  var title: String {
    switch self {
    case .automatic:
      return String(localized: "Automatic (Recommended)", bundle: AppLocalizer.shared.bundle)
    case .sdr:
      return "SDR"
    case .wideColor:
      return String(localized: "Wide Color", bundle: AppLocalizer.shared.bundle)
    case .hdrExperimental:
      return String(localized: "HDR (Experimental)", bundle: AppLocalizer.shared.bundle)
    }
  }
}

extension RecordingCaptureResolution {
  var title: String {
    switch self {
    case .native:
      return String(localized: "Native", bundle: AppLocalizer.shared.bundle)
    case .percent75:
      return "75%"
    case .percent50:
      return "50%"
    }
  }
}

extension RecordingCaptureBuffering {
  var title: String {
    switch self {
    case .lowLatency:
      return String(localized: "Low Latency", bundle: AppLocalizer.shared.bundle)
    case .balanced:
      return String(localized: "Balanced", bundle: AppLocalizer.shared.bundle)
    case .smoother:
      return String(localized: "Smoother", bundle: AppLocalizer.shared.bundle)
    }
  }
}

extension RecordingWindowCaptureStyle {
  var title: String {
    switch self {
    case .selectedWindowOnly:
      return String(localized: "Selected Window Only", bundle: AppLocalizer.shared.bundle)
    case .visibleAreaRectangle:
      return String(localized: "Visible Area Rectangle", bundle: AppLocalizer.shared.bundle)
    }
  }
}

extension MouseClickHighlightStyle {
  var title: String {
    switch self {
    case .system:
      return String(localized: "System", bundle: AppLocalizer.shared.bundle)
    case .ripple:
      return String(localized: "Ripple", bundle: AppLocalizer.shared.bundle)
    case .pulse:
      return String(localized: "Pulse", bundle: AppLocalizer.shared.bundle)
    case .spotlight:
      return String(localized: "Spotlight", bundle: AppLocalizer.shared.bundle)
    }
  }
}

extension WebcamAspectRatio {
  var title: String {
    switch self {
    case .square:
      return "1:1"
    case .fourThree:
      return "4:3"
    case .sixteenNine:
      return "16:9"
    }
  }
}

extension WebcamShape {
  var title: String {
    switch self {
    case .roundedRect:
      return String(localized: "Rounded Rectangle", bundle: AppLocalizer.shared.bundle)
    case .circle:
      return String(localized: "Circle", bundle: AppLocalizer.shared.bundle)
    }
  }
}

extension KeystrokeStyle {
  var title: String {
    switch self {
    case .compact:
      return String(localized: "Compact", bundle: AppLocalizer.shared.bundle)
    case .glass:
      return String(localized: "Glass", bundle: AppLocalizer.shared.bundle)
    }
  }
}

extension KeystrokeSize {
  var title: String {
    switch self {
    case .small:
      return String(localized: "Small", bundle: AppLocalizer.shared.bundle)
    case .medium:
      return String(localized: "Medium", bundle: AppLocalizer.shared.bundle)
    case .large:
      return String(localized: "Large", bundle: AppLocalizer.shared.bundle)
    }
  }
}
