@MainActor
protocol RegionSelectionOverlayEditingDelegate: AnyObject {
  func regionSelectionOverlayWillStartRecordingWebcamCapture(_ controller: RegionSelectionOverlayController) async
  func regionSelectionOverlayDidFinishRecordingFlow(_ controller: RegionSelectionOverlayController)
  func regionSelectionOverlay(_ controller: RegionSelectionOverlayController, didFailRecordingWithMessage message: String)
  func regionSelectionOverlayDidFinishEditing(_ controller: RegionSelectionOverlayController)
}
