import Foundation

extension StoreEntitlement {
  var badgeTitle: String? {
    badgeTitle(localizer: AppLocalizer.shared)
  }

  func badgeTitle(localizer: AppLocalizer) -> String? {
    if hasSupporterBadge {
      return localizer.string("Supporter")
    }
    if hasLifetimeUnlock {
      return localizer.string("Lifetime")
    }
    return nil
  }

  var tierTitle: String {
    tierTitle(localizer: AppLocalizer.shared)
  }

  func tierTitle(localizer: AppLocalizer) -> String {
    badgeTitle(localizer: localizer) ?? localizer.string("Free")
  }
}

extension StoreError: LocalizedError {
  var errorDescription: String? {
    switch self {
    case .verificationFailed:
      return AppLocalizer.shared.string("Purchase verification failed")
    case .productNotFound:
      return AppLocalizer.shared.string("Product not found")
    }
  }
}

extension PaidFeature {
  static let licenseFeatures = Array(PaidFeature.allCases)

  var title: String {
    title(localizer: AppLocalizer.shared)
  }

  func title(localizer: AppLocalizer) -> String {
    switch self {
    case .captureTransitions:
      return String(localized: "Capture transitions", bundle: localizer.bundle)
    case .microphoneAudioExport:
      return String(localized: "Microphone audio", bundle: localizer.bundle)
    case .webcamOverlay:
      return String(localized: "Webcam overlay", bundle: localizer.bundle)
    case .keystrokeOverlay:
      return String(localized: "Keystroke overlay", bundle: localizer.bundle)
    case .gifExport:
      return String(localized: "GIF export", bundle: localizer.bundle)
    case .hevcExport:
      return String(localized: "HEVC export", bundle: localizer.bundle)
    case .sixtyFPSExport:
      return String(localized: "60 fps export", bundle: localizer.bundle)
    case .highQualityExport:
      return String(localized: "High quality export", bundle: localizer.bundle)
    case .highBitrateExport:
      return String(localized: "High bitrate export", bundle: localizer.bundle)
    case .statistics:
      return String(localized: "Statistics", bundle: localizer.bundle)
    }
  }

  var comparisonTitle: String {
    comparisonTitle(localizer: AppLocalizer.shared)
  }

  func comparisonTitle(localizer: AppLocalizer) -> String {
    switch self {
    case .microphoneAudioExport:
      return String(localized: "Microphone audio export", bundle: localizer.bundle)
    case .webcamOverlay:
      return String(localized: "Webcam overlay export", bundle: localizer.bundle)
    case .keystrokeOverlay:
      return String(localized: "Keystroke overlay export", bundle: localizer.bundle)
    case .hevcExport:
      return String(localized: "Video codec", bundle: localizer.bundle)
    case .sixtyFPSExport:
      return String(localized: "Frame rate", bundle: localizer.bundle)
    case .highQualityExport:
      return String(localized: "Export quality", bundle: localizer.bundle)
    case .highBitrateExport:
      return String(localized: "Export bitrate", bundle: localizer.bundle)
    default:
      return title(localizer: localizer)
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
