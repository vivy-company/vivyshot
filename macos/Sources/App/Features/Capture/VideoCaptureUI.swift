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
  case discard
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
final class PostRecordingActionPanel: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
  private let inputURL: URL
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
    self.onAction = onAction

    let panel = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 920, height: 720),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    panel.title = "Review Recording"
    let toolbar = NSToolbar(identifier: "PostRecordingToolbar")
    toolbar.displayMode = .iconOnly
    toolbar.allowsUserCustomization = false
    toolbar.autosavesConfiguration = false
    panel.toolbarStyle = .unified
    panel.titlebarAppearsTransparent = false
    panel.titleVisibility = .visible
    panel.isMovableByWindowBackground = false
    panel.isReleasedWhenClosed = false
    panel.minSize = NSSize(width: 820, height: 620)

    super.init(window: panel)
    panel.delegate = self
    toolbar.delegate = self
    panel.toolbar = toolbar

    let safeDuration = durationSeconds.isFinite ? durationSeconds : 0
    let subtitle = details.subtitleText(
      durationSeconds: safeDuration,
      videoSize: videoSize
    )
    panel.subtitle = subtitle

    let actionView = PostRecordingActionView(
      inputURL: inputURL,
      thumbnail: thumbnail
    )
    panel.contentView = NSHostingView(rootView: actionView)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  func present() {
    window?.center()
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    guard !didPickAction else {
      return true
    }

    let alert = NSAlert()
    alert.messageText = "Discard this recording?"
    alert.informativeText = "Closing this window without saving will discard the temporary recording."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Discard Recording")
    alert.addButton(withTitle: "Keep Reviewing")

    let response = alert.runModal()
    guard response == .alertFirstButtonReturn else {
      return false
    }

    performAction(.discard)
    return true
  }

  func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    [.discardRecording, .flexibleSpace, .saveGIFRecording, .saveMP4Recording]
  }

  func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    toolbarAllowedItemIdentifiers(toolbar)
  }

  func toolbar(
    _ toolbar: NSToolbar,
    itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
    willBeInsertedIntoToolbar flag: Bool
  ) -> NSToolbarItem? {
    switch itemIdentifier {
    case .discardRecording:
      return toolbarButtonItem(
        identifier: itemIdentifier,
        label: "Discard",
        symbolName: "trash",
        action: #selector(discardRecording)
      )
    case .saveGIFRecording:
      return toolbarButtonItem(
        identifier: itemIdentifier,
        label: "Save GIF",
        symbolName: "square.and.arrow.down.on.square",
        action: #selector(saveGIFRecording)
      )
    case .saveMP4Recording:
      return toolbarButtonItem(
        identifier: itemIdentifier,
        label: "Save MP4",
        symbolName: "square.and.arrow.down",
        action: #selector(saveMP4Recording)
      )
    default:
      return nil
    }
  }

  private func toolbarButtonItem(
    identifier: NSToolbarItem.Identifier,
    label: String,
    symbolName: String,
    action: Selector
  ) -> NSToolbarItem {
    let item = NSToolbarItem(itemIdentifier: identifier)
    item.label = label
    item.paletteLabel = label
    item.toolTip = label
    item.target = self
    item.action = action
    item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label)
    item.isBordered = true
    return item
  }

  private func performAction(_ action: PostRecordingAction) {
    guard !didPickAction else {
      return
    }

    didPickAction = true
    window?.close()
    let actionHandler = onAction
    DispatchQueue.main.async {
      actionHandler(action)
    }
  }

  @objc
  private func discardRecording() {
    performAction(.discard)
  }

  @objc
  private func saveGIFRecording() {
    performAction(.saveGIF)
  }

  @objc
  private func saveMP4Recording() {
    performAction(.saveMP4)
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

  init(
    inputURL: URL,
    thumbnail: NSImage?
  ) {
    self.inputURL = inputURL
    self.thumbnail = thumbnail
  }

  var body: some View {
    ZStack {
      Color.black

      if FileManager.default.fileExists(atPath: inputURL.path) {
        PostRecordingPlayerPreview(url: inputURL)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if let thumbnail {
        Image(nsImage: thumbnail)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        Image(systemName: "film")
          .font(.system(size: 34, weight: .semibold))
          .foregroundStyle(.white.opacity(0.7))
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.black)
  }
}

private extension NSToolbarItem.Identifier {
  static let discardRecording = NSToolbarItem.Identifier("com.vivyshot.post-recording.discard")
  static let saveGIFRecording = NSToolbarItem.Identifier("com.vivyshot.post-recording.save-gif")
  static let saveMP4Recording = NSToolbarItem.Identifier("com.vivyshot.post-recording.save-mp4")
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
