import AppKit
import SwiftUI

private let toolbarNeutralForeground = Color.white.opacity(0.9)
private let toolbarSecondaryForeground = Color.white.opacity(0.72)

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
final class CaptureModeSelectionState: ObservableObject {
  @Published private(set) var selectedMode: CaptureMode

  init(selectedMode: CaptureMode = .selection) {
    self.selectedMode = selectedMode
  }

  func setSelectedMode(_ mode: CaptureMode, animated: Bool) {
    guard selectedMode != mode else {
      return
    }

    if animated {
      withAnimation(.smooth(duration: 0.22)) {
        selectedMode = mode
      }
    } else {
      selectedMode = mode
    }
  }
}

@MainActor
struct RecordingControlBar: View {
  let startedAt: Date
  let recordSystemAudio: Bool
  let recordMicrophone: Bool
  let showWebcam: Bool
  let highlightMouseClicks: Bool
  let highlightKeystrokes: Bool
  let toolOrder: [RecordingTool]
  let disabledTools: Set<RecordingTool>
  let accentColor: Color
  let usesExternalGlassSurface: Bool
  let onToggleSystemAudio: () -> Void
  let onToggleMicrophone: () -> Void
  let onToggleWebcam: () -> Void
  let onToggleMouseClicks: () -> Void
  let onToggleKeystrokes: () -> Void
  let onStop: () -> Void
  let onDrag: ((CGSize) -> Void)?
  let onDragEnd: (() -> Void)?

  private var hasToggleTools: Bool {
    !toolOrder.isEmpty
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
        ForEach(toolOrder) { tool in
          liveToggleButton(for: tool)
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
    TimelineView(.periodic(from: startedAt, by: 1)) { context in
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
        symbol: recordSystemAudio ? "speaker.wave.2.fill" : "speaker.slash.fill",
        help: helpText(recordSystemAudio ? "System audio on" : "System audio off", for: .systemAudio),
        isDisabled: disabledTools.contains(.systemAudio),
        isSelected: recordSystemAudio,
        action: onToggleSystemAudio
      )
    case .microphone:
      liveToggleButton(
        symbol: recordMicrophone ? "mic.fill" : "mic.slash.fill",
        help: helpText(recordMicrophone ? "Microphone on" : "Microphone off", for: .microphone),
        isDisabled: disabledTools.contains(.microphone),
        isSelected: recordMicrophone,
        action: onToggleMicrophone
      )
    case .webcam:
      liveToggleButton(
        symbol: showWebcam ? "video.fill" : "video.slash.fill",
        help: helpText(showWebcam ? "Camera overlay on" : "Camera overlay off", for: .webcam),
        isDisabled: disabledTools.contains(.webcam),
        isSelected: showWebcam,
        action: onToggleWebcam
      )
    case .mouseClicks:
      liveToggleButton(
        symbol: highlightMouseClicks ? "cursorarrow.rays" : "cursorarrow",
        help: helpText(highlightMouseClicks ? "Mouse clicks on" : "Mouse clicks off", for: .mouseClicks),
        isDisabled: disabledTools.contains(.mouseClicks),
        isSelected: highlightMouseClicks,
        action: onToggleMouseClicks
      )
    case .keystrokes:
      liveToggleButton(
        symbol: "keyboard",
        help: helpText(highlightKeystrokes ? "Keystrokes on" : "Keystrokes off", for: .keystrokes),
        isDisabled: disabledTools.contains(.keystrokes),
        isSelected: highlightKeystrokes,
        action: onToggleKeystrokes
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
      tintOverride: isSelected ? accentColor : toolbarNeutralForeground,
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
      action: onStop
    )
  }

  private func helpText(_ text: String, for tool: RecordingTool) -> String {
    disabledTools.contains(tool) ? "\(text). Change before recording." : text
  }

  private var dragGesture: some Gesture {
    DragGesture(minimumDistance: 2, coordinateSpace: .global)
      .onChanged { value in
        onDrag?(value.translation)
      }
      .onEnded { _ in
        onDragEnd?()
      }
  }

  private func formattedElapsedTime(at date: Date) -> String {
    let totalSeconds = max(0, Int(date.timeIntervalSince(startedAt)))
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds / 60) % 60
    let seconds = totalSeconds % 60
    if hours > 0 {
      return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
    return String(format: "%02d:%02d", minutes, seconds)
  }
}

@MainActor
struct CaptureAnnotationToolbar: View {
  let selectedCaptureMode: CaptureMode
  @ObservedObject var modeSelectionState: CaptureModeSelectionState
  var glassNamespace: Namespace.ID? = nil
  var usesExternalGlassSurface = false
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

  @Namespace private var modeSelectionNamespace

