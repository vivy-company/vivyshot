import ApplicationServices
import Foundation

enum AccessibilityPermission {
  static func isTrusted(promptIfNeeded: Bool) -> Bool {
    if promptIfNeeded {
      let options = ["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary
      return AXIsProcessTrustedWithOptions(options)
    }
    return AXIsProcessTrusted()
  }
}
