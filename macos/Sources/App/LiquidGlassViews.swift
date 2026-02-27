import AppKit
import SwiftUI

@MainActor
struct CaptureHintGlassCard: View {
  let selectedType: CaptureContentType

  var body: some View {
    Group {
      if #available(macOS 26.0, *) {
        GlassEffectContainer(spacing: 0) {
          panelContent
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .glassEffect(.regular, in: .rect(cornerRadius: 12, style: .continuous))
        }
      } else {
        panelContent
          .padding(.horizontal, 12)
          .padding(.vertical, 9)
          .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .fill(.ultraThinMaterial)
              .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                  .stroke(Color.white.opacity(0.12), lineWidth: 1)
              )
          )
      }
    }
    .fixedSize()
    .allowsHitTesting(false)
    .shadow(color: Color.black.opacity(0.26), radius: 12, x: 0, y: 5)
  }

  private var panelContent: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(primaryHintText)
        .font(.system(size: 12.5, weight: .semibold))
        .foregroundStyle(.white)

      Text("Esc cancel  •  1 screenshot  •  2 video  •  ⇧Tab switch")
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.white.opacity(0.84))
    }
  }

  private var primaryHintText: String {
    if selectedType == .screenshot {
      return "Drag area, or use ⌘C / ⌘S for full screen"
    }
    return "Drag area to start video capture"
  }
}

@MainActor
struct CaptureTypeSidebar: View {
  let selectedType: CaptureContentType
  let onSelectType: (CaptureContentType) -> Void

  var body: some View {
    Group {
      if #available(macOS 26.0, *) {
        GlassEffectContainer(spacing: 0) {
          panelContent
            .padding(.horizontal, 7)
            .padding(.vertical, 7)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
      } else {
        panelContent
          .padding(.horizontal, 7)
          .padding(.vertical, 7)
          .background(
            Capsule(style: .continuous)
              .fill(.ultraThinMaterial)
              .overlay(
                Capsule(style: .continuous)
                  .stroke(Color.white.opacity(0.1), lineWidth: 1)
              )
          )
      }
    }
    .fixedSize()
    .shadow(color: Color.black.opacity(0.24), radius: 12, x: 0, y: 6)
  }

  private var panelContent: some View {
    VStack(spacing: 4) {
      ForEach(CaptureContentType.allCases) { type in
        captureButton(type)
      }
    }
  }

  private func captureButton(_ type: CaptureContentType) -> some View {
    let isSelected = type == selectedType

    return Button {
      onSelectType(type)
    }
    label: {
      ZStack {
        Circle()
          .fill(Color.white.opacity(0.1))
          .frame(width: 38, height: 38)
          .overlay(
            Circle()
              .stroke(Color.white.opacity(0.14), lineWidth: 1)
          )

        Image(systemName: type.symbolName)
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(isSelected ? Color.accentColor : Color.white.opacity(0.92))
      }
      .frame(width: 44, height: 44)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(captureTypeHelp(type))
  }

  private func captureTypeHelp(_ type: CaptureContentType) -> String {
    switch type {
    case .screenshot:
      return "Screenshot (1, ⇧Tab)"
    case .video:
      return "Video (2, ⇧Tab)"
    }
  }
}

@MainActor
struct CaptureFloatingToolbar: View {
  let selectedMode: CaptureMode
  let onSelectMode: (CaptureMode) -> Void
  let onCancel: () -> Void
  let onCapture: () -> Void

