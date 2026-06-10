@MainActor
enum RecordingToolEntitlements {
  static func lockedTools(storeManager: StoreManager) -> Set<RecordingTool> {
    var tools = Set<RecordingTool>()
    if !storeManager.canUse(.microphoneAudioExport) {
      tools.insert(.microphone)
    }
    if !storeManager.canUse(.webcamOverlay) {
      tools.insert(.webcam)
    }
    if !storeManager.canUse(.keystrokeOverlay) {
      tools.insert(.keystrokes)
    }
    return tools
  }
}
