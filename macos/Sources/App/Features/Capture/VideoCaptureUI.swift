import AppKit
import AVFoundation
import AVKit
import CoreMedia
import SwiftUI

@MainActor
final class VideoRecordingHUDController: NSWindowController {
  private let recordSystemAudio: Bool
  private let recordMicrophone: Bool
  private let onStop: () -> Void
  private var timer: Timer?
  private var startedAt = Date()
  private var elapsedSeconds = 0
  private var anchorRect: CGRect = .zero
  private var hostingView: NSHostingView<VideoRecordingFloatingBar>?

  init(
    recordSystemAudio: Bool,
    recordMicrophone: Bool,
    onStop: @escaping () -> Void
  ) {
    self.recordSystemAudio = recordSystemAudio
    self.recordMicrophone = recordMicrophone
    self.onStop = onStop

    let panel = NSPanel(
      contentRect: CGRect(x: 0, y: 0, width: 300, height: 48),
      styleMask: [.nonactivatingPanel, .borderless],
      backing: .buffered,
      defer: false
    )
    panel.isReleasedWhenClosed = false
    panel.level = .statusBar
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    panel.hidesOnDeactivate = false
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.ignoresMouseEvents = false
    panel.isMovable = true
    panel.isMovableByWindowBackground = true

    super.init(window: panel)
    configureUI()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  func show(near rect: CGRect) {
    guard let panel = window as? NSPanel else {
      return
    }

    anchorRect = rect.standardized
    startedAt = Date()
    elapsedSeconds = 0
    refreshHUD()
    positionPanel(panel, near: anchorRect)
    panel.orderFrontRegardless()

    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      guard let self else {
        return
      }
      MainActor.assumeIsolated {
        self.refreshHUD()
      }
    }
  }

  override func close() {
    timer?.invalidate()
    timer = nil
    super.close()
  }

  private func configureUI() {
    guard let panel = window as? NSPanel else {
      return
    }
    let host = NSHostingView(rootView: makeBarView())
    panel.contentView = host
    hostingView = host
    refreshHUD()
  }

  private func makeBarView() -> VideoRecordingFloatingBar {
    VideoRecordingFloatingBar(
      elapsedSeconds: elapsedSeconds,
      recordSystemAudio: recordSystemAudio,
      recordMicrophone: recordMicrophone,
      onStop: { [weak self] in
        self?.onStop()
      }
    )
  }

  private func refreshHUD() {
    elapsedSeconds = max(0, Int(Date().timeIntervalSince(startedAt)))
    guard let panel = window as? NSPanel, let hostingView else {
      return
    }
    hostingView.rootView = makeBarView()
    hostingView.layoutSubtreeIfNeeded()
    let size = preferredPanelSize(for: hostingView.fittingSize)
    hostingView.frame = CGRect(origin: .zero, size: size)
    panel.setContentSize(size)
    if !anchorRect.isEmpty {
      positionPanel(panel, near: anchorRect)
    }
  }

  private func preferredPanelSize(for fittingSize: CGSize) -> CGSize {
    CGSize(
      width: max(220, ceil(fittingSize.width)),
      height: max(42, ceil(fittingSize.height))
    )
  }

  private func positionPanel(_ panel: NSPanel, near rect: CGRect) {
    let size = panel.frame.size
    var x = rect.midX - size.width * 0.5
    var y = rect.maxY + 12

    if let screen = NSScreen.screens.first(where: { $0.frame.intersects(rect) }) {
      let visible = screen.visibleFrame
      x = min(max(visible.minX + 8, x), visible.maxX - size.width - 8)
      y = min(max(visible.minY + 8, y), visible.maxY - size.height - 8)
    }

    panel.setFrame(
      CGRect(x: x, y: y, width: size.width, height: size.height).integral,
      display: false
    )
  }
}

// MARK: - Post-Recording Action Dialog

enum PostRecordingAction {
  case saveMP4
  case saveGIF
}

struct PostRecordingDetails {
  let frameRate: Int
  let systemAudioEnabled: Bool
  let microphoneEnabled: Bool
  let webcamEnabled: Bool
  let mouseClicksEnabled: Bool
  let keystrokesEnabled: Bool
  let keyEventCount: Int
  let clickEventCount: Int

  var toolsSummaryText: String {
    var tools: [String] = ["Screen"]
    if systemAudioEnabled { tools.append("System Audio") }
    if microphoneEnabled { tools.append("Microphone") }
    if webcamEnabled { tools.append("Webcam") }
    if mouseClicksEnabled {
      if clickEventCount > 0 {
        tools.append("Mouse Clicks (\(clickEventCount))")
      } else {
        tools.append("Mouse Clicks")
      }
    }
    if keystrokesEnabled {
      if keyEventCount > 0 {
        tools.append("Keystrokes (\(keyEventCount))")
      } else {
        tools.append("Keystrokes")
      }
    }
    return tools.joined(separator: " • ")
  }

