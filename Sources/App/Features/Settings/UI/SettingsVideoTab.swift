import SwiftUI

@MainActor
extension SettingsView {
  var recordingSection: some View {
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

  var webcamOverlaySection: some View {
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

  var keystrokeOverlaySection: some View {
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

  var mouseClickSection: some View {
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

  var recordingToolbarSection: some View {
    Section("Video Toolbar") {
      Text("Drag rows to reorder. Hidden tools won’t appear in video toolbar.")
        .font(.caption)
        .foregroundStyle(.secondary)

      SettingsToolbarReorderList(
        displayedTools: displayedRecordingTools,
        currentOrder: settings.recordingToolOrder,
        draggingTool: $draggingVideoTool,
        visibilityBinding: recordingToolVisibilityBinding(for:),
        onMove: settings.moveVideoTools
      )

      HStack {
        Spacer()
        Button("Reset Video Toolbar") {
          settings.resetVideoToolbarConfiguration()
        }
      }
    }
  }

  func overlaySizePercent(_ value: Double) -> String {
    "\(Int((value * 100).rounded()))%"
  }

  func overlaySliderRow(
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

  func overlayPickerRow<Selection: Hashable, Content: View>(
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

  func overlayPreviewActions(
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

  func isOverlayPreviewVisible(_ kind: RecordingOverlaySettingsPreviewKind) -> Bool {
    visibleOverlayPreviews.contains(kind)
  }

  func toggleOverlayPreview(_ kind: RecordingOverlaySettingsPreviewKind) {
    if visibleOverlayPreviews.contains(kind) {
      previewActions.closeRecordingOverlayPreview(kind)
      visibleOverlayPreviews.remove(kind)
    } else {
      previewActions.showRecordingOverlayPreview(kind, settings) { closedKind in
        visibleOverlayPreviews.remove(closedKind)
      }
      visibleOverlayPreviews.insert(kind)
    }
  }
}
