import AppKit
import CoreGraphics

@MainActor
extension RegionSelectionOverlayController: RegionSelectionViewDelegate {
  func regionSelectionView(
    _ view: RegionSelectionView,
    didFinishSelection localRect: CGRect?,
    captureType: CaptureContentType,
    captureMode: CaptureMode,
    windowID: CGWindowID?
  ) {
    guard view === selectionView, let window else {
      finishSelection(with: nil)
      return
    }

    guard let localRect else {
      closeWindow { [weak self] in
        self?.finishSelection(with: nil)
      }
      return
    }

    let globalRect = localRect
      .offsetBy(dx: window.frame.origin.x, dy: window.frame.origin.y)
      .standardized

    finishSelection(
      with: RegionSelectionResult(
        selectionRectInScreen: globalRect,
        captureType: captureType,
        captureMode: captureMode,
        windowID: windowID
      )
    )
  }

  func regionSelectionViewDidRequestCancel(_ view: RegionSelectionView) {
    guard view === selectionView else {
      finishSelection(with: nil)
      return
    }
    if transitionPreviewActive {
      closeTransitionPreview(animated: true)
      return
    }
    closeWindow { [weak self] in
      self?.finishSelection(with: nil)
    }
  }

  func regionSelectionViewDidRequestImmediateCancel(_ view: RegionSelectionView) {
    guard view === selectionView else {
      finishSelection(with: nil)
      return
    }
    if transitionPreviewActive {
      closeTransitionPreview(animated: false)
      return
    }
    closeWindow(animated: false) { [weak self] in
      self?.finishSelection(with: nil)
    }
  }

  func regionSelectionViewWillStartRecordingWebcamCapture(_ view: RegionSelectionView) async {
    guard view === selectionView else {
      return
    }
    await editingDelegate?.regionSelectionOverlayWillStartRecordingWebcamCapture(self)
  }

  func regionSelectionViewDidFinishRecordingFlow(_ view: RegionSelectionView) {
    guard view === selectionView else {
      return
    }
    editingDelegate?.regionSelectionOverlayDidFinishRecordingFlow(self)
  }

  func regionSelectionView(_ view: RegionSelectionView, didFailRecordingWithMessage message: String) {
    guard view === selectionView else {
      return
    }
    editingDelegate?.regionSelectionOverlay(self, didFailRecordingWithMessage: message)
  }

  func regionSelectionView(_ view: RegionSelectionView, didFinishEditingAnimatedClose animatedClose: Bool) {
    guard view === selectionView else {
      return
    }
    let delegate = editingDelegate
    clearFlowCallbacks()
    closeWindow(animated: animatedClose) {
      delegate?.regionSelectionOverlayDidFinishEditing(self)
    }
  }
}
