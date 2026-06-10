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
}
