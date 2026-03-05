import AppKit
import SwiftUI

private func captureModeHelpText(_ mode: CaptureMode) -> String {
  switch mode {
  case .screen:
    return "Full screen (⌃Tab modes)"
  case .window:
    return "Selected window (⌃Tab modes)"
  case .selection:
    return "Selected area (⌃Tab modes)"
  }
}

@MainActor
struct CaptureAnnotationToolbar: View {
  let selectedCaptureMode: CaptureMode
  let onSelectCaptureMode: (CaptureMode) -> Void
  let onCloseCapture: () -> Void
  let selectedTool: AnnotationTool
  let toolOrder: [AnnotationTool]
  let selectedColor: Color
  let onSelectTool: (AnnotationTool) -> Void
  let onColorChange: (Color) -> Void
  let onUndo: () -> Void
  let onRedo: () -> Void
  let onCopy: () -> Void
  let onSave: () -> Void
  let onAddStitchSegment: (() -> Void)?
  let onResetStitch: (() -> Void)?
  let isStitchRecordingActive: Bool
  let isStitchCaptureInProgress: Bool
  let mainAction: ScreenshotMainAction
  let onMainAction: () -> Void
  let accentColor: Color
  let onToolbarDrag: ((CGSize) -> Void)?
  let onToolbarDragEnd: (() -> Void)?

  var body: some View {
    Group {
      if #available(macOS 26.0, *) {
        GlassEffectContainer(spacing: 0) {
          HStack(spacing: 4) {
            closeCaptureButton
            separator
            captureModeButtons
            separator
            colorPickerButton

            separator

            HStack(spacing: 1) {
              ForEach(Array(toolOrder.enumerated()), id: \.element.id) { index, tool in
                toolbarIconButton(
                  symbol: tool.symbolName,
                  help: toolHelp(tool, index: index),
                  isSelected: selectedTool == tool
                ) {
                  onSelectTool(tool)
                }
              }
            }

            separator

            HStack(spacing: 1) {
              toolbarIconButton(symbol: "arrow.uturn.backward", help: "Undo (⌘Z)", action: onUndo)
              toolbarIconButton(symbol: "arrow.uturn.forward", help: "Redo (⇧⌘Z)", action: onRedo)
              toolbarIconButton(symbol: "doc.on.doc", help: "Copy (⌘C)", action: onCopy)
              toolbarIconButton(symbol: "square.and.arrow.down", help: "Save (⌘S)", action: onSave)
            }

            if onAddStitchSegment != nil {
              separator
              HStack(spacing: 1) {
                toolbarIconButton(
                  symbol: isStitchRecordingActive ? "stop.circle.fill" : "record.circle",
                  help: isStitchRecordingActive ? "Stop scrolling capture (⌘N)" : "Start scrolling capture (⌘N)"
                ) {
                  onAddStitchSegment?()
                }
                if onResetStitch != nil {
                  toolbarIconButton(
                    symbol: "arrow.counterclockwise",
                    help: "Reset stitch (⌘R)",
                    isDisabled: isStitchCaptureInProgress || isStitchRecordingActive
                  ) {
                    onResetStitch?()
                  }
                }
              }
            }

            separator

            mainActionButton
          }
          .padding(.horizontal, 8)
          .padding(.vertical, 8)
          .glassEffect(.regular.interactive(), in: .capsule)
        }
      } else {
        HStack(spacing: 4) {
          fallbackCloseCaptureButton
          separator
          fallbackCaptureModeButtons
          separator
          fallbackColorPickerButton
          separator
          ForEach(Array(toolOrder.enumerated()), id: \.element.id) { index, tool in
            fallbackIconButton(
              symbol: tool.symbolName,
              help: toolHelp(tool, index: index),
              isSelected: selectedTool == tool
            ) {
              onSelectTool(tool)
            }
          }
          separator
          fallbackIconButton(symbol: "arrow.uturn.backward", help: "Undo (⌘Z)", action: onUndo)
          fallbackIconButton(symbol: "arrow.uturn.forward", help: "Redo (⇧⌘Z)", action: onRedo)
          fallbackIconButton(symbol: "doc.on.doc", help: "Copy (⌘C)", action: onCopy)
          fallbackIconButton(symbol: "square.and.arrow.down", help: "Save (⌘S)", action: onSave)
          if onAddStitchSegment != nil {
            separator
            fallbackIconButton(
              symbol: isStitchRecordingActive ? "stop.circle.fill" : "record.circle",
              help: isStitchRecordingActive ? "Stop scrolling capture (⌘N)" : "Start scrolling capture (⌘N)"
            ) {
              onAddStitchSegment?()
            }
            if onResetStitch != nil {
              fallbackIconButton(
                symbol: "arrow.counterclockwise",
                help: "Reset stitch (⌘R)",
                isDisabled: isStitchCaptureInProgress || isStitchRecordingActive
              ) {
                onResetStitch?()
              }
            }
          }
          separator
          mainActionButton
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
      }
    }
    .fixedSize()
    .contentShape(Rectangle())
    .highPriorityGesture(dragGesture, including: .subviews)
  }

