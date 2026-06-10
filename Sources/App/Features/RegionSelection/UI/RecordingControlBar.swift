import AppKit
import SwiftUI

@MainActor
struct RecordingControlBar: View {
  let state: RecordingControlBarState
  let usesExternalGlassSurface: Bool
  let onAction: (RecordingControlBarAction) -> Void

  private var hasToggleTools: Bool {
    !state.toolOrder.isEmpty
  }

  var body: some View {
    Group {
      if usesExternalGlassSurface {
        barContent
          .padding(.horizontal, 8)
          .padding(.vertical, 8)
      } else if #available(macOS 26.0, *) {
        GlassEffectContainer(spacing: 0) {
          barContent
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .glassEffect(.regular.tint(Color.red.opacity(0.08)).interactive(), in: .capsule)
        }
      } else {
        barContent
          .padding(.horizontal, 8)
          .padding(.vertical, 8)
          .background(.ultraThinMaterial, in: Capsule(style: .continuous))
      }
    }
    .fixedSize()
  }

  private var barContent: some View {
    HStack(spacing: 6) {
      dragHandle
      recordingIndicator
      timerChip
      if hasToggleTools {
        separator
        ForEach(Array(state.toolOrder.enumerated()), id: \.element.id) { index, tool in
          liveToggleButton(for: tool)
          if state.toolOrder.shouldSeparateInputSources(after: index) {
            separator
          }
        }
      }
      separator
      stopButton
    }
  }

  private var dragHandle: some View {
    Image(systemName: "line.3.horizontal")
      .font(.system(size: 12, weight: .bold))
      .foregroundStyle(toolbarSecondaryForeground)
      .frame(width: 24, height: 26)
      .contentShape(Rectangle())
      .gesture(dragGesture)
      .help("Drag recording controls")
  }

  private var recordingIndicator: some View {
    HStack(spacing: 5) {
      Image(systemName: "record.circle.fill")
        .font(.system(size: 14, weight: .semibold))
      Text("REC")
        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
    }
    .foregroundStyle(Color.red)
    .frame(height: 26)
  }

  private var timerChip: some View {
    TimelineView(.periodic(from: state.startedAt, by: 1)) { context in
      Text(formattedElapsedTime(at: context.date))
        .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
        .foregroundStyle(toolbarNeutralForeground)
        .frame(minWidth: 58, minHeight: 26)
    }
  }

  private var separator: some View {
    Rectangle()
      .fill(Color.white.opacity(0.18))
      .frame(width: 1, height: 20)
  }

  @ViewBuilder
  private func liveToggleButton(for tool: RecordingTool) -> some View {
    switch tool {
    case .systemAudio:
      liveToggleButton(
        symbol: state.liveControls.recordSystemAudio ? "speaker.wave.2.fill" : "speaker.slash.fill",
        help: helpText(state.liveControls.recordSystemAudio ? "System audio on" : "System audio off", for: .systemAudio),
        isDisabled: state.liveControls.disabledTools.contains(.systemAudio),
        isSelected: state.liveControls.recordSystemAudio,
        action: { onAction(.toggleTool(.systemAudio)) }
      )
    case .microphone:
      RecordingSourceMenuButton(
        title: RecordingTool.microphone.title,
        labelText: "Mic",
        symbol: state.liveControls.recordMicrophone ? "mic.fill" : "mic.slash.fill",
        help: helpText(state.liveControls.recordMicrophone ? "Microphone on" : "Microphone off", for: .microphone),
        isDisabled: state.liveControls.disabledTools.contains(.microphone),
        isLocked: false,
        accentColor: state.accentColor,
        selectedSourceID: state.selectedMicrophoneID,
        sources: state.microphoneSources,
        isSourceEnabled: state.liveControls.recordMicrophone,
        onToggle: { onAction(.toggleTool(.microphone)) },
        onSelectSource: { onAction(.selectMicrophoneSource($0)) }
      )
    case .webcam:
      RecordingSourceMenuButton(
        title: RecordingTool.webcam.title,
        labelText: "Camera",
        symbol: state.liveControls.showWebcam ? "video.fill" : "video.slash.fill",
        help: helpText(state.liveControls.showWebcam ? "Camera overlay on" : "Camera overlay off", for: .webcam),
        isDisabled: state.liveControls.disabledTools.contains(.webcam),
        isLocked: false,
        accentColor: state.accentColor,
        selectedSourceID: state.selectedWebcamID,
        sources: state.webcamSources,
        isSourceEnabled: state.liveControls.showWebcam,
        onToggle: { onAction(.toggleTool(.webcam)) },
        onSelectSource: { onAction(.selectWebcamSource($0)) }
      )
    case .mouseClicks:
      liveToggleButton(
        symbol: state.liveControls.highlightMouseClicks ? "cursorarrow.rays" : "cursorarrow",
        help: helpText(state.liveControls.highlightMouseClicks ? "Mouse clicks on" : "Mouse clicks off", for: .mouseClicks),
        isDisabled: state.liveControls.disabledTools.contains(.mouseClicks),
        isSelected: state.liveControls.highlightMouseClicks,
        action: { onAction(.toggleTool(.mouseClicks)) }
      )
    case .keystrokes:
      liveToggleButton(
        symbol: "keyboard",
        help: helpText(state.liveControls.highlightKeystrokes ? "Keystrokes on" : "Keystrokes off", for: .keystrokes),
        isDisabled: state.liveControls.disabledTools.contains(.keystrokes),
        isSelected: state.liveControls.highlightKeystrokes,
        action: { onAction(.toggleTool(.keystrokes)) }
      )
    case .countdown:
      EmptyView()
    }
  }

  private func liveToggleButton(
    symbol: String,
    help: String,
    isDisabled: Bool,
    isSelected: Bool,
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
      showsInlineTooltip: false,
      action: action
    )
  }

  private var stopButton: some View {
    HoverTooltipIconButton(
      symbol: "stop.fill",
      help: "Stop recording",
      isSelected: true,
      isDisabled: false,
      symbolFontSize: 14,
      size: CGSize(width: 30, height: 30),
      cornerRadius: 7,
      selectedFillOpacity: 0.24,
      selectedStrokeOpacity: 0.42,
      tintOverride: Color.red,
      showsInlineTooltip: false,
      action: { onAction(.stop) }
    )
  }

  private func helpText(_ text: String, for tool: RecordingTool) -> String {
    state.liveControls.disabledTools.contains(tool) ? "\(text). Change before recording." : text
  }

  private var dragGesture: some Gesture {
    DragGesture(minimumDistance: 2, coordinateSpace: .global)
      .onChanged { _ in
        onAction(.drag(NSEvent.mouseLocation))
      }
      .onEnded { _ in
        onAction(.dragEnded)
      }
  }

  private func formattedElapsedTime(at date: Date) -> String {
    let totalSeconds = max(0, Int(date.timeIntervalSince(state.startedAt)))
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds / 60) % 60
    let seconds = totalSeconds % 60
    if hours > 0 {
      return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
    return String(format: "%02d:%02d", minutes, seconds)
  }
}
