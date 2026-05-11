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

struct RustVideoProjectRecordingInfo {
  let durationMS: UInt32
  let width: UInt32
  let height: UInt32
  let frameRate: UInt32
  let hasAudio: Bool
  let hasWebcamAsset: Bool
  let hasMicrophoneAudio: Bool
}

enum RustVideoRenderTarget: UInt8 {
  case preview = 0
  case export = 1
}

enum RustVideoRenderItemKind: UInt8 {
  case webcam = 1
  case keystroke = 2
}

struct RustVideoRenderItem {
  let kind: RustVideoRenderItemKind
  let rect: CGRect
  let opacity: CGFloat
  let styleFlags: UInt32
  let text: String
  let assetID: UInt32

  var webcamShapeCode: UInt8 {
    UInt8(styleFlags & 0xFF)
  }

  var keystrokeStyleCode: UInt8 {
    UInt8(styleFlags & 0xFF)
  }

  var keystrokeSizeCode: UInt8 {
    UInt8((styleFlags >> 8) & 0xFF)
  }
}

struct RustVideoRenderPlan {
  let items: [RustVideoRenderItem]
}

struct RustVideoProjectProRequirement {
  let reasonsMask: UInt32
}

struct RustVideoExportContext {
  let sourceHasAudio: Bool
  let sourceHasWebcamAsset: Bool
  let audioTrackVisible: Bool
  let webcamTrackVisible: Bool
  let textOverlayCount: Int
}

struct RustVideoPostRecordingCompositionPlan {
  let renderSize: CGSize
  let transform: CGAffineTransform
}

enum RustVideoExportContainer: UInt8 {
  case mp4 = 0
  case mov = 1
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

enum RustStatsEventType: UInt8, Sendable {
  case screenshotCaptured = 0
  case screenshotSessionCompleted = 1
  case recordingCompleted = 2
}

struct RustStatsDayKey: Equatable, Sendable {
  let year: Int
  let month: Int
  let day: Int

  var yyyyMMdd: String {
    String(format: "%04d-%02d-%02d", year, month, day)
  }
}

struct RustStatsEvent: Sendable {
  let eventKey: String
  let eventType: RustStatsEventType
  let occurredAtMS: Int64
  let timezoneOffsetMinutes: Int32
  let bytesProduced: Int64
  let durationMS: Int64?
  let screenshotCompletionDurationMS: Int64?
  let captureID: String
}

struct RustStatsSummary: Sendable {
  let totalScreenshotsCaptured: Int64
  let totalRecordingsCompleted: Int64
  let totalRecordedDurationMS: Int64
  let totalScreenshotCompletionDurationMS: Int64
  let completedScreenshotSessionCount: Int64
  let averageScreenshotEditorCompletionDurationMS: Int64
  let totalCaptureBytesProduced: Int64
  let currentCaptureStreakDays: Int
  let bestCaptureStreakDays: Int
  let activeCaptureDays: Int
  let firstCaptureDay: RustStatsDayKey?
  let lastCaptureDay: RustStatsDayKey?
  let mostActiveDay: RustStatsDayKey?
  let mostActiveDayScore: Int64
}

struct RustStatsDailyBucket: Sendable {
  let day: RustStatsDayKey
  let screenshotCount: Int
  let recordingCount: Int
  let recordedDurationMS: Int64
  let captureBytesProduced: Int64
  let firstCaptureAtMS: Int64?
  let lastCaptureAtMS: Int64?
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
