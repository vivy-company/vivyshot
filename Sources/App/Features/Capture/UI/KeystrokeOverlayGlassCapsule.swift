import SwiftUI

/// Preview and recording overlay for captured keystroke labels.
@MainActor
struct KeystrokeOverlayGlassCapsule: View {
  let text: String
  let style: KeystrokeStyle
  let size: KeystrokeSize
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
