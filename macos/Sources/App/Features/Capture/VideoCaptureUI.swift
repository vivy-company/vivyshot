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
  case saveVideo(PostRecordingExportOptions)
  case saveGIF
  case discard
}

struct PostRecordingExportOptions: Equatable {
  var codec: PostRecordingExportCodec
  var frameRate: PostRecordingExportFrameRate
  var quality: PostRecordingExportQuality
  var scale: PostRecordingExportScale
  var bitrate: PostRecordingExportBitratePreset

  @MainActor
  static func defaultOptions(settings: AppSettings) -> PostRecordingExportOptions {
    PostRecordingExportOptions(
      codec: settings.videoExportCodec,
      frameRate: settings.videoExportFrameRate,
      quality: settings.videoExportQuality,
      scale: settings.videoExportScale,
      bitrate: settings.videoExportBitrate
    )
  }

  @MainActor
  func normalizedForCurrentAccess(storeManager: StoreManager) -> PostRecordingExportOptions {
    guard !storeManager.hasPaidAccess else {
      return self
    }
    return PostRecordingExportOptions(
      codec: .h264,
      frameRate: .fps30,
      quality: .standard,
      scale: .full,
      bitrate: .standard
    )
  }
}

enum PostRecordingExportCodec: String, CaseIterable, Identifiable {
  case h264
  case hevc

  var id: String { rawValue }

  var title: String {
    switch self {
    case .h264:
      return "H.264"
    case .hevc:
      return "HEVC"
    }
  }
}

enum PostRecordingExportFrameRate: Int, CaseIterable, Identifiable {
  case fps30 = 30
  case fps60 = 60
  case fps120 = 120

  var id: Int { rawValue }

  var title: String {
    "\(rawValue) fps"
  }
}

enum PostRecordingExportQuality: String, CaseIterable, Identifiable {
  case standard
  case high

  var id: String { rawValue }

  var title: String {
    switch self {
    case .standard:
      return String(localized: "Standard", bundle: AppLocalizer.shared.bundle)
    case .high:
      return String(localized: "High", bundle: AppLocalizer.shared.bundle)
    }
  }
}

enum PostRecordingExportScale: String, CaseIterable, Identifiable {
  case full
  case percent75
  case percent50

  var id: String { rawValue }

  var title: String {
    switch self {
    case .full:
      return "100%"
    case .percent75:
      return "75%"
    case .percent50:
      return "50%"
    }
  }

  var factor: CGFloat {
    switch self {
    case .full:
      return 1.0
    case .percent75:
      return 0.75
    case .percent50:
      return 0.5
    }
  }
}

enum PostRecordingExportBitratePreset: String, CaseIterable, Identifiable {
  case standard
  case high
  case veryHigh

  var id: String { rawValue }

  var title: String {
    switch self {
    case .standard:
      return String(localized: "Standard", bundle: AppLocalizer.shared.bundle)
    case .high:
      return String(localized: "High", bundle: AppLocalizer.shared.bundle)
    case .veryHigh:
      return String(localized: "Very High", bundle: AppLocalizer.shared.bundle)
    }
  }
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
  private let storeManager = StoreManager.shared
  private var didPickAction = false
  private var exportSheetController: PostRecordingExportSheetController?

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
    panel.title = String(localized: "Review Recording", bundle: AppLocalizer.shared.bundle)
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
    alert.messageText = String(localized: "Discard this recording?", bundle: AppLocalizer.shared.bundle)
    alert.informativeText = String(localized: "Closing this window without saving will discard the temporary recording.", bundle: AppLocalizer.shared.bundle)
    alert.alertStyle = .warning
    alert.addButton(withTitle: String(localized: "Discard Recording", bundle: AppLocalizer.shared.bundle))
    alert.addButton(withTitle: String(localized: "Keep Reviewing", bundle: AppLocalizer.shared.bundle))

    let response = alert.runModal()
    guard response == .alertFirstButtonReturn else {
      return false
    }