  var body: some View {
    Group {
      if #available(macOS 26.0, *) {
        GlassEffectContainer(spacing: 12) {
          toolbarContent
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
      } else {
        toolbarContent
          .padding(.horizontal, 12)
          .padding(.vertical, 10)
          .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
              .fill(.ultraThinMaterial)
              .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                  .stroke(Color.white.opacity(0.08), lineWidth: 1)
              )
          )
      }
    }
    .fixedSize()
  }

  private var toolbarContent: some View {
    HStack(spacing: 10) {
      closeButton
      modeSwitcher
      separator
      passiveModeCluster
      separator
      optionsMenu
      captureButton
    }
  }

  private var closeButton: some View {
    iconButton(symbol: "xmark.circle.fill", help: "Cancel", isSelected: false, action: onCancel)
  }

  private var modeSwitcher: some View {
    HStack(spacing: 6) {
      ForEach(CaptureMode.allCases) { mode in
        iconButton(
          symbol: mode.symbolName,
          help: modeHelp(mode),
          isSelected: mode == selectedMode
        ) {
          onSelectMode(mode)
        }
      }
    }
  }

  private var passiveModeCluster: some View {
    HStack(spacing: 6) {
      ForEach(CaptureMode.allCases) { mode in
        Button(action: {}) {
          ZStack(alignment: .bottomTrailing) {
            Image(systemName: mode.symbolName)
              .font(.system(size: 15, weight: .semibold))
              .frame(width: 40, height: 34)
              .contentShape(Rectangle())

            Circle()
              .fill(Color.black.opacity(0.35))
              .frame(width: 11, height: 11)
              .overlay(
                Circle()
                  .stroke(Color.white.opacity(0.6), lineWidth: 1)
              )
              .offset(x: -6, y: -5)
          }
        }
        .buttonStyle(.plain)
        .disabled(true)
        .opacity(0.72)
      }
    }
  }

  private var optionsMenu: some View {
    Group {
      if #available(macOS 26.0, *) {
        Menu {
          Button("No Delay") {}
          Button("5 Second Timer") {}
          Divider()
          Button("Keep Floating Toolbar") {}
        } label: {
          HStack(spacing: 4) {
            Text("Options")
              .font(.system(size: 12, weight: .semibold))
            Image(systemName: "chevron.down")
              .font(.system(size: 11, weight: .semibold))
          }
          .frame(height: 34)
          .padding(.horizontal, 8)
        }
        .buttonStyle(.glass)
        .help("Capture options")
      } else {
        Menu {
          Button("No Delay") {}
          Button("5 Second Timer") {}
          Divider()
          Button("Keep Floating Toolbar") {}
        } label: {
          HStack(spacing: 4) {
            Text("Options")
              .font(.system(size: 12, weight: .semibold))
            Image(systemName: "chevron.down")
              .font(.system(size: 11, weight: .semibold))
          }
          .frame(height: 34)
          .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
        .background(
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.white.opacity(0.09))
        )
        .help("Capture options")
      }
    }
  }

  private var captureButton: some View {
    Group {
      if #available(macOS 26.0, *) {
        Button("Capture", action: onCapture)
          .font(.system(size: 15, weight: .semibold))
          .padding(.horizontal, 24)
          .frame(height: 40)
          .buttonStyle(.glassProminent)
          .help("Capture selection")
      } else {
        Button("Capture", action: onCapture)
          .font(.system(size: 15, weight: .semibold))
          .padding(.horizontal, 24)
          .frame(height: 40)
          .buttonStyle(.borderedProminent)
          .help("Capture selection")
      }
    }
  }

  private var separator: some View {
    Rectangle()
      .fill(Color.white.opacity(0.16))
      .frame(width: 1, height: 28)
  }

  @ViewBuilder
  private func iconButton(
    symbol: String,
    help: String,
    isSelected: Bool,
    action: @escaping () -> Void
  ) -> some View {
    let icon = Image(systemName: symbol)
      .font(.system(size: 15, weight: .semibold))
      .frame(width: 40, height: 34)
      .contentShape(Rectangle())

    if #available(macOS 26.0, *) {
      Button(action: action) {
        icon
      }
      .help(help)
      .buttonStyle(.glass(glassModeStyle(isSelected: isSelected)))
    } else {
      Button(action: action) {
        icon
      }
      .help(help)
      .buttonStyle(.plain)
      .background(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(isSelected ? Color.white.opacity(0.18) : Color.clear)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .stroke(Color.white.opacity(isSelected ? 0.26 : 0), lineWidth: 1)
      )
    }
  }

  @available(macOS 26.0, *)
  private func glassModeStyle(isSelected: Bool) -> Glass {
    if isSelected {
      return .regular.tint(.accentColor.opacity(0.65)).interactive()
    }
    return .regular.interactive()
  }

  private func modeHelp(_ mode: CaptureMode) -> String {
    switch mode {
    case .screen:
      return "Capture full screen (⌃Tab modes)"
    case .window:
      return "Capture selected window (⌃Tab modes)"
    case .selection:
      return "Capture selected area (⌃Tab modes)"
    }
  }
}

@MainActor
struct EditorGlassToolbar: View {
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
  let onDone: () -> Void
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

            doneButton
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
          doneButton
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

