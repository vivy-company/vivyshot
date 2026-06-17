import CoreGraphics

/// Capture target chosen before the region-selection flow begins.
enum CaptureMode: Int, CaseIterable, Identifiable {
  case screen = 0
  case window = 1
  case selection = 2

  var id: Int { rawValue }
}

/// Product mode for the selected capture area.
enum CaptureContentType: Int, CaseIterable, Identifiable {
  case screenshot = 0
  case video = 1

  var id: Int { rawValue }
}

/// Default action for screenshot captures after the selection is confirmed.
enum ScreenshotMainAction: Int, CaseIterable, Identifiable {
  case copy = 0
  case save = 1

  var id: Int { rawValue }
}

/// Screenshot behavior for window targets.
enum ScreenshotWindowCaptureStyle: Int, CaseIterable, Identifiable {
  case nativeWithShadow = 0
  case nativeWithoutShadow = 1
  case visibleAreaRectangle = 2

  var id: Int { rawValue }
}

/// Resolved native window target plus its overlay-local rectangle.
struct WindowCaptureTarget {
  let rect: CGRect
  let windowID: CGWindowID
}
