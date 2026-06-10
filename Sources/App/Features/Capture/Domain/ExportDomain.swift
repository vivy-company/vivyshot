import CoreGraphics
import Foundation

/// Minimum visible duration for text overlays in exported video.
let textMinimumVisibleSeconds: Float = 0.15

/// High-level export summary generated from trim, overlay, and source-media state.
struct ExportPlan {
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

/// Binary decision set for whether the export can pass through or needs compositing.
struct ExportDecision {
  let useCustomCompositor: Bool
  let requiresIntermediateForGIF: Bool
  let includeAudio: Bool
  let includeWebcam: Bool
}

/// Layout metrics for a single rendered overlay label.
struct OverlayLabelLayout {
  let width: CGFloat
  let height: CGFloat
  let y: CGFloat
  let fontSize: CGFloat
}

/// Time window where an overlay is visible, including fade duration.
struct OverlayClipWindow {
  let startSeconds: Double
  let endSeconds: Double
  let fadeDurationSeconds: Double
}

/// Source recording metadata used by the post-recording timeline.
struct RecordingInfo {
  let durationMS: UInt32
  let width: UInt32
  let height: UInt32
  let frameRate: UInt32
  let hasAudio: Bool
  let hasWebcamAsset: Bool
  let hasMicrophoneAudio: Bool
}

/// Rendering context for preview versus final export.
enum RenderTarget: UInt8 {
  case preview = 0
  case export = 1
}

/// Overlay item category used by render plans.
enum RenderItemKind: UInt8 {
  case webcam = 1
  case keystroke = 2
  case mouseClick = 3
}

/// Concrete overlay draw command at a timeline position.
struct RenderItem {
  let kind: RenderItemKind
  let rect: CGRect
  let opacity: CGFloat
  let styleFlags: UInt32
  let text: String
  let assetID: UInt32

  static func styleFlags(primary: UInt32, secondary: UInt32 = 0) -> UInt32 {
    (primary & 0xFF) | ((secondary & 0xFF) << 8)
  }

  var webcamShapeCode: UInt8 {
    primaryStyleCode
  }

  var keystrokeStyleCode: UInt8 {
    primaryStyleCode
  }

  var keystrokeSizeCode: UInt8 {
    secondaryStyleCode
  }

  var mouseClickStyleCode: UInt8 {
    primaryStyleCode
  }

  var mouseClickButtonCode: UInt8 {
    secondaryStyleCode
  }

  private var primaryStyleCode: UInt8 {
    UInt8(styleFlags & 0xFF)
  }

  private var secondaryStyleCode: UInt8 {
    UInt8((styleFlags >> 8) & 0xFF)
  }
}

/// Ordered set of overlay items to render for a preview or export frame.
struct RenderPlan {
  let items: [RenderItem]
}

/// User-visible source and track state used to decide the export path.
struct ExportContext {
  let sourceHasAudio: Bool
  let sourceHasWebcamAsset: Bool
  let audioTrackVisible: Bool
  let webcamTrackVisible: Bool
  let textOverlayCount: Int
  let clickOverlaysVisible: Bool
}

/// Geometry needed to render the source video into the requested output canvas.
struct CompositionPlan {
  let renderSize: CGSize
  let transform: CGAffineTransform
}

/// Container format for saved recordings.
enum ExportContainer: UInt8 {
  case mp4 = 0
  case mov = 1
}

/// Export pipeline path selected by the planner.
enum PlanMode: UInt8 {
  case passthrough = 0
  case compositeMP4 = 1
}

/// Requested final export type.
enum ExportTarget: UInt8 {
  case mp4 = 0
  case gif = 1
}

/// User decision target for a post-recording save action.
enum PostRecordingExportTarget {
  case video
  case gif

  var paidFeature: PaidFeature? {
    switch self {
    case .video:
      return nil
    case .gif:
      return .gifExport
    }
  }
}

/// Export options that affect codec, frame rate, quality, scale, and bitrate for video output.
struct PostRecordingExportOptions: Equatable {
  var codec: PostRecordingExportCodec
  var frameRate: PostRecordingExportFrameRate
  var quality: PostRecordingExportQuality
  var scale: PostRecordingExportScale
  var bitrate: PostRecordingExportBitratePreset
}

enum PostRecordingExportCodec: String, CaseIterable, Identifiable {
  case h264
  case hevc

  var id: String { rawValue }

  var paidFeature: PaidFeature? {
    switch self {
    case .h264:
      return nil
    case .hevc:
      return .hevcExport
    }
  }
}

enum PostRecordingExportFrameRate: Int, CaseIterable, Identifiable {
  case fps30 = 30
  case fps60 = 60

  var id: Int { rawValue }

  var paidFeature: PaidFeature? {
    switch self {
    case .fps30:
      return nil
    case .fps60:
      return .sixtyFPSExport
    }
  }
}

enum PostRecordingExportQuality: String, CaseIterable, Identifiable {
  case standard
  case high

  var id: String { rawValue }

  var paidFeature: PaidFeature? {
    switch self {
    case .standard:
      return nil
    case .high:
      return .highQualityExport
    }
  }
}

enum PostRecordingExportScale: String, CaseIterable, Identifiable {
  case full
  case percent75
  case percent50

  var id: String { rawValue }

  var factor: CGFloat {
    switch self {
    case .full:
      return 1.0
    case .percent75:
      return 0.75
    case .percent50:
      return 0.5
    }
  }
}

enum PostRecordingExportBitratePreset: String, CaseIterable, Identifiable {
  case standard
  case high
  case veryHigh

  var id: String { rawValue }

  var paidFeature: PaidFeature? {
    switch self {
    case .standard:
      return nil
    case .high, .veryHigh:
      return .highBitrateExport
    }
  }
}

/// Trim handle being manipulated in the review timeline.
enum TrimHandle: UInt8 {
  case unknown = 0
  case start = 1
  case end = 2
}

/// Frame schedule and bounds for GIF export.
struct GIFPlan {
  let startMS: UInt32
  let endMS: UInt32
  let frameRate: Double
  let frameCount: Int
  let maxDimension: Int
  let frameDelayMS: Int
}
