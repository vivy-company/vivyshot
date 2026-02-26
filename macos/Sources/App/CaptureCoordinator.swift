import AppKit
import CoreGraphics
import ScreenCaptureKit

@MainActor
final class CaptureCoordinator {
  private let selectionOverlay: RegionSelectionOverlayController

  private var captureInProgress = false
  private var requestedScreenPermissionThisSession = false
  private var showedPermissionHintThisSession = false

  init(settings: AppSettings = .shared) {
    selectionOverlay = RegionSelectionOverlayController(settings: settings)
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
        let frozenImage = try await self.captureFrozenImage(in: screenFrame)
        self.selectionOverlay.beginSelection(onScreenFrame: screenFrame, frozenImage: frozenImage) { [weak self] selectionRectInScreen in
          guard let self else {
            return
          }

          guard let selectionRectInScreen else {
            self.captureInProgress = false
            return
          }

          guard let session = RustCoreBridge.shared.makeSession(image: frozenImage) else {
            self.captureInProgress = false
            self.selectionOverlay.closeFlow()
            self.showCaptureError("Failed to initialize Rust editor session.")
            return
          }

          self.selectionOverlay.enterEditing(
            session: session,
            selectionRectInScreen: selectionRectInScreen
          ) { [weak self] in
            self?.captureInProgress = false
          }
        }
      } catch {
        self.captureInProgress = false
        self.showCaptureError("Failed to capture screen: \(error.localizedDescription)")
      }
    }
  }

  private func activeScreenForCapture() -> NSScreen? {
    let mouse = NSEvent.mouseLocation
    return NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main ?? NSScreen.screens.first
  }

  private func captureFrozenImage(in rect: CGRect) async throws -> CGImage {
    guard #available(macOS 15.2, *) else {
      throw NSError(
        domain: "com.vivy.vivyshot.capture",
        code: -10,
        userInfo: [NSLocalizedDescriptionKey: "Screen capture requires macOS 15.2 or newer."]
      )
    }

    return try await withCheckedThrowingContinuation { continuation in
      SCScreenshotManager.captureImage(in: rect) { image, error in
        if let error {
          continuation.resume(throwing: error)
          return
        }

        guard let image else {
          continuation.resume(
            throwing: NSError(
              domain: "com.vivy.vivyshot.capture",
              code: -11,
              userInfo: [NSLocalizedDescriptionKey: "No image returned by ScreenCaptureKit."]
            )
          )
          return
        }

        continuation.resume(returning: image)
      }
    }
  }

  private func cropFrozenImage(
    _ image: CGImage,
    selectionRectInScreen: CGRect,
    screenFrame: CGRect
  ) -> CGImage? {
    let normalizedSelection = selectionRectInScreen.standardized
    let clippedSelection = normalizedSelection.intersection(screenFrame)
    guard !clippedSelection.isNull, clippedSelection.width >= 2, clippedSelection.height >= 2 else {
      return nil
    }

    let localRect = clippedSelection.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
    let scaleX = CGFloat(image.width) / screenFrame.width
    let scaleY = CGFloat(image.height) / screenFrame.height

    let x = localRect.minX * scaleX
    let yTop = CGFloat(image.height) - (localRect.maxY * scaleY)
    let width = localRect.width * scaleX
    let height = localRect.height * scaleY

    var cropRect = CGRect(
      x: floor(x),
      y: floor(yTop),
      width: ceil(width),
      height: ceil(height)
    )

    let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    cropRect = cropRect.intersection(imageBounds)

    guard !cropRect.isNull, cropRect.width >= 2, cropRect.height >= 2 else {
      return nil
    }

    return image.cropping(to: cropRect.integral)
  }

  private func ensureScreenCapturePermission() -> Bool {
    if CGPreflightScreenCaptureAccess() {
      return true
    }

    if !requestedScreenPermissionThisSession {
      requestedScreenPermissionThisSession = true
      _ = CGRequestScreenCaptureAccess()
    }

    if CGPreflightScreenCaptureAccess() {
      return true
    }

    if showedPermissionHintThisSession {
      return false
    }
    showedPermissionHintThisSession = true

    let alert = NSAlert()
    alert.messageText = "Screen Recording Permission Needed"
    alert.informativeText = "Enable Screen Recording for VivyShotDev in System Settings > Privacy & Security > Screen Recording."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Open Settings")
    alert.addButton(withTitle: "Cancel")

    if alert.runModal() == .alertFirstButtonReturn,
       let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
      NSWorkspace.shared.open(url)
    }

    return false
  }

  private func showCaptureError(_ message: String) {
    let alert = NSAlert()
    alert.messageText = "Capture Failed"
    alert.informativeText = message
    alert.alertStyle = .critical
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }
}
