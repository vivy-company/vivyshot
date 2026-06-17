import SwiftUI

@MainActor
extension SettingsView {
  var recordingSection: some View {
    Section(localized("Recording")) {
      videoPickerRow(localized("Encoder"), title: localized("Recording Encoder"), selection: recordingEncoderBinding, width: 220) {
        ForEach(RecordingEncoder.allCases) { encoder in
          Text(encoder.title).tag(encoder)
        }
      }

      videoPickerRow(localized("Frame Rate"), title: localized("Video Frame Rate"), selection: recordingFrameRateBinding) {
        ForEach(RecordingFrameRate.allCases) { rate in
          Text(rate.title).tag(rate)
        }
      }

      videoPickerRow(localized("Countdown"), title: localized("Video Countdown"), selection: recordingCountdownBinding) {
        ForEach(RecordingCountdown.allCases) { countdown in
          Text(countdown.title).tag(countdown)
        }
      }

      videoPickerRow(
        localized("Color & Dynamic Range"),
        title: localized("Color and Dynamic Range"),
        selection: recordingColorProfileBinding,
        width: 230
      ) {
        ForEach(RecordingColorProfile.allCases) { profile in
          Text(profile.title).tag(profile)
        }
      }
    }
  }

  var audioSection: some View {
    Section(localized("Audio")) {
      Toggle(localized("Record system audio"), isOn: recordSystemAudioBinding)
        .toggleStyle(.switch)
      if microphoneFeatureVisible {
        Toggle(localized("Record microphone"), isOn: recordMicrophoneBinding)
          .toggleStyle(.switch)
      }
      Toggle(localized("Include VivyShot audio"), isOn: recordingIncludesAppAudioBinding)
        .toggleStyle(.switch)
    }
  }

  var windowRecordingSection: some View {
    Section {
      videoPickerRow(localized("Capture"), title: localized("Window Recording Capture"), selection: recordingWindowCaptureStyleBinding, width: 220) {
        ForEach(RecordingWindowCaptureStyle.allCases) { style in
          Text(style.title).tag(style)
        }
      }
    } header: {
      Text(localized("Window Recordings"))
    } footer: {
      Text(localized("Window Only records the selected app window without the surrounding desktop. Selected Area records the rectangle shown in the editor."))
    }
  }

  var webcamOverlaySection: some View {
    Section(localized("Camera")) {
      Toggle(localized("Show camera by default"), isOn: showWebcamBinding)
        .toggleStyle(.switch)

      overlaySliderRow(
        localized("Camera Size"),
        value: webcamOverlaySizeSliderBinding,
        range: AppSettings.webcamOverlaySizeRange,
        displayValue: settings.webcamOverlayNormalizedWidth
      )

      overlayPickerRow(localized("Camera Shape"), title: localized("Webcam Overlay Shape"), selection: webcamOverlayShapeBinding) {
        ForEach(WebcamShape.allCases) { shape in
          Text(shape.title).tag(shape)
        }
      }

      overlayPickerRow(localized("Aspect Ratio"), title: localized("Webcam Aspect Ratio"), selection: webcamOverlayAspectRatioBinding) {
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

  var pointerEffectsSection: some View {
    Section(localized("Pointer & Effects")) {
      Toggle(localized("Show pointer"), isOn: recordingShowsPointerBinding)
        .toggleStyle(.switch)
      Toggle(localized("Highlight mouse clicks"), isOn: highlightMouseClicksBinding)
        .toggleStyle(.switch)

      Picker(localized("Click Style"), selection: mouseClickHighlightStyleBinding) {
        ForEach(MouseClickHighlightStyle.allCases) { style in
          Text(style.title).tag(style)
        }
      }
      .pickerStyle(.menu)
      .disabled(!settings.highlightMouseClicks)

      if keystrokesFeatureVisible {
        Toggle(localized("Show keystrokes by default"), isOn: highlightKeystrokesBinding)
          .toggleStyle(.switch)

        overlayPickerRow(localized("Key Style"), title: localized("Keystroke Overlay Style"), selection: keystrokeOverlayStyleBinding) {
          ForEach(KeystrokeStyle.allCases) { style in
            Text(style.title).tag(style)
          }
        }

        overlaySliderRow(
          localized("Key Size"),
          value: keystrokeOverlaySizeSliderBinding,
          range: AppSettings.keystrokeOverlaySizeRange,
          displayValue: settings.keystrokeOverlayNormalizedWidth
        )

        overlayPreviewActions(.keystroke) {
          settings.resetKeystrokeOverlayPlacement()
        }
      }
    }
  }

  var advancedCaptureSection: some View {
    Section(localized("Advanced Capture")) {
      videoPickerRow(localized("Capture Resolution"), title: localized("Capture Resolution"), selection: recordingCaptureResolutionBinding) {
        ForEach(RecordingCaptureResolution.allCases) { resolution in
          Text(resolution.title).tag(resolution)
        }
      }

      videoPickerRow(localized("Capture Buffering"), title: localized("Capture Buffering"), selection: recordingCaptureBufferingBinding) {
        ForEach(RecordingCaptureBuffering.allCases) { buffering in
          Text(buffering.title).tag(buffering)
        }
      }

      Toggle(localized("System Click Rings"), isOn: recordingShowsSystemClickRingsBinding)
        .toggleStyle(.switch)
      Toggle(localized("Hide notifications (best effort)"), isOn: hideNotificationsBestEffortBinding)
        .toggleStyle(.switch)

      HStack {
        Spacer()
        Button(localized("Reset Recording Settings")) {
          settings.resetVideoCaptureSettings()
        }
      }
    }
  }

  var recordingToolbarSection: some View {
    Section(localized("Toolbar")) {
      Text(localized("Drag rows to reorder. Hidden tools won’t appear in video toolbar."))
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
        Button(localized("Reset Video Toolbar")) {
          settings.resetVideoToolbarConfiguration()
        }
      }
    }
  }

  func videoPickerRow<Selection: Hashable, Content: View>(
    _ label: String,
    title: String,
    selection: Binding<Selection>,
    width: CGFloat = 190,
    @ViewBuilder content: () -> Content
  ) -> some View {
    HStack(spacing: 10) {
      Text(label)
        .frame(width: 150, alignment: .leading)
      Spacer(minLength: 0)
      Picker(title, selection: selection) {
        content()
      }
      .labelsHidden()
      .pickerStyle(.menu)
      .frame(width: width, alignment: .trailing)
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
      Button(localized(isOverlayPreviewVisible(kind) ? "Hide Preview" : "Show Preview")) {
        toggleOverlayPreview(kind)
      }
      Spacer()
      Button(localized("Reset Placement"), action: reset)
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
