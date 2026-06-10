import AppKit
import SwiftUI

/// AppKit lifecycle adapter for menu-bar activation, UI-test presentation, and crash shutdown state.
final class AppDelegate: NSObject, NSApplicationDelegate {
  @MainActor
  var environment: AppEnvironment?
  private var uiTestWindow: NSWindow?

  func applicationDidFinishLaunching(_ notification: Notification) {
    if UITestRuntime.isEnabled {
      NSApp.setActivationPolicy(.regular)
      NSApp.activate(ignoringOtherApps: true)
      DispatchQueue.main.async {
        self.presentUITestHarnessWindowIfNeeded()
      }
    } else {
      NSApp.setActivationPolicy(.accessory)
      DispatchQueue.main.async {
        self.environment?.crashReporter.presentRecoveredCrashNoticeIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
          self.environment?.router.presentWelcomeIfNeeded()
        }
      }
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    environment?.crashReporter.markCleanShutdown()
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  @MainActor
  private func presentUITestHarnessWindowIfNeeded() {
    guard let statusController = environment?.statusController else {
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
