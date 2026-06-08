import CoreGraphics

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
}

/// Concrete overlay draw command at a timeline position.
struct RenderItem {
  let kind: RenderItemKind
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