  private var doneButton: some View {
    Button(action: onDone) {
      Image(systemName: "checkmark")
        .font(.system(size: 13, weight: .semibold))
        .frame(width: 30, height: 30)
        .contentShape(Circle())
    }
    .foregroundStyle(.white)
    .buttonStyle(.plain)
    .background(
      Circle()
        .fill(Color(red: 1, green: 0.31, blue: 0.34))
    )
    .overlay(
      Circle()
        .stroke(Color.white.opacity(0.24), lineWidth: 1)
    )
    .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 1)
    .help("Done")
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
      help: captureModeHelp(mode),
      isSelected: isSelected,
      isDisabled: false,
      diameter: 30
    ) {
      onSelectCaptureMode(mode)
    }
  }

  private func captureModeHelp(_ mode: CaptureMode) -> String {
    switch mode {
    case .screen:
      return "Full screen (⌃Tab modes)"
    case .window:
      return "Selected window (⌃Tab modes)"
    case .selection:
      return "Selected area (⌃Tab modes)"
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
struct VideoEditorGlassToolbar: View {
  let selectedCaptureMode: CaptureMode
  let onSelectCaptureMode: (CaptureMode) -> Void
  let onCloseCapture: () -> Void
  let recordSystemAudio: Bool
  let recordMicrophone: Bool
  let showWebcam: Bool
  let highlightMouseClicks: Bool
  let highlightKeystrokes: Bool
  let toolOrder: [VideoToolbarTool]
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
          .padding(.horizontal, 10)
          .padding(.vertical, 10)
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
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
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
      .frame(width: 1, height: 22)
  }

  private var recordButton: some View {
    Button(action: onToggleRecording) {
      Image(systemName: isRecordingActive ? "stop.circle.fill" : "record.circle.fill")
        .font(.system(size: 16, weight: .semibold))
        .frame(width: 34, height: 34)
        .contentShape(Circle())
    }
    .foregroundStyle(.white)
    .buttonStyle(.plain)
    .background(
      Circle()
        .fill(Color.red.opacity(0.9))
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
      .frame(height: 30)
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
      size: CGSize(width: 30, height: 28),
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
      size: CGSize(width: 29, height: 27),
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
      help: captureModeHelp(mode),
      isSelected: isSelected,
      isDisabled: disabled,
      diameter: 32
    ) {
      onSelectCaptureMode(mode)
    }
  }

  private func captureModeHelp(_ mode: CaptureMode) -> String {
    switch mode {
    case .screen:
      return "Full screen (⌃Tab modes)"
    case .window:
      return "Selected window (⌃Tab modes)"
    case .selection:
      return "Selected area (⌃Tab modes)"
    }
  }
}

@MainActor
struct StitchRecordingFloatingBar: View {
  let onStop: () -> Void

  var body: some View {
    Group {
      if #available(macOS 26.0, *) {
        GlassEffectContainer(spacing: 0) {
          barContent
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .glassEffect(.regular.interactive(), in: .capsule)
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
    HStack(spacing: 4) {
      Image(systemName: "record.circle.fill")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(Color.red)
        .frame(width: 18, height: 18)

      Text("Scrolling")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.white.opacity(0.9))

      Rectangle()
        .fill(Color.white.opacity(0.18))
        .frame(width: 1, height: 20)

      HoverTooltipIconButton(
        symbol: "stop.circle.fill",
        help: "Stop scrolling capture",
        isSelected: false,
        isDisabled: false,
        size: CGSize(width: 26, height: 24),
        cornerRadius: 7,
        selectedFillOpacity: 0.18,
        selectedStrokeOpacity: 0.34,
        action: onStop
      )
    }
  }
}

@MainActor
private struct HoverTooltipCircleModeButton: View {
  let symbol: String
  let help: String
  let isSelected: Bool
  let isDisabled: Bool
  let diameter: CGFloat
  let action: () -> Void

  @State private var isHovered = false
  @State private var symbolBounceToken = 0

  var body: some View {
    Button {
      symbolBounceToken += 1
      action()
    } label: {
      symbolImage
      .frame(width: diameter + 4, height: diameter + 4)
      .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .disabled(isDisabled)
    .opacity(isDisabled ? 0.45 : 1)
    .help(help)
    .overlay(alignment: .top) {
      if isHovered {
        HoverTooltipLabel(text: help)
          .offset(y: -36)
          .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .bottom)))
      }
    }
    .onHover { hovering in
      withAnimation(.easeOut(duration: 0.12)) {
        isHovered = hovering
      }
    }
    .zIndex(isHovered ? 50 : 0)
  }

  @ViewBuilder
  private var symbolImage: some View {
    let image = Image(systemName: symbol)
      .font(.system(size: max(12, diameter * 0.46), weight: .semibold))
      .foregroundStyle(isSelected ? Color.accentColor : Color.white.opacity(0.9))

    if #available(macOS 14.0, *) {
      image.symbolEffect(.bounce, value: symbolBounceToken)
    } else {
      image
    }
  }
}

