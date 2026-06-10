import AppKit
import AVFoundation
import Carbon
import SwiftUI

/// Opens the app settings window and brings it to the front.
@MainActor
func presentSettingsWindow() {
  NSApp.activate(ignoringOtherApps: true)

  if let openSettings = SettingsWindowPresentation.openSettings {
    openSettings()
  } else {
    let didOpen = NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    if !didOpen {
      _ = NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
  }

  bringSettingsWindowForward()
}

/// Installs the SwiftUI `openSettings` action from the app scene.
@MainActor
func installSettingsWindowPresenter(_ openSettings: OpenSettingsAction) {
  SettingsWindowPresentation.openSettings = {
    openSettings()
  }
}

/// Re-activates the current settings window after SwiftUI has presented it.
@MainActor
func bringSettingsWindowForward() {
  Task { @MainActor in
    await Task.yield()
    NSApp.activate(ignoringOtherApps: true)
    if let visibleWindow = NSApp.windows.first(where: { $0.canBecomeKey && $0.isVisible }) {
      visibleWindow.makeKeyAndOrderFront(nil)
    }
  }
}

@MainActor
private enum SettingsWindowPresentation {
  static var openSettings: (() -> Void)?
}

private enum RecordingOverlaySettingsPreviewKind: String {
  case webcam
  case keystroke
}

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
  @ObservedObject private var storeManager = StoreManager.shared
  @ObservedObject private var launchAtLoginController = LaunchAtLoginController.shared
  @State private var selectedTab: SettingsTab = .general
  @State private var isRecordingShortcut = false
  @State private var availableFamilies: [String] = AppSettings.availableTextFontFamilyNames()
  @State private var draggingScreenshotTool: AnnotationTool?
  @State private var draggingVideoTool: RecordingTool?
  @State private var isReviewerModeSheetPresented = false
  @State private var visibleOverlayPreviews: Set<RecordingOverlaySettingsPreviewKind> = []
  private var captureTransitionEffectsVisible: Bool { true }
  private var microphoneFeatureVisible: Bool { true }
  private var webcamFeatureVisible: Bool { true }
  private var keystrokesFeatureVisible: Bool { true }
  private let overlaySettingsLabelWidth: CGFloat = 108

  private var appVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1"
  }

  private var buildNumber: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
  }

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

      StatisticsView(presentation: .settings)
        .tabItem { Label(SettingsTab.statistics.title, systemImage: "chart.bar.xaxis") }
        .tag(SettingsTab.statistics)

      StoreSettingsView()
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
      RecordingOverlaySettingsPreviewCoordinator.shared.closeAll()
      visibleOverlayPreviews.removeAll()
    }
    .sheet(isPresented: $isReviewerModeSheetPresented) {
      ReviewerModeSheet()
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

  private var aboutHeroSection: some View {
    Section {
      VStack(spacing: 16) {
        Image(nsImage: NSApp.applicationIconImage)
          .resizable()
          .interpolation(.high)
          .frame(width: 80, height: 80)
          .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
          .shadow(color: .black.opacity(0.12), radius: 8, y: 4)

        Text("VivyShot")
          .font(.title)
          .fontWeight(.bold)

        Text("Screen capture and recording for macOS.")
          .font(.callout)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)

        Text("Capture a region, window, or screen, then annotate screenshots, trim recordings, and export when you are done.")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)

        Text("Version \(appVersion) (\(buildNumber))")
          .font(.callout.monospacedDigit())
          .foregroundStyle(.secondary)
          .onTapGesture(count: 7) {
            isReviewerModeSheetPresented = true
          }
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 20)
    }
  }

  private var aboutLinksSection: some View {
    Section("Links") {
      AboutLinkRow(
        title: String(localized: "Website", bundle: AppLocalizer.shared.bundle),
        systemImage: "globe",
        url: URL(string: "https://vivyshot.com")!
      )
      AboutLinkRow(
        title: String(localized: "Privacy Policy", bundle: AppLocalizer.shared.bundle),
        systemImage: "hand.raised",
        url: URL(string: "https://vivyshot.com/privacy")!
      )
      AboutLinkRow(
        title: String(localized: "Terms of Use", bundle: AppLocalizer.shared.bundle),
        systemImage: "doc.text",
        url: URL(string: "https://vivyshot.com/terms")!
      )
    }
  }

  private var aboutContactSection: some View {
    Section("Get in Touch") {
      AboutLinkRow(
        title: String(localized: "Developer", bundle: AppLocalizer.shared.bundle),
        systemImage: "person.crop.circle",
        url: URL(string: "https://x.com/wiedymi")!
      )
      AboutLinkRow(
        title: String(localized: "Discord", bundle: AppLocalizer.shared.bundle),
        systemImage: "bubble.left.and.bubble.right",
        url: URL(string: "https://discord.gg/zemMZtrkSb")!
      )
      AboutLinkRow(
        title: String(localized: "Email", bundle: AppLocalizer.shared.bundle),
        systemImage: "envelope",
        url: URL(string: "mailto:vivyshot@vivy.company")!
      )
    }
  }

  private var aboutAppsSection: some View {
    Section("Our Apps") {
      AboutLinkRow(
        title: "VVTerm",
        subtitle: String(localized: "Native SSH terminal and SFTP client for iPhone, iPad, and Mac.", bundle: AppLocalizer.shared.bundle),
        assetImage: "VVTermIcon",
        url: URL(string: "https://vvterm.com")!
      )
    }
  }

  private var languageSection: some View {
    Section {
      LabeledContent("Language") {
        Picker("App Language", selection: appLanguageBinding) {
          ForEach(AppLanguage.allCases) { language in
            Text(languageLabel(for: language)).tag(language)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 220, alignment: .trailing)
      }
    } header: {
      Text("App Language")
    } footer: {
      Text(String(localized: "System Default follows your macOS language.", bundle: AppLocalizer.shared.bundle))
    }
  }

  private var shortcutSection: some View {
    Section {
      LabeledContent("Shortcut") {
        ShortcutRecorderFieldRepresentable(
          displayText: settings.captureShortcutDisplay,
          isRecording: $isRecordingShortcut,
          onCapture: { keyCode, flags in
            settings.setCaptureShortcut(keyCode: keyCode, modifierFlags: flags)
          }
        )
        .frame(width: 240)
        .frame(minHeight: 28)
      }

      HStack(spacing: 8) {
        Button(isRecordingShortcut ? "Stop" : "Record") {
          isRecordingShortcut.toggle()
        }
        .buttonStyle(.borderedProminent)
        .tint(isRecordingShortcut ? .red : .accentColor)

        Button("Reset") {
          settings.resetCaptureShortcut()
          isRecordingShortcut = false
        }
        .buttonStyle(.bordered)

        Spacer(minLength: 0)
      }
    } header: {
      Text("Capture Shortcut")
    } footer: {
      Text(
        String(
          localized: isRecordingShortcut
            ? "Press the shortcut you want to use now. Esc cancels."
            : "Used to start capture from anywhere. Hold Command, Shift, Option, or Control while pressing a key.",
          bundle: AppLocalizer.shared.bundle
        )
      )
    }
  }

  private var startupSection: some View {
    Section {
      Toggle("Start VivyShot at login", isOn: launchAtLoginBinding)
        .toggleStyle(.switch)
        .controlSize(.small)
    } header: {
      Text("Startup")
    } footer: {
      Text(
        launchAtLoginController.detailText
          ?? String(
            localized: "Automatically launches the menu bar app after you sign in.",
            bundle: AppLocalizer.shared.bundle
          )
      )
    }
  }

  private var captureDefaultsSection: some View {
    Section {
      Toggle("Show Capture Helper", isOn: captureShowHelperBinding)
        .toggleStyle(.switch)
        .controlSize(.small)

      Toggle("Smart Window Selection", isOn: captureSmartWindowSelectionBinding)
        .toggleStyle(.switch)
        .controlSize(.small)

      LabeledContent("Start In") {
        Picker("Default Capture Type", selection: defaultCaptureTypeBinding) {
          ForEach(CaptureContentType.allCases) { type in
            Text(type.title).tag(type)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 220, alignment: .trailing)
      }
    } header: {
      Text("Capture Defaults")
    } footer: {
      Text(
        String(
          localized: "Turn off smart window selection if you prefer to draw an area before choosing a window.",
          bundle: AppLocalizer.shared.bundle
        )
      )
    }
  }

  private var savingSection: some View {
    let hasSaveLocation = settings.defaultSaveDirectoryURL != nil

    return Section {
      LabeledContent("Save Location") {
        Text(defaultSaveDirectoryDisplay)
          .font(.system(.callout, design: .monospaced))
          .foregroundStyle(hasSaveLocation ? .primary : .secondary)
          .lineLimit(2)
          .multilineTextAlignment(.trailing)
      }

      if !hasSaveLocation {
        Text("Choose a folder to enable automatic saves.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      HStack(spacing: 8) {
        Button(
          String(
            localized: hasSaveLocation ? "Change…" : "Choose Folder…",
            bundle: AppLocalizer.shared.bundle
          )
        ) {
          chooseDefaultSaveDirectory()
        }
        .buttonStyle(.bordered)

        if hasSaveLocation {
          Button("Show in Finder") {
            revealDefaultSaveDirectoryInFinder()
          }
          .buttonStyle(.bordered)

          Button("Clear") {
            settings.setDefaultSaveDirectory(nil)
          }
          .buttonStyle(.bordered)
        }

        Spacer(minLength: 0)
      }

      Text("Automatic Saving")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)

      VStack(alignment: .leading, spacing: 4) {
        Toggle("Save screenshots without asking", isOn: alwaysSaveToDefaultDirectoryBinding)
          .toggleStyle(.switch)
        Text("Use this for the Save action instead of opening the save dialog.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      .disabled(!hasSaveLocation)

      VStack(alignment: .leading, spacing: 4) {
        Toggle("Also save copied screenshots", isOn: saveCopiedScreenshotsToDefaultDirectoryBinding)
          .toggleStyle(.switch)
        Text("When you copy a screenshot, VivyShot also saves a PNG in this folder.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      .disabled(!hasSaveLocation)
    } header: {
      Text("Saving")
    } footer: {
      Text(
        String(
          localized: hasSaveLocation
            ? "Choose the automatic saving behavior that fits your workflow."
            : "Choose a folder first to enable automatic saving.",
          bundle: AppLocalizer.shared.bundle
        )
      )
    }
  }

  private var appearanceSection: some View {
    Section("Appearance") {
      HStack(spacing: 10) {
        Text("Accent")
          .frame(width: 90, alignment: .leading)
        Spacer(minLength: 0)
        ColorPicker("Toolbar Accent", selection: toolbarAccentColorBinding, supportsOpacity: false)
          .labelsHidden()
          .frame(width: 190, alignment: .trailing)
      }

      HStack(spacing: 10) {
        Text("Main Action")
          .frame(width: 90, alignment: .leading)
        Spacer(minLength: 0)
        Picker("Main Action Button", selection: screenshotMainActionBinding) {
          ForEach(ScreenshotMainAction.allCases) { action in
            Text(action.title).tag(action)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 190, alignment: .trailing)
      }

      Text("Applied to screenshot main action and video record button.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private var screenshotDrawingSection: some View {
    Section {
      HStack(spacing: 10) {
        Text("Line Width")
          .frame(width: 90, alignment: .leading)
        Slider(value: drawingStrokeWidthBinding, in: AppSettings.drawingStrokeWidthRange, step: 0.5)
        Text(String(format: "%.1f pt", settings.drawingStrokeWidth))
          .font(.system(.callout, design: .monospaced).weight(.semibold))
          .frame(width: 62, alignment: .trailing)
      }
    } header: {
      Text("Drawing")
    } footer: {
      Text("Applied to rectangle, circle, line, arrow, and paint tools.")
    }
  }

  private var screenshotToolbarSection: some View {
    Section("Toolbar") {
      Text("Drag rows to reorder. Hidden tools won’t appear in screenshot toolbar.")
        .font(.caption)
        .foregroundStyle(.secondary)

      VStack(spacing: 0) {
        ForEach(settings.toolOrder) { tool in
          HStack(spacing: 10) {
            Image(systemName: tool.symbolName)
              .frame(width: 18)
              .foregroundStyle(.secondary)

            Text(tool.title)
              .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("", isOn: visibilityBinding(for: tool))
              .toggleStyle(.checkbox)
              .labelsHidden()

            ReorderHandleGlyph(active: draggingScreenshotTool == tool)
              .onDrag {
                draggingScreenshotTool = tool
                return NSItemProvider(object: NSString(string: "\(tool.rawValue)"))
              }
              .help("Drag to reorder")
          }
          .padding(.horizontal, 4)
          .padding(.vertical, 5)
          .contentShape(Rectangle())
          .background(
            RoundedRectangle(cornerRadius: 7)
              .fill(draggingScreenshotTool == tool ? Color.primary.opacity(0.08) : .clear)
          )
          .onDrop(
            of: ["public.text"],
            delegate: ToolbarToolDropDelegate(
              target: tool,
              currentOrder: settings.toolOrder,
              draggingTool: $draggingScreenshotTool,
              onMove: settings.moveTools
            )
          )

          if tool != settings.toolOrder.last {
            Divider().opacity(0.35)
          }
        }
      }
      .padding(4)
      .onDrop(of: ["public.text"], isTargeted: nil) { _ in
        draggingScreenshotTool = nil
        return false
      }

      HStack {
        Spacer()
        Button("Reset Toolbar") {
          settings.resetToolbarConfiguration()
        }
      }
    }
  }

  private var recordingSection: some View {
    Section("Video Capture") {
      HStack(spacing: 10) {
        Text("Encoder")
          .frame(width: 78, alignment: .leading)
        Spacer(minLength: 0)
        Picker("Recording Encoder", selection: recordingEncoderBinding) {
          ForEach(RecordingEncoder.allCases) { encoder in
            Text(encoder.title).tag(encoder)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 220, alignment: .trailing)
      }

      HStack(spacing: 10) {
        Text("Frame Rate")
          .frame(width: 78, alignment: .leading)
        Spacer(minLength: 0)
        Picker("Video Frame Rate", selection: recordingFrameRateBinding) {
          ForEach(RecordingFrameRate.allCases) { rate in
            Text(rate.title).tag(rate)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 190, alignment: .trailing)
      }

      HStack(spacing: 10) {
        Text("Countdown")
          .frame(width: 78, alignment: .leading)
        Spacer(minLength: 0)
        Picker("Video Countdown", selection: recordingCountdownBinding) {
          ForEach(RecordingCountdown.allCases) { countdown in
            Text(countdown.title).tag(countdown)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 190, alignment: .trailing)
      }

      Toggle("Record system audio", isOn: recordSystemAudioBinding)
        .toggleStyle(.switch)
      if microphoneFeatureVisible {
        Toggle("Record microphone", isOn: recordMicrophoneBinding)
          .toggleStyle(.switch)
      }
      Toggle("Hide notifications (best effort)", isOn: hideNotificationsBestEffortBinding)
        .toggleStyle(.switch)

      HStack {
        Spacer()
        Button("Reset Video") {
          settings.resetVideoCaptureSettings()
        }
      }
    }
  }

  private var webcamOverlaySection: some View {
    Section("Camera Overlay") {
      Toggle("Show camera by default", isOn: showWebcamBinding)
        .toggleStyle(.switch)

      overlaySliderRow(
        "Camera Size",
        value: webcamOverlaySizeSliderBinding,
        range: AppSettings.webcamOverlaySizeRange,
        displayValue: settings.webcamOverlayNormalizedWidth
      )

      overlayPickerRow("Camera Shape", title: "Webcam Overlay Shape", selection: webcamOverlayShapeBinding) {
        ForEach(WebcamShape.allCases) { shape in
          Text(shape.title).tag(shape)
        }
      }

      overlayPickerRow("Aspect Ratio", title: "Webcam Aspect Ratio", selection: webcamOverlayAspectRatioBinding) {
        ForEach(WebcamAspectRatio.allCases) { aspectRatio in
          Text(aspectRatio.title).tag(aspectRatio)
        }
      }
      .disabled(settings.webcamOverlayShape == .circle)

      overlayPreviewActions(.webcam) {
        settings.resetWebcamOverlayPlacement()
      }
    }
  }

  private var keystrokeOverlaySection: some View {
    Section("Keyboard Overlay") {
      Toggle("Show keystrokes by default", isOn: highlightKeystrokesBinding)
        .toggleStyle(.switch)

      overlayPickerRow("Key Style", title: "Keystroke Overlay Style", selection: keystrokeOverlayStyleBinding) {
        ForEach(KeystrokeStyle.allCases) { style in
          Text(style.title).tag(style)
        }
      }

      overlaySliderRow(
        "Key Size",
        value: keystrokeOverlaySizeSliderBinding,
        range: AppSettings.keystrokeOverlaySizeRange,
        displayValue: settings.keystrokeOverlayNormalizedWidth
      )

      overlayPreviewActions(.keystroke) {
        settings.resetKeystrokeOverlayPlacement()
      }
    }
  }

  private var mouseClickSection: some View {
    Section("Mouse Click Highlights") {
      Toggle("Highlight mouse clicks", isOn: highlightMouseClicksBinding)

      Picker("Click Style", selection: mouseClickHighlightStyleBinding) {
        ForEach(MouseClickHighlightStyle.allCases) { style in
          Text(style.title).tag(style)
        }
      }
      .pickerStyle(.menu)
      .disabled(!settings.highlightMouseClicks)
    }
  }

  private var recordingToolbarSection: some View {
    Section("Video Toolbar") {
      Text("Drag rows to reorder. Hidden tools won’t appear in video toolbar.")
        .font(.caption)
        .foregroundStyle(.secondary)

      VStack(spacing: 0) {
        ForEach(settings.recordingToolOrder) { tool in
          if shouldShowRecordingTool(tool) {
            HStack(spacing: 10) {
              Image(systemName: tool.symbolName)
                .frame(width: 18)
                .foregroundStyle(.secondary)

              Text(tool.title)
                .frame(maxWidth: .infinity, alignment: .leading)

              Toggle("", isOn: recordingToolVisibilityBinding(for: tool))
                .toggleStyle(.checkbox)
                .labelsHidden()

              ReorderHandleGlyph(active: draggingVideoTool == tool)
                .onDrag {
                  draggingVideoTool = tool
                  return NSItemProvider(object: NSString(string: "\(tool.rawValue)"))
                }
                .help("Drag to reorder")
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(
              RoundedRectangle(cornerRadius: 7)
                .fill(draggingVideoTool == tool ? Color.primary.opacity(0.08) : .clear)
            )
            .onDrop(
              of: ["public.text"],
              delegate: RecordingToolDropDelegate(
                target: tool,
                currentOrder: settings.recordingToolOrder,
                draggingTool: $draggingVideoTool,
                onMove: settings.moveVideoTools
              )
            )

            if tool != lastVisibleRecordingTool {
              Divider().opacity(0.35)
            }
          }
        }
      }
      .padding(4)
      .onDrop(of: ["public.text"], isTargeted: nil) { _ in
        draggingVideoTool = nil
        return false
      }

      HStack {
        Spacer()
        Button("Reset Video Toolbar") {
          settings.resetVideoToolbarConfiguration()
        }
      }
    }
  }

  private var textToolSection: some View {
    Section("Text Tool") {
      HStack(spacing: 10) {
        Text("Font")
          .frame(width: 78, alignment: .leading)
        Spacer(minLength: 0)
        Picker("Font", selection: textFontNameBinding) {
          ForEach(availableFamilies, id: \.self) { family in
            Text(family).tag(family)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 190, alignment: .trailing)
      }

      HStack(spacing: 10) {
        Text("Size")
          .frame(width: 78, alignment: .leading)
        Slider(value: textFontSizeBinding, in: 10 ... 48, step: 1)
        Text("\(Int(settings.textFontSize)) pt")
          .font(.system(.callout, design: .monospaced).weight(.semibold))
          .frame(width: 48, alignment: .trailing)
      }

      LabeledContent("Preview") {
        textPreview
          .frame(maxWidth: .infinity, alignment: .leading)
      }

      HStack {
        Spacer()
        Button("Reset Text") {
          settings.resetTextSettings()
        }
      }
    }
  }

  private var effectsSection: some View {
    Section("Effects") {
      HStack(spacing: 10) {
        Text("Transition")
          .frame(width: 78, alignment: .leading)
        Spacer(minLength: 0)
        Picker("Transition", selection: captureTransitionStyleBinding) {
          ForEach(CaptureTransitionStyle.allCases) { style in
            Text(style.title).tag(style)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 150, alignment: .trailing)
      }

      LabeledContent("Speed") {
        HStack(spacing: 10) {
          Slider(
            value: captureTransitionSpeedBinding,
            in: 0.5 ... 2.4,
            step: 0.05
          )
          .disabled(settings.captureTransitionStyle == .none)
          Text(String(format: "%.2fx", settings.captureTransitionSpeed))
            .font(.system(.callout, design: .monospaced).weight(.semibold))
            .frame(width: 54, alignment: .trailing)
        }
      }

      LabeledContent("Strength") {
        HStack(spacing: 10) {
          Slider(
            value: captureTransitionIntensityBinding,
            in: 0.2 ... 1,
            step: 0.05
          )
          .disabled(settings.captureTransitionStyle == .none)
          Text(String(format: "%.0f%%", settings.captureTransitionIntensity * 100))
            .font(.system(.callout, design: .monospaced).weight(.semibold))
            .frame(width: 54, alignment: .trailing)
        }
      }

      HStack {
        Text(captureTransitionHelperText)
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
        Button("Preview") {
          previewCaptureTransition()
        }
        .disabled(settings.captureTransitionStyle == .none)
        Button("Reset Effects") {
          settings.resetCaptureTransitionSettings()
        }
      }
    }
  }

  private var captureTransitionHelperText: String {
    if storeManager.hasPaidAccess {
      return String(localized: "Applied on capture enter and exit.", bundle: AppLocalizer.shared.bundle)
    }
    return String(localized: "Preview is available. Real capture transitions require Pro.", bundle: AppLocalizer.shared.bundle)
  }

  private func visibilityBinding(for tool: AnnotationTool) -> Binding<Bool> {
    Binding(
      get: { settings.isToolVisible(tool) },
      set: { settings.setToolVisible(tool, isVisible: $0) }
    )
  }

  private func recordingToolVisibilityBinding(for tool: RecordingTool) -> Binding<Bool> {
    Binding(
      get: { settings.isRecordingToolVisible(tool) },
      set: { settings.setRecordingToolVisible(tool, isVisible: $0) }
    )
  }

  private var lastVisibleRecordingTool: RecordingTool? {
    settings.recordingToolOrder.last(where: shouldShowRecordingTool)
  }

  private func shouldShowRecordingTool(_ tool: RecordingTool) -> Bool {
    switch tool {
    case .microphone:
      return microphoneFeatureVisible
    case .webcam:
      return webcamFeatureVisible
    case .keystrokes:
      return keystrokesFeatureVisible
    default:
      return true
    }
  }

  @ViewBuilder
  private var textPreview: some View {
    if settings.textFontName == AppSettings.systemFontFamilyName {
      Text("The quick brown fox jumps over 123")
        .font(.system(size: settings.textFontSize, weight: .regular))
    } else {
      Text("The quick brown fox jumps over 123")
        .font(.custom(settings.textFontName, size: settings.textFontSize))
    }
  }

  private var textFontSizeBinding: Binding<Double> {
    Binding(
      get: { settings.textFontSize },
      set: { settings.setTextFontSize($0) }
    )
  }

  private var textFontNameBinding: Binding<String> {
    Binding(
      get: { settings.textFontName },
      set: { settings.setTextFontName($0) }
    )
  }

  private var drawingStrokeWidthBinding: Binding<Double> {
    Binding(
      get: { settings.drawingStrokeWidth },
      set: { settings.setDrawingStrokeWidth($0) }
    )
  }

  private var captureTransitionStyleBinding: Binding<CaptureTransitionStyle> {
    Binding(
      get: { settings.captureTransitionStyle },
      set: { settings.setCaptureTransitionStyle($0) }
    )
  }

  private var captureTransitionSpeedBinding: Binding<Double> {
    Binding(
      get: { settings.captureTransitionSpeed },
      set: { settings.setCaptureTransitionSpeed($0) }
    )
  }

  private var captureTransitionIntensityBinding: Binding<Double> {
    Binding(
      get: { settings.captureTransitionIntensity },
      set: { settings.setCaptureTransitionIntensity($0) }
    )
  }

  private var captureShowHelperBinding: Binding<Bool> {
    Binding(
      get: { settings.captureShowHelper },
      set: { settings.setCaptureShowHelper($0) }
    )
  }

  private var captureSmartWindowSelectionBinding: Binding<Bool> {
    Binding(
      get: { settings.captureSmartWindowSelectionEnabled },
      set: { settings.setCaptureSmartWindowSelectionEnabled($0) }
    )
  }

  private var launchAtLoginBinding: Binding<Bool> {
    Binding(
      get: { launchAtLoginController.isEnabled },
      set: { launchAtLoginController.setEnabled($0) }
    )
  }

  private var appLanguageBinding: Binding<AppLanguage> {
    Binding(
      get: { settings.appLanguage },
      set: { settings.setAppLanguage($0) }
    )
  }

  private var alwaysSaveToDefaultDirectoryBinding: Binding<Bool> {
    Binding(
      get: { settings.alwaysSaveToDefaultDirectory },
      set: { settings.setAlwaysSaveToDefaultDirectory($0) }
    )
  }

  private var saveCopiedScreenshotsToDefaultDirectoryBinding: Binding<Bool> {
    Binding(
      get: { settings.saveCopiedScreenshotsToDefaultDirectory },
      set: { settings.setSaveCopiedScreenshotsToDefaultDirectory($0) }
    )
  }

  private var toolbarAccentColorBinding: Binding<Color> {
    Binding(
      get: { Color(settings.toolbarAccentColor) },
      set: { settings.setToolbarAccentColor(NSColor($0)) }
    )
  }

  private var screenshotMainActionBinding: Binding<ScreenshotMainAction> {
    Binding(
      get: { settings.screenshotMainAction },
      set: { settings.setScreenshotMainAction($0) }
    )
  }

  private var defaultCaptureTypeBinding: Binding<CaptureContentType> {
    Binding(
      get: { settings.defaultCaptureType },
      set: { settings.setDefaultCaptureType($0) }
    )
  }

  private var recordingEncoderBinding: Binding<RecordingEncoder> {
    Binding(
      get: { settings.recordingEncoder },
      set: { settings.setRecordingEncoder($0) }
    )
  }

  private var recordingFrameRateBinding: Binding<RecordingFrameRate> {
    Binding(
      get: { settings.recordingFrameRate },
      set: { settings.setRecordingFrameRate($0) }
    )
  }

  private var recordingCountdownBinding: Binding<RecordingCountdown> {
    Binding(
      get: { settings.recordingCountdown },
      set: { settings.setRecordingCountdown($0) }
    )
  }

  private var exportCodecBinding: Binding<PostRecordingExportCodec> {
    Binding(
      get: { settings.exportCodec },
      set: { settings.setVideoExportCodec($0) }
    )
  }

  private var exportFrameRateBinding: Binding<PostRecordingExportFrameRate> {
    Binding(
      get: { settings.exportFrameRate },
      set: { settings.setVideoExportFrameRate($0) }
    )
  }

  private var exportQualityBinding: Binding<PostRecordingExportQuality> {
    Binding(
      get: { settings.exportQuality },
      set: { settings.setVideoExportQuality($0) }
    )
  }

  private var exportScaleBinding: Binding<PostRecordingExportScale> {
    Binding(
      get: { settings.exportScale },
      set: { settings.setVideoExportScale($0) }
    )
  }

  private var exportBitrateBinding: Binding<PostRecordingExportBitratePreset> {
    Binding(
      get: { settings.exportBitrate },
      set: { settings.setVideoExportBitrate($0) }
    )
  }

  private var recordSystemAudioBinding: Binding<Bool> {
    Binding(
      get: { settings.recordSystemAudio },
      set: { settings.setVideoRecordSystemAudio($0) }
    )
  }

  private var recordMicrophoneBinding: Binding<Bool> {
    Binding(
      get: { settings.recordMicrophone },
      set: { settings.setVideoRecordMicrophone($0) }
    )
  }

  private var showWebcamBinding: Binding<Bool> {
    Binding(
      get: { settings.showWebcam },
      set: { settings.setVideoShowWebcam($0) }
    )
  }

  private var webcamOverlaySizeSliderBinding: Binding<Double> {
    Binding(
      get: { settings.webcamOverlayNormalizedWidth },
      set: { settings.setWebcamOverlayWidth($0) }
    )
  }

  private var webcamOverlayShapeBinding: Binding<WebcamShape> {
    Binding(
      get: { settings.webcamOverlayShape },
      set: { settings.setWebcamOverlayShape($0) }
    )
  }

  private var webcamOverlayAspectRatioBinding: Binding<WebcamAspectRatio> {
    Binding(
      get: { settings.webcamOverlayAspectRatio },
      set: { settings.setWebcamOverlayAspectRatio($0) }
    )
  }

  private var mouseClickHighlightStyleBinding: Binding<MouseClickHighlightStyle> {
    Binding(
      get: { settings.mouseClickHighlightStyle },
      set: { settings.setMouseClickHighlightStyle($0) }
    )
  }

  private var highlightMouseClicksBinding: Binding<Bool> {
    Binding(
      get: { settings.highlightMouseClicks },
      set: { settings.setVideoHighlightMouseClicks($0) }
    )
  }

  private var highlightKeystrokesBinding: Binding<Bool> {
    Binding(
      get: { settings.highlightKeystrokes },
      set: { settings.setVideoHighlightKeystrokes($0) }
    )
  }

  private var keystrokeOverlayStyleBinding: Binding<KeystrokeStyle> {
    Binding(
      get: { settings.keystrokeOverlayStyle },
      set: { settings.setKeystrokeOverlayStyle($0) }
    )
  }

  private var keystrokeOverlaySizeSliderBinding: Binding<Double> {
    Binding(
      get: { settings.keystrokeOverlayNormalizedWidth },
      set: { settings.setKeystrokeOverlayScale($0) }
    )
  }

  private var hideNotificationsBestEffortBinding: Binding<Bool> {
    Binding(
      get: { settings.hideNotificationsBestEffort },
      set: { settings.setVideoHideNotificationsBestEffort($0) }
    )
  }

  private var availableExportCodecs: [PostRecordingExportCodec] {
    PostRecordingExportCodec.allCases
  }

  private var availableExportFrameRates: [PostRecordingExportFrameRate] {
    PostRecordingExportFrameRate.allCases
  }

  private var availableExportQualities: [PostRecordingExportQuality] {
    PostRecordingExportQuality.allCases
  }

  private var availableExportScales: [PostRecordingExportScale] {
    PostRecordingExportScale.allCases
  }

  private var availableExportBitrates: [PostRecordingExportBitratePreset] {
    PostRecordingExportBitratePreset.allCases
  }

  private var defaultSaveDirectoryDisplay: String {
    guard let url = settings.defaultSaveDirectoryURL else {
      return String(localized: "No folder selected", bundle: AppLocalizer.shared.bundle)
    }
    return (url.path as NSString).abbreviatingWithTildeInPath
  }

  private func languageLabel(for language: AppLanguage) -> String {
    if language == .system {
      return String(localized: String.LocalizationValue(language.nativeDisplayName), bundle: AppLocalizer.shared.bundle)
    }
    return language.nativeDisplayName
  }

  private func chooseDefaultSaveDirectory() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    panel.prompt = String(localized: "Choose", bundle: AppLocalizer.shared.bundle)
    panel.title = String(localized: "Choose Default Save Folder", bundle: AppLocalizer.shared.bundle)
    panel.directoryURL = settings.defaultSaveDirectoryURL
      ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first

    if panel.runModal() == .OK {
      settings.setDefaultSaveDirectory(panel.url)
    }
  }

  private func revealDefaultSaveDirectoryInFinder() {
    guard let url = settings.defaultSaveDirectoryURL else {
      return
    }
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }

  private func previewCaptureTransition() {
    CaptureTransitionPreviewCoordinator.shared.preview()
  }

  private func overlaySizePercent(_ value: Double) -> String {
    "\(Int((value * 100).rounded()))%"
  }

  private func overlaySliderRow(
    _ label: String,
    value: Binding<Double>,
    range: ClosedRange<Double>,
    displayValue: Double
  ) -> some View {
    HStack(spacing: 10) {
      Text(label)
        .frame(width: overlaySettingsLabelWidth, alignment: .leading)
      Slider(value: value, in: range, step: 0.01)
      Text(overlaySizePercent(displayValue))
        .font(.system(.callout, design: .monospaced).weight(.semibold))
        .frame(width: 54, alignment: .trailing)
    }
  }

  private func overlayPickerRow<Selection: Hashable, Content: View>(
    _ label: String,
    title: String,
    selection: Binding<Selection>,
    @ViewBuilder content: () -> Content
  ) -> some View {
    HStack(spacing: 10) {
      Text(label)
        .frame(width: overlaySettingsLabelWidth, alignment: .leading)
      Spacer(minLength: 0)
      Picker(title, selection: selection) {
        content()
      }
      .labelsHidden()
      .pickerStyle(.menu)
      .frame(width: 190, alignment: .trailing)
    }
  }

  private func overlayPreviewActions(
    _ kind: RecordingOverlaySettingsPreviewKind,
    reset: @escaping () -> Void
  ) -> some View {
    HStack {
      Button(isOverlayPreviewVisible(kind) ? "Hide Preview" : "Show Preview") {
        toggleOverlayPreview(kind)
      }
      Spacer()
      Button("Reset Placement", action: reset)
    }
  }

  private func isOverlayPreviewVisible(_ kind: RecordingOverlaySettingsPreviewKind) -> Bool {
    visibleOverlayPreviews.contains(kind)
  }

  private func toggleOverlayPreview(_ kind: RecordingOverlaySettingsPreviewKind) {
    if visibleOverlayPreviews.contains(kind) {
      RecordingOverlaySettingsPreviewCoordinator.shared.close(kind)
      visibleOverlayPreviews.remove(kind)
    } else {
      RecordingOverlaySettingsPreviewCoordinator.shared.show(kind, settings: settings) { closedKind in
        visibleOverlayPreviews.remove(closedKind)
      }
      visibleOverlayPreviews.insert(kind)
    }
  }
}

@MainActor
private final class RecordingOverlaySettingsPreviewCoordinator {
  static let shared = RecordingOverlaySettingsPreviewCoordinator()

  private var controllers: [RecordingOverlaySettingsPreviewKind: RecordingOverlaySettingsPreviewController] = [:]

  func show(
    _ kind: RecordingOverlaySettingsPreviewKind,
    settings: AppSettings,
    onClose: @escaping (RecordingOverlaySettingsPreviewKind) -> Void
  ) {
    close(kind)
    let controller = RecordingOverlaySettingsPreviewController(kind: kind, settings: settings) { [weak self] closedKind in
      self?.controllers[closedKind] = nil
      onClose(closedKind)
    }
    controllers[kind] = controller
    controller.show()
  }

  func close(_ kind: RecordingOverlaySettingsPreviewKind) {
    controllers.removeValue(forKey: kind)?.close()
  }

  func closeAll() {
    let activeControllers = Array(controllers.values)
    controllers.removeAll()
    for controller in activeControllers {
      controller.close()
    }
  }
}

@MainActor
private final class RecordingOverlaySettingsPreviewController: NSWindowController {
  private let kind: RecordingOverlaySettingsPreviewKind
  private let content: RecordingOverlaySettingsPreviewView
  private let onClosed: (RecordingOverlaySettingsPreviewKind) -> Void
  private var settingsObserver: NSObjectProtocol?
  private var didClose = false

  init(
    kind: RecordingOverlaySettingsPreviewKind,
    settings: AppSettings,
    onClosed: @escaping (RecordingOverlaySettingsPreviewKind) -> Void
  ) {
    self.kind = kind
    self.onClosed = onClosed
    let screenFrame = (NSApp.keyWindow?.screen ?? NSScreen.main)?.visibleFrame ?? CGRect(x: 0, y: 0, width: 960, height: 540)
    content = RecordingOverlaySettingsPreviewView(
      frame: CGRect(origin: .zero, size: screenFrame.size),
      kind: kind,
      settings: settings
    )

    let panel = NSPanel(
      contentRect: screenFrame,
      styleMask: [.nonactivatingPanel, .borderless],
      backing: .buffered,
      defer: false
    )
    panel.isReleasedWhenClosed = false
    panel.level = .screenSaver
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    panel.hidesOnDeactivate = false
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.contentView = content

    super.init(window: panel)

    content.onClose = { [weak self] in
      self?.close()
    }
    settingsObserver = NotificationCenter.default.addObserver(
      forName: .vivyShotSettingsDidChange,
      object: settings,
      queue: .main
    ) { [weak self, weak settings] _ in
      guard let self, let settings else {
        return
      }
      MainActor.assumeIsolated {
        self.content.update(settings: settings)
      }
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  func show() {
    window?.orderFrontRegardless()
    content.startPreview()
  }

  override func close() {
    guard !didClose else {
      return
    }
    didClose = true
    if let settingsObserver {
      NotificationCenter.default.removeObserver(settingsObserver)
      self.settingsObserver = nil
    }
    content.stopPreview()
    super.close()
    onClosed(kind)
  }
}

@MainActor
private final class RecordingOverlaySettingsPreviewView: NSView {
  var onClose: (() -> Void)?

  private let kind: RecordingOverlaySettingsPreviewKind
  private let placementView: CaptureOverlayPlacementView
  private let closeButton = SettingsPreviewCloseButton()
  private weak var settings: AppSettings?

  init(frame frameRect: NSRect, kind: RecordingOverlaySettingsPreviewKind, settings: AppSettings) {
    self.kind = kind
    placementView = CaptureOverlayPlacementView(kind: kind == .webcam ? .webcam : .keystroke)
    self.settings = settings
    super.init(frame: frameRect)

    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor

    placementView.translatesAutoresizingMaskIntoConstraints = true
    placementView.onFrameChanged = { [weak self] frame in
      self?.persist(frame: frame)
    }
    addSubview(placementView)

    addSubview(closeButton)

    update(settings: settings)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  override var isOpaque: Bool { false }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    let frame = placementContainerFrame.insetBy(dx: 0.5, dy: 0.5)
    NSColor.systemRed.withAlphaComponent(0.70).setStroke()
    let outline = NSBezierPath(roundedRect: frame, xRadius: 6, yRadius: 6)
    outline.lineWidth = 1.5
    outline.setLineDash([7, 5], count: 2, phase: 0)
    outline.stroke()
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    guard bounds.contains(point) else {
      return nil
    }
    if closeButtonHitFrame.contains(point) {
      return self
    }
    return placementView.hitTest(placementView.convert(point, from: self))
  }

  override func mouseUp(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    if closeButtonHitFrame.contains(point) {
      onClose?()
    }
  }

  override func layout() {
    super.layout()
    let containerFrame = placementContainerFrame
    let closeButtonSize = CGSize(width: 116, height: 30)
    closeButton.frame = CGRect(
      x: containerFrame.maxX - closeButtonSize.width,
      y: min(bounds.maxY - closeButtonSize.height - 12, containerFrame.maxY + 12),
      width: closeButtonSize.width,
      height: closeButtonSize.height
    ).integral

    guard let settings else {
      return
    }
    placementView.containerFrame = containerFrame
    switch kind {
    case .webcam:
      placementView.frame = resolvedWebcamOverlayFrame(settings.webcamOverlayNormalizedFrame, in: containerFrame)
    case .keystroke:
      placementView.frame = resolvedOverlayFrame(settings.keystrokeOverlayNormalizedFrame, in: containerFrame)
    }
  }

  func startPreview() {
    guard let settings, kind == .webcam else {
      return
    }
    placementView.updateWebcamPreview(preferredDeviceID: settings.webcamDeviceID)
  }

  func stopPreview() {
    placementView.stopWebcamPreview()
  }

  func update(settings: AppSettings) {
    self.settings = settings
    switch kind {
    case .webcam:
      placementView.webcamShape = settings.webcamOverlayShape
      placementView.webcamAspectRatio = settings.webcamOverlayAspectRatio
      placementView.updateWebcamPreview(preferredDeviceID: settings.webcamDeviceID)
    case .keystroke:
      placementView.keystrokeStyle = settings.keystrokeOverlayStyle
      placementView.keystrokeSize = settings.keystrokeOverlaySize
    }
    needsLayout = true
  }

  private var closeButtonHitFrame: CGRect {
    closeButton.frame.insetBy(dx: -8, dy: -8)
  }

  private func persist(frame: CGRect) {
    let containerFrame = placementContainerFrame
    guard let settings, containerFrame.width > 0, containerFrame.height > 0 else {
      return
    }
    let normalized = normalizedOverlayFrame(frame, in: containerFrame)
    switch kind {
    case .webcam:
      settings.setWebcamOverlayFrame(normalized)
    case .keystroke:
      settings.setKeystrokeOverlayFrame(normalized)
    }
  }

  private var placementContainerFrame: CGRect {
    let available = bounds.insetBy(dx: 48, dy: 84)
    guard available.width > 0, available.height > 0 else {
      return .zero
    }

    let targetRatio: CGFloat = 16.0 / 9.0
    var width = min(960, available.width)
    var height = width / targetRatio
    if height > available.height {
      height = available.height
      width = height * targetRatio
    }

    return CGRect(
      x: available.midX - width * 0.5,
      y: available.midY - height * 0.5,
      width: width,
      height: height
    ).integral
  }

  private func resolvedOverlayFrame(_ normalized: CGRect, in container: CGRect) -> CGRect {
    guard container.width > 0, container.height > 0 else {
      return .zero
    }

    let source = normalized.standardized
    let width = min(max(container.width * source.width, 36), container.width)
    let height = min(max(container.height * source.height, 28), container.height)
    let x = min(max(container.minX, container.minX + container.width * source.minX), container.maxX - width)
    let y = min(max(container.minY, container.minY + container.height * source.minY), container.maxY - height)
    return CGRect(x: x, y: y, width: width, height: height).integral
  }

  private func resolvedWebcamOverlayFrame(_ normalized: CGRect, in container: CGRect) -> CGRect {
    guard let settings else {
      return resolvedOverlayFrame(normalized, in: container)
    }

    let frame = resolvedOverlayFrame(normalized, in: container)
    let aspectRatio = settings.webcamOverlayShape == .circle
      ? WebcamAspectRatio.square
      : settings.webcamOverlayAspectRatio
    return aspectRatio.constrainedFrame(frame, in: container, minimumSize: CGSize(width: 84, height: 84))
  }

  private func normalizedOverlayFrame(_ frame: CGRect, in container: CGRect) -> CGRect {
    guard container.width > 0, container.height > 0 else {
      return .zero
    }

    let standardized = frame.standardized
    return CGRect(
      x: (standardized.minX - container.minX) / container.width,
      y: (standardized.minY - container.minY) / container.height,
      width: standardized.width / container.width,
      height: standardized.height / container.height
    )
  }
}

private final class SettingsPreviewCloseButton: NSView {
  private let shellView: NSView
  private let iconView = NSImageView()
  private let titleLabel = NSTextField(labelWithString: "Close Preview")

  init() {
    if #available(macOS 26.0, *) {
      let glassView = NSGlassEffectView()
      glassView.style = .regular
      glassView.cornerRadius = 15
      shellView = glassView
    } else {
      let visualEffectView = NSVisualEffectView()
      visualEffectView.blendingMode = .behindWindow
      visualEffectView.material = .hudWindow
      visualEffectView.state = .active
      visualEffectView.wantsLayer = true
      visualEffectView.layer?.cornerRadius = 15
      visualEffectView.layer?.masksToBounds = true
      shellView = visualEffectView
    }

    super.init(frame: .zero)

    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor
    translatesAutoresizingMaskIntoConstraints = true

    shellView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(shellView)

    iconView.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: nil)
    iconView.contentTintColor = .white.withAlphaComponent(0.88)
    iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
    iconView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(iconView)

    titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
    titleLabel.textColor = .white.withAlphaComponent(0.92)
    titleLabel.backgroundColor = .clear
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    addSubview(titleLabel)

    NSLayoutConstraint.activate([
      shellView.leadingAnchor.constraint(equalTo: leadingAnchor),
      shellView.trailingAnchor.constraint(equalTo: trailingAnchor),
      shellView.topAnchor.constraint(equalTo: topAnchor),
      shellView.bottomAnchor.constraint(equalTo: bottomAnchor),

      iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 11),
      iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
      iconView.widthAnchor.constraint(equalToConstant: 14),
      iconView.heightAnchor.constraint(equalToConstant: 14),

      titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
      titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
      titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  override var isOpaque: Bool {
    false
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    true
  }
}

private struct ReorderHandleGlyph: View {
  let active: Bool

  var body: some View {
    VStack(spacing: 2) {
      ForEach(0 ..< 4, id: \.self) { _ in
        Capsule(style: .continuous)
          .frame(width: 11, height: 1.5)
      }
    }
    .foregroundStyle(active ? .primary : .tertiary)
    .frame(width: 18, height: 18)
    .padding(.trailing, 2)
  }
}

private struct ToolbarToolDropDelegate: DropDelegate {
  let target: AnnotationTool
  let currentOrder: [AnnotationTool]
  @Binding var draggingTool: AnnotationTool?
  let onMove: (IndexSet, Int) -> Void

  func dropEntered(info: DropInfo) {
    guard let draggingTool else {
      return
    }
    guard draggingTool != target else {
      return
    }
    guard let fromIndex = currentOrder.firstIndex(of: draggingTool),
          let toIndex = currentOrder.firstIndex(of: target)
    else {
      return
    }
    guard currentOrder[toIndex] != draggingTool else {
      return
    }

    let destination = toIndex > fromIndex ? toIndex + 1 : toIndex
    withAnimation(.easeInOut(duration: 0.12)) {
      onMove(IndexSet(integer: fromIndex), destination)
    }
  }

  func dropUpdated(info: DropInfo) -> DropProposal? {
    DropProposal(operation: .move)
  }

  func performDrop(info: DropInfo) -> Bool {
    draggingTool = nil
    return true
  }
}

private struct RecordingToolDropDelegate: DropDelegate {
  let target: RecordingTool
  let currentOrder: [RecordingTool]
  @Binding var draggingTool: RecordingTool?
  let onMove: (IndexSet, Int) -> Void

  func dropEntered(info: DropInfo) {
    guard let draggingTool else {
      return
    }
    guard draggingTool != target else {
      return
    }
    guard let fromIndex = currentOrder.firstIndex(of: draggingTool),
          let toIndex = currentOrder.firstIndex(of: target)
    else {
      return
    }
    guard currentOrder[toIndex] != draggingTool else {
      return
    }

    let destination = toIndex > fromIndex ? toIndex + 1 : toIndex
    withAnimation(.easeInOut(duration: 0.12)) {
      onMove(IndexSet(integer: fromIndex), destination)
    }
  }

  func dropUpdated(info: DropInfo) -> DropProposal? {
    DropProposal(operation: .move)
  }

  func performDrop(info: DropInfo) -> Bool {
    draggingTool = nil
    return true
  }
}

private struct AboutLinkRow: View {
  let title: String
  var subtitle: String?
  var systemImage: String?
  var assetImage: String?
  let url: URL

  var body: some View {
    Link(destination: url) {
      HStack(spacing: 14) {
        icon
          .frame(width: 28, height: 28)

        VStack(alignment: .leading, spacing: 2) {
          Text(title)
          if let subtitle {
            Text(subtitle)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  @ViewBuilder
  private var icon: some View {
    if let assetImage {
      Image(assetImage)
        .resizable()
        .interpolation(.high)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    } else if let systemImage {
      Image(systemName: systemImage)
        .font(.system(size: 20, weight: .regular))
    }
  }
}

private struct ReviewerModeSheet: View {
  @ObservedObject private var storeManager = StoreManager.shared
  @Environment(\.dismiss) private var dismiss
  @State private var reviewCode = ""
  @State private var reviewError: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(spacing: 14) {
        ZStack {
          Circle()
            .fill(Color.green.opacity(0.16))
            .frame(width: 44, height: 44)
          Image(systemName: "checkmark.seal.fill")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.green)
        }

        VStack(alignment: .leading, spacing: 4) {
          Text("App Review")
            .font(.title3)
            .fontWeight(.semibold)
          Text("Temporarily unlocks Lifetime and Supporter access.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }

      statusCard

      if storeManager.isReviewModeEnabled {
        enabledSection
      } else {
        codeSection
      }

      HStack {
        Spacer()
        Button("Done") {
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(24)
    .frame(width: 460)
  }

  private var statusCard: some View {
    HStack {
      Text("Reviewer Mode")
        .font(.subheadline)
        .foregroundStyle(.secondary)
      Spacer()
      Text(storeManager.isReviewModeEnabled ? "Enabled" : "Disabled")
        .font(.caption)
        .fontWeight(.semibold)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
          Capsule()
            .fill(storeManager.isReviewModeEnabled ? Color.green.opacity(0.18) : Color.secondary.opacity(0.12))
        )
        .foregroundStyle(storeManager.isReviewModeEnabled ? .green : .secondary)
    }
    .padding(12)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color.primary.opacity(0.04))
    )
  }

  private var enabledSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Reviewer mode is active on this device.")
        .font(.subheadline)
      Text(reviewModeExpiryText)
        .font(.footnote)
        .foregroundStyle(.secondary)

      Button("Disable Reviewer Mode") {
        storeManager.setReviewModeEnabled(false)
      }
      .buttonStyle(.bordered)
    }
    .padding(16)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color.primary.opacity(0.04))
    )
  }

  private var codeSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Enter the review code to enable full access for App Review.")
        .font(.subheadline)
      TextField("Review Code", text: $reviewCode)
        .textFieldStyle(.roundedBorder)

      Button("Enable Reviewer Mode") {
        let success = storeManager.enableReviewMode(code: reviewCode)
        if success {
          reviewError = nil
          reviewCode = ""
        } else {
          reviewError = "Invalid review code."
        }
      }
      .buttonStyle(.borderedProminent)
      .disabled(reviewCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

      if let reviewError {
        Text(reviewError)
          .font(.footnote)
          .foregroundStyle(.red)
      }

      Text("Reviewer mode is local-only and expires after 2 hours or when the app restarts.")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
    .padding(16)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color.primary.opacity(0.04))
    )
  }

  private var reviewModeExpiryText: String {
    guard let expiresAt = storeManager.reviewModeExpiresAt else {
      return String(
        localized: "Lifetime and Supporter access are unlocked until the app restarts.",
        bundle: AppLocalizer.shared.bundle
      )
    }

    let format = String(
      localized: "Lifetime and Supporter access are unlocked until %@.",
      bundle: AppLocalizer.shared.bundle
    )
    return String(format: format, expiresAt.formatted(date: .omitted, time: .shortened))
  }
}

private struct ShortcutRecorderFieldRepresentable: NSViewRepresentable {
  let displayText: String
  @Binding var isRecording: Bool
  let onCapture: (UInt32, NSEvent.ModifierFlags) -> Void

  @MainActor
  final class Coordinator {
    var parent: ShortcutRecorderFieldRepresentable

    init(parent: ShortcutRecorderFieldRepresentable) {
      self.parent = parent
    }

    func handleCapture(keyCode: UInt32, flags: NSEvent.ModifierFlags) {
      parent.onCapture(keyCode, flags)
      parent.isRecording = false
    }

    func handleRecordingChange(_ active: Bool) {
      if parent.isRecording != active {
        parent.isRecording = active
      }
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  func makeNSView(context: Context) -> ShortcutRecorderTextField {
    let field = ShortcutRecorderTextField(frame: .zero)
    field.displayString = displayText
    field.stringValue = displayText
    field.onCapture = { keyCode, flags in
      context.coordinator.handleCapture(keyCode: keyCode, flags: flags)
    }
    field.onRecordingChange = { isActive in
      context.coordinator.handleRecordingChange(isActive)
    }
    return field
  }

  func updateNSView(_ nsView: ShortcutRecorderTextField, context: Context) {
    context.coordinator.parent = self

    nsView.displayString = displayText
    if !nsView.isRecording, nsView.stringValue != displayText {
      nsView.stringValue = displayText
    }

    if nsView.isRecording != isRecording {
      nsView.isRecording = isRecording
    }

    if isRecording, nsView.window?.firstResponder !== nsView {
      nsView.window?.makeFirstResponder(nsView)
    }
  }
}

private final class ShortcutRecorderTextField: NSTextField {
  var onCapture: ((UInt32, NSEvent.ModifierFlags) -> Void)?
  var onRecordingChange: ((Bool) -> Void)?
  var displayString: String = ""

  var isRecording: Bool = false {
    didSet {
      guard oldValue != isRecording else {
        return
      }
      if isRecording {
        stringValue = "Press Shortcut"
        window?.makeFirstResponder(self)
      } else {
        stringValue = displayString
      }
      updateAppearance()
      onRecordingChange?(isRecording)
    }
  }

  override var acceptsFirstResponder: Bool { true }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    isEditable = false
    isSelectable = false
    isBezeled = true
    bezelStyle = .roundedBezel
    focusRingType = .none
    alignment = .center
    lineBreakMode = .byTruncatingTail
    font = .systemFont(ofSize: 12, weight: .semibold)
    updateAppearance()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  override func keyDown(with event: NSEvent) {
    guard isRecording else {
      super.keyDown(with: event)
      return
    }

    let keyCode = UInt32(event.keyCode)
    if keyCode == UInt32(kVK_Escape) {
      isRecording = false
      return
    }

    if Self.modifierOnlyKeyCodes.contains(keyCode) {
      return
    }

    let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
    onCapture?(keyCode, flags)
    isRecording = false
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    guard isRecording else {
      return super.performKeyEquivalent(with: event)
    }
    keyDown(with: event)
    return true
  }

  override func resignFirstResponder() -> Bool {
    let resigned = super.resignFirstResponder()
    if resigned, isRecording {
      isRecording = false
    }
    return resigned
  }

  private func updateAppearance() {
    textColor = isRecording ? NSColor.controlAccentColor : NSColor.labelColor
  }

  private static let modifierOnlyKeyCodes: Set<UInt32> = [
    UInt32(kVK_Command),
    UInt32(kVK_RightCommand),
    UInt32(kVK_Shift),
    UInt32(kVK_RightShift),
    UInt32(kVK_Option),
    UInt32(kVK_RightOption),
    UInt32(kVK_Control),
    UInt32(kVK_RightControl),
    UInt32(kVK_CapsLock),
    UInt32(kVK_Function),
  ]
}
