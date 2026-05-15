import AppKit
import AVFoundation
import Carbon
import SwiftUI

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

@MainActor
func installSettingsWindowPresenter(_ openSettings: OpenSettingsAction) {
  SettingsWindowPresentation.openSettings = {
    openSettings()
  }
}

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

@MainActor
struct VivyShotSettingsView: View {
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
  @State private var draggingVideoTool: VideoToolbarTool?
  @State private var isReviewerModeSheetPresented = false
  private var captureTransitionEffectsVisible: Bool { true }
  private var videoMicrophoneFeatureVisible: Bool { true }
  private var videoWebcamFeatureVisible: Bool { true }
  private var videoKeystrokesFeatureVisible: Bool { true }

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
        videoCaptureSection
        if videoWebcamFeatureVisible {
          videoWebcamSection
        }
        videoMouseClickSection
        if videoKeystrokesFeatureVisible {
          videoKeystrokeSection
        }
        videoToolbarSection
      }
      .tabItem { Label(SettingsTab.video.title, systemImage: "record.circle") }
      .tag(SettingsTab.video)

      VivyShotStatisticsView(presentation: .settings)
        .tabItem { Label(SettingsTab.statistics.title, systemImage: "chart.bar.xaxis") }
        .tag(SettingsTab.statistics)

      VivyShotStoreSettingsView()
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
      if videoWebcamFeatureVisible {
        refreshWebcamDevices()
      }
    }
    .sheet(isPresented: $isReviewerModeSheetPresented) {
      VivyShotReviewerModeSheet()
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

        Text("Capture with intent. Edit with precision.")
          .font(.callout)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)

        Text("Selection-first screen capture for screenshots, recordings, and timeline-driven polish.")
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
      Link(destination: URL(string: "https://vivyshot.com")!) {
        Label("Website", systemImage: "globe")
      }

      Link(destination: URL(string: "https://vivyshot.com/privacy")!) {
        Label("Privacy Policy", systemImage: "hand.raised")
      }

      Link(destination: URL(string: "https://vivyshot.com/terms")!) {
        Label("Terms of Use", systemImage: "doc.text")
      }
    }
  }

  private var aboutContactSection: some View {
    Section("Get in Touch") {
      Link(destination: URL(string: "https://x.com/wiedymi")!) {
        Label("Developer", systemImage: "person.crop.circle")
      }

      Link(destination: URL(string: "https://discord.gg/zemMZtrkSb")!) {
        Label("Discord", systemImage: "bubble.left.and.bubble.right")
      }

      Link(destination: URL(string: "mailto:vivyshot@vivy.company")!) {
        Label("Email", systemImage: "envelope")
      }
    }
  }

  private var aboutAppsSection: some View {
    Section("Our Apps") {
      Link(destination: URL(string: "https://vvterm.com")!) {
        Label {
          VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: "VVTerm")
            Text("Professional SSH client for macOS and iOS")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        } icon: {
          Image(systemName: "terminal")
        }
      }
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
          localized: "Choose the default mode and whether VivyShot shows the helper after capture starts.",
          bundle: AppLocalizer.shared.bundle
        )
      )
    }
  }

  private var savingSection: some View {
    Section {
      LabeledContent("Default Folder") {
        Text(defaultSaveDirectoryDisplay)
          .font(.system(.callout, design: .monospaced))
          .foregroundStyle(settings.defaultSaveDirectoryURL == nil ? .secondary : .primary)
          .lineLimit(2)
          .multilineTextAlignment(.trailing)
      }

      HStack(spacing: 8) {
        Button("Choose Folder…") {
          chooseDefaultSaveDirectory()
        }
        .buttonStyle(.bordered)

        Button("Clear") {
          settings.setDefaultSaveDirectory(nil)
        }
        .buttonStyle(.bordered)
        .disabled(settings.defaultSaveDirectoryURL == nil)

        Button("Show in Finder") {
          revealDefaultSaveDirectoryInFinder()
        }
        .buttonStyle(.bordered)
        .disabled(settings.defaultSaveDirectoryURL == nil)

        Spacer(minLength: 0)
      }

      Toggle("Always save to this folder (skip Save dialog)", isOn: alwaysSaveToDefaultDirectoryBinding)
        .toggleStyle(.switch)
        .disabled(settings.defaultSaveDirectoryURL == nil)
    } header: {
      Text("Saving")
    } footer: {
      Text(
        String(
          localized: settings.defaultSaveDirectoryURL == nil
            ? "If no folder is selected, VivyShot asks where to save each capture."
            : "Turn on Always Save to skip the save dialog and save directly into the selected folder.",
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

  private var videoCaptureSection: some View {
    Section("Video Capture") {
      HStack(spacing: 10) {
        Text("Quality")
          .frame(width: 78, alignment: .leading)
        Spacer(minLength: 0)
        Picker("Video Quality", selection: videoCodecBinding) {
          ForEach(VideoCodecOption.allCases) { codec in
            Text(codec.title).tag(codec)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 190, alignment: .trailing)
      }

      HStack(spacing: 10) {
        Text("Frame Rate")
          .frame(width: 78, alignment: .leading)
        Spacer(minLength: 0)
        Picker("Video Frame Rate", selection: videoFrameRateBinding) {
          ForEach(VideoFrameRateOption.allCases) { rate in
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
        Picker("Video Countdown", selection: videoCountdownBinding) {
          ForEach(VideoCountdownOption.allCases) { countdown in
            Text(countdown.title).tag(countdown)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 190, alignment: .trailing)
      }

      Toggle("Record system audio", isOn: videoRecordSystemAudioBinding)
        .toggleStyle(.switch)
      if videoMicrophoneFeatureVisible {
        Toggle("Record microphone", isOn: videoRecordMicrophoneBinding)
          .toggleStyle(.switch)
      }
      Toggle("Hide notifications (best effort)", isOn: videoHideNotificationsBestEffortBinding)
        .toggleStyle(.switch)

      HStack {
        Spacer()
        Button("Reset Video") {
          settings.resetVideoCaptureSettings()
        }
      }
    }
  }

  private var videoWebcamSection: some View {
    Section {
      if videoWebcamFeatureVisible {
        Toggle("Show webcam", isOn: videoShowWebcamBinding)
          .toggleStyle(.switch)
      }
      if videoWebcamFeatureVisible, settings.videoShowWebcam {
        HStack(spacing: 10) {
          Text("Camera")
            .frame(width: 78, alignment: .leading)
          Spacer(minLength: 0)
          Picker("Webcam Device", selection: videoWebcamDeviceIDBinding) {
            Text("System Default").tag("")
            ForEach(webcamDevices) { device in
              Text(device.name).tag(device.id)
            }
            if !settings.videoWebcamDeviceID.isEmpty,
               !webcamDevices.contains(where: { $0.id == settings.videoWebcamDeviceID })
            {
              Text("Unavailable Camera").tag(settings.videoWebcamDeviceID)
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
          Picker("Webcam Overlay Size", selection: videoWebcamOverlaySizeBinding) {
            ForEach(VideoWebcamOverlaySizeOption.allCases) { size in
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
          Picker("Webcam Overlay Shape", selection: videoWebcamOverlayShapeBinding) {
            ForEach(VideoWebcamOverlayShapeOption.allCases) { shape in
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
          Picker("Webcam Aspect Ratio", selection: videoWebcamOverlayAspectRatioBinding) {
            ForEach(VideoWebcamOverlayAspectRatioOption.allCases) { aspectRatio in
              Text(aspectRatio.title).tag(aspectRatio)
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .frame(width: 190, alignment: .trailing)
          .disabled(settings.videoWebcamOverlayShape == .circle)
        }

        LabeledContent("Size") {
          HStack(spacing: 10) {
            Slider(
              value: videoWebcamOverlayWidthBinding,
              in: 0.12 ... 0.50,
              step: 0.01
            )
            Text(String(format: "%.0f%%", settings.videoWebcamOverlayNormalizedWidth * 100))
              .font(.system(.callout, design: .monospaced).weight(.semibold))
              .frame(width: 46, alignment: .trailing)
          }
        }

        HStack {
          Spacer()
          Button("Reset Webcam Placement") {
            settings.resetVideoWebcamOverlayPlacement()
          }
        }
      }
    } header: {
      Text("Webcam Overlay")
    } footer: {
      Text("Webcam overlays require camera permission.")
    }
  }

  private var videoMouseClickSection: some View {
    Section("Mouse Click Highlights") {
      Toggle("Highlight mouse clicks", isOn: videoHighlightMouseClicksBinding)
        .toggleStyle(.switch)
    }
  }

  private var videoKeystrokeSection: some View {
    Section {
      if videoKeystrokesFeatureVisible {
        Toggle("Highlight keystrokes", isOn: videoHighlightKeystrokesBinding)
          .toggleStyle(.switch)
        if settings.videoHighlightKeystrokes {
          HStack(spacing: 10) {
            Text("Key Style")
              .frame(width: 78, alignment: .leading)
            Spacer(minLength: 0)
            Picker("Keystroke Overlay Style", selection: videoKeystrokeOverlayStyleBinding) {
              ForEach(VideoKeystrokeOverlayStyleOption.allCases) { style in
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
            Picker("Keystroke Overlay Size", selection: videoKeystrokeOverlaySizeBinding) {
              ForEach(VideoKeystrokeOverlaySizeOption.allCases) { size in
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
                value: videoKeystrokeOverlayWidthBinding,
                in: 0.20 ... 0.72,
                step: 0.01
              )
              Text(String(format: "%.0f%%", settings.videoKeystrokeOverlayNormalizedWidth * 100))
                .font(.system(.callout, design: .monospaced).weight(.semibold))
                .frame(width: 46, alignment: .trailing)
            }
          }

          LabeledContent("Height") {
            HStack(spacing: 10) {
              Slider(
                value: videoKeystrokeOverlayHeightBinding,
                in: 0.07 ... 0.28,
                step: 0.01
              )
              Text(String(format: "%.0f%%", settings.videoKeystrokeOverlayNormalizedHeight * 100))
                .font(.system(.callout, design: .monospaced).weight(.semibold))
                .frame(width: 46, alignment: .trailing)
            }
          }

          HStack {
            Spacer()
            Button("Reset Key Placement") {
              settings.resetVideoKeystrokeOverlayPlacement()
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

  private var videoToolbarSection: some View {
    Section("Video Toolbar") {
      Text("Drag rows to reorder. Hidden tools won’t appear in video toolbar.")
        .font(.caption)
        .foregroundStyle(.secondary)

      VStack(spacing: 0) {
        ForEach(settings.videoToolOrder) { tool in
          if shouldShowVideoToolbarTool(tool) {
            HStack(spacing: 10) {
              Image(systemName: tool.symbolName)
                .frame(width: 18)
                .foregroundStyle(.secondary)

              Text(tool.title)
                .frame(maxWidth: .infinity, alignment: .leading)

              Toggle("", isOn: videoToolVisibilityBinding(for: tool))
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
              delegate: VideoToolbarToolDropDelegate(
                target: tool,
                currentOrder: settings.videoToolOrder,
                draggingTool: $draggingVideoTool,
                onMove: settings.moveVideoTools
              )
            )

            if tool != lastVisibleVideoToolbarTool {
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

  private func videoToolVisibilityBinding(for tool: VideoToolbarTool) -> Binding<Bool> {
    Binding(
      get: { settings.isVideoToolVisible(tool) },
      set: { settings.setVideoToolVisible(tool, isVisible: $0) }
    )
  }

  private var lastVisibleVideoToolbarTool: VideoToolbarTool? {
    settings.videoToolOrder.last(where: shouldShowVideoToolbarTool)
  }

  private func shouldShowVideoToolbarTool(_ tool: VideoToolbarTool) -> Bool {
    switch tool {
    case .microphone:
      return videoMicrophoneFeatureVisible
    case .webcam:
      return videoWebcamFeatureVisible
    case .keystrokes:
      return videoKeystrokesFeatureVisible
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

  private var videoCodecBinding: Binding<VideoCodecOption> {
    Binding(
      get: { settings.videoCodec },
      set: { settings.setVideoCodec($0) }
    )
  }

  private var videoFrameRateBinding: Binding<VideoFrameRateOption> {
    Binding(
      get: { settings.videoFrameRate },
      set: { settings.setVideoFrameRate($0) }
    )
  }

  private var videoCountdownBinding: Binding<VideoCountdownOption> {
    Binding(
      get: { settings.videoCountdown },
      set: { settings.setVideoCountdown($0) }
    )
  }

  private var videoExportCodecBinding: Binding<PostRecordingExportCodec> {
    Binding(
      get: { settings.videoExportCodec },
      set: { settings.setVideoExportCodec($0) }
    )
  }

  private var videoExportFrameRateBinding: Binding<PostRecordingExportFrameRate> {
    Binding(
      get: { settings.videoExportFrameRate },
      set: { settings.setVideoExportFrameRate($0) }
    )
  }

  private var videoExportQualityBinding: Binding<PostRecordingExportQuality> {
    Binding(
      get: { settings.videoExportQuality },
      set: { settings.setVideoExportQuality($0) }
    )
  }

  private var videoExportScaleBinding: Binding<PostRecordingExportScale> {
    Binding(
      get: { settings.videoExportScale },
      set: { settings.setVideoExportScale($0) }
    )
  }

  private var videoExportBitrateBinding: Binding<PostRecordingExportBitratePreset> {
    Binding(
      get: { settings.videoExportBitrate },
      set: { settings.setVideoExportBitrate($0) }
    )
  }

  private var videoRecordSystemAudioBinding: Binding<Bool> {
    Binding(
      get: { settings.videoRecordSystemAudio },
      set: { settings.setVideoRecordSystemAudio($0) }
    )
  }

  private var videoRecordMicrophoneBinding: Binding<Bool> {
    Binding(
      get: { settings.videoRecordMicrophone },
      set: { settings.setVideoRecordMicrophone($0) }
    )
  }

  private var videoShowWebcamBinding: Binding<Bool> {
    Binding(
      get: { settings.videoShowWebcam },
      set: { settings.setVideoShowWebcam($0) }
    )
  }

  private var videoWebcamDeviceIDBinding: Binding<String> {
    Binding(
      get: { settings.videoWebcamDeviceID },
      set: { settings.setVideoWebcamDeviceID($0) }
    )
  }

  private var videoWebcamOverlaySizeBinding: Binding<VideoWebcamOverlaySizeOption> {
    Binding(
      get: { settings.videoWebcamOverlaySize },
      set: { settings.setVideoWebcamOverlaySize($0) }
    )
  }

  private var videoWebcamOverlayShapeBinding: Binding<VideoWebcamOverlayShapeOption> {
    Binding(
      get: { settings.videoWebcamOverlayShape },
      set: { settings.setVideoWebcamOverlayShape($0) }
    )
  }

  private var videoWebcamOverlayAspectRatioBinding: Binding<VideoWebcamOverlayAspectRatioOption> {
    Binding(
      get: { settings.videoWebcamOverlayAspectRatio },
      set: { settings.setVideoWebcamOverlayAspectRatio($0) }
    )
  }

  private var videoWebcamOverlayWidthBinding: Binding<Double> {
    Binding(
      get: { settings.videoWebcamOverlayNormalizedWidth },
      set: { settings.setVideoWebcamOverlayNormalizedWidth($0) }
    )
  }

  private var videoHighlightMouseClicksBinding: Binding<Bool> {
    Binding(
      get: { settings.videoHighlightMouseClicks },
      set: { settings.setVideoHighlightMouseClicks($0) }
    )
  }

  private var videoHighlightKeystrokesBinding: Binding<Bool> {
    Binding(
      get: { settings.videoHighlightKeystrokes },
      set: { settings.setVideoHighlightKeystrokes($0) }
    )
  }

  private var videoKeystrokeOverlayStyleBinding: Binding<VideoKeystrokeOverlayStyleOption> {
    Binding(
      get: { settings.videoKeystrokeOverlayStyle },
      set: { settings.setVideoKeystrokeOverlayStyle($0) }
    )
  }

  private var videoKeystrokeOverlaySizeBinding: Binding<VideoKeystrokeOverlaySizeOption> {
    Binding(
      get: { settings.videoKeystrokeOverlaySize },
      set: { settings.setVideoKeystrokeOverlaySize($0) }
    )
  }

  private var videoKeystrokeOverlayWidthBinding: Binding<Double> {
    Binding(
      get: { settings.videoKeystrokeOverlayNormalizedWidth },
      set: { settings.setVideoKeystrokeOverlayNormalizedWidth($0) }
    )
  }

  private var videoKeystrokeOverlayHeightBinding: Binding<Double> {
    Binding(
      get: { settings.videoKeystrokeOverlayNormalizedHeight },
      set: { settings.setVideoKeystrokeOverlayNormalizedHeight($0) }
    )
  }

  private var videoHideNotificationsBestEffortBinding: Binding<Bool> {
    Binding(
      get: { settings.videoHideNotificationsBestEffort },
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
      return String(localized: "Not set", bundle: AppLocalizer.shared.bundle)
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

private struct VideoToolbarToolDropDelegate: DropDelegate {
  let target: VideoToolbarTool
  let currentOrder: [VideoToolbarTool]
  @Binding var draggingTool: VideoToolbarTool?
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

private struct VivyShotReviewerModeSheet: View {
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
