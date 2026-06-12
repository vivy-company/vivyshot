import AppKit
import SwiftUI

/// Root settings UI for app, capture, recording, statistics, license, and about sections.
@MainActor
struct SettingsView: View {
  private enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case appearance
    case screenshot
    case video
    case statistics
    case license
    case about

    var id: String { rawValue }

    var title: String {
      switch self {
      case .general:
        return String(localized: "General", bundle: AppLocalizer.shared.bundle)
      case .appearance:
        return String(localized: "Appearance", bundle: AppLocalizer.shared.bundle)
      case .screenshot:
        return String(localized: "Screenshot", bundle: AppLocalizer.shared.bundle)
      case .video:
        return String(localized: "Video", bundle: AppLocalizer.shared.bundle)
      case .statistics:
        return String(localized: "Statistics", bundle: AppLocalizer.shared.bundle)
      case .license:
        return String(localized: "License", bundle: AppLocalizer.shared.bundle)
      case .about:
        return String(localized: "About", bundle: AppLocalizer.shared.bundle)
      }
    }
  }

  @ObservedObject var settings: AppSettings
  @ObservedObject var localizer: AppLocalizer
  @ObservedObject var storeManager: StoreManager
  let statisticsStore: StatisticsStore
  @ObservedObject var launchAtLoginController: LaunchAtLoginController
  let presentPaywall: () -> Void
  let previewActions: SettingsPreviewActions
  @State private var selectedTab: SettingsTab = .general
  @State var isRecordingShortcut = false
  @State var availableFamilies: [String] = AppSettings.availableTextFontFamilyNames()
  @State var draggingScreenshotTool: AnnotationTool?
  @State var draggingVideoTool: RecordingTool?
  @State var isReviewerModeSheetPresented = false
  @State var visibleOverlayPreviews: Set<RecordingOverlaySettingsPreviewKind> = []
  var captureTransitionEffectsVisible: Bool { true }
  var microphoneFeatureVisible: Bool { true }
  var webcamFeatureVisible: Bool { true }
  var keystrokesFeatureVisible: Bool { true }
  let overlaySettingsLabelWidth: CGFloat = 108

  var body: some View {
    TabView(selection: $selectedTab) {
      settingsContainer {
        languageSection
        startupSection
        shortcutSection
        captureDefaultsSection
        savingSection
      }
      .tabItem { Label(SettingsTab.general.title, systemImage: "gearshape") }
      .tag(SettingsTab.general)

      settingsContainer {
        appearanceSection
      }
      .tabItem { Label(SettingsTab.appearance.title, systemImage: "paintpalette") }
      .tag(SettingsTab.appearance)

      settingsContainer {
        screenshotDrawingSection
        screenshotToolbarSection
        textToolSection
        if captureTransitionEffectsVisible {
          effectsSection
        }
      }
      .tabItem { Label(SettingsTab.screenshot.title, systemImage: "camera") }
      .tag(SettingsTab.screenshot)

      settingsContainer {
        recordingSection
        if webcamFeatureVisible {
          webcamOverlaySection
        }
        if keystrokesFeatureVisible {
          keystrokeOverlaySection
        }
        mouseClickSection
        recordingToolbarSection
      }
      .tabItem { Label(SettingsTab.video.title, systemImage: "record.circle") }
      .tag(SettingsTab.video)

      StatisticsView(
        presentation: .settings,
        storeManager: storeManager,
        statisticsStore: statisticsStore,
        onUpgrade: presentPaywall
      )
        .tabItem { Label(SettingsTab.statistics.title, systemImage: "chart.bar.xaxis") }
        .tag(SettingsTab.statistics)

      StoreSettingsView(storeManager: storeManager, localizer: localizer, presentPaywall: presentPaywall)
      .tabItem { Label(SettingsTab.license.title, systemImage: "sparkles") }
      .tag(SettingsTab.license)

      settingsContainer {
        aboutHeroSection
        aboutLinksSection
        aboutContactSection
        aboutAppsSection
      }
      .tabItem { Label(SettingsTab.about.title, systemImage: "info.circle") }
      .tag(SettingsTab.about)
    }
    .frame(minWidth: 500, minHeight: 620)
    .onAppear {
      availableFamilies = AppSettings.availableTextFontFamilyNames()
      launchAtLoginController.refresh()
    }
    .onDisappear {
      previewActions.closeAllRecordingOverlayPreviews()
      visibleOverlayPreviews.removeAll()
    }
    .background(SettingsWindowFocusReader())
    .sheet(isPresented: $isReviewerModeSheetPresented) {
      ReviewerModeSheet(storeManager: storeManager)
    }
  }

  private func settingsContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    ScrollView {
      Form {
        content()
      }
      .formStyle(.grouped)
      .frame(maxWidth: 560)
      .padding(14)
    }
  }


}

@MainActor
enum SettingsWindowFocus {
  private static weak var settingsWindow: NSWindow?

  static func present(_ openSettings: OpenSettingsAction) {
    NSApp.activate(ignoringOtherApps: true)
    openSettings()
    focusSoon()
  }

  static func register(_ window: NSWindow) {
    let shouldFocus = settingsWindow !== window
    settingsWindow = window
    if shouldFocus {
      focus(window)
    }
  }

  private static func focusSoon() {
    DispatchQueue.main.async {
      focusRegisteredWindow()
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
      focusRegisteredWindow()
    }
  }

  private static func focusRegisteredWindow() {
    guard let settingsWindow else {
      return
    }
    focus(settingsWindow)
  }

  private static func focus(_ window: NSWindow) {
    NSApp.activate(ignoringOtherApps: true)
    window.deminiaturize(nil)
    window.makeKeyAndOrderFront(nil)
  }
}

private struct SettingsWindowFocusReader: NSViewRepresentable {
  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    updateWindow(for: view)
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    updateWindow(for: nsView)
  }

  private func updateWindow(for view: NSView) {
    DispatchQueue.main.async {
      guard let window = view.window else {
        return
      }
      SettingsWindowFocus.register(window)
    }
  }
}
