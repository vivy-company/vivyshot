import SwiftUI

enum UITestRuntime {
  static let launchFlag = "--uitest-mode"

  static var isEnabled: Bool {
    ProcessInfo.processInfo.arguments.contains(launchFlag)
  }
}

struct VivyShotApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @StateObject private var statusController: StatusItemController

  init() {
    let settings = AppSettings.shared
    if UITestRuntime.isEnabled {
      _statusController = StateObject(
        wrappedValue: StatusItemController(
          settings: settings,
          captureCoordinatorFactory: { _ in UITestCaptureCoordinator() }
        )
      )
    } else {
      _statusController = StateObject(wrappedValue: StatusItemController(settings: settings))
    }
  }

  var body: some Scene {
    MenuBarExtra {
      MenuBarMenuContent(statusController: statusController)
    } label: {
      Label(
        "VivyShot",
        systemImage: statusController.isRecordingActive ? "stop.circle.fill" : "camera.viewfinder"
      )
    }
    .menuBarExtraStyle(.menu)

    Settings {
      if UITestRuntime.isEnabled {
        UITestHarnessView(statusController: statusController)
      } else {
        VivyShotSettingsView(settings: .shared)
      }
    }
  }
}

private struct MenuBarMenuContent: View {
  @ObservedObject var statusController: StatusItemController
  @Environment(\.openSettings) private var openSettings

  var body: some View {
    if statusController.isRecordingActive {
      Button("Stop Recording") {
        statusController.captureOrStopPressed()
      }
      .keyboardShortcut("s", modifiers: .command)
    } else {
      Button("Capture Region") {
        statusController.captureOrStopPressed()
      }
      .keyboardShortcut("c", modifiers: .command)
    }

    Divider()

    Button("Settings…") {
      openSettingsOnTop()
    }
    .keyboardShortcut(",", modifiers: .command)

    Divider()

    Button("Quit VivyShot") {
      statusController.quitPressed()
    }
    .keyboardShortcut("q", modifiers: .command)
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
}

private struct UITestHarnessView: View {
  @ObservedObject var statusController: StatusItemController

  private var recordingStateText: String {
    statusController.isRecordingActive ? "recording" : "idle"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("VivyShot UI Test Harness")
        .font(.headline)

      Text(recordingStateText)
        .font(.system(size: 14, weight: .semibold, design: .monospaced))
        .accessibilityIdentifier("recordingStateLabel")

      Button(statusController.isRecordingActive ? "Stop Recording" : "Capture Region") {
        statusController.captureOrStopPressed()
      }
      .accessibilityIdentifier("captureStopButton")
    }
    .padding(20)
  }
}

VivyShotApp.main()
