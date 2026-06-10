import AppKit
import AVFoundation
import CoreGraphics
import QuartzCore

@MainActor
final class RecordingWebcamOverlayView: RecordingDraggableOverlayView {
  private let previewLayer: AVCaptureVideoPreviewLayer
  private let shape: WebcamShape
  private let aspectRatio: WebcamAspectRatio
  private let resizeGripLayer = CAShapeLayer()

  override var allowsResizing: Bool { true }
  override var minimumFrameSize: CGSize { CGSize(width: 84, height: 84) }
  override var fixedAspectRatio: WebcamAspectRatio? { aspectRatio }

  init(
    normalizedFrame: CGRect,
    previewLayer: AVCaptureVideoPreviewLayer,
    shape: WebcamShape,
    aspectRatio: WebcamAspectRatio
  ) {
    self.previewLayer = previewLayer
    self.shape = shape
    self.aspectRatio = shape == .circle ? .square : aspectRatio
    super.init(normalizedFrame: normalizedFrame)
    layer?.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
    layer?.borderColor = NSColor.white.withAlphaComponent(0.7).cgColor
    layer?.borderWidth = 1
    layer?.masksToBounds = true
    layer?.addSublayer(previewLayer)
    resizeGripLayer.fillColor = nil
    resizeGripLayer.strokeColor = NSColor.white.withAlphaComponent(0.50).cgColor
    resizeGripLayer.lineWidth = 1.2
    resizeGripLayer.lineCap = .round
    layer?.addSublayer(resizeGripLayer)
  }

  override func layout() {
    super.layout()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    previewLayer.frame = bounds
    layer?.cornerRadius = shape == .circle ? min(bounds.width, bounds.height) * 0.5 : 14
    resizeGripLayer.frame = bounds
    resizeGripLayer.path = Self.resizeGripPath(in: bounds)
    CATransaction.commit()
  }

  private static func resizeGripPath(in bounds: CGRect) -> CGPath {
    let grip = CGRect(x: bounds.maxX - 20, y: bounds.maxY - 18, width: 12, height: 12)
    let path = CGMutablePath()
    for offset in stride(from: CGFloat(4), through: CGFloat(12), by: CGFloat(4)) {
      path.move(to: CGPoint(x: grip.maxX - offset, y: grip.maxY))
      path.addLine(to: CGPoint(x: grip.maxX, y: grip.maxY - offset))
    }
    return path
  }
}
