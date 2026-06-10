@MainActor
enum RegionSelectionCommandDispatcher {
  static func handle(
    _ command: SelectionCommand,
    selectionView: RegionSelectionView,
    includesStitchCommands: Bool
  ) -> Bool {
    switch command {
    case .cancel:
      selectionView.handleCancelShortcut()
      return true
    case .undo:
      selectionView.performUndoShortcut()
      return true
    case .redo:
      selectionView.performRedoShortcut()
      return true
    case .copy:
      selectionView.performCopyShortcut()
      return true
    case .save:
      selectionView.performSaveShortcut()
      return true
    case .addStitchSegment:
      guard includesStitchCommands else {
        return false
      }
      selectionView.performAddStitchSegmentShortcut()
      return true
    case .resetStitch:
      guard includesStitchCommands else {
        return false
      }
      selectionView.performResetStitchShortcut()
      return true
    case .zoomIn:
      selectionView.performZoomInShortcut()
      return true
    case .zoomOut:
      selectionView.performZoomOutShortcut()
      return true
    case .zoomReset:
      selectionView.performZoomResetShortcut()
      return true
    case .selectTool(let index):
      return selectionView.performSelectToolShortcut(index: index)
    case .cycleTools(let reverse):
      return selectionView.performCycleToolShortcut(reverse: reverse)
    case .cycleCaptureType:
      return selectionView.performCycleCaptureTypeShortcut()
    case .cycleCaptureModes(let reverse):
      return selectionView.performCycleCaptureModeShortcut(reverse: reverse)
    case .selectCaptureMode(let captureMode):
      return selectionView.performCaptureModeShortcut(captureMode)
    case .toggleVideoSystemAudio:
      return selectionView.performToggleVideoSystemAudioShortcut()
    case .toggleVideoMicrophone:
      return selectionView.performToggleVideoMicrophoneShortcut()
    case .toggleVideoWebcam:
      return selectionView.performToggleVideoWebcamShortcut()
    case .toggleVideoMouseClicks:
      return selectionView.performToggleVideoMouseClicksShortcut()
    case .toggleVideoKeystrokes:
      return selectionView.performToggleVideoKeystrokesShortcut()
    case .cycleVideoCountdown:
      return selectionView.performCycleVideoCountdownShortcut()
    case .toggleVideoRecording:
      return selectionView.performToggleVideoRecordingShortcut()
    case .performDefaultCaptureAction:
      return selectionView.performDefaultCaptureActionShortcut()
    }
  }
}
