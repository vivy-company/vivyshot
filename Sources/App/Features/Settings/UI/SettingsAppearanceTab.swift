import AppKit
import SwiftUI

@MainActor
extension SettingsView {
  var appearanceSection: some View {
    Section(localized("Appearance")) {
      HStack(spacing: 10) {
        Text(localized("Accent"))
          .frame(width: 90, alignment: .leading)
        Spacer(minLength: 0)
        ColorPicker(localized("Toolbar Accent"), selection: toolbarAccentColorBinding, supportsOpacity: false)
          .labelsHidden()
          .frame(width: 190, alignment: .trailing)
      }

      HStack(spacing: 10) {
        Text(localized("Main Action"))
          .frame(width: 90, alignment: .leading)
        Spacer(minLength: 0)
        Picker(localized("Main Action Button"), selection: screenshotMainActionBinding) {
          ForEach(ScreenshotMainAction.allCases) { action in
            Text(action.title).tag(action)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 190, alignment: .trailing)
      }

      Text(localized("Applied to screenshot main action and video record button."))
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

}
