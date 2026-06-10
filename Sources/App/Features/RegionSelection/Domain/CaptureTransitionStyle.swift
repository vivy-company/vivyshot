/// Animated transition used after a screenshot selection is confirmed.
enum CaptureTransitionStyle: Int, CaseIterable, Identifiable {
  case none = 0
  case fade = 1
  case ripple = 2
  case liquidDrop = 3
  case zoomBlur = 4
  case waterWave = 5

  var id: Int { rawValue }
}
