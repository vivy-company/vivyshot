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
      return "Move"
    case .rect:
      return "Rect"
    case .filledRect:
      return "Filled Rect"
    case .circle:
      return "Circle"
    case .filledCircle:
      return "Filled Circle"
    case .line:
      return "Line"
    case .arrow:
      return "Arrow"
    case .paint:
      return "Paint"
    case .text:
      return "Text"
    case .pixelate:
      return "Pixelate"
    case .blur:
      return "Blur"
    }
  }
}