  private var closeCaptureButton: some View {
    toolbarIconButton(symbol: "xmark.circle.fill", help: "Exit capture (Esc)", action: onCloseCapture)
  }

  private var fallbackCloseCaptureButton: some View {
    fallbackIconButton(symbol: "xmark.circle.fill", help: "Exit capture (Esc)", action: onCloseCapture)
  }

  private var captureModeButtons: some View {
    HStack(spacing: 2) {
      ForEach(CaptureMode.allCases) { mode in
        captureModeIconButton(mode)
      }
    }
  }

  private var fallbackCaptureModeButtons: some View {
    HStack(spacing: 2) {
      ForEach(CaptureMode.allCases) { mode in
        captureModeIconButton(mode)
      }
    }
  }

  private var separator: some View {
    Rectangle()
      .fill(Color.white.opacity(0.18))
      .frame(width: 1, height: 20)
  }

  private var colorPickerButton: some View {
    NativeColorWell(
      color: Binding(
        get: {
          NSColor(selectedColor).usingColorSpace(.deviceRGB) ?? .systemOrange
        },
        set: { newColor in
          let rgb = newColor.usingColorSpace(.deviceRGB) ?? newColor
          onColorChange(Color(rgb))
        }
      )
    )
    .frame(width: 28, height: 20)
    .padding(.leading, 14)
    .padding(.trailing, 10)
    .help("Annotation color")
  }

  private var fallbackColorPickerButton: some View {
    NativeColorWell(
      color: Binding(
        get: {
          NSColor(selectedColor).usingColorSpace(.deviceRGB) ?? .systemOrange
        },
        set: { newColor in
          let rgb = newColor.usingColorSpace(.deviceRGB) ?? newColor
          onColorChange(Color(rgb))
        }
      )
    )
    .frame(width: 26, height: 18)
    .padding(.leading, 12)
    .padding(.trailing, 9)
    .help("Annotation color")
  }

