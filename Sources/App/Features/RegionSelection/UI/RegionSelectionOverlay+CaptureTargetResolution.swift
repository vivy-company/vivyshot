import AppKit

@MainActor
extension RegionSelectionView {
  func ensureCaptureTargetIsResolved(forRecording: Bool) -> Bool {
    if !forRecording, resolvePendingCaptureTargetForStillShortcut() {
      return true
    }

    if selectedCaptureMode == .window, windowCapturePickPending {
      NSSound.beep()
      if forRecording {
        toastPresenter.show("Click a window to start recording")
      } else {
        toastPresenter.show("Click a window to capture first")
      }
      return false
    }

    if selectedCaptureMode == .screen, screenCapturePickPending {
      NSSound.beep()
      if forRecording {
        toastPresenter.show("Click anywhere to start full-screen recording")
      } else {
        toastPresenter.show("Click anywhere to capture full screen")
      }
      return false
    }

    return true
  }

  func resolvePendingVideoCaptureTargetForDefaultAction() -> Bool {
    guard mode == .editing, selectedCaptureType == .video else {
      return true
    }

    if selectedCaptureMode == .screen, screenCapturePickPending {
      return applyCaptureRect(bounds, as: .screen, rememberAsArea: false)
    }

    if selectedCaptureMode == .window, windowCapturePickPending {
      guard let windowRect = captureRectForWindowPick(atScreenPoint: NSEvent.mouseLocation) else {
        NSSound.beep()
        toastPresenter.show("Move the pointer over a window to start recording")
        return false
      }
      return applyCaptureRect(windowRect, as: .window, rememberAsArea: false)
    }

    return true
  }

  func resolvePendingCaptureTargetForStillShortcut() -> Bool {
    guard mode == .editing, selectedCaptureType == .screenshot else {
      return false
    }

    if selectedCaptureMode == .screen, screenCapturePickPending {
      return applyCaptureRect(bounds, as: .screen, rememberAsArea: false)
    }

    if selectedCaptureMode == .window, windowCapturePickPending {
      if let windowRect = captureRectForWindowPick(atScreenPoint: NSEvent.mouseLocation) {
        return applyCaptureRect(windowRect, as: .window, rememberAsArea: false)
      }
      return false
    }

    return false
  }
}
