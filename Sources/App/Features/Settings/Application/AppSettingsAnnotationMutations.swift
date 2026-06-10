import Foundation

@MainActor
extension AppSettings {
  func isToolVisible(_ tool: AnnotationTool) -> Bool {
    !hiddenTools.contains(tool)
  }

  func setToolVisible(_ tool: AnnotationTool, isVisible: Bool) {
    var updated = hiddenTools
    if isVisible {
      updated.remove(tool)
    } else {
      let currentlyVisible = toolOrder.filter { !updated.contains($0) }
      if currentlyVisible.count <= 1, currentlyVisible.contains(tool) {
        return
      }
      updated.insert(tool)
    }

    guard updated != hiddenTools else {
      return
    }

    hiddenTools = updated
    persistToolbarConfiguration()
  }

  func moveTool(_ tool: AnnotationTool, offset: Int) {
    guard let index = toolOrder.firstIndex(of: tool) else {
      return
    }

    let target = index + offset
    guard target >= 0, target < toolOrder.count else {
      return
    }

    var updated = toolOrder
    let moved = updated.remove(at: index)
    updated.insert(moved, at: target)
    toolOrder = updated
    persistToolbarConfiguration()
  }

  func moveTools(from source: IndexSet, to destination: Int) {
    guard let updated = Self.reordered(toolOrder, moving: source, to: destination) else { return }
    guard updated != toolOrder else {
      return
    }

    toolOrder = updated
    persistToolbarConfiguration()
  }

  func resetToolbarConfiguration() {
    toolOrder = AnnotationTool.allCases
    hiddenTools = []
    persistToolbarConfiguration()
  }

  func setTextFontSize(_ size: Double) {
    let clamped = Self.clampedTextFontSize(size)
    guard abs(textFontSize - clamped) > .ulpOfOne else {
      return
    }
    textFontSize = clamped
    persistTextSettings()
  }

  func setTextFontName(_ name: String) {
    let normalized = Self.normalizedTextFontName(name)
    guard textFontName != normalized else {
      return
    }
    textFontName = normalized
    persistTextSettings()
  }

  func setDrawingStrokeWidth(_ width: Double) {
    let clamped = Self.clampedDrawingStrokeWidth(width)
    guard abs(drawingStrokeWidth - clamped) > .ulpOfOne else {
      return
    }
    drawingStrokeWidth = clamped
    persistDrawingSettings()
  }

  func resetTextSettings() {
    textFontSize = Defaults.textFontSize
    textFontName = Self.systemFontFamilyName
    persistTextSettings()
  }
}
