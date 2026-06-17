import SwiftUI

@MainActor
extension SettingsView {
  var windowScreenshotSection: some View {
    Section {
      HStack(spacing: 10) {
        Text(localized("Style"))
          .frame(width: 90, alignment: .leading)
        Spacer(minLength: 0)
        Picker(localized("Window Screenshot Style"), selection: screenshotWindowCaptureStyleBinding) {
          ForEach(ScreenshotWindowCaptureStyle.allCases) { style in
            Text(style.title).tag(style)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 220, alignment: .trailing)
      }
    } header: {
      Text(localized("Window Screenshots"))
    } footer: {
      Text(localized("With Shadow matches the macOS window screenshot style and removes the background. Selected Area captures the window's visible rectangle from the screen."))
    }
  }

  var screenshotDrawingSection: some View {
    Section {
      HStack(spacing: 10) {
        Text(localized("Line Width"))
          .frame(width: 90, alignment: .leading)
        Slider(value: drawingStrokeWidthBinding, in: AppSettings.drawingStrokeWidthRange, step: 0.5)
        Text(String(format: "%.1f pt", settings.drawingStrokeWidth))
          .font(.system(.callout, design: .monospaced).weight(.semibold))
          .frame(width: 62, alignment: .trailing)
      }
    } header: {
      Text(localized("Drawing"))
    } footer: {
      Text(localized("Applied to rectangle, circle, line, arrow, and paint tools."))
    }
  }

  var screenshotToolbarSection: some View {
    Section(localized("Toolbar")) {
      Text(localized("Drag rows to reorder. Hidden tools won’t appear in screenshot toolbar."))
        .font(.caption)
        .foregroundStyle(.secondary)

      SettingsToolbarReorderList(
        displayedTools: settings.toolOrder,
        currentOrder: settings.toolOrder,
        draggingTool: $draggingScreenshotTool,
        visibilityBinding: visibilityBinding(for:),
        onMove: settings.moveTools
      )

      HStack {
        Spacer()
        Button(localized("Reset Toolbar")) {
          settings.resetToolbarConfiguration()
        }
      }
    }
  }

  var textToolSection: some View {
    Section(localized("Text Tool")) {
      HStack(spacing: 10) {
        Text(localized("Font"))
          .frame(width: 78, alignment: .leading)
        Spacer(minLength: 0)
        Picker(localized("Font"), selection: textFontNameBinding) {
          ForEach(availableFamilies, id: \.self) { family in
            Text(family).tag(family)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 190, alignment: .trailing)
      }

      HStack(spacing: 10) {
        Text(localized("Size"))
          .frame(width: 78, alignment: .leading)
        Slider(value: textFontSizeBinding, in: 10 ... 48, step: 1)
        Text("\(Int(settings.textFontSize)) pt")
          .font(.system(.callout, design: .monospaced).weight(.semibold))
          .frame(width: 48, alignment: .trailing)
      }

      LabeledContent(localized("Preview")) {
        textPreview
          .frame(maxWidth: .infinity, alignment: .leading)
      }

      HStack {
        Spacer()
        Button(localized("Reset Text")) {
          settings.resetTextSettings()
        }
      }
    }
  }

  var effectsSection: some View {
    Section(localized("Effects")) {
      HStack(spacing: 10) {
        Text(localized("Transition"))
          .frame(width: 78, alignment: .leading)
        Spacer(minLength: 0)
        Picker(localized("Transition"), selection: captureTransitionStyleBinding) {
          ForEach(CaptureTransitionStyle.allCases) { style in
            Text(style.title).tag(style)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 150, alignment: .trailing)
      }

      LabeledContent(localized("Speed")) {
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

      LabeledContent(localized("Strength")) {
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
        Button(localized("Preview")) {
          previewCaptureTransition()
        }
        .disabled(settings.captureTransitionStyle == .none)
        Button(localized("Reset Effects")) {
          settings.resetCaptureTransitionSettings()
        }
      }
    }
  }

  var captureTransitionHelperText: String {
    if storeManager.canUse(.captureTransitions) {
      return localized("Applied on capture enter and exit.")
    }
    return localized("Preview is available. Real capture transitions require Pro.")
  }

  func visibilityBinding(for tool: AnnotationTool) -> Binding<Bool> {
    Binding(
      get: { settings.isToolVisible(tool) },
      set: { settings.setToolVisible(tool, isVisible: $0) }
    )
  }

  func recordingToolVisibilityBinding(for tool: RecordingTool) -> Binding<Bool> {
    Binding(
      get: { settings.isRecordingToolVisible(tool) },
      set: { settings.setRecordingToolVisible(tool, isVisible: $0) }
    )
  }

  var displayedRecordingTools: [RecordingTool] {
    settings.recordingToolOrder.filter(shouldShowRecordingTool)
  }

  func shouldShowRecordingTool(_ tool: RecordingTool) -> Bool {
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
  var textPreview: some View {
    if settings.textFontName == AppSettings.systemFontFamilyName {
      Text("The quick brown fox jumps over 123")
        .font(.system(size: settings.textFontSize, weight: .regular))
    } else {
      Text("The quick brown fox jumps over 123")
        .font(.custom(settings.textFontName, size: settings.textFontSize))
    }
  }

  func previewCaptureTransition() {
    previewActions.previewCaptureTransition()
  }

}
