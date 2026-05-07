import Foundation
import CoreGraphics

enum CaptureMode: Int, CaseIterable, Identifiable {
  case screen = 0
  case window = 1
  case selection = 2

  var id: Int { rawValue }

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

enum CaptureContentType: Int, CaseIterable, Identifiable {
  case screenshot = 0
  case video = 1

  var id: Int { rawValue }

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

enum VideoToolbarTool: Int, CaseIterable, Identifiable {
  case systemAudio = 0
  case microphone = 1
  case webcam = 2
  case mouseClicks = 3
  case keystrokes = 4
  case countdown = 5

  var id: Int { rawValue }

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

enum ScreenshotMainAction: Int, CaseIterable, Identifiable {
  case copy = 0
  case save = 1

  var id: Int { rawValue }

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

enum VideoCodecOption: Int, CaseIterable, Identifiable {
  case h264 = 0
  case hevc = 1

  var id: Int { rawValue }

  var title: String {
    switch self {
    case .h264:
      return String(localized: "Standard (H.264)", bundle: AppLocalizer.shared.bundle)
    case .hevc:
      return String(localized: "High (HEVC)", bundle: AppLocalizer.shared.bundle)
    }
  }
}

enum VideoFrameRateOption: Int, CaseIterable, Identifiable {
  case fps30 = 30
  case fps60 = 60

  var id: Int { rawValue }

  var title: String {
    "\(rawValue) fps"
  }
}

enum VideoCountdownOption: Int, CaseIterable, Identifiable {
  case off = 0
  case three = 3
  case five = 5

  var id: Int { rawValue }

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

enum VideoWebcamOverlaySizeOption: Int, CaseIterable, Identifiable {
  case small = 0
  case medium = 1
  case large = 2

  var id: Int { rawValue }

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

  var widthFraction: CGFloat {
    switch self {
    case .small:
      return 0.18
    case .medium:
      return 0.24
    case .large:
      return 0.30
    }
  }
}

enum VideoWebcamOverlayShapeOption: Int, CaseIterable, Identifiable {
  case roundedRect = 0
  case circle = 1

  var id: Int { rawValue }

  var title: String {
    switch self {
    case .roundedRect:
      return String(localized: "Rounded Rectangle", bundle: AppLocalizer.shared.bundle)
    case .circle:
      return String(localized: "Circle", bundle: AppLocalizer.shared.bundle)
    }
  }
}

enum VideoKeystrokeOverlayStyleOption: Int, CaseIterable, Identifiable {
  case compact = 0
  case glass = 1

  var id: Int { rawValue }

  var title: String {
    switch self {
    case .compact:
      return String(localized: "Compact", bundle: AppLocalizer.shared.bundle)
    case .glass:
      return String(localized: "Glass", bundle: AppLocalizer.shared.bundle)
    }
  }
}

enum VideoKeystrokeOverlaySizeOption: Int, CaseIterable, Identifiable {
  case small = 0
  case medium = 1
  case large = 2

  var id: Int { rawValue }

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

  var normalizedSize: CGSize {
    switch self {
    case .small:
      return CGSize(width: 0.32, height: 0.10)
    case .medium:
      return CGSize(width: 0.40, height: 0.12)
    case .large:
      return CGSize(width: 0.48, height: 0.14)
    }
  }
}
