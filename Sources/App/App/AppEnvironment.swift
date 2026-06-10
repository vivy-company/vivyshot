import AppKit
import Combine
import SwiftUI

/// Objects composed once at app launch and passed through the app shell.
@MainActor
final class AppEnvironment: ObservableObject {
  let settings: AppSettings
  let localizer: AppLocalizer
  let storeManager: StoreManager
  let proExportTrialStore: ProExportTrialStore
  let statisticsStore: StatisticsStore
  let welcomeStateStore: WelcomeStateStore
  let launchAtLoginController: LaunchAtLoginController
  let crashReporter: CrashReporting
  let toastPresenter: ToastPresenting
  let statusController: StatusItemController
  let windowPresenter: AppWindowPresenter
  let router: AppRouter
  private var appLanguageCancellable: AnyCancellable?

  static func live(isUITestMode: Bool = UITestRuntime.isEnabled) -> AppEnvironment {
    let localizer = AppLocalizer.shared
    return AppEnvironment(
      settings: AppSettings(),
      localizer: localizer,
      storeManager: StoreManager(localizer: localizer),
      proExportTrialStore: ProExportTrialStore(),
      statisticsStore: StatisticsStore(),
      welcomeStateStore: WelcomeStateStore(),
      launchAtLoginController: LaunchAtLoginController(localizer: localizer),
      crashReporter: CrashReporter(),
      toastPresenter: TransientToastPresenter(),
      isUITestMode: isUITestMode
    )
  }

  init(
    settings: AppSettings,
    localizer: AppLocalizer,
    storeManager: StoreManager,
    proExportTrialStore: ProExportTrialStore,
    statisticsStore: StatisticsStore,
    welcomeStateStore: WelcomeStateStore,
    launchAtLoginController: LaunchAtLoginController,
    crashReporter: CrashReporting,
    toastPresenter: ToastPresenting,
    isUITestMode: Bool
  ) {
    self.settings = settings
    self.localizer = localizer
    self.storeManager = storeManager
    self.proExportTrialStore = proExportTrialStore
    self.statisticsStore = statisticsStore
    self.welcomeStateStore = welcomeStateStore
    self.launchAtLoginController = launchAtLoginController
    self.crashReporter = crashReporter
    self.toastPresenter = toastPresenter
    windowPresenter = AppWindowPresenter(
      settings: settings,
      localizer: localizer,
      storeManager: storeManager,
      statisticsStore: statisticsStore,
      welcomeStateStore: welcomeStateStore,
      launchAtLoginController: launchAtLoginController,
      toastPresenter: toastPresenter
    )
    let presentPaywall = { [windowPresenter] in
      windowPresenter.presentPaywall()
    }
    if isUITestMode {
      statusController = StatusItemController(
        settings: settings,
        captureCoordinator: UITestCaptureCoordinator()
      )
    } else {
      statusController = StatusItemController(
        settings: settings,
        captureCoordinator: CaptureCoordinator(
          settings: settings,
          storeManager: storeManager,
          proExportTrialStore: proExportTrialStore,
          statisticsStore: statisticsStore,
          toastPresenter: toastPresenter,
          presentPaywall: presentPaywall
        )
      )
    }
    router = AppRouter(
      statusController: statusController,
      windowPresenter: windowPresenter
    )
    configureLocalization()
  }

  private func configureLocalization() {
    localizer.update(language: settings.appLanguage)
    appLanguageCancellable = settings.appLanguageChanges
      .sink { [weak self] in
        guard let self else { return }
        self.localizer.update(language: self.settings.appLanguage)
      }
  }
}

/// Cross-feature navigation owned by the app shell.
@MainActor
final class AppRouter {
  private unowned let statusController: StatusItemController
  private unowned let windowPresenter: AppWindowPresenter

  init(
    statusController: StatusItemController,
    windowPresenter: AppWindowPresenter
  ) {
    self.statusController = statusController
    self.windowPresenter = windowPresenter
  }

  func startCapture() {
    statusController.startCapturePressed()
  }

  func captureOrStop() {
    statusController.captureOrStopPressed()
  }

  func quit() {
    statusController.quitPressed()
  }

  func presentPaywall() {
    windowPresenter.presentPaywall()
  }

  func presentWelcome() {
    windowPresenter.presentWelcome(
      onStartCapture: { [weak self] in self?.startCapture() },
      onOpenSettings: { [weak self] in self?.presentSettings() }
    )
  }

  func presentWelcomeIfNeeded() {
    windowPresenter.presentWelcomeIfNeeded(
      onStartCapture: { [weak self] in self?.startCapture() },
      onOpenSettings: { [weak self] in self?.presentSettings() }
    )
  }

  func presentStatistics() {
    windowPresenter.presentStatistics()
  }

  func presentSettings() {
    windowPresenter.presentSettings()
  }
}
