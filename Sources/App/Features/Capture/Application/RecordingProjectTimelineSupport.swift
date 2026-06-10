import CoreGraphics
import Foundation

struct KeyEvent {
  let timestampMS: UInt32
  let token: String
}

struct ClickEvent {
  let timestampMS: UInt32
  let normalizedX: CGFloat
  let normalizedY: CGFloat
  let button: UInt32
}

struct OverlayPlacement {
  let timestampMS: UInt32
  let frame: CGRect
}

struct WebcamOverlayState {
  var enabled = false
  var shape = WebcamShape.roundedRect.rawValue
  var aspectRatio = WebcamAspectRatio.square.rawValue
  var assetID: UInt32 = 1
  var placements: [OverlayPlacement] = []

  func frame(at timeMS: UInt32) -> CGRect? {
    placements.last { $0.timestampMS <= timeMS }?.frame ?? placements.first?.frame
  }
}

struct KeystrokeOverlayState {
  var enabled = false
  var style = KeystrokeStyle.compact.rawValue
  var size = KeystrokeSize.medium.rawValue
  var placements: [OverlayPlacement] = []

  func frame(at timeMS: UInt32) -> CGRect? {
    placements.last { $0.timestampMS <= timeMS }?.frame ?? placements.first?.frame
  }
}

extension MouseClickHighlightStyle {
  var clickVisibleWindowMS: UInt32 {
    switch self {
    case .system:
      return 420
    case .ripple:
      return 650
    case .pulse:
      return 280
    case .spotlight:
      return 900
    }
  }

  func clickDiameter(base: CGFloat, progress: CGFloat) -> CGFloat {
    let clampedBase = max(1, base)
    switch self {
    case .system:
      return clampedBase * (0.040 + CGFloat(sin(Double(progress) * Double.pi)) * 0.018)
    case .ripple:
      return clampedBase * (0.030 + progress * 0.110)
    case .pulse:
      return clampedBase * (0.045 + CGFloat(sin(Double(progress) * Double.pi)) * 0.035)
    case .spotlight:
      return clampedBase * (0.135 + progress * 0.025)
    }
  }

  func clickOpacity(progress: CGFloat) -> CGFloat {
    let fade = max(0, 1 - progress)
    switch self {
    case .system:
      return min(1, 0.92 * pow(fade, 0.50))
    case .pulse:
      return min(1, 0.90 * pow(fade, 0.65))
    case .spotlight:
      return min(0.85, 0.70 * pow(fade, 0.45))
    case .ripple:
      return min(1, fade * 0.95)
    }
  }
}

extension UInt32 {
  func saturatingAdd(_ value: UInt32) -> UInt32 {
    let (result, overflow) = addingReportingOverflow(value)
    return overflow ? UInt32.max : result
  }

  func saturatingSubtract(_ value: UInt32) -> UInt32 {
    value > self ? 0 : self - value
  }
}

extension CGRect {
  var isFiniteAndNonEmpty: Bool {
    minX.isFinite && minY.isFinite && width.isFinite && height.isFinite && width > 0 && height > 0
  }
}
