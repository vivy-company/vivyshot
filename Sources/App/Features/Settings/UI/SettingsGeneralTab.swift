import AppKit
import SwiftUI

@MainActor
extension SettingsView {
  var languageSection: some View {
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

  var shortcutSection: some View {
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

  var startupSection: some View {
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

  var captureDefaultsSection: some View {
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

  var savingSection: some View {
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

  var defaultSaveDirectoryDisplay: String {
    guard let url = settings.defaultSaveDirectoryURL else {
      return String(localized: "No folder selected", bundle: AppLocalizer.shared.bundle)
    }
    return (url.path as NSString).abbreviatingWithTildeInPath
  }

  func languageLabel(for language: AppLanguage) -> String {
    if language == .system {
      return String(localized: String.LocalizationValue(language.nativeDisplayName), bundle: AppLocalizer.shared.bundle)
    }
    return language.nativeDisplayName
  }

  func chooseDefaultSaveDirectory() {
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

  func revealDefaultSaveDirectoryInFinder() {
    guard let url = settings.defaultSaveDirectoryURL else {
      return
    }
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }

}
