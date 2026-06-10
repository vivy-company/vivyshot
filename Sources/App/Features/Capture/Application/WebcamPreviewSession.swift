import AVFoundation
import Foundation

@MainActor
final class WebcamPreviewSession {
  private var session: AVCaptureSession?
  private var sessionRunner: CaptureSessionRunner?
  private(set) var previewLayer: AVCaptureVideoPreviewLayer?
  private var deviceID: String?
  private var accessRequestActive = false

  var isShowingPreview: Bool {
    previewLayer != nil
  }

  func update(
    preferredDeviceID: String,
    attachPreviewLayer: @escaping (AVCaptureVideoPreviewLayer) -> Void
  ) {
    guard session == nil || deviceID != preferredDeviceID else {
      return
    }
    stopDetached()

    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      configure(preferredDeviceID: preferredDeviceID, attachPreviewLayer: attachPreviewLayer)
    case .notDetermined:
      guard !accessRequestActive else {
        return
      }
      accessRequestActive = true
      Task { @MainActor [weak self] in
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        guard let self else {
          return
        }
        self.accessRequestActive = false
        if granted {
          self.configure(preferredDeviceID: preferredDeviceID, attachPreviewLayer: attachPreviewLayer)
        }
      }
    case .denied, .restricted:
      return
    @unknown default:
      return
    }
  }

  func stopDetached() {
    let runner = clear()
    runner?.stopDetached()
  }

  func stop() async {
    let runner = clear()
    if let runner {
      await runner.stop()
    }
  }

  private func clear() -> CaptureSessionRunner? {
    previewLayer?.removeFromSuperlayer()
    previewLayer = nil
    let runner = sessionRunner
    session = nil
    sessionRunner = nil
    deviceID = nil
    return runner
  }

  private func configure(
    preferredDeviceID: String,
    attachPreviewLayer: (AVCaptureVideoPreviewLayer) -> Void
  ) {
    let devices = AVCaptureDevice.DiscoverySession(
      deviceTypes: RecordingSourceProvider.webcamDeviceTypes,
      mediaType: .video,
      position: .unspecified
    ).devices
    let selectedDevice = devices.first { $0.uniqueID == preferredDeviceID }
    guard let device = selectedDevice ?? AVCaptureDevice.default(for: .video) ?? devices.first,
          let input = try? AVCaptureDeviceInput(device: device)
    else {
      return
    }

    let session = AVCaptureSession()
    session.beginConfiguration()
    session.sessionPreset = .medium
    if session.canAddInput(input) {
      session.addInput(input)
    }
    session.commitConfiguration()
    guard !session.inputs.isEmpty else {
      return
    }

    let layer = AVCaptureVideoPreviewLayer(session: session)
    layer.videoGravity = .resizeAspectFill
    let runner = CaptureSessionRunner(
      session: session,
      label: "com.vivyshot.webcam-placement-preview.session"
    )
    attachPreviewLayer(layer)
    self.session = session
    sessionRunner = runner
    previewLayer = layer
    deviceID = preferredDeviceID
    runner.startDetached()
  }
}
