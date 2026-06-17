import SwiftUI

@MainActor
extension SettingsView {
  var screenshotDrawingSection: some View {
    Section {
      HStack(spacing: 10) {
        Text("Window Capture")
          .frame(width: 90, alignment: .leading)
        Spacer(minLength: 0)
        Picker("Window Capture", selection: screenshotWindowCaptureStyleBinding) {
          ForEach(ScreenshotWindowCaptureStyle.allCases) { style in
            Text(style.title).tag(style)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 220, alignment: .trailing)
      }

      HStack(spacing: 10) {
        Text("Line Width")
          .frame(width: 90, alignment: .leading)
        Slider(value: drawingStrokeWidthBinding, in: AppSettings.drawingStrokeWidthRange, step: 0.5)
        Text(String(format: "%.1f pt", settings.drawingStrokeWidth))
          .font(.system(.callout, design: .monospaced).weight(.semibold))
          .frame(width: 62, alignment: .trailing)
      }
    } header: {
      Text("Capture & Drawing")
    } footer: {
      Text("Window screenshots use native window capture by default. Drawing width applies to rectangle, circle, line, arrow, and paint tools.")
    }
  }

  var screenshotToolbarSection: some View {
    Section("Toolbar") {
      Text("Drag rows to reorder. Hidden tools won’t appear in screenshot toolbar.")
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
        Button("Reset Toolbar") {
          settings.resetToolbarConfiguration()
        }
      }
    }
  }

  var textToolSection: some View {
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

  var effectsSection: some View {
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

  var captureTransitionHelperText: String {
    if storeManager.canUse(.captureTransitions) {
      return String(localized: "Applied on capture enter and exit.", bundle: AppLocalizer.shared.bundle)
    }
    return String(localized: "Preview is available. Real capture transitions require Pro.", bundle: AppLocalizer.shared.bundle)
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