  private var visualSelectedCaptureMode: CaptureMode {
    modeSelectionState.selectedMode
  }

  var body: some View {
    Group {
      if usesExternalGlassSurface {
        toolbarContent
          .padding(.horizontal, 8)
          .padding(.vertical, 8)
      } else if #available(macOS 26.0, *) {
        if glassNamespace != nil {
          glassToolbarSurface
        } else {
          GlassEffectContainer(spacing: 0) {
            glassToolbarSurface
          }
        }
      } else {
        toolbarContent
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

  @available(macOS 26.0, *)
  @ViewBuilder
  private var glassToolbarSurface: some View {
    if let glassNamespace {
      toolbarContent
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .glassEffect(.regular.interactive(), in: .capsule)
        .glassEffectID("region-selection-toolbar-shell", in: glassNamespace)
        .glassEffectTransition(.matchedGeometry)
    } else {
      toolbarContent
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
  }

  private var toolbarContent: some View {
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

  private var fallbackCaptureModeButtons: some View {
    HStack(spacing: 2) {
      ForEach(CaptureMode.allCases) { mode in
        captureModeIconButton(mode)
      }
    }
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
    .foregroundStyle(accentColor)
    .buttonStyle(.plain)
    .overlay(
      Circle()
        .stroke(accentColor.opacity(0.42), lineWidth: 1)
    )
    .help(mainAction == .copy ? "Copy (Return, ⌘C)" : "Save (Return, ⌘S)")
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
      tintOverride: isSelected ? accentColor : toolbarNeutralForeground,
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
    let isSelected = visualSelectedCaptureMode == mode

    return HoverTooltipCircleModeButton(
      symbol: mode.symbolName,
      help: captureModeHelpText(mode),
      isSelected: isSelected,
      isDisabled: false,
      diameter: 30,
      selectionNamespace: modeSelectionNamespace,
      selectionID: "annotation-capture-mode",
      showsSelectionBackground: false,
      selectedTint: accentColor,
      normalTint: toolbarNeutralForeground
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
  @ObservedObject var modeSelectionState: CaptureModeSelectionState
  var glassNamespace: Namespace.ID? = nil
  var usesExternalGlassSurface = false
  let onSelectCaptureMode: (CaptureMode) -> Void
  let onCloseCapture: () -> Void
  let recordSystemAudio: Bool
  let recordMicrophone: Bool
  let showWebcam: Bool
  let highlightMouseClicks: Bool
  let highlightKeystrokes: Bool
  let toolOrder: [RecordingTool]
  let lockedTools: Set<RecordingTool>
  let accentColor: Color
  let isRecordingActive: Bool
  let isRecordingPending: Bool
  let countdown: RecordingCountdown
  let onToggleSystemAudio: () -> Void
  let onToggleMicrophone: () -> Void
  let onToggleWebcam: () -> Void
  let onToggleMouseClicks: () -> Void
  let onToggleKeystrokes: () -> Void
  let onSelectCountdown: (RecordingCountdown) -> Void
  let onToggleRecording: () -> Void
  let onToolbarDrag: ((CGSize) -> Void)?
  let onToolbarDragEnd: (() -> Void)?

  @Namespace private var modeSelectionNamespace

  private var visualSelectedCaptureMode: CaptureMode {
    modeSelectionState.selectedMode
  }

  private var hasConfigurableTools: Bool {
    !toolOrder.isEmpty
  }

  var body: some View {
    Group {
      if usesExternalGlassSurface {
        toolbarContent
          .padding(.horizontal, 8)
          .padding(.vertical, 8)
      } else if #available(macOS 26.0, *) {
        if glassNamespace != nil {
          glassToolbarSurface
        } else {
          GlassEffectContainer(spacing: 0) {
            glassToolbarSurface
          }
        }
      } else {
        toolbarContent
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

  @available(macOS 26.0, *)
  @ViewBuilder
  private var glassToolbarSurface: some View {
    if let glassNamespace {
      toolbarContent
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .glassEffect(.regular.interactive(), in: .capsule)
        .glassEffectID("region-selection-toolbar-shell", in: glassNamespace)
        .glassEffectTransition(.matchedGeometry)
    } else {
      toolbarContent
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
  }

  private var toolbarContent: some View {
    HStack(spacing: 5) {
      closeCaptureButton
      separator
      captureModeButtons
      if hasConfigurableTools {
        separator
        ForEach(toolOrder) { tool in
          recordingToolButton(tool, fallback: false)
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

  private var fallbackCaptureModeButtons: some View {
    HStack(spacing: 2) {
      ForEach(CaptureMode.allCases) { mode in
        captureModeIconButton(mode)
      }
    }
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
    Button(action: onToggleRecording) {
      Image(systemName: isRecordingActive ? "stop.circle.fill" : "record.circle.fill")
        .font(.system(size: 13.5, weight: .semibold))
        .frame(width: 30, height: 30)
        .contentShape(Circle())
    }
    .foregroundStyle(accentColor)
    .buttonStyle(.plain)
    .overlay(
      Circle()
        .stroke(accentColor.opacity(0.42), lineWidth: 1)
    )
    .help(isRecordingActive ? "Stop recording (⌥⌘R)" : "Start video recording (Return, ⌥⌘R)")
    .padding(.leading, 4)
    .disabled(isRecordingPending)
    .opacity(isRecordingPending ? 0.6 : 1)
  }

  private var countdownMenuButton: some View {
    let isCountdownEnabled = countdown != .off
    return Menu {
      ForEach(RecordingCountdown.allCases) { option in
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
          .foregroundStyle(isCountdownEnabled ? accentColor : toolbarNeutralForeground)
        Text(countdown.title)
          .font(.system(size: 11.5, weight: .semibold))
          .foregroundStyle(isCountdownEnabled ? accentColor : toolbarNeutralForeground)
        Image(systemName: "chevron.down")
          .font(.system(size: 9, weight: .bold))
          .foregroundStyle(toolbarSecondaryForeground)
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
  private func recordingToolButton(_ tool: RecordingTool, fallback: Bool) -> some View {
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
      let locked = lockedTools.contains(.microphone)
      if fallback {
        fallbackIconButton(
          symbol: recordMicrophone ? "mic.fill" : "mic.slash.fill",
          help: locked ? "Microphone (Paid)" : "Microphone (⌥⌘M)",
          isSelected: recordMicrophone,
          isDisabled: isRecordingActive || isRecordingPending,
          isLocked: locked,
          action: onToggleMicrophone
        )
      } else {
        toolbarIconButton(
          symbol: recordMicrophone ? "mic.fill" : "mic.slash.fill",
          help: locked ? "Microphone (Paid)" : "Microphone (⌥⌘M)",
          isSelected: recordMicrophone,
          isDisabled: isRecordingActive || isRecordingPending,
          isLocked: locked,
          action: onToggleMicrophone
        )
      }

    case .webcam:
      let locked = lockedTools.contains(.webcam)
      if fallback {
        fallbackIconButton(
          symbol: showWebcam ? "video.fill" : "video.slash.fill",
          help: locked ? "Webcam Overlay (Paid)" : "Webcam Overlay (⌥⌘W)",
          isSelected: showWebcam,
          isDisabled: isRecordingActive || isRecordingPending,
          isLocked: locked,
          action: onToggleWebcam
        )
      } else {
        toolbarIconButton(
          symbol: showWebcam ? "video.fill" : "video.slash.fill",
          help: locked ? "Webcam Overlay (Paid)" : "Webcam Overlay (⌥⌘W)",
          isSelected: showWebcam,
          isDisabled: isRecordingActive || isRecordingPending,
          isLocked: locked,
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
      let locked = lockedTools.contains(.keystrokes)
      if fallback {
        fallbackIconButton(
          symbol: highlightKeystrokes ? "keyboard" : "keyboard.fill",
          help: locked ? "Keystroke Highlights (Paid)" : "Keystroke Highlights (⌥⌘K)",
          isSelected: highlightKeystrokes,
          isDisabled: isRecordingActive || isRecordingPending,
          isLocked: locked,
          action: onToggleKeystrokes
        )
      } else {
        toolbarIconButton(
          symbol: highlightKeystrokes ? "keyboard" : "keyboard.fill",
          help: locked ? "Keystroke Highlights (Paid)" : "Keystroke Highlights (⌥⌘K)",
          isSelected: highlightKeystrokes,
          isDisabled: isRecordingActive || isRecordingPending,
          isLocked: locked,
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
      tintOverride: isSelected ? accentColor : toolbarNeutralForeground,
      isLocked: isLocked,
      action: action
    )
  }

  private func fallbackIconButton(
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
      size: CGSize(width: 25, height: 23),
      cornerRadius: 7,
      selectedFillOpacity: 0.2,
      selectedStrokeOpacity: 0,
      isLocked: isLocked,
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
    let isSelected = visualSelectedCaptureMode == mode
    let disabled = isRecordingActive || isRecordingPending

    return HoverTooltipCircleModeButton(
      symbol: mode.symbolName,
      help: captureModeHelpText(mode),
      isSelected: isSelected,
      isDisabled: disabled,
      diameter: 30,
      selectionNamespace: modeSelectionNamespace,
      selectionID: "video-capture-mode",
      showsSelectionBackground: false,
      selectedTint: accentColor,
      normalTint: toolbarNeutralForeground
    ) {
      onSelectCaptureMode(mode)
    }
  }
}
