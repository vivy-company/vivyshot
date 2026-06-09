import AVFoundation
import CoreGraphics
import UniformTypeIdentifiers

/// Plans post-recording exports: file containers, AVFoundation presets, trim ranges, GIF frames, and composition needs.
enum ExportPlanner {
  /// Minimum bitrate used for file-size estimates so tiny captures do not report unrealistically small outputs.
  private static let minimumEstimatedBitrate = 2_000_000.0
  /// High-quality exports use more bits than the standard preset while still staying below the explicit bitrate tiers.
  private static let highQualityBitrateMultiplier = 1.2
  /// 60 fps exports need more bits than 30 fps exports to avoid a visible quality drop.
  private static let sixtyFPSBitrateMultiplier = 1.35
  /// HEVC is estimated lower than H.264 for similar perceptual quality.
  private static let hevcBitrateMultiplier = 0.72
  /// GIF previews default to a low frame rate because GIF files grow quickly.
  private static let defaultGIFFPS = 12.0
  /// GIF export intentionally caps frame rate to keep files practical and encoding responsive.
  private static let maximumGIFFPS = 30.0
  /// Smallest GIF canvas dimension we allow after clamping.
  private static let minimumGIFDimension = 64
  /// Largest GIF canvas dimension we allow after clamping.
  private static let maximumGIFDimension = 2_048
  private static let millisecondsPerSecond = 1000.0

  static func preferredSaveContentType(codec: PostRecordingExportCodec) -> UTType {
    preferredSaveContainer(codec: codec) == .mov ? .quickTimeMovie : .mpeg4Movie
  }

  static func allowedSaveContentTypes(codec: PostRecordingExportCodec) -> [UTType] {
    codec == .hevc ? [.quickTimeMovie, .mpeg4Movie] : [.mpeg4Movie, .quickTimeMovie]
  }

  static func preferredSaveContainer(codec: PostRecordingExportCodec) -> ExportContainer {
    codec == .hevc ? .mov : .mp4
  }

  static func preferredAndFallbackSaveContainers(codec: PostRecordingExportCodec) -> (ExportContainer, ExportContainer) {
    codec == .hevc ? (.mov, .mp4) : (.mp4, .mov)
  }

  static func bestSaveFileType(
    codec: PostRecordingExportCodec,
    supportedTypes: [AVFileType],
    preferredContainer: PostRecordingVideoSaveContainer? = nil
  ) -> AVFileType {
    if let preferredContainer, supportedTypes.contains(preferredContainer.fileType) {
      return preferredContainer.fileType
    }
    let container = bestSaveContainer(
      codec: codec,
      supportsMP4: supportedTypes.contains(.mp4),
      supportsMOV: supportedTypes.contains(.mov)
    )
    if container == .mov, supportedTypes.contains(.mov) {
      return .mov
    }
    if supportedTypes.contains(.mp4) {
      return .mp4
    }
    return supportedTypes.first ?? (codec == .hevc ? .mov : .mp4)
  }

  static func bestSaveContainer(codec: PostRecordingExportCodec, supportsMP4: Bool, supportsMOV: Bool) -> ExportContainer {
    let preferred = preferredSaveContainer(codec: codec)
    if preferred == .mp4, supportsMP4 { return .mp4 }
    if preferred == .mov, supportsMOV { return .mov }
    if supportsMP4 { return .mp4 }
    return .mov
  }

  static func bestExportPreset(
    codec: PostRecordingExportCodec,
    quality: PostRecordingExportQuality,
    compatiblePresets: [String]
  ) -> String {
    exportPresetCandidates(codec: codec, quality: quality).first(where: compatiblePresets.contains)
      ?? AVAssetExportPresetHighestQuality
  }

  static func bestAvailableExportPreset(
    codec: PostRecordingExportCodec,
    quality: PostRecordingExportQuality,
    asset: AVAsset
  ) -> String {
    for preset in exportPresetCandidates(codec: codec, quality: quality) {
      if AVAssetExportSession(asset: asset, presetName: preset) != nil {
        return preset
      }
    }
    return AVAssetExportPresetHighestQuality
  }

