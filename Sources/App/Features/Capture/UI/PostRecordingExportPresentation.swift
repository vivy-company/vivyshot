import Foundation

extension PostRecordingExportOptions {
  @MainActor
  static func defaultOptions(settings: AppSettings) -> PostRecordingExportOptions {
    PostRecordingExportOptions(
      codec: settings.exportCodec,
      frameRate: settings.exportFrameRate,
      quality: settings.exportQuality,
      scale: settings.exportScale,
      bitrate: settings.exportBitrate
    )
  }
}

extension ProExportRequirement {
  var featureListText: String {
    features.map(\.title).joined(separator: ", ")
  }
}

extension PostRecordingVideoSaveContainer {
  var title: String {
    switch self {
    case .mp4:
      return String(localized: "Save as MP4", bundle: AppLocalizer.shared.bundle)
    case .mov:
      return String(localized: "Save as MOV", bundle: AppLocalizer.shared.bundle)
    }
  }
}

extension PostRecordingExportCodec {
  var title: String {
    switch self {
    case .h264:
      return "H.264"
    case .hevc:
      return "HEVC"
    }
  }
}

extension PostRecordingExportFrameRate {
  var title: String {
    "\(rawValue) fps"
  }
}

extension PostRecordingExportQuality {
  var title: String {
    switch self {
    case .standard:
      return String(localized: "Standard", bundle: AppLocalizer.shared.bundle)
    case .high:
      return String(localized: "High", bundle: AppLocalizer.shared.bundle)
    }
  }
}

extension PostRecordingExportScale {
  var title: String {
    switch self {
    case .full:
      return "100%"
    case .percent75:
      return "75%"
    case .percent50:
      return "50%"
    }
  }
}

extension PostRecordingExportBitratePreset {
  var title: String {
    switch self {
    case .standard:
      return String(localized: "Standard", bundle: AppLocalizer.shared.bundle)
    case .high:
      return String(localized: "High", bundle: AppLocalizer.shared.bundle)
    case .veryHigh:
      return String(localized: "Very High", bundle: AppLocalizer.shared.bundle)
    }
  }
}