  func subtitleText(durationSeconds: Double, videoSize: CGSize?) -> String {
    var parts: [String] = []
    if let videoSize {
      parts.append("\(Int(videoSize.width))×\(Int(videoSize.height))")
    }
    parts.append(formattedDuration(durationSeconds))
    parts.append("\(frameRate) fps")
    return parts.joined(separator: " • ")
  }

  private func formattedDuration(_ seconds: Double) -> String {
    let total = max(0, Int(seconds))
    let hours = total / 3600
    let minutes = (total / 60) % 60
    let secs = total % 60
    if hours > 0 {
      return String(format: "%02d:%02d:%02d", hours, minutes, secs)
    }
    return String(format: "%02d:%02d", minutes, secs)
  }
}

@MainActor
final class PostRecordingActionPanel: NSWindowController, NSWindowDelegate {
  private let inputURL: URL
  private let details: PostRecordingDetails
  private let onAction: (PostRecordingAction) -> Void
  private var didPickAction = false

  init(
    inputURL: URL,
    details: PostRecordingDetails,
    durationSeconds: Double,
    thumbnail: NSImage?,
    videoSize: CGSize?,
    onAction: @escaping (PostRecordingAction) -> Void
  ) {
    self.inputURL = inputURL
    self.details = details
    self.onAction = onAction

    let panel = NSPanel(
      contentRect: CGRect(x: 0, y: 0, width: 420, height: 360),
      styleMask: [.titled, .closable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    panel.level = .floating
    panel.title = "Recording Ready"
    panel.toolbar = NSToolbar(identifier: "PostRecordingToolbar")
    panel.toolbarStyle = .unified
    panel.titlebarAppearsTransparent = true
    panel.titleVisibility = .visible
    panel.isMovableByWindowBackground = true
    panel.isReleasedWhenClosed = false
    panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
    panel.standardWindowButton(.zoomButton)?.isHidden = true

    super.init(window: panel)
    panel.delegate = self

    let safeDuration = durationSeconds.isFinite ? durationSeconds : 0
    let subtitle = details.subtitleText(
      durationSeconds: safeDuration,
      videoSize: videoSize
    )
    panel.subtitle = subtitle

    let actionView = PostRecordingActionView(
      inputURL: inputURL,
      thumbnail: thumbnail,
      durationSeconds: safeDuration,
      subtitleText: subtitle,
      toolsSummaryText: details.toolsSummaryText
    ) { [weak self] action in
      guard let self, !self.didPickAction else {
        return
      }
      self.didPickAction = true
      self.window?.close()
      let actionHandler = self.onAction
      DispatchQueue.main.async {
        actionHandler(action)
      }
    }
    panel.contentView = NSHostingView(rootView: actionView)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  func present() {
    window?.center()
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func windowWillClose(_ notification: Notification) {
    if !didPickAction {
      didPickAction = true
      let actionHandler = onAction
      DispatchQueue.main.async {
        actionHandler(.saveMP4)
      }
    }
  }

  static func loadAssetInfo(url: URL) async -> (durationSeconds: Double, thumbnail: NSImage?, videoSize: CGSize?) {
    let asset = AVURLAsset(url: url)

    let durationSeconds: Double
    if let duration = try? await asset.load(.duration) {
      durationSeconds = max(0, CMTimeGetSeconds(duration))
    } else {
      durationSeconds = 0
    }

    let thumbnail: NSImage?
    do {
      let generator = AVAssetImageGenerator(asset: asset)
      generator.appliesPreferredTrackTransform = true
      generator.maximumSize = CGSize(width: 320, height: 320)
      generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)
      generator.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
      let (cgImage, _) = try await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600))
      thumbnail = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    } catch {
      thumbnail = nil
    }

    let videoSize: CGSize?
    do {
      let tracks = try await asset.loadTracks(withMediaType: .video)
      if let track = tracks.first {
        let naturalSize = try await track.load(.naturalSize)
        let preferredTransform = try await track.load(.preferredTransform)
        let transformed = naturalSize.applying(preferredTransform)
        videoSize = CGSize(width: abs(transformed.width), height: abs(transformed.height))
      } else {
        videoSize = nil
      }
    } catch {
      videoSize = nil
    }

    return (durationSeconds, thumbnail, videoSize)
  }
}

private struct PostRecordingActionView: View {
  let inputURL: URL
  let thumbnail: NSImage?
  let durationSeconds: Double
  let subtitleText: String
  let toolsSummaryText: String
  let onAction: (PostRecordingAction) -> Void