  private static func exportPresetCandidates(
    codec: PostRecordingExportCodec,
    quality: PostRecordingExportQuality
  ) -> [String] {
    switch (codec, quality) {
    case (.h264, .standard):
      return [AVAssetExportPreset1920x1080, AVAssetExportPreset1280x720, AVAssetExportPresetMediumQuality, AVAssetExportPresetHighestQuality]
    case (.h264, .high):
      return [AVAssetExportPresetHighestQuality, AVAssetExportPreset1920x1080, AVAssetExportPreset1280x720]
    case (.hevc, .standard):
      return [AVAssetExportPresetHEVC1920x1080, AVAssetExportPresetHEVCHighestQuality, AVAssetExportPresetHighestQuality]
    case (.hevc, .high):
      return [AVAssetExportPresetHEVCHighestQuality, AVAssetExportPresetHEVC1920x1080, AVAssetExportPresetHighestQuality]
    }
  }

  static func estimatedFileLengthLimit(durationSeconds: Double, options: PostRecordingExportOptions) -> Int64? {
    guard durationSeconds.isFinite, durationSeconds > 0 else {
      return nil
    }
    var videoBitrate = baseBitrate(options.bitrate)
    videoBitrate *= options.quality == .high ? highQualityBitrateMultiplier : 1.0
    videoBitrate *= options.frameRate == .fps60 ? sixtyFPSBitrateMultiplier : 1.0
    switch options.scale {
    case .full:
      break
    case .percent75:
      videoBitrate *= 0.72
    case .percent50:
      videoBitrate *= 0.55
    }
    videoBitrate *= options.codec == .hevc ? hevcBitrateMultiplier : 1.0
    return Int64(((durationSeconds * max(minimumEstimatedBitrate, videoBitrate)) / 8.0).rounded(.up))
  }

  static func compositionPlan(
    naturalSize: CGSize,
    preferredTransform: CGAffineTransform,
    scale: PostRecordingExportScale
  ) -> CompositionPlan? {
    guard naturalSize.width.isFinite, naturalSize.height.isFinite, naturalSize.width > 0, naturalSize.height > 0 else {
      return nil
    }
    let factor = scaleFactor(scale)
    var scaled = preferredTransform
    scaled.a *= factor
    scaled.b *= factor
    scaled.c *= factor
    scaled.d *= factor
    let corners = [
      CGPoint(x: 0, y: 0).applying(scaled),
      CGPoint(x: naturalSize.width, y: 0).applying(scaled),
      CGPoint(x: 0, y: naturalSize.height).applying(scaled),
      CGPoint(x: naturalSize.width, y: naturalSize.height).applying(scaled)
    ]
    let minX = corners.map(\.x).min() ?? 0
    let maxX = corners.map(\.x).max() ?? naturalSize.width
    let minY = corners.map(\.y).min() ?? 0
    let maxY = corners.map(\.y).max() ?? naturalSize.height
    let renderWidth = roundedEven(maxX - minX)
    let renderHeight = roundedEven(maxY - minY)
    let translated = scaled.concatenating(CGAffineTransform(translationX: -minX, y: -minY))
    return CompositionPlan(renderSize: CGSize(width: renderWidth, height: renderHeight), transform: translated)
  }

