import Foundation

extension StoreEntitlement {
  var badgeTitle: String? {
    if hasSupporterBadge {
      return String(localized: "Supporter", bundle: AppLocalizer.shared.bundle)
    }
    if hasLifetimeUnlock {
      return String(localized: "Lifetime", bundle: AppLocalizer.shared.bundle)
    }
    return nil
  }

  var tierTitle: String {
    badgeTitle ?? String(localized: "Free", bundle: AppLocalizer.shared.bundle)
  }
}

extension StoreError: LocalizedError {
  var errorDescription: String? {
    switch self {
    case .verificationFailed:
      return String(localized: "Purchase verification failed", bundle: AppLocalizer.shared.bundle)
    case .productNotFound:
      return String(localized: "Product not found", bundle: AppLocalizer.shared.bundle)
    }
  }
}

extension PaidFeature {
  static let licenseFeatures = Array(PaidFeature.allCases)

  var title: String {
    switch self {
    case .captureTransitions:
      return String(localized: "Capture transitions", bundle: AppLocalizer.shared.bundle)
    case .microphoneAudioExport:
      return String(localized: "Microphone audio", bundle: AppLocalizer.shared.bundle)
    case .webcamOverlay:
      return String(localized: "Webcam overlay", bundle: AppLocalizer.shared.bundle)
    case .keystrokeOverlay:
      return String(localized: "Keystroke overlay", bundle: AppLocalizer.shared.bundle)
    case .gifExport:
      return String(localized: "GIF export", bundle: AppLocalizer.shared.bundle)
    case .hevcExport:
      return String(localized: "HEVC export", bundle: AppLocalizer.shared.bundle)
    case .sixtyFPSExport:
      return String(localized: "60 fps export", bundle: AppLocalizer.shared.bundle)
    case .highQualityExport:
      return String(localized: "High quality export", bundle: AppLocalizer.shared.bundle)
    case .highBitrateExport:
      return String(localized: "High bitrate export", bundle: AppLocalizer.shared.bundle)
    case .statistics:
      return String(localized: "Statistics", bundle: AppLocalizer.shared.bundle)
    }
  }

  var comparisonTitle: String {
    switch self {
    case .microphoneAudioExport:
      return String(localized: "Microphone audio export", bundle: AppLocalizer.shared.bundle)
    case .webcamOverlay:
      return String(localized: "Webcam overlay export", bundle: AppLocalizer.shared.bundle)
    case .keystrokeOverlay:
      return String(localized: "Keystroke overlay export", bundle: AppLocalizer.shared.bundle)
    case .hevcExport:
      return String(localized: "Video codec", bundle: AppLocalizer.shared.bundle)
    case .sixtyFPSExport:
      return String(localized: "Frame rate", bundle: AppLocalizer.shared.bundle)
    case .highQualityExport:
      return String(localized: "Export quality", bundle: AppLocalizer.shared.bundle)
    case .highBitrateExport:
      return String(localized: "Export bitrate", bundle: AppLocalizer.shared.bundle)
    default:
      return title
    }
  }

  var symbolName: String {
    switch self {
    case .captureTransitions:
      return "sparkles"
    case .microphoneAudioExport:
      return "mic.fill"
    case .webcamOverlay:
      return "video.fill"
    case .keystrokeOverlay:
      return "keyboard"
    case .gifExport:
      return "photo.stack"
    case .hevcExport:
      return "film"
    case .sixtyFPSExport:
      return "gauge.with.dots.needle.bottom.50percent"
    case .highQualityExport:
      return "slider.horizontal.3"
    case .highBitrateExport:
      return "speedometer"
    case .statistics:
      return "chart.bar.xaxis"
    }
  }
}