  private var formattedDuration: String {
    let minutes = Int(durationSeconds) / 60
    let seconds = Int(durationSeconds) % 60
    let centiseconds = Int((durationSeconds.truncatingRemainder(dividingBy: 1)) * 100)
    return String(format: "%02d:%02d.%02d", minutes, seconds, centiseconds)
  }

  init(
    inputURL: URL,
    thumbnail: NSImage?,
    durationSeconds: Double,
    subtitleText: String,
    toolsSummaryText: String,
    onAction: @escaping (PostRecordingAction) -> Void
  ) {
    self.inputURL = inputURL
    self.thumbnail = thumbnail
    self.durationSeconds = durationSeconds
    self.subtitleText = subtitleText
    self.toolsSummaryText = toolsSummaryText
    self.onAction = onAction
  }

  var body: some View {
    content
      .padding(16)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var content: some View {
    VStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(subtitleText)
          .font(.system(size: 12.5, weight: .semibold))
          .foregroundStyle(.secondary)
        Text(toolsSummaryText)
          .font(.system(size: 11.5, weight: .regular))
          .foregroundStyle(.secondary.opacity(0.95))
          .lineLimit(2)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      previewCard

      durationChip

      VStack(spacing: 9) {
        primaryButton(title: "Save as MP4", action: { onAction(.saveMP4) })
          .keyboardShortcut(.return, modifiers: [])

        secondaryButton(title: "Save as GIF", action: { onAction(.saveGIF) })
      }
    }
  }

  @ViewBuilder
  private var previewCard: some View {
    if FileManager.default.fileExists(atPath: inputURL.path) {
      PostRecordingPlayerPreview(url: inputURL)
        .frame(maxWidth: .infinity, minHeight: 170, maxHeight: 182)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
    } else if let thumbnail {
      Image(nsImage: thumbnail)
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(maxWidth: .infinity, minHeight: 170, maxHeight: 182)
        .background(Color.black.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
    } else {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(Color.black.opacity(0.82))
        .frame(maxWidth: .infinity, minHeight: 170, maxHeight: 182)
        .overlay(
          Image(systemName: "film")
            .font(.system(size: 34, weight: .semibold))
            .foregroundStyle(.white.opacity(0.7))
        )
        .overlay(
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
    }
  }

  private var durationChip: some View {
    HStack(spacing: 6) {
      Image(systemName: "clock.fill")
        .font(.system(size: 11, weight: .semibold))
      Text(formattedDuration)
        .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
    }
    .foregroundStyle(.white.opacity(0.88))
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(
      Capsule(style: .continuous)
        .fill(Color.white.opacity(0.12))
        .overlay(
          Capsule(style: .continuous)
            .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    )
  }

  @ViewBuilder
  private func primaryButton(title: String, action: @escaping () -> Void) -> some View {
    if #available(macOS 26.0, *) {
      Button(action: action) {
        Text(title)
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.glassProminent)
      .controlSize(.large)
    } else {
      Button(action: action) {
        Text(title)
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
    }
  }

  @ViewBuilder
  private func secondaryButton(title: String, action: @escaping () -> Void) -> some View {
    if #available(macOS 26.0, *) {
      Button(action: action) {
        Text(title)
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.glass)
      .controlSize(.large)
    } else {
      Button(action: action) {
        Text(title)
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.bordered)
      .controlSize(.large)
    }
  }
}

private struct PostRecordingPlayerPreview: NSViewRepresentable {
  let url: URL

  final class Coordinator {
    var player: AVPlayer?
  }

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeNSView(context: Context) -> AVPlayerView {
    let view = AVPlayerView()
    view.controlsStyle = .floating
    view.videoGravity = .resizeAspect
    view.showsFullScreenToggleButton = false

    let player = AVPlayer(url: url)
    player.actionAtItemEnd = .pause
    view.player = player
    context.coordinator.player = player
    return view
  }

  func updateNSView(_ nsView: AVPlayerView, context: Context) {
    guard let currentURL = (nsView.player?.currentItem?.asset as? AVURLAsset)?.url else {
      let player = AVPlayer(url: url)
      player.actionAtItemEnd = .pause
      nsView.player = player
      context.coordinator.player = player
      return
    }

    guard currentURL != url else {
      return
    }

    nsView.player?.pause()
    let player = AVPlayer(url: url)
    player.actionAtItemEnd = .pause
    nsView.player = player
    context.coordinator.player = player
  }

  static func dismantleNSView(_ nsView: AVPlayerView, coordinator: Coordinator) {
    nsView.player?.pause()
    nsView.player = nil
    coordinator.player = nil
  }
}
