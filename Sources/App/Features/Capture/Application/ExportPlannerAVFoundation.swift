import AVFoundation

extension ExportPlanner {
  static func bestSaveFileType(
    codec: PostRecordingExportCodec,
    supportedTypes: [AVFileType],
    preferredContainer: ExportContainer? = nil
  ) -> AVFileType {
    if let preferredContainer {
      let preferredFileType: AVFileType = preferredContainer == .mov ? .mov : .mp4
      if supportedTypes.contains(preferredFileType) {
        return preferredFileType
      }
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
}
