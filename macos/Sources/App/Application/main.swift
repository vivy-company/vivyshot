import SwiftUI

struct VivyShotApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @StateObject private var statusController = StatusItemController(settings: .shared)

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
      VivyShotSettingsView(settings: .shared)
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

VivyShotApp.main()
