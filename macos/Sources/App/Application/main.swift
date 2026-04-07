import SwiftUI

enum UITestRuntime {
  static let launchFlag = "--uitest-mode"
  @MainActor static var statusController: StatusItemController?

  static var isEnabled: Bool {
    ProcessInfo.processInfo.arguments.contains(launchFlag)
  }
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
    if UITestRuntime.isEnabled {
      UITestRuntime.statusController = controller
    }
  }

  var body: some Scene {
    MenuBarExtra {
      MenuBarMenuContent(statusController: statusController)
        .environment(\.locale, localizer.locale)
    } label: {
      Label(
        "VivyShot",
        systemImage: statusController.isRecordingActive ? "stop.circle.fill" : "camera.viewfinder"
      )
    }
    .menuBarExtraStyle(.menu)

    Settings {
      VivyShotSettingsView(settings: .shared)
        .environment(\.locale, localizer.locale)
    }

    Window("Statistics", id: StatisticsWindowScene.id) {
      StatisticsWindowSceneRootView()
        .environment(\.locale, localizer.locale)
    }
    .defaultLaunchBehavior(.suppressed)
    .restorationBehavior(.disabled)
    .defaultSize(width: 780, height: 680)
    .windowResizability(.contentMinSize)
    .windowToolbarStyle(.unified(showsTitle: true))
  }
}

private struct MenuBarMenuContent: View {
  @ObservedObject var statusController: StatusItemController
  @ObservedObject private var storeManager = StoreManager.shared
  @Environment(\.openWindow) private var openWindow
  @Environment(\.openSettings) private var openSettings

  var body: some View {
    Group {
      if statusController.isRecordingActive {
        Button(LocalizedStringKey("Stop Recording")) {
          statusController.captureOrStopPressed()
        }
        .keyboardShortcut("s", modifiers: .command)
      } else {
        Button(LocalizedStringKey("Capture Region")) {
          statusController.captureOrStopPressed()
        }
        .keyboardShortcut("c", modifiers: .command)
      }

      Divider()

      if storeManager.hasPaidAccess {
        HStack {
          Text("Plan")
          Spacer()
          if let badgeTitle = storeManager.badgeTitle {
            StoreBadgeChip(
              title: badgeTitle,
              prominence: badgeTitle == "Supporter" ? .supporter : .lifetime
            )
          } else {
            Text(storeManager.tierTitle)
              .foregroundStyle(.secondary)
          }
        }
        .padding(.vertical, 2)
      } else {
        Button(LocalizedStringKey("Upgrade")) {
          presentPaywallWindow()
        }
      }

      Button(LocalizedStringKey("Statistics…")) {
        openStatisticsWindow()
      }

      Button(LocalizedStringKey("Settings…")) {
        openSettingsOnTop()
      }
      .keyboardShortcut(",", modifiers: .command)

      Divider()

      Button(LocalizedStringKey("Quit VivyShot")) {
        statusController.quitPressed()
      }
      .keyboardShortcut("q", modifiers: .command)
    }
  }

  private func openSettingsOnTop() {
    NSApp.activate(ignoringOtherApps: true)
    openSettings()
    Task { @MainActor in
      await Task.yield()
      NSApp.activate(ignoringOtherApps: true)
      if let visibleWindow = NSApp.windows.first(where: { $0.canBecomeKey && $0.isVisible }) {
        visibleWindow.makeKeyAndOrderFront(nil)
      }
    }
  }

  private func openStatisticsWindow() {
    NSApp.activate(ignoringOtherApps: true)
    openWindow(id: StatisticsWindowScene.id)
  }
}

VivyShotApp.main()
