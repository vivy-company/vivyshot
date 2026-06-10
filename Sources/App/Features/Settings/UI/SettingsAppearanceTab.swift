import AppKit
import SwiftUI

@MainActor
extension SettingsView {
  var appearanceSection: some View {
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

}
