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
