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

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    AppDockPresence.frontTrackedWindows()
    return false
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

enum AppDockPresenceReason: Hashable {
  case postRecordingReview(ObjectIdentifier)
  case postRecordingExportProgress(ObjectIdentifier)
  case settings
  case statistics(ObjectIdentifier)
  case paywall(ObjectIdentifier)
  case welcome(ObjectIdentifier)
}

@MainActor
enum AppDockPresence {
  private final class WeakWindow {
    weak var window: NSWindow?

    init(_ window: NSWindow) {
      self.window = window
    }
  }

  private static var trackedWindows: [AppDockPresenceReason: WeakWindow] = [:]
  private static var closeObservers: [AppDockPresenceReason: NSObjectProtocol] = [:]
  private static var pendingTokens: [AppDockPresenceReason: UUID] = [:]
  private static var activationReasons: Set<AppDockPresenceReason> = []

  static func acquire(_ reason: AppDockPresenceReason) {
    pendingTokens[reason] = nil
    activationReasons.insert(reason)
    applyActivationPolicy()
  }

  static func prepareForWindowPresentation(_ reason: AppDockPresenceReason, timeout: TimeInterval = 1.0) {
    let token = UUID()
    pendingTokens[reason] = token
    applyActivationPolicy()

    DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
      guard pendingTokens[reason] == token else {
        return
      }
      pendingTokens[reason] = nil
      applyActivationPolicy()
    }
  }

  static func track(_ reason: AppDockPresenceReason, window: NSWindow) {
    pendingTokens[reason] = nil
    activationReasons.insert(reason)
    trackedWindows[reason] = WeakWindow(window)
    observeClose(of: window, reason: reason)
    applyActivationPolicy()
  }

  static func release(_ reason: AppDockPresenceReason) {
    pendingTokens[reason] = nil
    activationReasons.remove(reason)
    trackedWindows[reason] = nil
    removeCloseObserver(for: reason)
    applyActivationPolicy()
  }

  @discardableResult
  static func frontTrackedWindows() -> Bool {
    pruneReleasedWindows()
    let windows = trackedWindows.values.compactMap(\.window)
    guard !windows.isEmpty else {
      applyActivationPolicy()
      return false
    }

    NSApp.setActivationPolicy(.regular)
    for window in windows {
      window.deminiaturize(nil)
      window.makeKeyAndOrderFront(nil)
    }
    NSApp.activate(ignoringOtherApps: true)
    return true
  }

  private static func observeClose(of window: NSWindow, reason: AppDockPresenceReason) {
    removeCloseObserver(for: reason)
    closeObservers[reason] = NotificationCenter.default.addObserver(
      forName: NSWindow.willCloseNotification,
      object: window,
      queue: .main
    ) { _ in
      Task { @MainActor in
        release(reason)
      }
    }
  }

  private static func removeCloseObserver(for reason: AppDockPresenceReason) {
    guard let observer = closeObservers.removeValue(forKey: reason) else {
      return
    }
    NotificationCenter.default.removeObserver(observer)
  }

  private static func pruneReleasedWindows() {
    let releasedReasons = trackedWindows.compactMap { reason, weakWindow in
      weakWindow.window == nil ? reason : nil
    }
    for reason in releasedReasons {
      trackedWindows[reason] = nil
      activationReasons.remove(reason)
      removeCloseObserver(for: reason)
    }
  }

  private static func applyActivationPolicy() {
    if UITestRuntime.isEnabled {
      NSApp.setActivationPolicy(.regular)
      return
    }

    pruneReleasedWindows()
    if trackedWindows.isEmpty && pendingTokens.isEmpty && activationReasons.isEmpty {
      NSApp.setActivationPolicy(.accessory)
    } else {
      NSApp.setActivationPolicy(.regular)
    }
  }
}
