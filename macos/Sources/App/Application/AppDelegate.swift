import AppKit
import Darwin
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
  private var uiTestWindow: NSWindow?

  func applicationDidFinishLaunching(_ notification: Notification) {
    if CaptureBackendSmokeRuntime.isEnabled {
      NSApp.setActivationPolicy(.regular)
      NSApp.activate(ignoringOtherApps: true)
      Task { @MainActor in
        let exitCode = await CaptureBackendSmokeRuntime.runAndPrint()
        NSApp.terminate(nil)
        exit(exitCode)
      }
      return
    }

    if UITestRuntime.isEnabled {
      NSApp.setActivationPolicy(.regular)
      NSApp.activate(ignoringOtherApps: true)
      DispatchQueue.main.async {
        self.presentUITestHarnessWindowIfNeeded()
      }
    } else {
      NSApp.setActivationPolicy(.accessory)
      DispatchQueue.main.async {
        CrashReporter.shared.presentRecoveredCrashNoticeIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
          presentWelcomeWindowIfNeeded(
            onStartCapture: {
              VivyShotRuntime.statusController?.startCapturePressed()
            },
            onOpenSettings: {
              presentSettingsWindow()
            }
          )
        }
      }
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    CrashReporter.shared.markCleanShutdown()
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  @MainActor
  private func presentUITestHarnessWindowIfNeeded() {
    guard let statusController = UITestRuntime.statusController else {
      return
    }

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 420, height: 220),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.center()
    window.title = "VivyShot UI Test Harness"
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView: UITestHarnessView(statusController: statusController))
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    uiTestWindow = window
  }
}