    performAction(.discard)
    return true
  }

  func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    [
      .flexibleSpace,
      .exportVideoRecording,
      .saveVideoRecording
    ]
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
    case .exportVideoRecording:
      return toolbarButtonItem(
        identifier: itemIdentifier,
        label: String(localized: "Export", bundle: AppLocalizer.shared.bundle),
        symbolName: "slider.horizontal.3",
        tintColor: .labelColor,
        prominent: false,
        action: #selector(exportVideoRecording)
      )
    case .saveVideoRecording:
      return toolbarButtonItem(
        identifier: itemIdentifier,
        label: String(localized: "Save", bundle: AppLocalizer.shared.bundle),
        symbolName: "square.and.arrow.down",
        tintColor: .white,
        prominent: true,
        action: #selector(saveVideoRecording)
      )
    default:
      return nil
    }
  }

  private func toolbarButtonItem(
    identifier: NSToolbarItem.Identifier,
    label: String,
    symbolName: String,
    tintColor: NSColor = .labelColor,
    prominent: Bool = false,
    action: Selector
  ) -> NSToolbarItem {
    let item = NSToolbarItem(itemIdentifier: identifier)
    item.label = label
    item.paletteLabel = label
    item.toolTip = label
    let button = NSButton(title: label, target: self, action: action)
    button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label)
    button.imagePosition = .imageLeading
    button.bezelStyle = .rounded
    button.controlSize = .regular
    button.contentTintColor = tintColor
    button.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
    button.imageScaling = .scaleProportionallyDown
    if prominent {
      button.bezelColor = .controlAccentColor
    }
    button.setButtonType(.momentaryPushIn)
    button.sizeToFit()
    let fittedSize = button.frame.size
    button.frame.size = CGSize(width: fittedSize.width + 18, height: max(36, fittedSize.height))
    item.view = button
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
  private func exportVideoRecording() {
    guard let window else {
      return
    }

    let controller = PostRecordingExportSheetController(
      initialOptions: defaultExportOptions(),
      storeManager: storeManager
    ) { [weak self] options in
      self?.performAction(.saveVideo(options))
    }
    exportSheetController = controller
    controller.presentSheet(for: window)
  }

  @objc
  private func saveVideoRecording() {
    performAction(.saveVideo(defaultExportOptions()))
  }

  private func defaultExportOptions() -> PostRecordingExportOptions {
    PostRecordingExportOptions
      .defaultOptions(settings: .shared)
      .normalizedForCurrentAccess(storeManager: storeManager)
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

@MainActor
private final class PostRecordingExportSheetController: NSWindowController {
  private let onSave: (PostRecordingExportOptions) -> Void

  init(
    initialOptions: PostRecordingExportOptions,
    storeManager: StoreManager,
    onSave: @escaping (PostRecordingExportOptions) -> Void
  ) {
    self.onSave = onSave

    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 420, height: 340),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.title = String(localized: "Export Video", bundle: AppLocalizer.shared.bundle)
    window.isReleasedWhenClosed = false

    super.init(window: window)

    let rootView = PostRecordingExportSheetView(
      initialOptions: initialOptions,
      storeManager: storeManager,
      onCancel: { [weak self] in
        self?.dismiss()
      },
      onSave: { [weak self] options in
        self?.dismiss()
        self?.onSave(options)
      }
    )
    window.contentView = NSHostingView(rootView: rootView.environment(\.locale, AppLocalizer.shared.locale))
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  func presentSheet(for parent: NSWindow) {
    guard let window else {
      return
    }
    parent.beginSheet(window)
  }

  private func dismiss() {
    guard let window, let parent = window.sheetParent else {
      return
    }
    parent.endSheet(window)
  }
}

private struct PostRecordingExportSheetView: View {
  @ObservedObject private var storeManager: StoreManager
  @State private var options: PostRecordingExportOptions
  let onCancel: () -> Void
  let onSave: (PostRecordingExportOptions) -> Void

  init(
    initialOptions: PostRecordingExportOptions,
    storeManager: StoreManager,
    onCancel: @escaping () -> Void,
    onSave: @escaping (PostRecordingExportOptions) -> Void
  ) {
    _storeManager = ObservedObject(wrappedValue: storeManager)
    _options = State(initialValue: initialOptions.normalizedForCurrentAccess(storeManager: storeManager))
    self.onCancel = onCancel
    self.onSave = onSave
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          Text("Export Video")
            .font(.title3.weight(.semibold))
          Text("Choose how this recording should be exported.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }

        Spacer()

        Button {
          onCancel()
        } label: {
          Image(systemName: "xmark")
            .font(.system(size: 11, weight: .semibold))
            .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
      }

      Form {
        Picker("Codec", selection: $options.codec) {
          ForEach(PostRecordingExportCodec.allCases) { codec in
            Text(menuTitle(for: codec)).tag(codec).disabled(isLocked(codec))
          }
        }

        Picker("Frame Rate", selection: $options.frameRate) {
          ForEach(PostRecordingExportFrameRate.allCases) { frameRate in
            Text(menuTitle(for: frameRate)).tag(frameRate).disabled(isLocked(frameRate))
          }
        }

        Picker("Quality", selection: $options.quality) {
          ForEach(PostRecordingExportQuality.allCases) { quality in
            Text(menuTitle(for: quality)).tag(quality).disabled(isLocked(quality))
          }
        }

        Picker("Scale", selection: $options.scale) {
          ForEach(PostRecordingExportScale.allCases) { scale in
            Text(menuTitle(for: scale)).tag(scale).disabled(isLocked(scale))
          }
        }

        Picker("Bitrate", selection: $options.bitrate) {
          ForEach(PostRecordingExportBitratePreset.allCases) { bitrate in
            Text(menuTitle(for: bitrate)).tag(bitrate).disabled(isLocked(bitrate))
          }
        }
      }
      .formStyle(.grouped)
      .fixedSize(horizontal: false, vertical: true)

      HStack {
        Spacer()
        Button(LocalizedStringKey("Cancel")) {
          onCancel()
        }
        Button(LocalizedStringKey("Export")) {
          onSave(options.normalizedForCurrentAccess(storeManager: storeManager))
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(.horizontal, 18)
    .padding(.top, 16)
    .padding(.bottom, 14)
    .frame(width: 420)
  }

  private func isLocked(_ codec: PostRecordingExportCodec) -> Bool {
    codec == .hevc && !storeManager.hasPaidAccess
  }

  private func isLocked(_ frameRate: PostRecordingExportFrameRate) -> Bool {
    frameRate != .fps30 && !storeManager.hasPaidAccess
  }

  private func isLocked(_ quality: PostRecordingExportQuality) -> Bool {
    quality != .standard && !storeManager.hasPaidAccess
  }

  private func isLocked(_ scale: PostRecordingExportScale) -> Bool {
    scale != .full && !storeManager.hasPaidAccess
  }

  private func isLocked(_ bitrate: PostRecordingExportBitratePreset) -> Bool {
    bitrate != .standard && !storeManager.hasPaidAccess
  }

  private func menuTitle(for codec: PostRecordingExportCodec) -> String {
    isLocked(codec) ? String(format: String(localized: "%@ (Paid)", bundle: AppLocalizer.shared.bundle), codec.title) : codec.title
  }

  private func menuTitle(for frameRate: PostRecordingExportFrameRate) -> String {
    isLocked(frameRate) ? String(format: String(localized: "%@ (Paid)", bundle: AppLocalizer.shared.bundle), frameRate.title) : frameRate.title
  }

  private func menuTitle(for quality: PostRecordingExportQuality) -> String {
    isLocked(quality) ? String(format: String(localized: "%@ (Paid)", bundle: AppLocalizer.shared.bundle), quality.title) : quality.title
  }

  private func menuTitle(for scale: PostRecordingExportScale) -> String {
    isLocked(scale) ? String(format: String(localized: "%@ (Paid)", bundle: AppLocalizer.shared.bundle), scale.title) : scale.title
  }

  private func menuTitle(for bitrate: PostRecordingExportBitratePreset) -> String {
    isLocked(bitrate) ? String(format: String(localized: "%@ (Paid)", bundle: AppLocalizer.shared.bundle), bitrate.title) : bitrate.title
  }
}

private extension NSToolbarItem.Identifier {
  static let exportVideoRecording = NSToolbarItem.Identifier("com.vivyshot.post-recording.export-video")
  static let saveVideoRecording = NSToolbarItem.Identifier("com.vivyshot.post-recording.save-video")
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