  private var mainActionButton: some View {
    Button(action: onMainAction) {
      Image(systemName: mainAction.symbolName)
        .font(.system(size: 13, weight: .semibold))
        .frame(width: 30, height: 30)
        .contentShape(Circle())
    }
    .foregroundStyle(.white)
    .buttonStyle(.plain)
    .background(
      Circle()
        .fill(accentColor)
    )
    .overlay(
      Circle()
        .stroke(Color.white.opacity(0.24), lineWidth: 1)
    )
    .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 1)
    .help(mainAction == .copy ? "Copy (⌘C)" : "Save (⌘S)")
    .padding(.leading, 6)
    .padding(.trailing, 4)
  }

  private func toolbarIconButton(
    symbol: String,
    help: String,
    isSelected: Bool = false,
    isDisabled: Bool = false,
    action: @escaping () -> Void
  ) -> some View {
    HoverTooltipIconButton(
      symbol: symbol,
      help: help,
      isSelected: isSelected,
      isDisabled: isDisabled,
      size: CGSize(width: 26, height: 24),
      cornerRadius: 7,
      selectedFillOpacity: 0.18,
      selectedStrokeOpacity: 0.34,
      action: action
    )
  }

  private func fallbackIconButton(
    symbol: String,
    help: String,
    isSelected: Bool = false,
    isDisabled: Bool = false,
    action: @escaping () -> Void
  ) -> some View {
    HoverTooltipIconButton(
      symbol: symbol,
      help: help,
      isSelected: isSelected,
      isDisabled: isDisabled,
      size: CGSize(width: 25, height: 23),
      cornerRadius: 7,
      selectedFillOpacity: 0.2,
      selectedStrokeOpacity: 0,
      action: action
    )
  }

  private var dragGesture: some Gesture {
    DragGesture(minimumDistance: 5, coordinateSpace: .global)
      .onChanged { value in
        onToolbarDrag?(value.translation)
      }
      .onEnded { _ in
        onToolbarDragEnd?()
      }
  }

  private func captureModeIconButton(_ mode: CaptureMode) -> some View {
    let isSelected = selectedCaptureMode == mode

    return HoverTooltipCircleModeButton(
      symbol: mode.symbolName,
      help: captureModeHelpText(mode),
      isSelected: isSelected,
      isDisabled: false,
      diameter: 30
    ) {
      onSelectCaptureMode(mode)
    }
  }

  private func toolHelp(_ tool: AnnotationTool, index: Int) -> String {
    let slot = index + 1
    guard slot <= 9 else {
      return tool.title
    }
    return "\(tool.title) (⌘\(slot))"
  }
}

@MainActor
struct CaptureVideoToolbar: View {
  let selectedCaptureMode: CaptureMode
  let onSelectCaptureMode: (CaptureMode) -> Void
  let onCloseCapture: () -> Void
  let recordSystemAudio: Bool
  let recordMicrophone: Bool
  let showWebcam: Bool
  let highlightMouseClicks: Bool
  let highlightKeystrokes: Bool
  let toolOrder: [VideoToolbarTool]
  let accentColor: Color
  let isRecordingActive: Bool
  let isRecordingPending: Bool
  let countdown: VideoCountdownOption
  let onToggleSystemAudio: () -> Void
  let onToggleMicrophone: () -> Void
  let onToggleWebcam: () -> Void
  let onToggleMouseClicks: () -> Void
  let onToggleKeystrokes: () -> Void
  let onSelectCountdown: (VideoCountdownOption) -> Void
  let onToggleRecording: () -> Void
  let onToolbarDrag: ((CGSize) -> Void)?
  let onToolbarDragEnd: (() -> Void)?

  private var hasConfigurableTools: Bool {
    !toolOrder.isEmpty
  }

  var body: some View {
    Group {
      if #available(macOS 26.0, *) {
        GlassEffectContainer(spacing: 0) {
          HStack(spacing: 5) {
            closeCaptureButton
            separator
            captureModeButtons
            if hasConfigurableTools {
              separator
              ForEach(toolOrder) { tool in
                videoToolButton(tool, fallback: false)
              }
            }
            separator
            recordButton
          }
          .padding(.horizontal, 8)
          .padding(.vertical, 8)
          .glassEffect(.regular.interactive(), in: .capsule)
        }
      } else {
        HStack(spacing: 5) {
          fallbackCloseCaptureButton
          separator
          fallbackCaptureModeButtons
          if hasConfigurableTools {
            separator
            ForEach(toolOrder) { tool in
              videoToolButton(tool, fallback: true)
            }
          }
          separator
          recordButton
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
      }
    }
    .fixedSize()
    .contentShape(Rectangle())
    .highPriorityGesture(dragGesture, including: .subviews)
  }

  private var closeCaptureButton: some View {
    toolbarIconButton(
      symbol: "xmark.circle.fill",
      help: "Exit capture (Esc)",
      isSelected: false,
      isDisabled: isRecordingPending,
      action: onCloseCapture
    )
  }