@MainActor
private struct HoverTooltipIconButton: View {
  let symbol: String
  let help: String
  let isSelected: Bool
  let isDisabled: Bool
  var symbolFontSize: CGFloat = 13
  let size: CGSize
  let cornerRadius: CGFloat
  let selectedFillOpacity: CGFloat
  let selectedStrokeOpacity: CGFloat
  let action: () -> Void

  @State private var isHovered = false
  @State private var symbolBounceToken = 0

  var body: some View {
    Button {
      symbolBounceToken += 1
      action()
    } label: {
      symbolImage
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(isDisabled)
    .opacity(isDisabled ? 0.45 : 1)
    .help(help)
    .overlay(alignment: .top) {
      if isHovered {
        HoverTooltipLabel(text: help)
          .offset(y: -36)
          .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .bottom)))
      }
    }
    .onHover { hovering in
      withAnimation(.easeOut(duration: 0.12)) {
        isHovered = hovering
      }
    }
    .zIndex(isHovered ? 50 : 0)
  }

  @ViewBuilder
  private var symbolImage: some View {
    let image = Image(systemName: symbol)
      .font(.system(size: symbolFontSize, weight: .semibold))
      .foregroundStyle(isSelected ? Color.accentColor : Color.white.opacity(0.9))

    if #available(macOS 14.0, *) {
      image.symbolEffect(.bounce, value: symbolBounceToken)
    } else {
      image
    }
  }
}

@MainActor
private struct HoverTooltipLabel: View {
  let text: String

  var body: some View {
    Text(text)
      .font(.system(size: 12, weight: .medium))
      .foregroundStyle(.white)
      .lineLimit(1)
      .padding(.horizontal, 9)
      .padding(.vertical, 6)
      .background(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(Color.black.opacity(0.78))
          .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .stroke(Color.white.opacity(0.14), lineWidth: 1)
          )
      )
      .allowsHitTesting(false)
      .fixedSize()
      .shadow(color: Color.black.opacity(0.26), radius: 8, y: 3)
  }
}

@MainActor
private struct NativeColorWell: NSViewRepresentable {
  @Binding var color: NSColor

  func makeCoordinator() -> Coordinator {
    Coordinator(color: $color)
  }

  func makeNSView(context: Context) -> NSColorWell {
    let well = OverlayColorWell(frame: NSRect(x: 0, y: 0, width: 30, height: 24))
    well.color = color
    well.isBordered = true
    well.wantsLayer = true
    well.layer?.cornerRadius = 5
    well.layer?.masksToBounds = true
    well.target = context.coordinator
    well.action = #selector(Coordinator.didChange(_:))
    return well
  }

  func updateNSView(_ nsView: NSColorWell, context _: Context) {
    let rgb = color.usingColorSpace(.deviceRGB) ?? color
    if nsView.color != rgb {
      nsView.color = rgb
    }
  }

  final class Coordinator: NSObject {
    private var color: Binding<NSColor>

    init(color: Binding<NSColor>) {
      self.color = color
    }

    @objc
    func didChange(_ sender: NSColorWell) {
      color.wrappedValue = sender.color.usingColorSpace(.deviceRGB) ?? sender.color
    }
  }
}

private final class OverlayColorWell: NSColorWell {
  override func activate(_ exclusive: Bool) {
    super.activate(exclusive)
    elevateColorPanel()
  }

  override func mouseDown(with event: NSEvent) {
    super.mouseDown(with: event)
    elevateColorPanel()
  }

  private func elevateColorPanel() {
    let panel = NSColorPanel.shared
    panel.level = .screenSaver
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.orderFrontRegardless()
    NSApp.activate(ignoringOtherApps: true)
  }
}
