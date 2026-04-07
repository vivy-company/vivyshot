import Foundation

enum AnnotationTool: Int, CaseIterable, Identifiable {
  case move = 0
  case rect = 1
  case filledRect = 2
  case circle = 3
  case filledCircle = 4
  case line = 5
  case arrow = 6
  case paint = 7
  case text = 8
  case pixelate = 9
  case blur = 10

  var id: Int { rawValue }

  var symbolName: String {
    switch self {
    case .move:
      return "cursorarrow.motionlines"
    case .rect:
      return "square.on.square"
    case .filledRect:
      return "square.fill"
    case .circle:
      return "circle"
    case .filledCircle:
      return "circle.fill"
    case .line:
      return "line.diagonal"
    case .arrow:
      return "arrow.up.right"
    case .paint:
      return "paintbrush.pointed"
    case .text:
      return "textformat"
    case .pixelate:
      return "square.grid.3x3"
    case .blur:
      return "drop.halffull"
    }
  }

  var title: String {
    switch self {
    case .move:
      return String(localized: "Move", bundle: AppLocalizer.shared.bundle)
    case .rect:
      return String(localized: "Rect", bundle: AppLocalizer.shared.bundle)
    case .filledRect:
      return String(localized: "Filled Rect", bundle: AppLocalizer.shared.bundle)
    case .circle:
      return String(localized: "Circle", bundle: AppLocalizer.shared.bundle)
    case .filledCircle:
      return String(localized: "Filled Circle", bundle: AppLocalizer.shared.bundle)
    case .line:
      return String(localized: "Line", bundle: AppLocalizer.shared.bundle)
    case .arrow:
      return String(localized: "Arrow", bundle: AppLocalizer.shared.bundle)
    case .paint:
      return String(localized: "Paint", bundle: AppLocalizer.shared.bundle)
    case .text:
      return String(localized: "Text", bundle: AppLocalizer.shared.bundle)
    case .pixelate:
      return String(localized: "Pixelate", bundle: AppLocalizer.shared.bundle)
    case .blur:
      return String(localized: "Blur", bundle: AppLocalizer.shared.bundle)
    }
  }
}
