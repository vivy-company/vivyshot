import AppKit
import CoreGraphics
import QuartzCore
import SwiftUI

enum CaptureOverlayPlacementKind {
  case webcam
  case keystroke
}

@MainActor
final class CaptureOverlayPlacementView: NSView {
  let kind: CaptureOverlayPlacementKind
  var containerFrame: CGRect = .zero
  var onFrameChanged: ((CGRect) -> Void)?
  var webcamShape: WebcamShape = .roundedRect {
    didSet { needsDisplay = true }
  }
  var webcamAspectRatio: WebcamAspectRatio = .square {
    didSet { needsLayout = true }
  }
  var keystrokeStyle: KeystrokeStyle = .glass {
    didSet {
      updateKeystrokeHostingView()
      needsDisplay = true
    }
  }
  var keystrokeSize: KeystrokeSize = .medium {
    didSet {
      updateKeystrokeHostingView()
    }
  }

  private var dragStartFrame: CGRect = .zero
  private var dragStartLocation: CGPoint = .zero
  private var activeInteraction: OverlayFrameInteraction = .move
  private let webcamPreview = WebcamPreviewSession()
  private var keystrokeHostingView: NSHostingView<KeystrokeOverlayGlassCapsule>?

  private enum OverlayFrameInteraction {
    case move
    case resize(ResizeCorner)
  }

