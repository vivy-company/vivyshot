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
      return "Screenshot"
    case .video:
      return "Video"
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
      return "System Audio"
    case .microphone:
      return "Microphone"
    case .webcam:
      return "Webcam Overlay"
    case .mouseClicks:
      return "Mouse Click Highlights"
    case .keystrokes:
      return "Keystroke Highlights"
    case .countdown:
      return "Countdown"
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
      return "Copy"
    case .save:
      return "Save"
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
      return "Standard (H.264)"
    case .hevc:
      return "High (HEVC)"
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
      return "Off"
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
      return "Small"
    case .medium:
      return "Medium"
    case .large:
      return "Large"
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
      return "Rounded Rectangle"
    case .circle:
      return "Circle"
    }
  }
}
