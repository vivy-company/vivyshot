import CoreGraphics

@MainActor
protocol RegionSelectionViewDelegate: AnyObject {
  func regionSelectionView(
    _ view: RegionSelectionView,
    didFinishSelection localRect: CGRect?,
    captureType: CaptureContentType,
    captureMode: CaptureMode
  )
  func regionSelectionViewDidRequestCancel(_ view: RegionSelectionView)
  func regionSelectionViewDidRequestImmediateCancel(_ view: RegionSelectionView)
  func regionSelectionViewWillStartRecordingWebcamCapture(_ view: RegionSelectionView) async
  func regionSelectionViewDidFinishRecordingFlow(_ view: RegionSelectionView)
  func regionSelectionView(_ view: RegionSelectionView, didFailRecordingWithMessage message: String)
  func regionSelectionView(_ view: RegionSelectionView, didFinishEditingAnimatedClose animatedClose: Bool)
}
