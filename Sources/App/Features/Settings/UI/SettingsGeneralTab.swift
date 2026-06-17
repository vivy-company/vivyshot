import AppKit
import SwiftUI

@MainActor
extension SettingsView {
  var languageSection: some View {
    Section {
      LabeledContent(localized("Language")) {
        Picker(localized("App Language"), selection: appLanguageBinding) {
          ForEach(AppLanguage.allCases) { language in
            Text(languageLabel(for: language)).tag(language)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 220, alignment: .trailing)
      }
    } header: {
      Text(localized("App Language"))
    } footer: {
      Text(localized("System Default follows your macOS language."))
    }
  }

  var shortcutSection: some View {
    Section {
      LabeledContent(localized("Shortcut")) {
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
        Button(localized(isRecordingShortcut ? "Stop" : "Record")) {
          isRecordingShortcut.toggle()
        }
        .buttonStyle(.borderedProminent)
        .tint(isRecordingShortcut ? .red : .accentColor)

        Button(localized("Reset")) {
          settings.resetCaptureShortcut()
          isRecordingShortcut = false
        }
        .buttonStyle(.bordered)

        Spacer(minLength: 0)
      }
    } header: {
      Text(localized("Capture Shortcut"))
    } footer: {
      Text(
        localized(
          isRecordingShortcut
            ? "Press the shortcut you want to use now. Esc cancels."
            : "Used to start capture from anywhere. Hold Command, Shift, Option, or Control while pressing a key."
        )
      )
    }
  }

  var startupSection: some View {
    Section {
      Toggle(localized("Start VivyShot at login"), isOn: launchAtLoginBinding)
        .toggleStyle(.switch)
        .controlSize(.small)
    } header: {
      Text(localized("Startup"))
    } footer: {
      Text(
        launchAtLoginController.detailText
          ?? localized("Automatically launches the menu bar app after you sign in.")
      )
    }
  }

  var captureDefaultsSection: some View {
    Section {
      Toggle(localized("Show Capture Helper"), isOn: captureShowHelperBinding)
        .toggleStyle(.switch)
        .controlSize(.small)

      Toggle(localized("Smart Window Selection"), isOn: captureSmartWindowSelectionBinding)
        .toggleStyle(.switch)
        .controlSize(.small)

      LabeledContent(localized("Start In")) {
        Picker(localized("Default Capture Type"), selection: defaultCaptureTypeBinding) {
          ForEach(CaptureContentType.allCases) { type in
            Text(type.title).tag(type)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 220, alignment: .trailing)
      }
    } header: {
      Text(localized("Capture Defaults"))
    } footer: {
      Text(localized("Turn off smart window selection if you prefer to draw an area before choosing a window."))
    }
  }

  var savingSection: some View {
    Group {
      screenshotSavingSection
      videoSavingSection
    }
  }

  var screenshotSavingSection: some View {
    let hasScreenshotSaveLocation = settings.defaultSaveDirectoryURL != nil

    return Section {
      saveFolderRow(
        title: localized("Folder"),
        displayText: defaultSaveDirectoryDisplay,
        hasLocation: hasScreenshotSaveLocation,
        choose: chooseDefaultSaveDirectory,
        reveal: revealDefaultSaveDirectoryInFinder,
        clear: { settings.setDefaultSaveDirectory(nil) }
      )

      Toggle(localized("Save screenshots without asking"), isOn: alwaysSaveToDefaultDirectoryBinding)
        .toggleStyle(.switch)
        .disabled(!hasScreenshotSaveLocation)

      Toggle(localized("Also save copied screenshots"), isOn: saveCopiedScreenshotsToDefaultDirectoryBinding)
        .toggleStyle(.switch)
        .disabled(!hasScreenshotSaveLocation)
    } header: {
      Text(localized("Screenshot Saving"))
    } footer: {
      Text(localized("Choose where screenshot Save and copied-screenshot auto-saves write files."))
    }
  }

  var videoSavingSection: some View {
    let hasVideoSaveLocation = settings.videoSaveDirectoryURL != nil

    return Section {
      saveFolderRow(
        title: localized("Folder"),
        displayText: videoSaveDirectoryDisplay,
        hasLocation: hasVideoSaveLocation,
        choose: chooseVideoSaveDirectory,
        reveal: revealVideoSaveDirectoryInFinder,
        clear: { settings.setVideoSaveDirectory(nil) }
      )

      Toggle(localized("Save videos without asking"), isOn: videoSaveSkipsDialogBinding)
        .toggleStyle(.switch)
        .disabled(!hasVideoSaveLocation)

      Toggle(localized("Also save copied videos"), isOn: saveCopiedVideosToDefaultDirectoryBinding)
        .toggleStyle(.switch)
        .disabled(!hasVideoSaveLocation)

      Text(localized("When enabled, the post-recording Save menu writes to the video folder instead of opening the save dialog."))
        .font(.footnote)
        .foregroundStyle(.secondary)
    } header: {
      Text(localized("Video Saving"))
    } footer: {
      Text(localized("Video exports still use the selected Save menu format, such as MP4, MOV, or GIF."))
    }
  }

  func saveFolderRow(
    title: String,
    displayText: String,
    hasLocation: Bool,
    choose: @escaping () -> Void,
    reveal: @escaping () -> Void,
    clear: @escaping () -> Void
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      LabeledContent(title) {
        Text(displayText)
          .font(.system(.callout, design: .monospaced))
          .foregroundStyle(hasLocation ? .primary : .secondary)
          .lineLimit(2)
          .multilineTextAlignment(.trailing)
      }

      HStack(spacing: 8) {
        Button(localized(hasLocation ? "Change…" : "Choose Folder…"), action: choose)
        .buttonStyle(.bordered)

        if hasLocation {
          Button(localized("Show in Finder"), action: reveal)
            .buttonStyle(.bordered)

          Button(localized("Clear"), action: clear)
            .buttonStyle(.bordered)
        }

        Spacer(minLength: 0)
      }
    }
  }

  var defaultSaveDirectoryDisplay: String {
    saveDirectoryDisplay(settings.defaultSaveDirectoryURL)
  }

  var videoSaveDirectoryDisplay: String {
    saveDirectoryDisplay(settings.videoSaveDirectoryURL)
  }

  func saveDirectoryDisplay(_ url: URL?) -> String {
    guard let url else {
      return localized("No folder selected")
    }
    return (url.path as NSString).abbreviatingWithTildeInPath
  }

  func languageLabel(for language: AppLanguage) -> String {
    if language == .system {
      return localized(language.nativeDisplayName)
    }
    return language.nativeDisplayName
  }

  func chooseDefaultSaveDirectory() {
    let panel = saveDirectoryPanel(
      title: "Choose Default Save Folder",
      initialDirectory: settings.defaultSaveDirectoryURL,
      fallbackDirectory: FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
    )

    if panel.runModal() == .OK {
      settings.setDefaultSaveDirectory(panel.url)
    }
  }

  func chooseVideoSaveDirectory() {
    let panel = saveDirectoryPanel(
      title: "Choose Video Save Folder",
      initialDirectory: settings.videoSaveDirectoryURL,
      fallbackDirectory: settings.defaultSaveDirectoryURL
        ?? FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
    )

    if panel.runModal() == .OK {
      settings.setVideoSaveDirectory(panel.url)
    }
  }

  func saveDirectoryPanel(
    title: String.LocalizationValue,
    initialDirectory: URL?,
    fallbackDirectory: URL?
  ) -> NSOpenPanel {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    panel.prompt = localized("Choose")
    panel.title = localized(title)
    panel.directoryURL = initialDirectory ?? fallbackDirectory
    return panel
  }

  func revealDefaultSaveDirectoryInFinder() {
    guard let url = settings.defaultSaveDirectoryURL else {
      return
    }
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }

  func revealVideoSaveDirectoryInFinder() {
    guard let url = settings.videoSaveDirectoryURL else {
      return
    }
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }

}
