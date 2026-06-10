import SwiftUI

@MainActor
struct CaptureVideoToolbar: View {
  @ObservedObject var modeSelectionState: CaptureModeSelectionState
  var glassNamespace: Namespace.ID? = nil
  var usesExternalGlassSurface = false
  let state: CaptureVideoToolbarState
  let onAction: (CaptureVideoToolbarAction) -> Void

  @Namespace private var modeSelectionNamespace

  private var visualSelectedCaptureMode: CaptureMode {
    modeSelectionState.selectedMode
  }

  private var hasConfigurableTools: Bool {
    !state.toolOrder.isEmpty
  }

  var body: some View {
    toolbarContent
      .floatingCapsuleGlassSurface(
        usesExternalSurface: usesExternalGlassSurface,
        glassNamespace: glassNamespace,
        glassID: "region-selection-toolbar-shell"
      )
    .fixedSize()
    .contentShape(Rectangle())
    .highPriorityGesture(dragGesture, including: .subviews)
  }

  private var closeCaptureButton: some View {
    toolbarIconButton(
      symbol: "xmark.circle.fill",
      help: "Exit capture (Esc)",
      isSelected: false,
      isDisabled: state.isRecordingPending,
      action: { onAction(.closeCapture) }
    )
  }

  private var toolbarContent: some View {
    HStack(spacing: 5) {
      closeCaptureButton
      separator
      captureModeButtons
      if hasConfigurableTools {
        separator
        ForEach(Array(state.toolOrder.enumerated()), id: \.element.id) { index, tool in
          recordingToolButton(tool)
          if state.toolOrder.shouldSeparateInputSources(after: index) {
            separator
          }
        }
      }
      separator
      recordButton
    }
  }

  private var captureModeButtons: some View {
    ZStack(alignment: .leading) {
      captureModeSelectionBackground

      HStack(spacing: 2) {
        ForEach(CaptureMode.allCases) { mode in
          captureModeIconButton(mode)
        }
      }
    }
    .frame(height: 34)
  }

