import SwiftUI

enum UITestRuntime {
  static let launchFlag = "--uitest-mode"
  @MainActor static var statusController: StatusItemController?

  static var isEnabled: Bool {
    ProcessInfo.processInfo.arguments.contains(launchFlag)
  }
}

@MainActor
enum VivyShotRuntime {
  static var statusController: StatusItemController?
}

struct VivyShotApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @StateObject private var localizer = AppLocalizer.shared
  @StateObject private var statusController: StatusItemController
  @StateObject private var storeManager = StoreManager.shared

  init() {
    if !UITestRuntime.isEnabled {
      CrashReporter.shared.install()
    }

    let settings = AppSettings.shared
    let controller: StatusItemController
    if UITestRuntime.isEnabled {
      controller = StatusItemController(
        settings: settings,
        captureCoordinatorFactory: { _ in UITestCaptureCoordinator() }
      )
    } else {
      controller = StatusItemController(settings: settings)
    }
    _statusController = StateObject(wrappedValue: controller)
    VivyShotRuntime.statusController = controller
    if UITestRuntime.isEnabled {
      UITestRuntime.statusController = controller
    }
  }

  var body: some Scene {
    MenuBarExtra {
      MenuBarMenuContent(statusController: statusController)
        .environment(\.locale, localizer.locale)
    } label: {
      MenuBarStatusLabel(statusController: statusController)
    }
    .menuBarExtraStyle(.menu)

    Settings {
      VivyShotSettingsView(settings: .shared)
        .environment(\.locale, localizer.locale)
    }
  }
}

private struct MenuBarMenuContent: View {
  @ObservedObject var statusController: StatusItemController
  @ObservedObject private var storeManager = StoreManager.shared
  @Environment(\.openSettings) private var openSettings

  var body: some View {
    Group {
      if statusController.isRecordingActive {
        Button {
          statusController.captureOrStopPressed()
        } label: {
          Label("Stop Recording", systemImage: "stop.circle")
        }
        .keyboardShortcut("s", modifiers: .command)
      } else {
        Button {
          statusController.captureOrStopPressed()
        } label: {
          Label("Capture Region", systemImage: "camera.viewfinder")
        }
        .keyboardShortcut("c", modifiers: .command)
      }

      Divider()

      if storeManager.hasPaidAccess {
        Button {
          presentPaywallWindow()
        } label: {
          Label(
            "Plan: \(storeManager.badgeTitle ?? storeManager.tierTitle)",
            systemImage: storeManager.hasSupporterBadge ? "heart.circle.fill" : "checkmark.seal.fill"
          )
        }
      } else {
        Button {
          presentPaywallWindow()
        } label: {
          Label("Purchase License", systemImage: "sparkles")
        }
      }

      Divider()

      Button {
        presentWelcomeWindow(
          onStartCapture: {
            statusController.startCapturePressed()
          },
          onOpenSettings: presentSettingsWindow
        )
      } label: {
        Label("Getting Started…", systemImage: "questionmark.circle")
      }

      Button {
        openStatisticsWindow()
      } label: {
        Label("Statistics…", systemImage: "chart.bar.xaxis")
      }

      Button {
        openSettingsOnTop()
      } label: {
        Label("Settings…", systemImage: "gearshape")
      }
      .keyboardShortcut(",", modifiers: .command)

      Divider()

      Button {
        statusController.quitPressed()
      } label: {
        Label("Quit VivyShot", systemImage: "power")
      }
      .keyboardShortcut("q", modifiers: .command)
    }
  }

  private func openSettingsOnTop() {
    NSApp.activate(ignoringOtherApps: true)
    openSettings()
    bringSettingsWindowForward()
  }

  private func openStatisticsWindow() {
    NSApp.activate(ignoringOtherApps: true)
    presentStatisticsWindow()
  }
}

private struct MenuBarStatusLabel: View {
  @ObservedObject var statusController: StatusItemController
  @Environment(\.openSettings) private var openSettings

  var body: some View {
    Label(
      "VivyShot",
      systemImage: statusController.isRecordingActive ? "stop.circle.fill" : "camera.viewfinder"
    )
    .onAppear {
      installSettingsWindowPresenter(openSettings)
    }
  }
}

VivyShotApp.main()
