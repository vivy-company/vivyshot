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
  case saveVideo(PostRecordingExportOptions, consumesFreeProExportTrial: Bool)
  case saveGIF(consumesFreeProExportTrial: Bool)
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
}

enum PostRecordingExportTarget {
  case video
  case gif
}

struct ProExportRequirement: Equatable {
  let reasons: [ProExportReason]

  var requiresPro: Bool {
    !reasons.isEmpty
  }

  var featureListText: String {
    reasons.map(\.title).joined(separator: ", ")
  }

  static func evaluate(
    project: PostRecordingProject,
    options: PostRecordingExportOptions?,
    target: PostRecordingExportTarget
  ) -> ProExportRequirement {
    ProExportRequirement(
      reasons: project.rustProject.proRequirement(target: target, options: options) ?? []
    )
  }
}

enum ProExportReason: String, CaseIterable, Identifiable {
  case webcamOverlay
  case keystrokeOverlay
  case microphoneAudio
  case gifExport
  case hevcExport
  case sixtyFPS
  case highQuality
  case highBitrate
  case bakedTransition

  var id: String { rawValue }

  var title: String {
    switch self {
    case .webcamOverlay:
      return String(localized: "Webcam overlay", bundle: AppLocalizer.shared.bundle)
    case .keystrokeOverlay:
      return String(localized: "Keystroke overlay", bundle: AppLocalizer.shared.bundle)
    case .microphoneAudio:
      return String(localized: "Microphone audio", bundle: AppLocalizer.shared.bundle)
    case .gifExport:
      return String(localized: "GIF export", bundle: AppLocalizer.shared.bundle)
    case .hevcExport:
      return String(localized: "HEVC export", bundle: AppLocalizer.shared.bundle)
    case .sixtyFPS:
      return String(localized: "60 fps export", bundle: AppLocalizer.shared.bundle)
    case .highQuality:
      return String(localized: "High quality export", bundle: AppLocalizer.shared.bundle)
    case .highBitrate:
      return String(localized: "High bitrate export", bundle: AppLocalizer.shared.bundle)
    case .bakedTransition:
      return String(localized: "Capture transitions", bundle: AppLocalizer.shared.bundle)
    }
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
  private let project: PostRecordingProject
  private let onAction: (PostRecordingAction) -> Void
  private let storeManager = StoreManager.shared
  private var didPickAction = false
  private var exportSheetController: PostRecordingExportSheetController?

  init(
    inputURL: URL,
    project: PostRecordingProject,
    details: PostRecordingDetails,
    durationSeconds: Double,
    thumbnail: NSImage?,
    videoSize: CGSize?,
    onAction: @escaping (PostRecordingAction) -> Void
  ) {
    self.inputURL = inputURL
    self.project = project
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
      project: project,
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
    guard let approvedAction = approvedActionAfterExportGate(action) else {
      return
    }

    didPickAction = true
    window?.close()
    let actionHandler = onAction
    DispatchQueue.main.async {
      actionHandler(approvedAction)
    }
  }

  private func approvedActionAfterExportGate(_ action: PostRecordingAction) -> PostRecordingAction? {
    switch action {
    case .saveVideo(let options, _):
      guard let consumesTrial = proExportGateDecision(target: .video, options: options) else {
        return nil
      }
      return .saveVideo(options, consumesFreeProExportTrial: consumesTrial)
    case .saveGIF(_):
      guard let consumesTrial = proExportGateDecision(target: .gif, options: nil) else {
        return nil
      }
      return .saveGIF(consumesFreeProExportTrial: consumesTrial)
    case .discard:
      return action
    }
  }

  private func proExportGateDecision(
    target: PostRecordingExportTarget,
    options: PostRecordingExportOptions?
  ) -> Bool? {
    let requirement = ProExportRequirement.evaluate(
      project: project,
      options: options,
      target: target
    )
    guard requirement.requiresPro, !storeManager.hasPaidAccess else {
      return false
    }

    if AppSettings.shared.isProExportTrialAvailable {
      return confirmFreeProExport(requirement: requirement)
    }

    showConsumedTrialPaywallPrompt(requirement: requirement)
    return nil
  }

  private func confirmFreeProExport(requirement: ProExportRequirement) -> Bool? {
    let alert = NSAlert()
    alert.messageText = String(localized: "Use your free Pro export?", bundle: AppLocalizer.shared.bundle)
    alert.informativeText = String(
      format: String(localized: "This recording uses Pro features: %@. Your first Pro export is free.", bundle: AppLocalizer.shared.bundle),
      requirement.featureListText
    )
    alert.alertStyle = .informational
    alert.addButton(withTitle: String(localized: "Use Free Pro Export", bundle: AppLocalizer.shared.bundle))
    alert.addButton(withTitle: String(localized: "Upgrade", bundle: AppLocalizer.shared.bundle))
    alert.addButton(withTitle: String(localized: "Cancel", bundle: AppLocalizer.shared.bundle))

    switch alert.runModal() {
    case .alertFirstButtonReturn:
      return true
    case .alertSecondButtonReturn:
      presentPaywallWindow()
      return nil
    default:
      return nil
    }
  }

  private func showConsumedTrialPaywallPrompt(requirement: ProExportRequirement) {
    let alert = NSAlert()
    alert.messageText = String(localized: "Upgrade for unlimited Pro exports", bundle: AppLocalizer.shared.bundle)
    alert.informativeText = String(
      format: String(localized: "This export uses Pro features: %@. Upgrade to export unlimited Pro recordings.", bundle: AppLocalizer.shared.bundle),
      requirement.featureListText
    )
    alert.alertStyle = .informational
    alert.addButton(withTitle: String(localized: "Upgrade", bundle: AppLocalizer.shared.bundle))
    alert.addButton(withTitle: String(localized: "Cancel", bundle: AppLocalizer.shared.bundle))

    if alert.runModal() == .alertFirstButtonReturn {
      presentPaywallWindow()
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
      self?.performAction(.saveVideo(options, consumesFreeProExportTrial: false))
    } onSaveGIF: { [weak self] in
      self?.performAction(.saveGIF(consumesFreeProExportTrial: false))
    }
    exportSheetController = controller
    controller.presentSheet(for: window)
  }

  @objc
  private func saveVideoRecording() {
    performAction(.saveVideo(defaultExportOptions(), consumesFreeProExportTrial: false))
  }

  private func defaultExportOptions() -> PostRecordingExportOptions {
    PostRecordingExportOptions.defaultOptions(settings: .shared)
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
  let project: PostRecordingProject
  let thumbnail: NSImage?
  @StateObject private var playbackState = PostRecordingPreviewPlaybackState()

  init(
    project: PostRecordingProject,
    thumbnail: NSImage?
  ) {
    self.project = project
    self.thumbnail = thumbnail
  }

  var body: some View {
    ZStack {
      Color.black

      if FileManager.default.fileExists(atPath: project.inputURL.path) {
        VStack(spacing: 0) {
          ZStack {
            PostRecordingPlayerPreview(url: project.inputURL, playbackState: playbackState)
              .frame(maxWidth: .infinity, maxHeight: .infinity)

            PostRecordingOverlayPreviewLayer(project: project, playbackState: playbackState)
              .frame(maxWidth: .infinity, maxHeight: .infinity)
              .allowsHitTesting(false)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)

          PostRecordingPlaybackControls(playbackState: playbackState)
        }
        .onAppear {
          playbackState.durationSeconds = project.durationSeconds
        }
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

private final class PostRecordingPreviewPlaybackState: ObservableObject {
  @Published var currentSeconds: Double = 0
  @Published var durationSeconds: Double = 0
  @Published var isPlaying = false

  weak var player: AVPlayer?

  func attach(player: AVPlayer) {
    self.player = player
  }

  func detach(player: AVPlayer?) {
    guard self.player === player else {
      return
    }
    self.player = nil
    isPlaying = false
  }

  func togglePlayback() {
    guard let player else {
      return
    }
    if isPlaying {
      player.pause()
      isPlaying = false
      return
    }
    if durationSeconds > 0, currentSeconds >= durationSeconds - 0.05 {
      seek(to: 0)
    }
    player.play()
    isPlaying = true
  }

  func seek(to seconds: Double) {
    let clamped = max(0, min(durationSeconds > 0 ? durationSeconds : seconds, seconds))
    currentSeconds = clamped
    player?.seek(
      to: CMTime(seconds: clamped, preferredTimescale: 600),
      toleranceBefore: .zero,
      toleranceAfter: .zero
    )
  }

  func skip(by deltaSeconds: Double) {
    seek(to: currentSeconds + deltaSeconds)
  }
}

private struct PostRecordingPlaybackControls: View {
  @ObservedObject var playbackState: PostRecordingPreviewPlaybackState
  @State private var isScrubbing = false
  @State private var scrubSeconds = 0.0

  private var duration: Double {
    max(0.1, playbackState.durationSeconds)
  }

  private var displayedSeconds: Double {
    isScrubbing ? scrubSeconds : playbackState.currentSeconds
  }

  var body: some View {
    HStack(spacing: 12) {
      Button {
        playbackState.skip(by: -5)
      } label: {
        Image(systemName: "gobackward.5")
      }
      .help("Back 5 seconds")

      Button {
        playbackState.togglePlayback()
      } label: {
        Image(systemName: playbackState.isPlaying ? "pause.fill" : "play.fill")
          .font(.system(size: 16, weight: .semibold))
          .frame(width: 28, height: 28)
      }
      .help(playbackState.isPlaying ? "Pause" : "Play")

      Button {
        playbackState.skip(by: 5)
      } label: {
        Image(systemName: "goforward.5")
      }
      .help("Forward 5 seconds")

      Text(Self.formatTime(displayedSeconds))
        .font(.system(size: 12, weight: .medium, design: .monospaced))
        .foregroundStyle(.white.opacity(0.78))
        .frame(width: 46, alignment: .trailing)

      Slider(
        value: Binding(
          get: {
            min(duration, max(0, displayedSeconds))
          },
          set: { value in
            scrubSeconds = value
            if !isScrubbing {
              playbackState.seek(to: value)
            }
          }
        ),
        in: 0...duration,
        onEditingChanged: { editing in
          isScrubbing = editing
          if editing {
            scrubSeconds = playbackState.currentSeconds
          } else {
            playbackState.seek(to: scrubSeconds)
          }
        }
      )
      .disabled(playbackState.durationSeconds <= 0)

      Text(Self.formatTime(playbackState.durationSeconds))
        .font(.system(size: 12, weight: .medium, design: .monospaced))
        .foregroundStyle(.white.opacity(0.55))
        .frame(width: 46, alignment: .leading)
    }
    .buttonStyle(.plain)
    .foregroundStyle(.white.opacity(0.86))
    .padding(.horizontal, 16)
    .frame(height: 48)
    .background(Color.black)
  }

  private static func formatTime(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds > 0 else {
      return "00:00"
    }
    let total = Int(seconds.rounded(.down))
    return String(format: "%02d:%02d", total / 60, total % 60)
  }
}

private struct PostRecordingOverlayPreviewLayer: View {
  let project: PostRecordingProject
  @ObservedObject var playbackState: PostRecordingPreviewPlaybackState

  var body: some View {
    GeometryReader { proxy in
      let videoRect = aspectFitVideoRect(in: proxy.size)
      let renderPlan = project.rustProject.renderPlan(
        timeSeconds: playbackState.currentSeconds,
        renderSize: videoRect.size,
        target: .preview
      )

      ZStack(alignment: .topLeading) {
        ForEach(Array((renderPlan?.items ?? []).enumerated()), id: \.offset) { _, item in
          let itemRect = viewRect(for: item.rect, videoRect: videoRect)
          switch item.kind {
          case .webcam:
            if let webcamURL = project.webcamURL {
              webcamOverlay(url: webcamURL, rect: itemRect, shape: webcamShape(for: item))
            }
          case .keystroke:
            PostRecordingKeystrokeOverlayPreview(
              text: item.text.isEmpty ? "⌘K" : item.text,
              style: keystrokeStyle(for: item),
              size: keystrokeSize(for: item)
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
  private func webcamOverlay(url: URL, rect: CGRect, shape: VideoWebcamOverlayShapeOption) -> some View {
    let preview = PostRecordingWebcamOverlayPreview(
      url: url,
      seconds: playbackState.currentSeconds,
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

  private func webcamShape(for item: RustVideoRenderItem) -> VideoWebcamOverlayShapeOption {
    VideoWebcamOverlayShapeOption(rawValue: Int(item.webcamShapeCode))
      ?? .roundedRect
  }

  private func keystrokeStyle(for item: RustVideoRenderItem) -> VideoKeystrokeOverlayStyleOption {
    VideoKeystrokeOverlayStyleOption(rawValue: Int(item.keystrokeStyleCode))
      ?? .compact
  }

  private func keystrokeSize(for item: RustVideoRenderItem) -> VideoKeystrokeOverlaySizeOption {
    VideoKeystrokeOverlaySizeOption(rawValue: Int(item.keystrokeSizeCode))
      ?? .medium
  }
}

private struct PostRecordingKeystrokeOverlayPreview: View {
  let text: String
  let style: VideoKeystrokeOverlayStyleOption
  let size: VideoKeystrokeOverlaySizeOption

  var body: some View {
    KeystrokeOverlayGlassCapsule(
      text: text,
      style: style,
      size: size,
      showsResizeGrip: false
    )
  }
}

private struct PostRecordingWebcamOverlayPreview: NSViewRepresentable {
  let url: URL
  let seconds: Double
  let isPlaying: Bool

  final class Coordinator: @unchecked Sendable {
    var player: AVPlayer?
    var url: URL?
  }

  final class PlayerLayerView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
      super.init(frame: frameRect)
      wantsLayer = true
      playerLayer.videoGravity = .resizeAspectFill
      layer?.addSublayer(playerLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      nil
    }

    override func layout() {
      super.layout()
      playerLayer.frame = bounds
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeNSView(context: Context) -> PlayerLayerView {
    let view = PlayerLayerView()
    configurePlayerIfNeeded(in: view, coordinator: context.coordinator)
    return view
  }

  func updateNSView(_ nsView: PlayerLayerView, context: Context) {
    configurePlayerIfNeeded(in: nsView, coordinator: context.coordinator)
    guard let player = context.coordinator.player else {
      return
    }

    let current = CMTimeGetSeconds(player.currentTime())
    if current.isFinite, abs(current - seconds) > (isPlaying ? 0.35 : 0.05) {
      player.seek(
        to: CMTime(seconds: max(0, seconds), preferredTimescale: 600),
        toleranceBefore: .zero,
        toleranceAfter: .zero
      )
    }

    if isPlaying {
      if player.rate == 0 {
        player.play()
      }
    } else {
      player.pause()
    }
  }

  static func dismantleNSView(_ nsView: PlayerLayerView, coordinator: Coordinator) {
    coordinator.player?.pause()
    nsView.playerLayer.player = nil
    coordinator.player = nil
    coordinator.url = nil
  }

  private func configurePlayerIfNeeded(in view: PlayerLayerView, coordinator: Coordinator) {
    guard coordinator.url != url else {
      return
    }

    let player = AVPlayer(url: url)
    player.isMuted = true
    player.actionAtItemEnd = .pause
    view.playerLayer.player = player
    coordinator.player = player
    coordinator.url = url
  }
}

@MainActor
private final class PostRecordingExportSheetController: NSWindowController {
  private let onSave: (PostRecordingExportOptions) -> Void
  private let onSaveGIF: () -> Void

  init(
    initialOptions: PostRecordingExportOptions,
    storeManager: StoreManager,
    onSave: @escaping (PostRecordingExportOptions) -> Void,
    onSaveGIF: @escaping () -> Void
  ) {
    self.onSave = onSave
    self.onSaveGIF = onSaveGIF

    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 420, height: 380),
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
      },
      onSaveGIF: { [weak self] in
        guard let self else {
          return
        }
        self.dismiss()
        self.onSaveGIF()
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
  let onSaveGIF: () -> Void

  init(
    initialOptions: PostRecordingExportOptions,
    storeManager: StoreManager,
    onCancel: @escaping () -> Void,
    onSave: @escaping (PostRecordingExportOptions) -> Void,
    onSaveGIF: @escaping () -> Void
  ) {
    _storeManager = ObservedObject(wrappedValue: storeManager)
    _options = State(initialValue: initialOptions)
    self.onCancel = onCancel
    self.onSave = onSave
    self.onSaveGIF = onSaveGIF
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
            Text(menuTitle(for: codec)).tag(codec)
          }
        }

        Picker("Frame Rate", selection: $options.frameRate) {
          ForEach(PostRecordingExportFrameRate.allCases) { frameRate in
            Text(menuTitle(for: frameRate)).tag(frameRate)
          }
        }

        Picker("Quality", selection: $options.quality) {
          ForEach(PostRecordingExportQuality.allCases) { quality in
            Text(menuTitle(for: quality)).tag(quality)
          }
        }

        Picker("Scale", selection: $options.scale) {
          ForEach(PostRecordingExportScale.allCases) { scale in
            Text(menuTitle(for: scale)).tag(scale)
          }
        }

        Picker("Bitrate", selection: $options.bitrate) {
          ForEach(PostRecordingExportBitratePreset.allCases) { bitrate in
            Text(menuTitle(for: bitrate)).tag(bitrate)
          }
        }
      }
      .formStyle(.grouped)
      .fixedSize(horizontal: false, vertical: true)

      HStack {
        Button(gifButtonTitle) {
          onSaveGIF()
        }

        Spacer()
        Button(LocalizedStringKey("Cancel")) {
          onCancel()
        }
        Button(LocalizedStringKey("Export")) {
          onSave(options)
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(.horizontal, 18)
    .padding(.top, 16)
    .padding(.bottom, 14)
    .frame(width: 420)
  }

  private var gifButtonTitle: LocalizedStringKey {
    storeManager.hasPaidAccess ? "Export GIF" : "Export GIF (Pro)"
  }

  private func menuTitle(for codec: PostRecordingExportCodec) -> String {
    codec == .hevc ? proMenuTitle(codec.title) : codec.title
  }

  private func menuTitle(for frameRate: PostRecordingExportFrameRate) -> String {
    frameRate != .fps30 ? proMenuTitle(frameRate.title) : frameRate.title
  }

  private func menuTitle(for quality: PostRecordingExportQuality) -> String {
    quality != .standard ? proMenuTitle(quality.title) : quality.title
  }

  private func menuTitle(for scale: PostRecordingExportScale) -> String {
    scale.title
  }

  private func menuTitle(for bitrate: PostRecordingExportBitratePreset) -> String {
    bitrate != .standard ? proMenuTitle(bitrate.title) : bitrate.title
  }

  private func proMenuTitle(_ title: String) -> String {
    guard !storeManager.hasPaidAccess else {
      return title
    }
    return String(format: String(localized: "%@ (Pro)", bundle: AppLocalizer.shared.bundle), title)
  }
}

private extension NSToolbarItem.Identifier {
  static let exportVideoRecording = NSToolbarItem.Identifier("com.vivyshot.post-recording.export-video")
  static let saveVideoRecording = NSToolbarItem.Identifier("com.vivyshot.post-recording.save-video")
}

private struct PostRecordingPlayerPreview: NSViewRepresentable {
  let url: URL
  @ObservedObject var playbackState: PostRecordingPreviewPlaybackState

  final class Coordinator: @unchecked Sendable {
    var player: AVPlayer?
    var timeObserver: Any?
    weak var playbackState: PostRecordingPreviewPlaybackState?

    func installTimeObserver(on player: AVPlayer) {
      removeTimeObserver()
      timeObserver = player.addPeriodicTimeObserver(
        forInterval: CMTime(seconds: 0.05, preferredTimescale: 600),
        queue: .main
      ) { [weak self, weak player] time in
        guard let self, let playbackState = self.playbackState else {
          return
        }
        let seconds = CMTimeGetSeconds(time)
        playbackState.currentSeconds = seconds.isFinite ? max(0, seconds) : 0
        playbackState.isPlaying = (player?.rate ?? 0) != 0
      }
    }

    func removeTimeObserver() {
      if let timeObserver, let player {
        player.removeTimeObserver(timeObserver)
      }
      timeObserver = nil
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeNSView(context: Context) -> AVPlayerView {
    let view = AVPlayerView()
    view.controlsStyle = .none
    view.videoGravity = .resizeAspect
    view.showsFullScreenToggleButton = false
    context.coordinator.playbackState = playbackState

    let player = AVPlayer(url: url)
    player.actionAtItemEnd = .pause
    view.player = player
    context.coordinator.player = player
    playbackState.attach(player: player)
    context.coordinator.installTimeObserver(on: player)
    return view
  }

  func updateNSView(_ nsView: AVPlayerView, context: Context) {
    context.coordinator.playbackState = playbackState
    guard let currentURL = (nsView.player?.currentItem?.asset as? AVURLAsset)?.url else {
      let player = AVPlayer(url: url)
      player.actionAtItemEnd = .pause
      nsView.player = player
      context.coordinator.player = player
      playbackState.attach(player: player)
      context.coordinator.installTimeObserver(on: player)
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
    playbackState.attach(player: player)
    context.coordinator.installTimeObserver(on: player)
  }

  static func dismantleNSView(_ nsView: AVPlayerView, coordinator: Coordinator) {
    nsView.player?.pause()
    coordinator.playbackState?.detach(player: coordinator.player)
    coordinator.removeTimeObserver()
    nsView.player = nil
    coordinator.player = nil
  }
}
