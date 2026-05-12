import AppKit



@MainActor
final class StatusItemController: ObservableObject {
  private let settings: AppSettings
  private let captureCoordinator: CaptureCoordinating
  private let hotKeyManager = GlobalHotKeyManager()
  private var settingsObserver: NSObjectProtocol?
  @Published private(set) var isRecordingActive = false

  init(
    settings: AppSettings = .shared,
    captureCoordinatorFactory: ((AppSettings) -> CaptureCoordinating)? = nil
  ) {
    self.settings = settings
    self.captureCoordinator = captureCoordinatorFactory?(settings) ?? CaptureCoordinator(settings: settings)
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
    settingsObserver = NotificationCenter.default.addObserver(
      forName: .vivyShotSettingsDidChange,
      object: settings,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.applyHotKeyFromSettings()
      }
    }
  }

  private func observeRecordingState() {
    captureCoordinator.onRecordingStateChanged = { [weak self] isRecording in
      self?.isRecordingActive = isRecording
    }
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
