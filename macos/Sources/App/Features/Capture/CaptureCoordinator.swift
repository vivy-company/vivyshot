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

@MainActor
final class CaptureCoordinator {
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
        let frozenImage = try await self.captureFrozenImage(in: screenFrame)
        self.selectionOverlay.beginSelection(onScreenFrame: screenFrame, frozenImage: frozenImage) { [weak self] result in
          guard let self else {
            return
          }

          guard let result else {
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
            selectionRectInScreen: result.selectionRectInScreen,
            initialCaptureType: result.captureType,
            onStartVideo: { [weak self] rect, completion in
              guard let self else {
                completion(false)
                return
              }
              var started = false
              self.videoCaptureCoordinator.startRecording(
                selectionRectInScreen: rect,
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