  init(kind: CaptureOverlayPlacementKind) {
    self.kind = kind
    super.init(frame: .zero)
    wantsLayer = true
    layer?.cornerRadius = kind == .webcam ? 18 : 14
    layer?.masksToBounds = false
    layer?.shadowColor = NSColor.black.cgColor
    layer?.shadowOpacity = 0.22
    layer?.shadowRadius = 10
    layer?.shadowOffset = CGSize(width: 0, height: -2)
    if kind == .keystroke {
      let host = NSHostingView(
        rootView: KeystrokeOverlayGlassCapsule(
          text: "⌘K",
          style: keystrokeStyle,
          size: keystrokeSize,
          showsResizeGrip: true
        )
      )
      host.translatesAutoresizingMaskIntoConstraints = true
      host.wantsLayer = true
      host.layer?.backgroundColor = NSColor.clear.cgColor
      addSubview(host)
      keystrokeHostingView = host
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  override func resetCursorRects() {
    addCursorRect(bounds, cursor: .openHand)
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    true
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    guard !isHidden, bounds.contains(point) else {
      return nil
    }
    return self
  }

  override func mouseDown(with event: NSEvent) {
    dragStartFrame = frame
    dragStartLocation = window?.convertPoint(toScreen: event.locationInWindow) ?? .zero
    let localPoint = convert(event.locationInWindow, from: nil)
    activeInteraction = RecordingOverlayFrameGeometry
      .resizeCorner(at: localPoint, in: bounds)
      .map(OverlayFrameInteraction.resize) ?? .move
    NSCursor.closedHand.set()
  }

  override func mouseDragged(with event: NSEvent) {
    let location = window?.convertPoint(toScreen: event.locationInWindow) ?? .zero
    let delta = CGSize(width: location.x - dragStartLocation.x, height: location.y - dragStartLocation.y)
    let proposed: CGRect
    switch activeInteraction {
    case .move:
      proposed = dragStartFrame.offsetBy(dx: delta.width, dy: delta.height)
    case .resize(let corner):
      proposed = RecordingOverlayFrameGeometry.resizedOverlayFrame(
        from: dragStartFrame,
        corner: corner,
        delta: delta,
        minimumSize: minimumFrameSize
      )
    }
    frame = clampedFrame(proposed)
    onFrameChanged?(frame)
  }

  override func mouseUp(with _: NSEvent) {
    NSCursor.openHand.set()
    onFrameChanged?(frame)
  }

  override func layout() {
    super.layout()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    webcamPreview.previewLayer?.frame = bounds
    layer?.cornerRadius = kind == .webcam && webcamShape == .circle ? min(bounds.width, bounds.height) * 0.5 : (kind == .webcam ? 18 : 14)
    CATransaction.commit()
    keystrokeHostingView?.frame = bounds
  }

  func updateWebcamPreview(preferredDeviceID: String) {
    guard kind == .webcam else {
      return
    }
    webcamPreview.update(preferredDeviceID: preferredDeviceID) { [weak self] previewLayer in
      guard let self else {
        return
      }
      self.layer?.insertSublayer(previewLayer, at: 0)
      self.needsDisplay = true
      self.needsLayout = true
    }
  }

  func stopWebcamPreview() {
    webcamPreview.stopDetached()
    needsDisplay = true
  }

  func stopWebcamPreviewForRecordingStart() async {
    await webcamPreview.stop()
    needsDisplay = true
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    if kind == .keystroke, keystrokeHostingView != nil {
      return
    }

    let rect = bounds.insetBy(dx: 1, dy: 1)
    let path: NSBezierPath
    switch kind {
    case .webcam:
      if webcamShape == .circle {
        path = NSBezierPath(ovalIn: rect)
      } else {
        path = NSBezierPath(roundedRect: rect, xRadius: 18, yRadius: 18)
      }
    case .keystroke:
      path = NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14)
    }

    let fillAlpha: CGFloat = kind == .keystroke && keystrokeStyle == .compact ? 0.68 : 0.46
    if kind == .keystroke && keystrokeStyle == .glass {
      drawGlassFill(in: rect, clippedTo: path)
    } else {
      NSColor.black.withAlphaComponent(fillAlpha).setFill()
      path.fill()
    }

    NSColor.white.withAlphaComponent(kind == .keystroke && keystrokeStyle == .glass ? 0.42 : 0.34).setStroke()
    path.lineWidth = 1
    path.stroke()

    if kind == .webcam || kind == .keystroke {
      drawResizeGrip(in: rect)
    }

    if kind == .webcam, webcamPreview.isShowingPreview {
      return
    }

    let symbolName: String
    let title: String
    switch kind {
    case .webcam:
      symbolName = "video.fill"
      title = String(localized: "Webcam", bundle: AppLocalizer.shared.bundle)
    case .keystroke:
      symbolName = "keyboard"
      title = "⌘K"
    }

    if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
      let size: CGFloat = kind == .webcam ? 18 : 16
      symbol.draw(
        in: CGRect(x: rect.midX - size * 0.5, y: rect.midY + 2, width: size, height: size),
        from: .zero,
        operation: .sourceOver,
        fraction: 0.92
      )
    }

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: kind == .webcam ? 13 : 16, weight: .semibold),
      .foregroundColor: NSColor.white.withAlphaComponent(0.92),
      .paragraphStyle: paragraph
    ]
    NSString(string: title).draw(
      in: CGRect(x: rect.minX + 6, y: rect.midY - 20, width: rect.width - 12, height: 18),
      withAttributes: attrs
    )
  }

  private func drawGlassFill(in rect: CGRect, clippedTo path: NSBezierPath) {
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    let gradient = NSGradient(colors: [
      NSColor.white.withAlphaComponent(0.30),
      NSColor.controlAccentColor.withAlphaComponent(0.18),
      NSColor.black.withAlphaComponent(0.30)
    ])
    gradient?.draw(in: rect, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    let shine = NSBezierPath(roundedRect: rect.insetBy(dx: 2.5, dy: 2.5), xRadius: min(rect.height * 0.5, 14), yRadius: min(rect.height * 0.5, 14))
    NSColor.white.withAlphaComponent(0.08).setStroke()
    shine.lineWidth = 1
    shine.stroke()
  }

  private func drawResizeGrip(in rect: CGRect) {
    let grip = CGRect(x: rect.maxX - 18, y: rect.minY + 5, width: 12, height: 12)
    let path = NSBezierPath()
    for offset in stride(from: CGFloat(4), through: CGFloat(12), by: CGFloat(4)) {
      path.move(to: CGPoint(x: grip.maxX - offset, y: grip.minY))
      path.line(to: CGPoint(x: grip.maxX, y: grip.minY + offset))
    }
    NSColor.white.withAlphaComponent(0.42).setStroke()
    path.lineWidth = 1.2
    path.stroke()
  }

  private var minimumFrameSize: CGSize {
    switch kind {
    case .webcam:
      return CGSize(width: 84, height: 84)
    case .keystroke:
      return CGSize(width: 112, height: 42)
    }
  }

  private func clampedFrame(_ proposed: CGRect) -> CGRect {
    guard !containerFrame.isNull, !containerFrame.isEmpty else {
      return proposed
    }
    let minimum = minimumFrameSize
    if kind == .webcam {
      let aspectRatio = webcamShape == .circle ? WebcamAspectRatio.square : webcamAspectRatio
      return aspectRatio.constrainedFrame(proposed, in: containerFrame, minimumSize: minimum)
    }
    return RecordingOverlayFrameGeometry.clampedOverlayFrame(
      proposed,
      in: containerFrame,
      minimumSize: minimum
    )
  }

  private func updateKeystrokeHostingView() {
    keystrokeHostingView?.rootView = KeystrokeOverlayGlassCapsule(
      text: "⌘K",
      style: keystrokeStyle,
      size: keystrokeSize,
      showsResizeGrip: true
    )
  }

}
