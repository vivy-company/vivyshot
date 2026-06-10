import SwiftUI

struct PostRecordingOverlayPreviewLayer: View {
  let project: PostRecordingProject
  @ObservedObject var playbackState: PostRecordingPreviewPlaybackState

  var body: some View {
    GeometryReader { proxy in
      let videoRect = aspectFitVideoRect(in: proxy.size)
      let renderPlan = project.videoProject.renderPlan(
        timeSeconds: playbackState.currentSeconds,
        renderSize: videoRect.size,
        target: .preview
      )

      ZStack(alignment: .topLeading) {
        ForEach(Array((renderPlan?.items ?? []).enumerated()), id: \.offset) { _, item in
          let itemRect = viewRect(for: item.rect, videoRect: videoRect)
          switch item.kind {
          case .webcam:
            if !project.overlaysBurnedIn, let webcamURL = project.webcamURL {
              webcamOverlay(
                url: webcamURL,
                seconds: playbackState.currentSeconds + project.webcamTimeOffsetSeconds,
                rect: itemRect,
                shape: webcamShape(for: item)
              )
            }
          case .keystroke:
            if !project.overlaysBurnedIn {
              PostRecordingKeystrokeOverlayPreview(
                text: item.text.isEmpty ? "⌘K" : item.text,
                style: keystrokeStyle(for: item),
                size: keystrokeSize(for: item)
              )
              .frame(width: itemRect.width, height: itemRect.height)
              .position(x: itemRect.midX, y: itemRect.midY)
            }
          case .mouseClick:
            PostRecordingMouseClickOverlayPreview(
              style: mouseClickStyle(for: item),
              button: item.mouseClickButtonCode,
              opacity: item.opacity
            )
            .frame(width: itemRect.width, height: itemRect.height)
            .position(x: itemRect.midX, y: itemRect.midY)
          }
        }
      }
      .frame(width: proxy.size.width, height: proxy.size.height)
    }
  }

  private func aspectFitVideoRect(in container: CGSize) -> CGRect {
    let source = project.videoSize ?? container
    guard container.width > 0, container.height > 0, source.width > 0, source.height > 0 else {
      return CGRect(origin: .zero, size: container)
    }

    let scale = min(container.width / source.width, container.height / source.height)
    let size = CGSize(width: source.width * scale, height: source.height * scale)
    return CGRect(
      x: (container.width - size.width) * 0.5,
      y: (container.height - size.height) * 0.5,
      width: size.width,
      height: size.height
    )
  }

  private func viewRect(for renderRect: CGRect, videoRect: CGRect) -> CGRect {
    CGRect(
      x: videoRect.minX + renderRect.minX,
      y: videoRect.minY + videoRect.height - renderRect.maxY,
      width: renderRect.width,
      height: renderRect.height
    ).integral
  }

  @ViewBuilder
  private func webcamOverlay(
    url: URL,
    seconds: Double,
    rect: CGRect,
    shape: WebcamShape
  ) -> some View {
    let preview = PostRecordingWebcamOverlayPreview(
      url: url,
      seconds: seconds,
      isPlaying: playbackState.isPlaying
    )
    .frame(width: rect.width, height: rect.height)

    switch shape {
    case .circle:
      preview
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.55), lineWidth: 1))
        .position(x: rect.midX, y: rect.midY)
    case .roundedRect:
      preview
        .clipShape(RoundedRectangle(cornerRadius: min(rect.height * 0.18, 18), style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: min(rect.height * 0.18, 18), style: .continuous)
            .stroke(Color.white.opacity(0.55), lineWidth: 1)
        )
        .position(x: rect.midX, y: rect.midY)
    }
  }

  private func webcamShape(for item: RenderItem) -> WebcamShape {
    WebcamShape(rawValue: Int(item.webcamShapeCode))
      ?? .roundedRect
  }

  private func keystrokeStyle(for item: RenderItem) -> KeystrokeStyle {
    KeystrokeStyle(rawValue: Int(item.keystrokeStyleCode))
      ?? .compact
  }

  private func keystrokeSize(for item: RenderItem) -> KeystrokeSize {
    KeystrokeSize(rawValue: Int(item.keystrokeSizeCode))
      ?? .medium
  }

  private func mouseClickStyle(for item: RenderItem) -> MouseClickHighlightStyle {
    MouseClickHighlightStyle(rawValue: Int(item.mouseClickStyleCode))
      ?? .ripple
  }
}

private struct PostRecordingKeystrokeOverlayPreview: View {
  let text: String
  let style: KeystrokeStyle
  let size: KeystrokeSize

  var body: some View {
    KeystrokeOverlayGlassCapsule(
      text: text,
      style: style,
      size: size,
      showsResizeGrip: false
    )
  }
}

private struct PostRecordingMouseClickOverlayPreview: View {
  let style: MouseClickHighlightStyle
  let button: UInt8
  let opacity: CGFloat

  var body: some View {
    GeometryReader { proxy in
      let side = min(proxy.size.width, proxy.size.height)
      let lineWidth = max(1.4, side * 0.055)
      let color = clickColor
      ZStack {
        switch style {
        case .system:
          Circle()
            .fill(color.opacity(0.26))
          Circle()
            .stroke(Color.white.opacity(0.78), lineWidth: max(1.5, lineWidth * 0.65))
            .padding(lineWidth)
          Circle()
            .fill(Color.white.opacity(0.92))
            .frame(width: max(4, side * 0.18), height: max(4, side * 0.18))
        case .ripple:
          Circle()
            .stroke(color.opacity(0.92), lineWidth: lineWidth)
          Circle()
            .stroke(Color.white.opacity(0.52), lineWidth: max(1, lineWidth * 0.42))
            .padding(lineWidth * 1.35)
        case .pulse:
          Circle()
            .fill(color.opacity(0.44))
          Circle()
            .stroke(Color.white.opacity(0.82), lineWidth: max(1.5, lineWidth * 0.70))
            .padding(lineWidth * 1.25)
          Circle()
            .fill(Color.white.opacity(0.88))
            .frame(width: max(4, side * 0.24), height: max(4, side * 0.24))
        case .spotlight:
          Circle()
            .fill(
              RadialGradient(
                colors: [
                  color.opacity(0.48),
                  color.opacity(0.16),
                  .clear
                ],
                center: .center,
                startRadius: 0,
                endRadius: side * 0.5
              )
            )
          Circle()
            .fill(Color.white.opacity(0.68))
            .frame(width: max(3, side * 0.10), height: max(3, side * 0.10))
        }
      }
      .opacity(opacity)
    }
    .allowsHitTesting(false)
  }

  private var clickColor: Color {
    switch button {
    case 1:
      return .orange
    case 2:
      return .mint
    default:
      return .accentColor
    }
  }
}
