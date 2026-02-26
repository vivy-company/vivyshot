import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
  private var statusItemController: StatusItemController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    if hasOtherRunningInstance() {
      NSApp.terminate(nil)
      return
    }

    NSApp.setActivationPolicy(.accessory)
    statusItemController = StatusItemController()
  }

  private func hasOtherRunningInstance() -> Bool {
    guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
      return false
    }

    let currentPID = ProcessInfo.processInfo.processIdentifier
    let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
      .filter { app in
        app.processIdentifier != currentPID && !app.isTerminated
      }

    return !others.isEmpty
  }
}
