import AppKit
import CoreGraphics
import Foundation


struct TextAnnotationStyle {
  let fontSize: CGFloat
  let color: NSColor

  static let `default` = TextAnnotationStyle(
    fontSize: 16,
    color: .white
  )
}

struct RustAnnotationInfo {
  let index: Int
  let kind: Int
  let bounds: CGRect

  func contains(_ point: CGPoint) -> Bool {
    let x = point.x
    let y = point.y
    return x >= bounds.minX && x <= bounds.maxX && y >= bounds.minY && y <= bounds.maxY
  }
}

struct RustVideoSessionConfig {
  let frameRate: Int
  let captureSystemAudio: Bool
  let captureMicrophone: Bool
  let showWebcam: Bool
  let highlightMouseClicks: Bool
  let highlightKeystrokes: Bool
}

struct RustVideoExportPlan {
  let trimStartMS: Int
  let trimEndMS: Int
  let keyEventCount: Int
  let clickEventCount: Int
  let planMode: UInt8
  let includeAudio: Bool
  let includeWebcam: Bool
  let textOverlayCount: Int
  let overlayItemCount: Int
  let requiresIntermediateForGIF: Bool
  let needsCustomCompositor: Bool
}

struct RustVideoExportDecision {
  let useCustomCompositor: Bool
  let requiresIntermediateForGIF: Bool
  let includeAudio: Bool
  let includeWebcam: Bool
}

struct RustVideoOverlayLabelLayout {
  let width: CGFloat
  let height: CGFloat
  let y: CGFloat
  let fontSize: CGFloat
}

struct RustVideoOverlayClipWindow {
  let startSeconds: Double
  let endSeconds: Double
  let fadeDurationSeconds: Double
}

struct RustVideoExportContext {
  let sourceHasAudio: Bool
  let sourceHasWebcamAsset: Bool
  let audioTrackVisible: Bool
  let webcamTrackVisible: Bool
  let textOverlayCount: Int
}

enum RustVideoPlanMode: UInt8 {
  case passthrough = 0
  case compositeMP4 = 1
}

enum RustVideoExportTarget: UInt8 {
  case mp4 = 0
  case gif = 1
}

enum RustImageEncodeFormat: UInt8 {
  case png = 0
  case jpeg = 1
}

enum RustFFIStatus: Int32 {
  case ok = 0
  case noChange = 1
  case nullPointer = -1
  case invalidArgument = -2
  case rejected = -3
  case bufferTooSmall = -4
  case notFound = -5

  static func isSuccess(_ raw: Int32, allowNoChange: Bool = false) -> Bool {
    if raw == RustFFIStatus.ok.rawValue {
      return true
    }
    if allowNoChange, raw == RustFFIStatus.noChange.rawValue {
      return true
    }
    return false
  }
}

enum RustTrimHandle: UInt8 {
  case unknown = 0
  case start = 1
  case end = 2
}

struct RustGIFExportPlan {
  let startMS: UInt32
  let endMS: UInt32
  let frameRate: Double
  let frameCount: Int
  let maxDimension: Int
  let frameDelayMS: Int
}

struct RustStitchAutoScrollState {
  var directionSign: Int32
  var noMotionTicks: UInt32
  var didFlipDirection: Bool
}

struct RustStitchSessionResult {
  let accepted: Bool
  let rows: Int
  let side: UInt8
  let score: Double
  let directionLocked: Bool
  let expectedRows: Int
  let segmentCount: Int
  let scrollDirectionSign: Int
}


