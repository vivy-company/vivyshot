import AppKit
import SwiftUI

@MainActor
struct HoverTooltipCircleModeButton: View {
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
struct HoverTooltipIconButton: View {
  let symbol: String
  let help: String
  let isSelected: Bool
  let isDisabled: Bool
  var symbolFontSize: CGFloat = 13
  let size: CGSize
  let cornerRadius: CGFloat
  let selectedFillOpacity: CGFloat
  let selectedStrokeOpacity: CGFloat
  var tintOverride: Color? = nil
  var showsInlineTooltip: Bool = true
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
      if showsInlineTooltip && isHovered {
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
    let tint = tintOverride ?? (isSelected ? Color.accentColor : Color.white.opacity(0.9))
    let image = Image(systemName: symbol)
      .font(.system(size: symbolFontSize, weight: .semibold))
      .foregroundStyle(tint)

    if #available(macOS 14.0, *) {
      image.symbolEffect(.bounce, value: symbolBounceToken)
    } else {
      image
    }
  }
}

@MainActor
struct HoverTooltipLabel: View {
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
struct NativeColorWell: NSViewRepresentable {
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

  @MainActor final class Coordinator: NSObject {
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

final class OverlayColorWell: NSColorWell {
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
