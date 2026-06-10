import AppKit
import ApplicationServices
import Foundation

enum ScreenRecordingPermission {
  static var isGranted: Bool {
    CGPreflightScreenCaptureAccess()
  }

  @discardableResult
  static func requestAccess() -> Bool {
    if isGranted {
      return true
    }
    _ = CGRequestScreenCaptureAccess()
    return isGranted
  }

  @MainActor
  static func openSystemSettings() {
    guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
      return
    }
    NSWorkspace.shared.open(url)
    NSApp.activate(ignoringOtherApps: true)
  }
}
