extension CaptureTransitionStyle {
  var title: String {
    switch self {
    case .none:
      return AppLocalizer.shared.string("None")
    case .fade:
      return AppLocalizer.shared.string("Fade")
    case .ripple:
      return AppLocalizer.shared.string("Wave Drop")
    case .liquidDrop:
      return AppLocalizer.shared.string("Liquid Drop")
    case .zoomBlur:
      return AppLocalizer.shared.string("Zoom Blur")
    case .waterWave:
      return AppLocalizer.shared.string("Water Wave")
    }
  }
}
