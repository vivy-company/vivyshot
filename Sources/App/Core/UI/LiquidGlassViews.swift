import AppKit
import SwiftUI

extension View {
  @MainActor
  @ViewBuilder
  func floatingCapsuleGlassSurface(
    usesExternalSurface: Bool = false,
    horizontalPadding: CGFloat = 8,
    verticalPadding: CGFloat = 8,
    tint: Color? = nil,
    isInteractive: Bool = true,
    glassNamespace: Namespace.ID? = nil,
    glassID: String? = nil,
    fallbackStroke: Color? = nil
  ) -> some View {
    if usesExternalSurface {
      padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
    } else if #available(macOS 26.0, *) {
      if let glassNamespace, let glassID {
        padding(.horizontal, horizontalPadding)
          .padding(.vertical, verticalPadding)
          .regularCapsuleGlass(tint: tint, isInteractive: isInteractive)
          .glassEffectID(glassID, in: glassNamespace)
          .glassEffectTransition(.matchedGeometry)
      } else {
        GlassEffectContainer(spacing: 0) {
          padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .regularCapsuleGlass(tint: tint, isInteractive: isInteractive)
        }
      }
    } else if let fallbackStroke {
      padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .overlay(
          Capsule(style: .continuous)
            .stroke(fallbackStroke, lineWidth: 1)
        )
    } else {
      padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
    }
  }

  @MainActor
  @ViewBuilder
  func floatingRoundedGlassSurface(
    usesExternalSurface: Bool = false,
    horizontalPadding: CGFloat,
    verticalPadding: CGFloat,
    cornerRadius: CGFloat,
    tint: Color? = nil,
    isInteractive: Bool = true,
    fallbackStroke: Color? = nil
  ) -> some View {
    if usesExternalSurface {
      padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
    } else if #available(macOS 26.0, *) {
      GlassEffectContainer(spacing: 0) {
        padding(.horizontal, horizontalPadding)
          .padding(.vertical, verticalPadding)
          .regularRoundedGlass(
            cornerRadius: cornerRadius,
            tint: tint,
            isInteractive: isInteractive
          )
      }
    } else if let fallbackStroke {
      padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background(
          RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
              RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(fallbackStroke, lineWidth: 1)
            )
        )
    } else {
      padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background(
          RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
        )
    }
  }

  @available(macOS 26.0, *)
  @MainActor
  @ViewBuilder
  private func regularCapsuleGlass(tint: Color?, isInteractive: Bool) -> some View {
    if let tint {
      if isInteractive {
        glassEffect(.regular.tint(tint).interactive(), in: .capsule)
      } else {
        glassEffect(.regular.tint(tint), in: .capsule)
      }
    } else if isInteractive {
      glassEffect(.regular.interactive(), in: .capsule)
    } else {
      glassEffect(.regular, in: .capsule)
    }
  }

  @available(macOS 26.0, *)
  @MainActor
  @ViewBuilder
  private func regularRoundedGlass(
    cornerRadius: CGFloat,
    tint: Color?,
    isInteractive: Bool
  ) -> some View {
    if let tint {
      if isInteractive {
        glassEffect(
          .regular.tint(tint).interactive(),
          in: .rect(cornerRadius: cornerRadius, style: .continuous)
        )
      } else {
        glassEffect(
          .regular.tint(tint),
          in: .rect(cornerRadius: cornerRadius, style: .continuous)
        )
      }
    } else if isInteractive {
      glassEffect(
        .regular.interactive(),
        in: .rect(cornerRadius: cornerRadius, style: .continuous)
      )
    } else {
      glassEffect(
        .regular,
        in: .rect(cornerRadius: cornerRadius, style: .continuous)
      )
    }
  }
}

/// Circular toolbar button with hover tooltip and optional matched glass selection state.
@MainActor
struct HoverTooltipCircleModeButton: View {
  let symbol: String
  let help: String
  let isSelected: Bool
  let isDisabled: Bool
  let diameter: CGFloat
  var selectionNamespace: Namespace.ID? = nil
  var selectionID: String? = nil
  var showsSelectionBackground = true
  var selectedTint: Color = .accentColor
  var normalTint: Color = Color.white.opacity(0.9)
  let action: () -> Void

  @State private var isHovered = false
  @State private var symbolBounceToken = 0

  var body: some View {
    Button {
      symbolBounceToken += 1
      withAnimation(.smooth(duration: 0.18)) {
        action()
      }
    } label: {
      ZStack {
        if showsSelectionBackground {
          selectedGlassBackground
        }

        symbolImage
      }
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
      .foregroundStyle(isSelected ? selectedTint : normalTint)

    if #available(macOS 14.0, *) {
      image.symbolEffect(.bounce, value: symbolBounceToken)
    } else {
      image
    }
  }

  @ViewBuilder
  private var selectedGlassBackground: some View {
    let size = diameter + 4
    if isSelected {
      if #available(macOS 26.0, *),
         let selectionNamespace,
         let selectionID {
        Circle()
          .fill(Color.white.opacity(0.001))
          .frame(width: size, height: size)
          .glassEffect(.regular.tint(Color.white.opacity(0.08)).interactive(), in: Circle())
          .glassEffectID(selectionID, in: selectionNamespace)
          .glassEffectTransition(.matchedGeometry)
          .overlay(
            Circle()
              .stroke(Color.white.opacity(0.32), lineWidth: 1)
          )
      } else {
        Circle()
          .fill(Color.white.opacity(0.18))
          .overlay(
            Circle()
              .stroke(Color.white.opacity(0.28), lineWidth: 1)
          )
          .frame(width: size, height: size)
      }
    }
  }
}

/// Rectangular icon button with hover tooltip used by capture and settings controls.
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
  var isLocked: Bool = false
  let action: () -> Void

  @State private var isHovered = false
  @State private var symbolBounceToken = 0

  var body: some View {
    Button {
      symbolBounceToken += 1
      action()
    } label: {
      ZStack(alignment: .bottomTrailing) {
        symbolImage
          .frame(width: size.width, height: size.height)

        if isLocked {
          Image(systemName: "lock.fill")
            .font(.system(size: 7, weight: .bold))
            .foregroundStyle(Color.white.opacity(0.9))
            .padding(2)
            .background(Color.black.opacity(0.62), in: Circle())
            .offset(x: 2, y: 1)
        }
      }
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
    let well = ElevatedColorWell(frame: NSRect(x: 0, y: 0, width: 30, height: 24))
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

final class ElevatedColorWell: NSColorWell {
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
