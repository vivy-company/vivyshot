import Foundation
import CoreGraphics

/// Capture target chosen before the region-selection flow begins.
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

/// Product mode for the selected capture area.
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

/// Optional controls that can appear in the recording toolbar.
enum RecordingTool: Int, CaseIterable, Identifiable {
  case microphone = 1
  case webcam = 2
  case systemAudio = 0
  case mouseClicks = 3
  case keystrokes = 4
  case countdown = 5

  var id: Int { rawValue }

  var isInputSource: Bool {
    switch self {
    case .microphone, .webcam:
      return true
    case .systemAudio, .mouseClicks, .keystrokes, .countdown:
      return false
    }
  }

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

/// Runtime controls for an active recording session. This is intentionally separate from
/// `AppSettings`, which configures the next recording.
struct RecordingLiveControlState: Equatable {
  var recordSystemAudio: Bool
  var recordMicrophone: Bool
  var showWebcam: Bool
  var highlightMouseClicks: Bool
  var highlightKeystrokes: Bool
  var disabledTools: Set<RecordingTool> = []

  func isEnabled(_ tool: RecordingTool) -> Bool {
    switch tool {
    case .systemAudio:
      return recordSystemAudio
    case .microphone:
      return recordMicrophone
    case .webcam:
      return showWebcam
    case .mouseClicks:
      return highlightMouseClicks
    case .keystrokes:
      return highlightKeystrokes
    case .countdown:
      return false
    }
  }

}

/// A selectable recording input source. Empty IDs mean the current system default device.
struct RecordingSourceOption: Identifiable, Hashable {
  let id: String
  let name: String

  static let systemDefault = RecordingSourceOption(
    id: "",
    name: String(localized: "System Default", bundle: AppLocalizer.shared.bundle)
  )
}

/// Default action for screenshot captures after the selection is confirmed.
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

/// Encoder used by the live recording pipeline.
enum RecordingEncoder: Int, CaseIterable, Identifiable {
  case standardH264 = 0
  case smallerFileHEVC = 1
  case cpuH264 = 2

  var id: Int { rawValue }

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

/// Capture frame-rate preset stored in settings and applied to ScreenCaptureKit.
enum RecordingFrameRate: Int, CaseIterable, Identifiable {
  case fps30 = 30
  case fps60 = 60
  case fps120 = 120

  var id: Int { rawValue }

  var title: String {
    "\(rawValue) fps"
  }
}

/// Countdown delay shown before recording begins.
enum RecordingCountdown: Int, CaseIterable, Identifiable {
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

/// Mouse click visualization used while recording or rendered by VivyShot after recording.
enum MouseClickHighlightStyle: Int, CaseIterable, Identifiable {
  case system = 1
  case ripple = 2
  case pulse = 3
  case spotlight = 4

  var id: Int { rawValue }

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

/// Relative size for the draggable webcam overlay.
enum WebcamOverlaySize: Int, CaseIterable, Identifiable {
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
      return Self.smallWidthFraction
    case .medium:
      return Self.mediumWidthFraction
    case .large:
      return Self.largeWidthFraction
    }
  }

  /// Normalized width against the selected recording area.
  private static let smallWidthFraction: CGFloat = 0.18
  /// Default normalized width; large enough for face camera detail without covering the recording.
  private static let mediumWidthFraction: CGFloat = 0.24
  /// Largest normalized width exposed in settings.
  private static let largeWidthFraction: CGFloat = 0.30
}

/// Aspect-ratio lock for webcam overlay resizing.
enum WebcamAspectRatio: Int, CaseIterable, Identifiable {
  case square = 0
  case fourThree = 1
  case sixteenNine = 2

  var id: Int { rawValue }

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

  var widthToHeight: CGFloat {
    switch self {
    case .square:
      return Self.squareRatio
    case .fourThree:
      return Self.fourThreeRatio
    case .sixteenNine:
      return Self.sixteenNineRatio
    }
  }

  func constrainedFrame(_ frame: CGRect, in container: CGRect, minimumSize: CGSize) -> CGRect {
    guard !container.isNull, !container.isEmpty, widthToHeight > 0 else {
      return frame.standardized
    }

    let source = frame.standardized
    let minWidth = min(max(1, minimumSize.width), container.width)
    let minHeight = min(max(1, minimumSize.height), container.height)
    var width = max(minWidth, min(source.width, container.width))
    var height = width / widthToHeight

    if height < minHeight {
      height = minHeight
      width = height * widthToHeight
    }

    if height > container.height {
      height = container.height
      width = height * widthToHeight
    }

    if width > container.width {
      width = container.width
      height = width / widthToHeight
    }

    let x = min(max(container.minX, source.midX - width * 0.5), container.maxX - width)
    let y = min(max(container.minY, source.midY - height * 0.5), container.maxY - height)
    return CGRect(x: x, y: y, width: width, height: height).integral
  }

  /// Square camera crop used by circle overlays.
  private static let squareRatio: CGFloat = 1
  /// Classic webcam aspect ratio.
  private static let fourThreeRatio: CGFloat = 4.0 / 3.0
  /// Widescreen webcam aspect ratio.
  private static let sixteenNineRatio: CGFloat = 16.0 / 9.0
}

/// Visual mask used by the webcam overlay.
enum WebcamShape: Int, CaseIterable, Identifiable {
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

/// Visual treatment for rendered keystroke overlays.
enum KeystrokeStyle: Int, CaseIterable, Identifiable {
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

/// Relative size for keystroke overlay placement.
enum KeystrokeSize: Int, CaseIterable, Identifiable {
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
      return Self.smallNormalizedSize
    case .medium:
      return Self.mediumNormalizedSize
    case .large:
      return Self.largeNormalizedSize
    }
  }

  /// Compact normalized frame for short hotkey labels.
  private static let smallNormalizedSize = CGSize(width: 0.32, height: 0.10)
  /// Default normalized frame for readable keystroke labels.
  private static let mediumNormalizedSize = CGSize(width: 0.40, height: 0.12)
  /// Large normalized frame for presentation-style recordings.
  private static let largeNormalizedSize = CGSize(width: 0.48, height: 0.14)
}
