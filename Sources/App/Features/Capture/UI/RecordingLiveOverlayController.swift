import AppKit
import AVFoundation
import CoreGraphics

@MainActor
final class RecordingOverlayController: NSWindowController {
  private let captureRectInScreen: CGRect
  private var webcamOverlayView: RecordingWebcamOverlayView?
  private var keystrokeOverlayView: RecordingKeystrokeOverlayView?
  private var localPointerMonitor: Any?
  private var globalPointerMonitor: Any?
  private var isDraggingOverlay = false

  init(
    captureRectInScreen: CGRect,
    webcamPreviewLayer: AVCaptureVideoPreviewLayer?,
    webcamFrame: CGRect,
    webcamShape: WebcamShape,
    webcamAspectRatio: WebcamAspectRatio,
    showKeystrokeOverlay: Bool,
    keystrokeFrame: CGRect,
    keystrokeStyle: KeystrokeStyle,
    keystrokeSize: KeystrokeSize,
    onWebcamFrameChanged: @escaping (CGRect) -> Void,
    onKeystrokeFrameChanged: @escaping (CGRect) -> Void
  ) {
    self.captureRectInScreen = captureRectInScreen.standardized

    let panel = NSPanel(
      contentRect: captureRectInScreen.standardized,
      styleMask: [.nonactivatingPanel, .borderless],
      backing: .buffered,
      defer: false
    )
    panel.isReleasedWhenClosed = false
    panel.level = .screenSaver
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    panel.hidesOnDeactivate = false
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.ignoresMouseEvents = true
    panel.acceptsMouseMovedEvents = true

    let container = RecordingOverlayContainerView(frame: CGRect(origin: .zero, size: captureRectInScreen.size))
    container.wantsLayer = true
    container.layer?.backgroundColor = NSColor.clear.cgColor
    panel.contentView = container

    if let webcamPreviewLayer {
      let view = RecordingWebcamOverlayView(
        normalizedFrame: RecordingOverlayState.normalizedFrame(webcamFrame),
        previewLayer: webcamPreviewLayer,
        shape: webcamShape,
        aspectRatio: webcamAspectRatio
      )
      view.frame = Self.denormalizedWebcamFrame(
        view.normalizedFrame,
        aspectRatio: webcamAspectRatio,
        in: container.bounds
      )
      view.isHidden = false
      view.onNormalizedFrameChanged = onWebcamFrameChanged
      container.addSubview(view)
      webcamOverlayView = view
    } else {
      webcamOverlayView = nil
    }

    let keystrokeView = RecordingKeystrokeOverlayView(
      normalizedFrame: RecordingOverlayState.normalizedFrame(keystrokeFrame),
      style: keystrokeStyle,
      size: keystrokeSize
    )
    keystrokeView.frame = Self.denormalizedFrame(keystrokeView.normalizedFrame, in: container.bounds)
    keystrokeView.isHidden = !showKeystrokeOverlay
    keystrokeView.onNormalizedFrameChanged = onKeystrokeFrameChanged
    container.addSubview(keystrokeView)
    keystrokeOverlayView = keystrokeView

    super.init(window: panel)
    webcamOverlayView?.onDragStateChanged = { [weak self] isDragging in
      self?.setOverlayDragging(isDragging)
    }
    keystrokeOverlayView?.onDragStateChanged = { [weak self] isDragging in
      self?.setOverlayDragging(isDragging)
    }
    installPointerMonitors()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  func show() {
    guard let panel = window as? NSPanel else {
      return
    }
    panel.setFrame(captureRectInScreen, display: true)
    panel.orderFrontRegardless()
    updateMouseEventPassthroughAtCurrentPointerLocation()
  }

  override func close() {
    removePointerMonitors()
    super.close()
  }

  var capturedWindowID: CGWindowID? {
    guard let window else {
      return nil
    }
    return CGWindowID(window.windowNumber)
  }

  func showKeystroke(_ token: String) {
    keystrokeOverlayView?.showToken(token)
  }

  @discardableResult
  func setWebcamVisible(_ visible: Bool) -> Bool {
    guard let webcamOverlayView else {
      return false
    }
    webcamOverlayView.isHidden = !visible
    updateMouseEventPassthroughAtCurrentPointerLocation()
    return true
  }

  @discardableResult
  func setKeystrokeOverlayVisible(_ visible: Bool) -> Bool {
    guard let keystrokeOverlayView else {
      return false
    }
    keystrokeOverlayView.isHidden = !visible
    updateMouseEventPassthroughAtCurrentPointerLocation()
    return true
  }

  private func setOverlayDragging(_ isDragging: Bool) {
    isDraggingOverlay = isDragging
    updateMouseEventPassthroughAtCurrentPointerLocation()
  }

  private func installPointerMonitors() {
    let mask: NSEvent.EventTypeMask = [
      .mouseMoved,
      .leftMouseDragged,
      .rightMouseDragged,
      .otherMouseDragged
    ]
    localPointerMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
      MainActor.assumeIsolated {
        self?.updateMouseEventPassthroughAtCurrentPointerLocation()
      }
      return event
    }
    globalPointerMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
      Task { @MainActor in
        self?.updateMouseEventPassthroughAtCurrentPointerLocation()
      }
    }
  }

  private func removePointerMonitors() {
    if let localPointerMonitor {
      NSEvent.removeMonitor(localPointerMonitor)
      self.localPointerMonitor = nil
    }
    if let globalPointerMonitor {
      NSEvent.removeMonitor(globalPointerMonitor)
      self.globalPointerMonitor = nil
    }
  }

  private func updateMouseEventPassthroughAtCurrentPointerLocation() {
    updateMouseEventPassthrough(atScreenPoint: NSEvent.mouseLocation)
  }

  private func updateMouseEventPassthrough(atScreenPoint screenPoint: NSPoint) {
    guard let panel = window,
          let container = panel.contentView as? RecordingOverlayContainerView
    else {
      return
    }

    let pointInWindow = panel.convertPoint(fromScreen: screenPoint)
    let shouldCaptureMouse = isDraggingOverlay || container.containsInteractiveOverlay(at: pointInWindow)
    panel.ignoresMouseEvents = !shouldCaptureMouse
  }

  private static func denormalizedFrame(_ normalized: CGRect, in bounds: CGRect) -> CGRect {
    RecordingOverlayFrameGeometry.denormalizedOverlayFrame(normalized, in: bounds)
  }

  private static func denormalizedWebcamFrame(
    _ normalized: CGRect,
    aspectRatio: WebcamAspectRatio,
    in bounds: CGRect
  ) -> CGRect {
    aspectRatio.constrainedFrame(
      denormalizedFrame(normalized, in: bounds),
      in: bounds,
      minimumSize: CGSize(width: 84, height: 84)
    )
  }
}