  private var fallbackCloseCaptureButton: some View {
    fallbackIconButton(
      symbol: "xmark.circle.fill",
      help: "Exit capture (Esc)",
      isSelected: false,
      isDisabled: isRecordingPending,
      action: onCloseCapture
    )
  }

  private var captureModeButtons: some View {
    HStack(spacing: 2) {
      ForEach(CaptureMode.allCases) { mode in
        captureModeIconButton(mode)
      }
    }
  }

  private var fallbackCaptureModeButtons: some View {
    HStack(spacing: 2) {
      ForEach(CaptureMode.allCases) { mode in
        captureModeIconButton(mode)
      }
    }
  }

  private var separator: some View {
    Rectangle()
      .fill(Color.white.opacity(0.18))
      .frame(width: 1, height: 20)
  }

  private var recordButton: some View {
    Button(action: onToggleRecording) {
      Image(systemName: isRecordingActive ? "stop.circle.fill" : "record.circle.fill")
        .font(.system(size: 13.5, weight: .semibold))
        .frame(width: 30, height: 30)
        .contentShape(Circle())
    }
    .foregroundStyle(.white)
    .buttonStyle(.plain)
    .background(
      Circle()
        .fill(accentColor)
    )
    .overlay(
      Circle()
        .stroke(Color.white.opacity(0.24), lineWidth: 1)
    )
    .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 1)
    .help(isRecordingActive ? "Stop recording (⌥⌘R)" : "Start video recording (⌥⌘R)")
    .padding(.leading, 4)
    .disabled(isRecordingPending)
    .opacity(isRecordingPending ? 0.6 : 1)
  }

  private var countdownMenuButton: some View {
    let isCountdownEnabled = countdown != .off
    return Menu {
      ForEach(VideoCountdownOption.allCases) { option in
        Button {
          onSelectCountdown(option)
        } label: {
          if option == countdown {
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
          .foregroundStyle(isCountdownEnabled ? Color.accentColor : Color.white.opacity(0.9))
        Text(countdown.title)
          .font(.system(size: 11.5, weight: .semibold))
          .foregroundStyle(isCountdownEnabled ? Color.accentColor : Color.white.opacity(0.9))
        Image(systemName: "chevron.down")
          .font(.system(size: 9, weight: .bold))
          .foregroundStyle(Color.white.opacity(0.72))
      }
      .frame(height: 26)
      .padding(.horizontal, 10)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(isRecordingActive || isRecordingPending)
    .opacity((isRecordingActive || isRecordingPending) ? 0.45 : 1)
    .help("Countdown: \(countdown.title) (⌥⌘T)")
  }

  @ViewBuilder
  private func videoToolButton(_ tool: VideoToolbarTool, fallback: Bool) -> some View {
    switch tool {
    case .systemAudio:
      if fallback {
        fallbackIconButton(
          symbol: recordSystemAudio ? "speaker.wave.2.fill" : "speaker.slash.fill",
          help: "System Audio (⌥⌘A)",
          isSelected: recordSystemAudio,
          isDisabled: isRecordingActive || isRecordingPending,
          action: onToggleSystemAudio
        )
      } else {
        toolbarIconButton(
          symbol: recordSystemAudio ? "speaker.wave.2.fill" : "speaker.slash.fill",
          help: "System Audio (⌥⌘A)",
          isSelected: recordSystemAudio,
          isDisabled: isRecordingActive || isRecordingPending,
          action: onToggleSystemAudio
        )
      }

    case .microphone:
      if fallback {
        fallbackIconButton(
          symbol: recordMicrophone ? "mic.fill" : "mic.slash.fill",
          help: "Microphone (⌥⌘M)",
          isSelected: recordMicrophone,
          isDisabled: isRecordingActive || isRecordingPending,
          action: onToggleMicrophone
        )
      } else {
        toolbarIconButton(
          symbol: recordMicrophone ? "mic.fill" : "mic.slash.fill",
          help: "Microphone (⌥⌘M)",
          isSelected: recordMicrophone,
          isDisabled: isRecordingActive || isRecordingPending,
          action: onToggleMicrophone
        )
      }

    case .webcam:
      if fallback {
        fallbackIconButton(
          symbol: showWebcam ? "video.fill" : "video.slash.fill",
          help: "Webcam Overlay (⌥⌘W)",
          isSelected: showWebcam,
          isDisabled: isRecordingActive || isRecordingPending,
          action: onToggleWebcam
        )
      } else {
        toolbarIconButton(
          symbol: showWebcam ? "video.fill" : "video.slash.fill",
          help: "Webcam Overlay (⌥⌘W)",
          isSelected: showWebcam,
          isDisabled: isRecordingActive || isRecordingPending,
          action: onToggleWebcam
        )
      }

    case .mouseClicks:
      if fallback {
        fallbackIconButton(
          symbol: highlightMouseClicks ? "cursorarrow.rays" : "cursorarrow",
          help: "Mouse Click Highlights (⌥⌘L)",
          isSelected: highlightMouseClicks,
          isDisabled: isRecordingActive || isRecordingPending,
          action: onToggleMouseClicks
        )
      } else {
        toolbarIconButton(
          symbol: highlightMouseClicks ? "cursorarrow.rays" : "cursorarrow",
          help: "Mouse Click Highlights (⌥⌘L)",
          isSelected: highlightMouseClicks,
          isDisabled: isRecordingActive || isRecordingPending,
          action: onToggleMouseClicks
        )
      }

    case .keystrokes:
      if fallback {
        fallbackIconButton(
          symbol: highlightKeystrokes ? "keyboard" : "keyboard.fill",
          help: "Keystroke Highlights (⌥⌘K)",
          isSelected: highlightKeystrokes,
          isDisabled: isRecordingActive || isRecordingPending,
          action: onToggleKeystrokes
        )
      } else {
        toolbarIconButton(
          symbol: highlightKeystrokes ? "keyboard" : "keyboard.fill",
          help: "Keystroke Highlights (⌥⌘K)",
          isSelected: highlightKeystrokes,
          isDisabled: isRecordingActive || isRecordingPending,
          action: onToggleKeystrokes
        )
      }

    case .countdown:
      countdownMenuButton
    }
  }

  private func toolbarIconButton(
    symbol: String,
    help: String,
    isSelected: Bool,
    isDisabled: Bool = false,
    action: @escaping () -> Void
  ) -> some View {
    HoverTooltipIconButton(
      symbol: symbol,
      help: help,
      isSelected: isSelected,
      isDisabled: isDisabled,
      symbolFontSize: 15,
      size: CGSize(width: 26, height: 24),
      cornerRadius: 7,
      selectedFillOpacity: 0.18,
      selectedStrokeOpacity: 0.34,
      action: action
    )
  }

  private func fallbackIconButton(
    symbol: String,
    help: String,
    isSelected: Bool,
    isDisabled: Bool = false,
    action: @escaping () -> Void
  ) -> some View {
    HoverTooltipIconButton(
      symbol: symbol,
      help: help,
      isSelected: isSelected,
      isDisabled: isDisabled,
      symbolFontSize: 15,
      size: CGSize(width: 25, height: 23),
      cornerRadius: 7,
      selectedFillOpacity: 0.2,
      selectedStrokeOpacity: 0,
      action: action
    )
  }

  private var dragGesture: some Gesture {
    DragGesture(minimumDistance: 5, coordinateSpace: .global)
      .onChanged { value in
        onToolbarDrag?(value.translation)
      }
      .onEnded { _ in
        onToolbarDragEnd?()
      }
  }

  private func captureModeIconButton(_ mode: CaptureMode) -> some View {
    let isSelected = selectedCaptureMode == mode
    let disabled = isRecordingActive || isRecordingPending

    return HoverTooltipCircleModeButton(
      symbol: mode.symbolName,
      help: captureModeHelpText(mode),
      isSelected: isSelected,
      isDisabled: disabled,
      diameter: 30
    ) {
      onSelectCaptureMode(mode)
    }
  }

}
