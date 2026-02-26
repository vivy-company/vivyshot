import Foundation

enum CaptureMode: Int, CaseIterable, Identifiable {
  case screen = 0
  case window = 1
  case selection = 2

  var id: Int { rawValue }

  var symbolName: String {
    switch self {
    case .screen:
      return "rectangle"
    case .window:
      return "macwindow"
    case .selection:
      return "rectangle.dashed"
    }
  }
}
