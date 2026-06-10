extension CaptureTransitionStyle {
  var title: String {
    switch self {
    case .none:
      return String(localized: "None", bundle: AppLocalizer.shared.bundle)
    case .fade:
      return String(localized: "Fade", bundle: AppLocalizer.shared.bundle)
    case .ripple:
      return String(localized: "Wave Drop", bundle: AppLocalizer.shared.bundle)
    case .liquidDrop:
      return String(localized: "Liquid Drop", bundle: AppLocalizer.shared.bundle)
    case .zoomBlur:
      return String(localized: "Zoom Blur", bundle: AppLocalizer.shared.bundle)
    case .waterWave:
      return String(localized: "Water Wave", bundle: AppLocalizer.shared.bundle)
    }
  }
}
