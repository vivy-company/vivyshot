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
  private let paywallWindowController: PaywallWindowController
  private let welcomeWindowController: WelcomeWindowController
  private let statisticsWindowController: StatisticsWindowController
  private let captureTransitionPreviewCoordinator: CaptureTransitionPreviewCoordinator
  private let recordingOverlaySettingsPreviewCoordinator = RecordingOverlaySettingsPreviewCoordinator()

  init(
    settings: AppSettings,
    localizer: AppLocalizer,
    storeManager: StoreManager,
    statisticsStore: StatisticsStore,
    welcomeStateStore: WelcomeStateStore,
    toastPresenter: ToastPresenting
  ) {
    self.settings = settings
    self.localizer = localizer
    self.storeManager = storeManager
    self.statisticsStore = statisticsStore
    self.welcomeStateStore = welcomeStateStore
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

  func presentPaywall() {
    paywallWindowController.show()
  }

  func dismissPaywall() {
    paywallWindowController.close()
  }

  func presentWelcome(
    onStartCapture: @escaping () -> Void = {}
  ) {
    welcomeWindowController.show(
      onStartCapture: onStartCapture
    )
  }

  func presentWelcomeIfNeeded(
    onStartCapture: @escaping () -> Void = {}
  ) {
    guard !welcomeStateStore.hasSeenWelcome else {
      return
    }
    presentWelcome(onStartCapture: onStartCapture)
  }

  func presentStatistics() {
    statisticsWindowController.show()
  }
}