  @ViewBuilder
  private var captureModeSelectionBackground: some View {
    let itemSize: CGFloat = 34
    let spacing: CGFloat = 2
    let selectedIndex = CaptureMode.allCases.firstIndex(of: visualSelectedCaptureMode) ?? 0
    let xOffset = CGFloat(selectedIndex) * (itemSize + spacing)

    if #available(macOS 26.0, *) {
      Circle()
        .fill(Color.accentColor.opacity(0.07))
        .overlay(
          Circle()
            .stroke(Color.accentColor.opacity(0.24), lineWidth: 1)
        )
        .frame(width: itemSize, height: itemSize)
        .offset(x: xOffset)
        .animation(.smooth(duration: 0.22), value: visualSelectedCaptureMode)
        .allowsHitTesting(false)
    } else {
      Circle()
        .fill(Color.white.opacity(0.18))
        .overlay(
          Circle()
            .stroke(Color.white.opacity(0.28), lineWidth: 1)
        )
        .frame(width: itemSize, height: itemSize)
        .offset(x: xOffset)
        .animation(.easeOut(duration: 0.18), value: visualSelectedCaptureMode)
        .allowsHitTesting(false)
    }
  }

  private var separator: some View {
    Rectangle()
      .fill(Color.white.opacity(0.18))
      .frame(width: 1, height: 20)
  }

  private var recordButton: some View {
    Button {
      onAction(.toggleRecording)
    } label: {
      Image(systemName: state.isRecordingActive ? "stop.circle.fill" : "record.circle.fill")
        .font(.system(size: 13.5, weight: .semibold))
        .frame(width: 30, height: 30)
        .contentShape(Circle())
    }
    .foregroundStyle(state.accentColor)
    .buttonStyle(.plain)
    .overlay(
      Circle()
        .stroke(state.accentColor.opacity(0.42), lineWidth: 1)
    )
    .help(state.isRecordingActive ? "Stop recording (⌥⌘R)" : "Start video recording (Return, ⌥⌘R)")
    .padding(.leading, 4)
    .disabled(state.isRecordingPending)
    .opacity(state.isRecordingPending ? 0.6 : 1)
  }

  private var countdownMenuButton: some View {
    let isCountdownEnabled = state.countdown != .off
    return Menu {
      ForEach(RecordingCountdown.allCases) { option in
        Button {
          onAction(.selectCountdown(option))
        } label: {
          if option == state.countdown {
            Label(option.title, systemImage: "checkmark")
          } else {
            Text(option.title)
          }
        }
      }
    } label: {
      HStack(spacing: 4) {
        Image(systemName: "timer")
          .font(.system(size: 13.5, weight: .semibold))
          .foregroundStyle(isCountdownEnabled ? state.accentColor : toolbarNeutralForeground)
        Text(state.countdown.title)
          .font(.system(size: 11.5, weight: .semibold))
          .foregroundStyle(isCountdownEnabled ? state.accentColor : toolbarNeutralForeground)
        Image(systemName: "chevron.down")
          .font(.system(size: 9, weight: .bold))
          .foregroundStyle(toolbarSecondaryForeground)
      }
      .frame(height: 26)
      .padding(.horizontal, 10)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(state.isConfigurationLocked)
    .opacity(state.isConfigurationLocked ? 0.45 : 1)
    .help("Countdown: \(state.countdown.title) (⌥⌘T)")
  }

  @ViewBuilder
  private func recordingToolButton(_ tool: RecordingTool) -> some View {
    switch tool {
    case .systemAudio:
      toolbarIconButton(
        symbol: state.recordingControls.recordSystemAudio ? "speaker.wave.2.fill" : "speaker.slash.fill",
        help: "System Audio (⌥⌘A)",
        isSelected: state.recordingControls.recordSystemAudio,
        isDisabled: state.isConfigurationLocked,
        action: { onAction(.toggleTool(.systemAudio)) }
      )

    case .microphone:
      let locked = state.lockedTools.contains(.microphone)
      RecordingSourceMenuButton(
        title: RecordingTool.microphone.title,
        labelText: "Mic",
        symbol: state.recordingControls.recordMicrophone ? "mic.fill" : "mic.slash.fill",
        help: locked ? "Microphone (Paid)" : "Microphone (⌥⌘M)",
        isDisabled: state.isConfigurationLocked,
        isLocked: locked,
        accentColor: state.accentColor,
        selectedSourceID: state.selectedMicrophoneID,
        sources: state.microphoneSources,
        isSourceEnabled: state.recordingControls.recordMicrophone,
        onToggle: { onAction(.toggleTool(.microphone)) },
        onSelectSource: { onAction(.selectMicrophoneSource($0)) }
      )

    case .webcam:
      let locked = state.lockedTools.contains(.webcam)
      RecordingSourceMenuButton(
        title: RecordingTool.webcam.title,
        labelText: "Camera",
        symbol: state.recordingControls.showWebcam ? "video.fill" : "video.slash.fill",
        help: locked ? "Webcam Overlay (Paid)" : "Webcam Overlay (⌥⌘W)",
        isDisabled: state.isConfigurationLocked,
        isLocked: locked,
        accentColor: state.accentColor,
        selectedSourceID: state.selectedWebcamID,
        sources: state.webcamSources,
        isSourceEnabled: state.recordingControls.showWebcam,
        onToggle: { onAction(.toggleTool(.webcam)) },
        onSelectSource: { onAction(.selectWebcamSource($0)) }
      )

    case .mouseClicks:
      toolbarIconButton(
        symbol: state.recordingControls.highlightMouseClicks ? "cursorarrow.rays" : "cursorarrow",
        help: "Mouse Click Highlights (⌥⌘L)",
        isSelected: state.recordingControls.highlightMouseClicks,
        isDisabled: state.isConfigurationLocked,
        action: { onAction(.toggleTool(.mouseClicks)) }
      )

    case .keystrokes:
      let locked = state.lockedTools.contains(.keystrokes)
      toolbarIconButton(
        symbol: state.recordingControls.highlightKeystrokes ? "keyboard" : "keyboard.fill",
        help: locked ? "Keystroke Highlights (Paid)" : "Keystroke Highlights (⌥⌘K)",
        isSelected: state.recordingControls.highlightKeystrokes,
        isDisabled: state.isConfigurationLocked,
        isLocked: locked,
        action: { onAction(.toggleTool(.keystrokes)) }
      )

    case .countdown:
      countdownMenuButton
    }
  }

  private func toolbarIconButton(
    symbol: String,
    help: String,
    isSelected: Bool,
    isDisabled: Bool = false,
    isLocked: Bool = false,
    action: @escaping () -> Void
  ) -> some View {
    HoverTooltipIconButton(
      symbol: symbol,
      help: help,
      isSelected: isSelected,
      isDisabled: isDisabled,
      symbolFontSize: 13,
      size: CGSize(width: 26, height: 24),
      cornerRadius: 7,
      selectedFillOpacity: 0.18,
      selectedStrokeOpacity: 0.34,
      tintOverride: isSelected ? state.accentColor : toolbarNeutralForeground,
      isLocked: isLocked,
      action: action
    )
  }

  private var dragGesture: some Gesture {
    DragGesture(minimumDistance: 5, coordinateSpace: .global)
      .onChanged { value in
        onAction(.drag(value.translation))
      }
      .onEnded { _ in
        onAction(.dragEnded)
      }
  }

  private func captureModeIconButton(_ mode: CaptureMode) -> some View {
    let isSelected = visualSelectedCaptureMode == mode
    let disabled = state.isConfigurationLocked

    return HoverTooltipCircleModeButton(
      symbol: mode.symbolName,
      help: captureModeHelpText(mode),
      isSelected: isSelected,
      isDisabled: disabled,
      diameter: 30,
      selectionNamespace: modeSelectionNamespace,
      selectionID: "video-capture-mode",
      showsSelectionBackground: false,
      selectedTint: state.accentColor,
      normalTint: toolbarNeutralForeground
    ) {
      onAction(.selectCaptureMode(mode))
    }
  }
}
