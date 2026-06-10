import AppKit
import Combine

/// Menu-bar controller that connects the global shortcut, capture coordinator, and menu actions.
@MainActor
final class StatusItemController: ObservableObject {
  private let settings: AppSettings
  private let captureCoordinator: CaptureCoordinating
  private let hotKeyManager = GlobalHotKeyManager()
  private var settingsChangeCancellable: AnyCancellable?
  @Published private(set) var isRecordingActive = false

  init(
    settings: AppSettings,
    captureCoordinator: CaptureCoordinating
  ) {
    self.settings = settings
    self.captureCoordinator = captureCoordinator
    configureHotKey()
    observeSettingsChanges()
    observeRecordingState()
  }

  private func configureHotKey() {
    hotKeyManager.onTrigger = { [weak self] in
      guard let self else { return }
      if self.captureCoordinator.isVideoRecordingActive {
        self.captureCoordinator.stopActiveRecordingFromStatusItem()
      } else {
        self.captureCoordinator.startRegionCapture()
      }
    }

    applyHotKeyFromSettings()
  }

  private func observeSettingsChanges() {
    settingsChangeCancellable = settings.captureShortcutChanges
      .sink { [weak self] in
        self?.applyHotKeyFromSettings()
      }
  }

  private func observeRecordingState() {
    captureCoordinator.recordingStateObserver = self
  }

  private func applyHotKeyFromSettings() {
    let registered = hotKeyManager.registerHotKey(
      keyCode: settings.captureKeyCode,
      modifiers: settings.captureModifierFlags
    )
    if registered {
      return
    }

    NSLog("[VivyShot] Failed to register configured capture shortcut. Falling back to default.")
    let fallbackRegistered = hotKeyManager.registerDefaultHotKey()
    if fallbackRegistered {
      settings.resetCaptureShortcut()
    }
  }

  func captureOrStopPressed() {
    if captureCoordinator.isVideoRecordingActive {
      captureCoordinator.stopActiveRecordingFromStatusItem()
    } else {
      captureCoordinator.startRegionCapture()
    }
  }

  func startCapturePressed() {
    guard !captureCoordinator.isVideoRecordingActive else {
      return
    }
    captureCoordinator.startRegionCapture()
  }

  func quitPressed() {
    NSApplication.shared.terminate(nil)
  }
}

extension StatusItemController: RecordingStateObserving {
  func recordingStateDidChange(isRecording: Bool) {
    isRecordingActive = isRecording
  }
}
