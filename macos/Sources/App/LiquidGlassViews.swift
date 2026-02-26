import AppKit
import SwiftUI

@MainActor
struct CaptureHintGlassCard: View {
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
      Text("Drag to select area")
        .font(.system(size: 12.5, weight: .semibold))
        .foregroundStyle(.white)

      Text("Esc cancel  •  ⌘C copy  •  ⌘S save")
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.white.opacity(0.84))
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
      return "Capture full screen"
    case .window:
      return "Capture window-sized area"
    case .selection:
      return "Capture selected area"
    }
  }
}

@MainActor
struct EditorGlassToolbar: View {
  let selectedTool: AnnotationTool
  let toolOrder: [AnnotationTool]
  let selectedColor: Color
  let onSelectTool: (AnnotationTool) -> Void
  let onColorChange: (Color) -> Void
  let onUndo: () -> Void
  let onRedo: () -> Void
  let onCopy: () -> Void
  let onSave: () -> Void
  let onDone: () -> Void
  let onToolbarDrag: ((CGSize) -> Void)?
  let onToolbarDragEnd: (() -> Void)?

  var body: some View {
    Group {
      if #available(macOS 26.0, *) {
        GlassEffectContainer(spacing: 0) {
          HStack(spacing: 4) {
            colorPickerButton

            separator

            HStack(spacing: 1) {
              ForEach(toolOrder) { tool in
                toolbarIconButton(
                  symbol: tool.symbolName,
                  help: tool.title,
                  isSelected: selectedTool == tool
                ) {
                  onSelectTool(tool)
                }
              }
            }

            separator

            HStack(spacing: 1) {
              toolbarIconButton(symbol: "arrow.uturn.backward", help: "Undo", action: onUndo)
              toolbarIconButton(symbol: "arrow.uturn.forward", help: "Redo", action: onRedo)
              toolbarIconButton(symbol: "doc.on.doc", help: "Copy", action: onCopy)
              toolbarIconButton(symbol: "square.and.arrow.down", help: "Save", action: onSave)
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
          fallbackColorPickerButton
          separator
          ForEach(toolOrder) { tool in
            fallbackIconButton(symbol: tool.symbolName, help: tool.title, isSelected: selectedTool == tool) {
              onSelectTool(tool)
            }
          }
          separator
          fallbackIconButton(symbol: "arrow.uturn.backward", help: "Undo", action: onUndo)
          fallbackIconButton(symbol: "arrow.uturn.forward", help: "Redo", action: onRedo)
          fallbackIconButton(symbol: "doc.on.doc", help: "Copy", action: onCopy)
          fallbackIconButton(symbol: "square.and.arrow.down", help: "Save", action: onSave)
          separator
          doneButton
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
      }
    }
    .fixedSize()
    .highPriorityGesture(dragGesture, including: .all)
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
    action: @escaping () -> Void
  ) -> some View {
    HoverTooltipIconButton(
      symbol: symbol,
      help: help,
      isSelected: isSelected,
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
    action: @escaping () -> Void
  ) -> some View {
    HoverTooltipIconButton(
      symbol: symbol,
      help: help,
      isSelected: isSelected,
      size: CGSize(width: 25, height: 23),
      cornerRadius: 7,
      selectedFillOpacity: 0.2,
      selectedStrokeOpacity: 0,
      action: action
    )
  }

  private var dragGesture: some Gesture {
    DragGesture(minimumDistance: 5)
      .onChanged { value in
        onToolbarDrag?(value.translation)
      }
      .onEnded { _ in
        onToolbarDragEnd?()
      }
  }
}

@MainActor
private struct HoverTooltipIconButton: View {
  let symbol: String
  let help: String
  let isSelected: Bool
  let size: CGSize
  let cornerRadius: CGFloat
  let selectedFillOpacity: CGFloat
  let selectedStrokeOpacity: CGFloat
  let action: () -> Void

  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 13, weight: .semibold))
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(help)
    .background(
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .fill(isSelected ? Color.white.opacity(selectedFillOpacity) : Color.clear)
    )
    .overlay(
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .stroke(Color.white.opacity(isSelected ? selectedStrokeOpacity : 0), lineWidth: 1)
    )
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
