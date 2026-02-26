import AppKit



@MainActor
final class StatusItemController: NSObject {
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private let settings = AppSettings.shared
  private lazy var captureCoordinator = CaptureCoordinator(settings: settings)
  private let hotKeyManager = GlobalHotKeyManager()
  private var settingsWindowController: SettingsWindowController?
  private var settingsObserver: NSObjectProtocol?

  override init() {
    super.init()
    configureMenu()
    configureHotKey()
    observeSettingsChanges()
  }

  private func configureMenu() {
    if let button = statusItem.button {
      button.title = "VS"
      button.toolTip = "VivyShot"
      button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "VivyShot")
      button.imagePosition = .imageLeading
    }

    let menu = NSMenu()
    let captureItem = NSMenuItem(
      title: "Capture Region",
      action: #selector(capturePressed),
      keyEquivalent: "c"
    )
    captureItem.keyEquivalentModifierMask = [.command]
    captureItem.target = self
    menu.addItem(captureItem)
    menu.addItem(.separator())
    let settingsItem = NSMenuItem(
      title: "Settings…",
      action: #selector(settingsPressed),
      keyEquivalent: ","
    )
    settingsItem.keyEquivalentModifierMask = [.command]
    settingsItem.target = self
    menu.addItem(settingsItem)
    menu.addItem(.separator())
    let quitItem = menu.addItem(
      withTitle: "Quit VivyShot",
      action: #selector(quitPressed),
      keyEquivalent: "q"
    )
    quitItem.target = self
    statusItem.menu = menu
  }

  private func configureHotKey() {
    hotKeyManager.onTrigger = { [weak self] in
      self?.captureCoordinator.startRegionCapture()
    }

    applyHotKeyFromSettings()
  }

  private func observeSettingsChanges() {
    settingsObserver = NotificationCenter.default.addObserver(
      forName: .vivyShotSettingsDidChange,
      object: settings,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.applyHotKeyFromSettings()
      }
    }
  }

  private func applyHotKeyFromSettings() {
    _ = hotKeyManager.registerHotKey(
      keyCode: settings.captureKeyCode,
      modifiers: settings.captureModifierFlags
    )
  }

  @objc
  private func capturePressed() {
    captureCoordinator.startRegionCapture()
  }

  @objc
  private func settingsPressed() {
    if settingsWindowController == nil {
      settingsWindowController = SettingsWindowController(settings: settings)
    }
    settingsWindowController?.present()
  }

  @objc
  private func quitPressed() {
    NSApplication.shared.terminate(nil)
  }
}
