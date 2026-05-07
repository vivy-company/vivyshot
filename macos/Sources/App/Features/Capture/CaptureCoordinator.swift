import AppKit
import ApplicationServices
import AVFoundation
import AVKit
import Carbon
import CoreGraphics
import CoreMedia
import ImageIO
import QuartzCore
import ScreenCaptureKit
import SwiftUI
import UniformTypeIdentifiers

private func releaseDetachedPixelBuffer(
  _ info: UnsafeMutableRawPointer?,
  _ data: UnsafeRawPointer,
  _ size: Int
) {
  free(UnsafeMutableRawPointer(mutating: data))
}

@MainActor
final class CaptureCoordinator: CaptureCoordinating {
  private let settings: AppSettings
  private let selectionOverlay: RegionSelectionOverlayController
  private let videoCaptureCoordinator: VideoCaptureCoordinator

  var onRecordingStateChanged: ((Bool) -> Void)? {
    didSet {
      onRecordingStateChanged?(videoCaptureCoordinator.isRecordingActive)
    }
  }

  private var captureInProgress = false
  private var requestedScreenPermissionThisSession = false
  private var showingScreenPermissionAlert = false

  init(settings: AppSettings = .shared) {
    self.settings = settings
    selectionOverlay = RegionSelectionOverlayController(settings: settings)
    videoCaptureCoordinator = VideoCaptureCoordinator(settings: settings)
    videoCaptureCoordinator.onRecordingStateChanged = { [weak self] isRecording in
      self?.onRecordingStateChanged?(isRecording)
    }
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
            onStartVideo: { [weak self] rect, overlayState, completion in
              guard let self else {
                completion(false)
                return
              }
              var started = false
              self.videoCaptureCoordinator.startRecording(
                selectionRectInScreen: rect,
                overlayState: overlayState,
                showFloatingHUD: true,
                onStarted: { [weak self] in
                  started = true
                  // Close the frozen selection overlay once recording is live so
                  // the user can interact with the captured app region directly.
                  self?.selectionOverlay.closeFlow()
                  completion(true)
                },
                onDone: { [weak self] in
                  self?.captureInProgress = false
                },
                onError: { [weak self] message in
                  if !started {
                    completion(false)
                  } else {
                    self?.captureInProgress = false
                  }
                  self?.showCaptureError(message)
                }
              )
            },
            onStopVideo: { [weak self] in
              self?.videoCaptureCoordinator.stopRecordingFromInlineToolbar()
            },
            onDone: { [weak self] in
              self?.captureInProgress = false
            }
          )
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
        domain: "com.vivyshot.capture",
        code: -10,
        userInfo: [NSLocalizedDescriptionKey: "Screen capture requires macOS 15.2 or newer."]
      )
    }

    return try await withCheckedThrowingContinuation { continuation in
      let captureRect: CGRect
      if let primaryHeight = NSScreen.screens.first?.frame.height {
        captureRect = CGRect(
          x: rect.origin.x,
          y: primaryHeight - rect.maxY,
          width: rect.width,
          height: rect.height
        )
      } else {
        captureRect = rect
      }

      SCScreenshotManager.captureImage(in: captureRect) { image, error in
        if let error {
          continuation.resume(throwing: error)
          return
        }

        guard let image else {
          continuation.resume(
            throwing: NSError(
              domain: "com.vivyshot.capture",
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

    if alert.runModal() == .alertFirstButtonReturn,
       let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
      NSWorkspace.shared.open(url)
    }

    return false
  }

  private func showCaptureError(_ message: String) {
    if captureInProgress {
      TransientToast.show(message, duration: 3.0)
    } else {
      let alert = NSAlert()
      alert.messageText = "Capture Failed"
      alert.informativeText = message
      alert.alertStyle = .critical
      alert.addButton(withTitle: "OK")
      alert.runModal()
    }
  }

  func stopActiveRecordingFromStatusItem() {
    videoCaptureCoordinator.stopRecordingFromStatusBar()
  }

  var isVideoRecordingActive: Bool {
    videoCaptureCoordinator.isRecordingActive
  }
}
