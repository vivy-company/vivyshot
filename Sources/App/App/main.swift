import SwiftUI

/// Shared state for deterministic UI-test launches.
enum UITestRuntime {
  static let launchFlag = "--uitest-mode"

  static var isEnabled: Bool {
    ProcessInfo.processInfo.arguments.contains(launchFlag)
  }
}

/// SwiftUI application entry point and menu-bar scene composition.
struct AppRoot: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @StateObject private var localizer: AppLocalizer
  @StateObject private var environment: AppEnvironment

  init() {
    let environment = AppEnvironment.live()
    if !UITestRuntime.isEnabled {
      environment.crashReporter.install()
    }

    _environment = StateObject(wrappedValue: environment)
    _localizer = StateObject(wrappedValue: environment.localizer)
    appDelegate.environment = environment
  }

  var body: some Scene {
    MenuBarExtra {
      MenuBarMenuContent(environment: environment)
        .environment(\.locale, environment.localizer.locale)
    } label: {
      MenuBarStatusLabel(statusController: environment.statusController)
    }
    .menuBarExtraStyle(.menu)

    Settings {
      SettingsView(
        settings: environment.settings,
        localizer: environment.localizer,
        storeManager: environment.storeManager,
        statisticsStore: environment.statisticsStore,
        launchAtLoginController: environment.launchAtLoginController,
        presentPaywall: {
          environment.router.presentPaywall()
        },
        previewActions: environment.windowPresenter.settingsPreviewActions
      )
        .environment(\.locale, environment.localizer.locale)
    }
  }
}

private struct MenuBarMenuContent: View {
  @ObservedObject var environment: AppEnvironment

  private var statusController: StatusItemController {
    environment.statusController
  }

  private var storeManager: StoreManager {
    environment.storeManager
  }

  var body: some View {
    Group {
      if statusController.isRecordingActive {
        Button {
          environment.router.captureOrStop()
        } label: {
          Label("Stop Recording", systemImage: "stop.circle")
        }
        .keyboardShortcut("s", modifiers: .command)
      } else {
        Button {
          environment.router.captureOrStop()
        } label: {
          Label("Capture Region", systemImage: "camera.viewfinder")
        }
        .keyboardShortcut("c", modifiers: .command)
      }

      Divider()

      if storeManager.hasPaidAccess {
        Button {
          environment.router.presentPaywall()
        } label: {
          Label(
            "Plan: \(storeManager.badgeTitle ?? storeManager.tierTitle)",
            systemImage: storeManager.hasSupporterBadge ? "heart.circle.fill" : "checkmark.seal.fill"
          )
        }
      } else {
        Button {
          environment.router.presentPaywall()
        } label: {
          Label("Purchase License", systemImage: "sparkles")
        }
      }

      Divider()

      Button {
        environment.router.presentWelcome()
      } label: {
        Label("Getting Started…", systemImage: "questionmark.circle")
      }

      Button {
        environment.router.presentStatistics()
      } label: {
        Label("Statistics…", systemImage: "chart.bar.xaxis")
      }

      Button {
        environment.router.presentSettings()
      } label: {
        Label("Settings…", systemImage: "gearshape")
      }
      .keyboardShortcut(",", modifiers: .command)

      Divider()

      Button {
        environment.router.quit()
      } label: {
        Label("Quit VivyShot", systemImage: "power")
      }
      .keyboardShortcut("q", modifiers: .command)
    }
  }

}

private struct MenuBarStatusLabel: View {
  @ObservedObject var statusController: StatusItemController

  var body: some View {
    Label(
      "VivyShot",
      systemImage: statusController.isRecordingActive ? "stop.circle.fill" : "camera.viewfinder"
    )
  }
}

AppRoot.main()
