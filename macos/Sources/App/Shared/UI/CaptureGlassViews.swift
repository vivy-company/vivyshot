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
      return String(localized: "Click a window or drag an area", bundle: AppLocalizer.shared.bundle)
    }
    return String(localized: "Click a window or drag an area for video", bundle: AppLocalizer.shared.bundle)
  }
}

@MainActor
struct KeystrokeOverlayGlassCapsule: View {
  let text: String
  let style: VideoKeystrokeOverlayStyleOption
  let size: VideoKeystrokeOverlaySizeOption
  let showsResizeGrip: Bool

  var body: some View {
    GeometryReader { proxy in
      let radius = min(proxy.size.height * 0.5, 22)
      let fontSize = max(
        13,
        min(proxy.size.height * fontScale, proxy.size.width / CGFloat(max(4, text.count)) * 1.8)
      )

      ZStack(alignment: .bottomTrailing) {
        background(radius: radius)

        Text(text)
          .font(.system(size: fontSize, weight: .semibold, design: .monospaced))
          .foregroundStyle(.white)
          .lineLimit(1)
          .minimumScaleFactor(0.5)
          .padding(.horizontal, max(14, proxy.size.height * 0.32))
          .frame(maxWidth: .infinity, maxHeight: .infinity)

        if showsResizeGrip {
          ResizeGripGlyph()
            .stroke(Color.white.opacity(style == .glass ? 0.50 : 0.34), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            .frame(width: 14, height: 14)
            .padding(.trailing, 8)
            .padding(.bottom, 7)
        }
      }
    }
    .shadow(color: Color.black.opacity(style == .glass ? 0.24 : 0.10), radius: 10, y: 4)
  }

  private var fontScale: CGFloat {
    switch size {
    case .small:
      return 0.30
    case .medium:
      return 0.36
    case .large:
      return 0.42
    }
  }

  @ViewBuilder
  private func background(radius: CGFloat) -> some View {
    let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
    switch style {
    case .compact:
      shape
        .fill(Color.black.opacity(0.78))
        .overlay(shape.stroke(Color.white.opacity(0.16), lineWidth: 1))
    case .glass:
      if #available(macOS 26.0, *) {
        let glass = showsResizeGrip
          ? Glass.regular.tint(Color.white.opacity(0.08)).interactive()
          : Glass.regular.tint(Color.white.opacity(0.08))
        GlassEffectContainer(spacing: 0) {
          shape
            .fill(Color.white.opacity(0.001))
            .glassEffect(glass, in: shape)
            .overlay(shape.stroke(Color.white.opacity(0.46), lineWidth: 1))
            .overlay(
              shape
                .inset(by: 2.5)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
        }
      } else {
        ZStack {
          shape.fill(.ultraThinMaterial)
          shape.fill(
            LinearGradient(
              colors: [
                Color.white.opacity(0.30),
                Color.accentColor.opacity(0.18),
                Color.black.opacity(0.28)
              ],
              startPoint: .top,
              endPoint: .bottom
            )
          )
          shape.stroke(Color.white.opacity(0.40), lineWidth: 1)
          shape
            .inset(by: 2.5)
            .stroke(Color.white.opacity(0.10), lineWidth: 1)
        }
      }
    }
  }
}

private struct ResizeGripGlyph: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    for offset in stride(from: CGFloat(4), through: CGFloat(12), by: CGFloat(4)) {
      path.move(to: CGPoint(x: rect.maxX - offset, y: rect.maxY))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - offset))
    }
    return path
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
