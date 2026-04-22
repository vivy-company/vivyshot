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
        Button {
          presentPaywallWindow()
        } label: {
          Label("Purchase License", systemImage: "sparkles")
        }
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
    presentStatisticsWindow()
  }
}

VivyShotApp.main()
