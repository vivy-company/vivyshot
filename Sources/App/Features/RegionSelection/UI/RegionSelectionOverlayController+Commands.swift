import AppKit

@MainActor
extension RegionSelectionOverlayController: SelectionCommandHandling {
  func handleSelectionCommand(_ command: SelectionCommand) -> Bool {
    guard let selectionView else {
      return false
    }

    if commandRouting.onlyHandlesCancel {
      guard case .cancel = command else {
        return false
      }
      selectionView.handleCancelShortcut()
      return true
    }

    return RegionSelectionCommandDispatcher.handle(
      command,
      selectionView: selectionView,
      includesStitchCommands: commandRouting.includesStitchCommands
    )
  }
}
