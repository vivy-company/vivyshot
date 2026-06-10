import AppKit
import SwiftUI

@MainActor
struct CaptureAnnotationToolbar: View {
  @ObservedObject var modeSelectionState: CaptureModeSelectionState
  var glassNamespace: Namespace.ID? = nil
  var usesExternalGlassSurface = false
  let selectedTool: AnnotationTool
  let toolOrder: [AnnotationTool]
  let selectedColor: Color
  let stitchState: StitchToolbarState?
  let mainAction: ScreenshotMainAction
  let accentColor: Color
  let onAction: (CaptureAnnotationToolbarAction) -> Void

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
    toolbarIconButton(symbol: "xmark.circle.fill", help: "Exit capture (Esc)") {
      onAction(.closeCapture)
    }
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
            onAction(.selectTool(tool))
          }
        }
      }

      separator

      HStack(spacing: 1) {
        toolbarIconButton(symbol: "arrow.uturn.backward", help: "Undo (⌘Z)") { onAction(.undo) }
        toolbarIconButton(symbol: "arrow.uturn.forward", help: "Redo (⇧⌘Z)") { onAction(.redo) }
        toolbarIconButton(symbol: "doc.on.doc", help: "Copy (⌘C)") { onAction(.copy) }
        toolbarIconButton(symbol: "square.and.arrow.down", help: "Save (⌘S)") { onAction(.save) }
      }

      if let stitchState {
        separator
        HStack(spacing: 1) {
          toolbarIconButton(
            symbol: stitchState.isRecordingActive ? "stop.circle.fill" : "record.circle",
            help: stitchState.isRecordingActive ? "Stop scrolling capture (⌘N)" : "Start scrolling capture (⌘N)"
          ) {
            onAction(.addStitchSegment)
          }
          if stitchState.canReset {
            toolbarIconButton(
              symbol: "arrow.counterclockwise",
              help: "Reset stitch (⌘R)",
              isDisabled: stitchState.isCaptureInProgress || stitchState.isRecordingActive
            ) {
              onAction(.resetStitch)
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
          onAction(.changeColor(Color(rgb)))
        }
      )
    )
    .frame(width: 28, height: 20)
    .padding(.leading, 14)
    .padding(.trailing, 10)
    .help("Annotation color")
  }

  private var mainActionButton: some View {
    Button {
      onAction(.mainAction)
    } label: {
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
      onAction(.selectCaptureMode(mode))
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
