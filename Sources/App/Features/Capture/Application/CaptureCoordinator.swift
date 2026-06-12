import AppKit
import ApplicationServices
import AVFoundation
import AVKit
import Carbon
import CoreGraphics
import CoreMedia
import ImageIO
import QuartzCore
import UniformTypeIdentifiers

private func releaseDetachedPixelBuffer(
  _: UnsafeMutableRawPointer?,
  _ data: UnsafeRawPointer,
  _: Int
) {
  free(UnsafeMutableRawPointer(mutating: data))
}

/// App-facing coordinator for screenshot capture, region selection, and recording startup.
@MainActor
final class CaptureCoordinator: CaptureCoordinating, RecordingStateObserving {
  private let settings: AppSettings
  private let toastPresenter: ToastPresenting
  private let selectionOverlay: RegionSelectionOverlayController
  private let recordingCoordinator: RecordingCoordinator

  weak var recordingStateObserver: (any RecordingStateObserving)? {
    didSet {
      recordingStateObserver?.recordingStateDidChange(isRecording: recordingCoordinator.isRecordingActive)
    }
  }

  private var captureInProgress = false
  private var requestedScreenPermissionThisSession = false
  private var showingScreenPermissionAlert = false

  init(
    settings: AppSettings,
    storeManager: StoreManager,
    proExportTrialStore: ProExportTrialStore,
    statisticsStore: StatisticsStore,
    toastPresenter: ToastPresenting,
    presentPaywall: @escaping () -> Void = {}
  ) {
    self.settings = settings
    self.toastPresenter = toastPresenter
    selectionOverlay = RegionSelectionOverlayController(
      settings: settings,
      storeManager: storeManager,
      statisticsStore: statisticsStore,
      toastPresenter: toastPresenter
    )
    recordingCoordinator = RecordingCoordinator(
      settings: settings,
      storeManager: storeManager,
      proExportTrialStore: proExportTrialStore,
      statisticsStore: statisticsStore,
      toastPresenter: toastPresenter,
      presentPaywall: presentPaywall
    )
    recordingCoordinator.recordingStateObserver = self
  }

  func startRegionCapture() {
    guard !captureInProgress else {
      return
    }

    guard ensureScreenCapturePermission() else {
      return
    }

    guard let screen = activeScreenForCapture() else {
      showCaptureError("No active display found.")
      return
    }
    let screenFrame = screen.frame

    captureInProgress = true
    Task { [weak self] in
      guard let self else {
        return
      }

      do {
        let capturedImage = try await self.captureFrozenImage(in: screenFrame)
        let frozenImage = self.detachedImageCopy(capturedImage) ?? capturedImage
        self.selectionOverlay.beginSelection(onScreenFrame: screenFrame, frozenImage: frozenImage) { [weak self] result in
          guard let self else {
            return
          }

          guard let result else {
            self.captureInProgress = false
            return
          }

          self.selectionOverlay.enterEditing(
            session: nil,
            selectionRectInScreen: result.selectionRectInScreen,
            initialCaptureType: result.captureType,
            initialCaptureMode: result.captureMode,
            recordingController: self.recordingCoordinator,
            delegate: self
          )
        }
      } catch {
        self.captureInProgress = false
        self.showCaptureError("Failed to capture screen: \(error.localizedDescription)")
      }
    }
  }

  private func activeScreenForCapture() -> NSScreen? {
    DisplayCoordinateConversion.activeScreen(containing: NSEvent.mouseLocation)
  }

  private func captureFrozenImage(in rect: CGRect) async throws -> CGImage {
    try await ScreenCaptureSnapshot.captureImage(inCocoaScreenRect: rect)
  }

  // Build a plain BGRA-backed copy so we can drop ScreenCaptureKit surface-backed storage promptly.
  private func detachedImageCopy(_ image: CGImage) -> CGImage? {
    let width = image.width
    let height = image.height
    guard width > 0, height > 0 else {
      return nil
    }

    let stride = width * 4
    let byteCount = stride * height
    guard let pixelBuffer = malloc(byteCount) else {
      return nil
    }

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue

    let didDraw: Bool = {
      guard let context = CGContext(
        data: pixelBuffer,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: stride,
        space: colorSpace,
        bitmapInfo: bitmapInfo
      ) else {
        return false
      }
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }()

    guard didDraw else {
      free(pixelBuffer)
      return nil
    }

    guard let provider = CGDataProvider(
      dataInfo: nil,
      data: pixelBuffer,
      size: byteCount,
      releaseData: releaseDetachedPixelBuffer
    ) else {
      free(pixelBuffer)
      return nil
    }

    return CGImage(
      width: width,
      height: height,
      bitsPerComponent: 8,
      bitsPerPixel: 32,
      bytesPerRow: stride,
      space: colorSpace,
      bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
      provider: provider,
      decode: nil,
      shouldInterpolate: false,
      intent: .defaultIntent
    )
  }

  private func ensureScreenCapturePermission() -> Bool {
    if ScreenRecordingPermission.isGranted {
      return true
    }

    if !requestedScreenPermissionThisSession {
      requestedScreenPermissionThisSession = true
      _ = ScreenRecordingPermission.requestAccess()
    }

    if ScreenRecordingPermission.isGranted {
      return true
    }

    if showingScreenPermissionAlert {
      return false
    }
    showingScreenPermissionAlert = true
    defer {
      showingScreenPermissionAlert = false
    }

    NSApp.activate(ignoringOtherApps: true)
    let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
      ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
      ?? "VivyShot"

    let alert = NSAlert()
    alert.messageText = "Screen Recording Permission Needed"
    alert.informativeText = "Enable Screen Recording for \(appName) in System Settings > Privacy & Security > Screen Recording."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Open Settings")
    alert.addButton(withTitle: "Cancel")

    if alert.runModal() == .alertFirstButtonReturn {
      ScreenRecordingPermission.openSystemSettings()
    }

    return false
  }

  private func showCaptureError(_ message: String) {
    if captureInProgress {
      toastPresenter.show(message, duration: 3.0)
    } else {
      NSApp.activate(ignoringOtherApps: true)
      let alert = NSAlert()
      alert.messageText = "Capture Failed"
      alert.informativeText = message
      alert.alertStyle = .critical
      alert.addButton(withTitle: "OK")
      alert.runModal()
    }
  }

  func stopActiveRecordingFromStatusItem() {
    recordingCoordinator.stopRecordingFromStatusBar()
  }

  var isVideoRecordingActive: Bool {
    recordingCoordinator.isRecordingActive
  }

  func recordingStateDidChange(isRecording: Bool) {
    recordingStateObserver?.recordingStateDidChange(isRecording: isRecording)
  }
}

extension CaptureCoordinator: RegionSelectionOverlayEditingDelegate {
  func regionSelectionOverlayWillStartRecordingWebcamCapture(_: RegionSelectionOverlayController) async {
    await selectionOverlay.stopVideoWebcamPreviewForRecordingStart()
  }

  func regionSelectionOverlayDidFinishRecordingFlow(_: RegionSelectionOverlayController) {
    selectionOverlay.closeFlow(animated: false)
    captureInProgress = false
  }

  func regionSelectionOverlay(_: RegionSelectionOverlayController, didFailRecordingWithMessage message: String) {
    showCaptureError(message)
  }

  func regionSelectionOverlayDidFinishEditing(_: RegionSelectionOverlayController) {
    captureInProgress = false
  }
}