  static func exportPlan(
    trimStartMS: Int,
    trimEndMS: Int,
    keyEventCount: Int,
    clickEventCount: Int,
    context: ExportContext
  ) -> ExportPlan? {
    guard trimEndMS >= trimStartMS, trimStartMS >= 0, keyEventCount >= 0, clickEventCount >= 0 else {
      return nil
    }
    let includeAudio = context.sourceHasAudio && context.audioTrackVisible
    let includeWebcam = context.sourceHasWebcamAsset && context.webcamTrackVisible
    let clickOverlayCount = context.clickOverlaysVisible ? clickEventCount : 0
    let overlayCount = context.textOverlayCount + keyEventCount + clickOverlayCount
    let needsCompositor = includeWebcam || overlayCount > 0 || (context.sourceHasAudio && !includeAudio)
    return ExportPlan(
      trimStartMS: trimStartMS,
      trimEndMS: trimEndMS,
      keyEventCount: keyEventCount,
      clickEventCount: clickEventCount,
      planMode: needsCompositor ? PlanMode.compositeMP4.rawValue : PlanMode.passthrough.rawValue,
      includeAudio: includeAudio,
      includeWebcam: includeWebcam,
      textOverlayCount: context.textOverlayCount,
      overlayItemCount: overlayCount,
      requiresIntermediateForGIF: needsCompositor,
      needsCustomCompositor: needsCompositor
    )
  }

  static func decision(target: ExportTarget, plan: ExportPlan) -> ExportDecision? {
    let composite = plan.planMode == PlanMode.compositeMP4.rawValue || plan.needsCustomCompositor
    let intermediate = plan.requiresIntermediateForGIF || composite
    return ExportDecision(
      useCustomCompositor: target == .mp4 ? composite : intermediate,
      requiresIntermediateForGIF: intermediate,
      includeAudio: plan.includeAudio,
      includeWebcam: plan.includeWebcam
    )
  }

  static func trimRange(durationMS: UInt32, startMS: UInt32, endMS: UInt32, minGapMS: UInt32, activeHandle: TrimHandle) -> (startMS: UInt32, endMS: UInt32)? {
    guard durationMS > 0 else {
      return nil
    }
    let gap = min(minGapMS, durationMS)
    var start = min(startMS, durationMS)
    var end = min(max(endMS, start), durationMS)
    if end - start < gap {
      switch activeHandle {
      case .start:
        start = end > gap ? end - gap : 0
      case .end:
        end = min(durationMS, start + gap)
      case .unknown:
        end = min(durationMS, start + gap)
        if end - start < gap {
          start = end > gap ? end - gap : 0
        }
      }
    }
    return (start, end)
  }

  static func gifPlan(startMS: UInt32, endMS: UInt32, preferredFPS: Double = defaultGIFFPS, maxDimension: Int = 960) -> GIFPlan? {
    guard endMS > startMS, preferredFPS.isFinite, preferredFPS > 0 else {
      return nil
    }
    let frameRate = min(max(preferredFPS, 1), maximumGIFFPS)
    let duration = Double(endMS - startMS) / millisecondsPerSecond
    let frameCount = max(1, Int((duration * frameRate).rounded(.up)))
    return GIFPlan(
      startMS: startMS,
      endMS: endMS,
      frameRate: frameRate,
      frameCount: frameCount,
      maxDimension: max(minimumGIFDimension, min(maximumGIFDimension, maxDimension)),
      frameDelayMS: max(1, Int((millisecondsPerSecond / frameRate).rounded()))
    )
  }

  static func gifFrameTimeMS(plan: GIFPlan, index: Int) -> UInt32? {
    guard index >= 0, index < plan.frameCount else {
      return nil
    }
    if plan.frameCount <= 1 {
      return plan.startMS
    }
    let progress = Double(index) / Double(plan.frameCount - 1)
    return plan.startMS + UInt32((Double(plan.endMS - plan.startMS) * progress).rounded())
  }

  private static func roundedEven(_ value: CGFloat) -> CGFloat {
    let rounded = max(2, Int(value.rounded(.up)))
    return CGFloat(rounded.isMultiple(of: 2) ? rounded : rounded + 1)
  }

  private static func scaleFactor(_ scale: PostRecordingExportScale) -> CGFloat {
    switch scale {
    case .full:
      return 1
    case .percent75:
      return 0.75
    case .percent50:
      return 0.5
    }
  }

  private static func baseBitrate(_ bitrate: PostRecordingExportBitratePreset) -> Double {
    switch bitrate {
    case .standard:
      return 8_000_000
    case .high:
      return 14_000_000
    case .veryHigh:
      return 22_000_000
    }
  }
}
