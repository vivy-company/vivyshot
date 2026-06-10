import AppKit
import SwiftUI

/// Owns app-level windows that are reachable from multiple features.
@MainActor
final class AppWindowPresenter {
  private let settings: AppSettings
  private let localizer: AppLocalizer
  private let storeManager: StoreManager
  private let statisticsStore: StatisticsStore
  private let welcomeStateStore: WelcomeStateStore
  private let launchAtLoginController: LaunchAtLoginController
  private let paywallWindowController: PaywallWindowController
  private let welcomeWindowController: WelcomeWindowController
  private let statisticsWindowController: StatisticsWindowController
  private let captureTransitionPreviewCoordinator: CaptureTransitionPreviewCoordinator
  private let recordingOverlaySettingsPreviewCoordinator = RecordingOverlaySettingsPreviewCoordinator()
  private var settingsWindowController: NSWindowController?

  init(
    settings: AppSettings,
    localizer: AppLocalizer,
    storeManager: StoreManager,
    statisticsStore: StatisticsStore,
    welcomeStateStore: WelcomeStateStore,
    launchAtLoginController: LaunchAtLoginController,
    toastPresenter: ToastPresenting
  ) {
    self.settings = settings
    self.localizer = localizer
    self.storeManager = storeManager
    self.statisticsStore = statisticsStore
    self.welcomeStateStore = welcomeStateStore
    self.launchAtLoginController = launchAtLoginController
    let paywallWindowController = PaywallWindowController(
      localizer: localizer,
      storeManager: storeManager
    )
    self.paywallWindowController = paywallWindowController
    welcomeWindowController = WelcomeWindowController(
      settings: settings,
      localizer: localizer,
      welcomeStateStore: welcomeStateStore
    )
    statisticsWindowController = StatisticsWindowController(
      localizer: localizer,
      storeManager: storeManager,
      statisticsStore: statisticsStore,
      presentPaywall: {
        paywallWindowController.show()
      }
    )
    captureTransitionPreviewCoordinator = CaptureTransitionPreviewCoordinator(
      settings: settings,
      storeManager: storeManager,
      statisticsStore: statisticsStore,
      toastPresenter: toastPresenter
    )
  }

  var settingsPreviewActions: SettingsPreviewActions {
    SettingsPreviewActions(
      previewCaptureTransition: { [weak self] in
        self?.captureTransitionPreviewCoordinator.preview()
      },
      showRecordingOverlayPreview: { [weak self] kind, settings, onClose in
        self?.recordingOverlaySettingsPreviewCoordinator.show(kind, settings: settings, onClose: onClose)
      },
      closeRecordingOverlayPreview: { [weak self] kind in
        self?.recordingOverlaySettingsPreviewCoordinator.close(kind)
      },
      closeAllRecordingOverlayPreviews: { [weak self] in
        self?.recordingOverlaySettingsPreviewCoordinator.closeAll()
      }
    )
  }

  func presentSettings() {
    if let window = settingsWindowController?.window {
      NSApp.activate(ignoringOtherApps: true)
      window.makeKeyAndOrderFront(nil)
      return
    }

    let rootView = PresentedSettingsView(
      localizer: localizer,
      settings: settings,
      storeManager: storeManager,
      statisticsStore: statisticsStore,
      launchAtLoginController: launchAtLoginController,
      presentPaywall: { [weak self] in
        self?.presentPaywall()
      },
      previewActions: settingsPreviewActions
    )
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 980, height: 720),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.center()
    window.title = "VivyShot Settings"
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView: rootView)
    let controller = NSWindowController(window: window)
    settingsWindowController = controller
    NSApp.activate(ignoringOtherApps: true)
    controller.showWindow(nil)
  }

  func presentPaywall() {
    paywallWindowController.show()
  }

  func dismissPaywall() {
    paywallWindowController.close()
  }

  func presentWelcome(
    onStartCapture: @escaping () -> Void = {},
    onOpenSettings: @escaping () -> Void
  ) {
    welcomeWindowController.show(
      onStartCapture: onStartCapture,
      onOpenSettings: onOpenSettings
    )
  }

  func presentWelcomeIfNeeded(
    onStartCapture: @escaping () -> Void = {},
    onOpenSettings: @escaping () -> Void
  ) {
    guard !welcomeStateStore.hasSeenWelcome else {
      return
    }
    presentWelcome(onStartCapture: onStartCapture, onOpenSettings: onOpenSettings)
  }

  func presentStatistics() {
    statisticsWindowController.show()
  }
}

private struct PresentedSettingsView: View {
  @ObservedObject var localizer: AppLocalizer
  @ObservedObject var settings: AppSettings
  @ObservedObject var storeManager: StoreManager
  let statisticsStore: StatisticsStore
  @ObservedObject var launchAtLoginController: LaunchAtLoginController
  let presentPaywall: () -> Void
  let previewActions: SettingsPreviewActions

  var body: some View {
    SettingsView(
      settings: settings,
      storeManager: storeManager,
      statisticsStore: statisticsStore,
      launchAtLoginController: launchAtLoginController,
      presentPaywall: presentPaywall,
      previewActions: previewActions
    )
    .environment(\.locale, localizer.locale)
  }
}
