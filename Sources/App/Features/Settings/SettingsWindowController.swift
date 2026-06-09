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
  @State private var webcamDevices: [WebcamDeviceOption] = []
  @State private var draggingScreenshotTool: AnnotationTool?
  @State private var draggingVideoTool: RecordingTool?
  @State private var isReviewerModeSheetPresented = false
  private var captureTransitionEffectsVisible: Bool { true }
  private var microphoneFeatureVisible: Bool { true }
  private var webcamFeatureVisible: Bool { true }
  private var keystrokesFeatureVisible: Bool { true }

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
          webcamSection
        }
        mouseClickSection
        if keystrokesFeatureVisible {
          keystrokeSection
        }
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
      if webcamFeatureVisible {
        refreshWebcamDevices()
      }
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

  private var webcamSection: some View {
    Section {
      if webcamFeatureVisible {
        Toggle("Show webcam", isOn: showWebcamBinding)
          .toggleStyle(.switch)
      }
      if webcamFeatureVisible, settings.showWebcam {
        HStack(spacing: 10) {
          Text("Camera")
            .frame(width: 78, alignment: .leading)
          Spacer(minLength: 0)
          Picker("Webcam Device", selection: webcamDeviceIDBinding) {
            Text("System Default").tag("")
            ForEach(webcamDevices) { device in
              Text(device.name).tag(device.id)
            }
            if !settings.webcamDeviceID.isEmpty,
               !webcamDevices.contains(where: { $0.id == settings.webcamDeviceID })
            {
              Text("Unavailable Camera").tag(settings.webcamDeviceID)
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .frame(width: 190, alignment: .trailing)
        }

        HStack(spacing: 10) {
          Text("Webcam Size")
            .frame(width: 78, alignment: .leading)
          Spacer(minLength: 0)
          Picker("Webcam Overlay Size", selection: webcamOverlaySizeBinding) {
            ForEach(WebcamOverlaySize.allCases) { size in
              Text(size.title).tag(size)
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .frame(width: 190, alignment: .trailing)
        }

        HStack(spacing: 10) {
          Text("Webcam Shape")
            .frame(width: 78, alignment: .leading)
          Spacer(minLength: 0)
          Picker("Webcam Overlay Shape", selection: webcamOverlayShapeBinding) {
            ForEach(WebcamShape.allCases) { shape in
              Text(shape.title).tag(shape)
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .frame(width: 190, alignment: .trailing)
        }

        HStack(spacing: 10) {
          Text("Aspect Ratio")
            .frame(width: 78, alignment: .leading)
          Spacer(minLength: 0)
          Picker("Webcam Aspect Ratio", selection: webcamOverlayAspectRatioBinding) {
            ForEach(WebcamAspectRatio.allCases) { aspectRatio in
              Text(aspectRatio.title).tag(aspectRatio)
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .frame(width: 190, alignment: .trailing)
          .disabled(settings.webcamOverlayShape == .circle)
        }

        LabeledContent("Size") {
          HStack(spacing: 10) {
            Slider(
              value: webcamOverlayWidthBinding,
              in: 0.12 ... 0.50,
              step: 0.01
            )
            Text(String(format: "%.0f%%", settings.webcamOverlayNormalizedWidth * 100))
              .font(.system(.callout, design: .monospaced).weight(.semibold))
              .frame(width: 46, alignment: .trailing)
          }
        }

        HStack {
          Spacer()
          Button("Reset Webcam Placement") {
            settings.resetWebcamOverlayPlacement()
          }
        }
      }
    } header: {
      Text("Webcam Overlay")
    } footer: {
      Text("Webcam overlays require camera permission.")
    }
  }

  private var mouseClickSection: some View {
    Section("Mouse Click Highlights") {
      Picker("Click Style", selection: mouseClickHighlightStyleBinding) {
        ForEach(MouseClickHighlightStyle.allCases) { style in
          Text(style.title).tag(style)
        }
      }
      .pickerStyle(.menu)
    }
  }

  private var keystrokeSection: some View {
    Section {
      if keystrokesFeatureVisible {
        Toggle("Highlight keystrokes", isOn: highlightKeystrokesBinding)
          .toggleStyle(.switch)
        if settings.highlightKeystrokes {
          HStack(spacing: 10) {
            Text("Key Style")
              .frame(width: 78, alignment: .leading)
            Spacer(minLength: 0)
            Picker("Keystroke Overlay Style", selection: keystrokeOverlayStyleBinding) {
              ForEach(KeystrokeStyle.allCases) { style in
                Text(style.title).tag(style)
              }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 190, alignment: .trailing)
          }

          HStack(spacing: 10) {
            Text("Key Size")
              .frame(width: 78, alignment: .leading)
            Spacer(minLength: 0)
            Picker("Keystroke Overlay Size", selection: keystrokeOverlaySizeBinding) {
              ForEach(KeystrokeSize.allCases) { size in
                Text(size.title).tag(size)
              }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 190, alignment: .trailing)
          }

          LabeledContent("Width") {
            HStack(spacing: 10) {
              Slider(
                value: keystrokeOverlayWidthBinding,
                in: 0.20 ... 0.72,
                step: 0.01
              )
              Text(String(format: "%.0f%%", settings.keystrokeOverlayNormalizedWidth * 100))
                .font(.system(.callout, design: .monospaced).weight(.semibold))
                .frame(width: 46, alignment: .trailing)
            }
          }

          LabeledContent("Height") {
            HStack(spacing: 10) {
              Slider(
                value: keystrokeOverlayHeightBinding,
                in: 0.07 ... 0.28,
                step: 0.01
              )
              Text(String(format: "%.0f%%", settings.keystrokeOverlayNormalizedHeight * 100))
                .font(.system(.callout, design: .monospaced).weight(.semibold))
                .frame(width: 46, alignment: .trailing)
            }
          }

          HStack {
            Spacer()
            Button("Reset Key Placement") {
              settings.resetKeystrokeOverlayPlacement()
            }
          }
        }
      }
    } header: {
      Text("Keystroke Overlay")
    } footer: {
      Text("Keystroke overlays require accessibility permission.")
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

  private var webcamDeviceIDBinding: Binding<String> {
    Binding(
      get: { settings.webcamDeviceID },
      set: { settings.setVideoWebcamDeviceID($0) }
    )
  }

  private var webcamOverlaySizeBinding: Binding<WebcamOverlaySize> {
    Binding(
      get: { settings.webcamOverlaySize },
      set: { settings.setWebcamOverlaySize($0) }
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

  private var webcamOverlayWidthBinding: Binding<Double> {
    Binding(
      get: { settings.webcamOverlayNormalizedWidth },
      set: { settings.setWebcamOverlayWidth($0) }
    )
  }

  private var mouseClickHighlightStyleBinding: Binding<MouseClickHighlightStyle> {
    Binding(
      get: { settings.mouseClickHighlightStyle },
      set: { settings.setMouseClickHighlightStyle($0) }
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

  private var keystrokeOverlaySizeBinding: Binding<KeystrokeSize> {
    Binding(
      get: { settings.keystrokeOverlaySize },
      set: { settings.setKeystrokeOverlaySize($0) }
    )
  }

  private var keystrokeOverlayWidthBinding: Binding<Double> {
    Binding(
      get: { settings.keystrokeOverlayNormalizedWidth },
      set: { settings.setKeystrokeOverlayWidth($0) }
    )
  }

  private var keystrokeOverlayHeightBinding: Binding<Double> {
    Binding(
      get: { settings.keystrokeOverlayNormalizedHeight },
      set: { settings.setKeystrokeOverlayHeight($0) }
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

  private func refreshWebcamDevices() {
    var deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
    if #available(macOS 14.0, *) {
      deviceTypes.append(.external)
    } else {
      deviceTypes.append(.externalUnknown)
    }
    let discovery = AVCaptureDevice.DiscoverySession(
      deviceTypes: deviceTypes,
      mediaType: .video,
      position: .unspecified
    )
    webcamDevices = discovery.devices
      .map { WebcamDeviceOption(id: $0.uniqueID, name: $0.localizedName) }
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  private func previewCaptureTransition() {
    CaptureTransitionPreviewCoordinator.shared.preview()
  }
}

private struct WebcamDeviceOption: Identifiable, Hashable {
  let id: String
  let name: String
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
