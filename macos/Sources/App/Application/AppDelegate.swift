import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    if UITestRuntime.isEnabled {
      NSApp.setActivationPolicy(.regular)
      NSApp.activate(ignoringOtherApps: true)
      DispatchQueue.main.async {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
      }
    } else {
      NSApp.setActivationPolicy(.accessory)
    }
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }
}
