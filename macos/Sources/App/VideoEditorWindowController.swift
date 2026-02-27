import AppKit
import AVFoundation
import AVKit
import CoreGraphics
import CoreMedia
import ImageIO
import QuartzCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class VideoEditorWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
  private enum TrimHandle {
    case start
    case end
    case unknown
  }

  private let inputURL: URL
  private let overlay: VideoExportOverlayConfiguration
  private let rustSession: RustVideoSession?
  private let onDone: () -> Void

  private let player: AVPlayer
  private let playerView = AVPlayerView()
  private var timelineToolbarHost: NSHostingView<TimelineEditorView>?
  private var previewOverlayHost: NSHostingView<TimelinePreviewOverlay>?
  private let startSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
  private let endSlider = NSSlider(value: 1, minValue: 0, maxValue: 1, target: nil, action: nil)
  private let statusLabel = NSTextField(labelWithString: "")
  private var thumbnailImages: [NSImage] = []
  private var textOverlays: [VideoTextOverlayClip] = []
  private var selectedTextOverlayID: UUID?
  private let asset: AVAsset
  private let hasSourceAudioTrack: Bool
  private var durationSeconds: Double = 0
  private var currentPlayheadSeconds: Double = 0
  private var includeAudioTrack = true
  private var includeWebcamTrack = false
  private var isExportInFlight = false
  private var playerTimeObserver: Any?
  private var timelineState: TimelineState?
  private var thumbnailTask: Task<Void, Never>?
  private var isScrubbingTimeline = false
  private var lastEditedTrimHandle: TrimHandle = .unknown

  init(
    inputURL: URL,
    overlay: VideoExportOverlayConfiguration,
    rustSession: RustVideoSession?,
    onDone: @escaping () -> Void
  ) {
    self.inputURL = inputURL
    self.overlay = overlay
    self.rustSession = rustSession
    self.onDone = onDone
    player = AVPlayer(url: inputURL)
    asset = AVAsset(url: inputURL)
    hasSourceAudioTrack = !asset.tracks(withMediaType: .audio).isEmpty
    includeAudioTrack = hasSourceAudioTrack
    includeWebcamTrack = overlay.webcamURL != nil

    let window = NSWindow(
      contentRect: CGRect(x: 140, y: 120, width: 860, height: 640),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = inputURL.lastPathComponent
    window.subtitle = "Preparing video details…"
    window.toolbarStyle = .unified
    window.titleVisibility = .visible
    window.titlebarAppearsTransparent = false
    window.titlebarSeparatorStyle = .automatic
    window.isReleasedWhenClosed = false

    super.init(window: window)
    window.delegate = self
    configureNSToolbar()
    configureUI()
    loadAsset()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  func present() {
    showWindow(nil)
    window?.center()
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func windowWillClose(_ notification: Notification) {
    if let observer = playerTimeObserver {
      player.removeTimeObserver(observer)
      playerTimeObserver = nil
    }
    thumbnailTask?.cancel()
    thumbnailTask = nil
    onDone()
  }

  private func configureUI() {
    guard let content = window?.contentView else {
      return
    }

    playerView.translatesAutoresizingMaskIntoConstraints = false
    playerView.controlsStyle = .none
    playerView.showsFullScreenToggleButton = false
    playerView.videoGravity = .resizeAspect
    playerView.player = player
    player.pause()
    installPlayerObserver()

    startSlider.target = self
    startSlider.action = #selector(trimSliderChanged)
    endSlider.target = self
    endSlider.action = #selector(trimSliderChanged)

    statusLabel.font = .systemFont(ofSize: 11, weight: .medium)
    statusLabel.textColor = .secondaryLabelColor
    statusLabel.translatesAutoresizingMaskIntoConstraints = false
    statusLabel.lineBreakMode = .byTruncatingTail

    content.addSubview(playerView)
    content.addSubview(statusLabel)

    NSLayoutConstraint.activate([
      playerView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
      playerView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
      playerView.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
      playerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 320),

      statusLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
      statusLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
      statusLabel.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -12),
    ])
  }

  // MARK: - NSToolbar

  private static let toolbarID = NSToolbar.Identifier("VideoTrimToolbar")
  private static let playItemID = NSToolbarItem.Identifier("play")
  private static let timecodeItemID = NSToolbarItem.Identifier("timecode")

  private var playToolbarButton: NSButton?
  private var timecodeLabel: NSTextField?

  private func configureNSToolbar() {
    let toolbar = NSToolbar(identifier: Self.toolbarID)
    toolbar.delegate = self
    toolbar.displayMode = .iconOnly
    toolbar.allowsUserCustomization = false
    window?.toolbar = toolbar
  }

  func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    [
      .flexibleSpace,
      Self.playItemID,
      Self.timecodeItemID,
      .flexibleSpace,
    ]
  }

  func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    toolbarDefaultItemIdentifiers(toolbar)
  }

  func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
    switch itemIdentifier {
    case Self.playItemID:
      let item = NSToolbarItem(itemIdentifier: itemIdentifier)
      let button = NSButton(image: NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Play")!, target: self, action: #selector(playPauseToolbar))
      button.bezelStyle = .texturedRounded
      button.isBordered = true
      button.setContentHuggingPriority(.defaultHigh, for: .horizontal)
      playToolbarButton = button
      item.view = button
      item.label = "Play"
      return item

    case Self.timecodeItemID:
      let item = NSToolbarItem(itemIdentifier: itemIdentifier)
      let label = NSTextField(labelWithString: "00:00:00 / 00:00:00")
      label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
      label.textColor = .secondaryLabelColor
      label.alignment = .center
      label.setContentHuggingPriority(.defaultLow, for: .horizontal)
      timecodeLabel = label
      item.view = label
      item.label = "Time"
      return item

    default:
      return nil
    }
  }

  @objc private func playPauseToolbar() { playPausePressed() }

  func updateToolbarPlayState() {
    let symbolName = (timelineState?.isPlaying ?? false) ? "pause.fill" : "play.fill"
    playToolbarButton?.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
  }

  func updateToolbarTimecode() {
    guard let state = timelineState else { return }
    let current = TimelineEditorView.formatTimeCompact(ms: state.playheadMS)
    let total = TimelineEditorView.formatTimeCompact(ms: state.durationMS)
    timecodeLabel?.stringValue = "\(current) / \(total)"
  }

  private func installTimelineToolbar() {
    guard let content = window?.contentView, let state = timelineState else {
      return
    }

    let toolbarView = makeTimelineToolbarView(state: state)
    let host = NSHostingView(rootView: toolbarView)
    host.translatesAutoresizingMaskIntoConstraints = false
    timelineToolbarHost = host
    content.addSubview(host)

    NSLayoutConstraint.activate([
      host.leadingAnchor.constraint(equalTo: content.leadingAnchor),
      host.trailingAnchor.constraint(equalTo: content.trailingAnchor),
      host.topAnchor.constraint(equalTo: playerView.bottomAnchor, constant: 12),
      host.heightAnchor.constraint(greaterThanOrEqualToConstant: 176),
      statusLabel.topAnchor.constraint(equalTo: host.bottomAnchor, constant: 10),
    ])

    // Preview overlay for text/shape clips on top of the player
    let overlayView = TimelinePreviewOverlay(state: state)
    let overlayHost = NSHostingView(rootView: overlayView)
    overlayHost.translatesAutoresizingMaskIntoConstraints = false
    overlayHost.layer?.backgroundColor = .clear
    previewOverlayHost = overlayHost
    playerView.addSubview(overlayHost)

    NSLayoutConstraint.activate([
      overlayHost.leadingAnchor.constraint(equalTo: playerView.leadingAnchor),
      overlayHost.trailingAnchor.constraint(equalTo: playerView.trailingAnchor),
      overlayHost.topAnchor.constraint(equalTo: playerView.topAnchor),
      overlayHost.bottomAnchor.constraint(equalTo: playerView.bottomAnchor),
    ])
  }

  private func loadAsset() {
    durationSeconds = max(0, CMTimeGetSeconds(asset.duration))
    if !durationSeconds.isFinite || durationSeconds <= 0 {
      durationSeconds = 1
    }

    startSlider.minValue = 0
    startSlider.maxValue = durationSeconds
    endSlider.minValue = 0
    endSlider.maxValue = durationSeconds
    startSlider.doubleValue = 0
    endSlider.doubleValue = durationSeconds
    currentPlayheadSeconds = 0

    // Determine video size for timeline session
    let videoTrack = asset.tracks(withMediaType: .video).first
    let transformedSize = videoTrack.map { track -> CGSize in
      let s = track.naturalSize.applying(track.preferredTransform)
      return CGSize(width: abs(s.width), height: abs(s.height))
    } ?? CGSize(width: 1920, height: 1080)

    let durationMS = UInt32(durationSeconds * 1000)
    if let session = RustCoreBridge.shared.makeTimelineSession(
      durationMS: durationMS,
      width: UInt32(transformedSize.width),
      height: UInt32(transformedSize.height)
    ) {
      // Add default video track with full-duration clip
      _ = session.addTrack(kind: .video)
      _ = session.addClip(trackIndex: 0, startMS: 0, endMS: durationMS, kind: .video)

      // Add audio track if available
      if hasSourceAudioTrack {
        _ = session.addTrack(kind: .audio)
        _ = session.addClip(trackIndex: 1, startMS: 0, endMS: durationMS, kind: .audio)
      }

      // Add webcam track if available
      if overlay.webcamURL != nil {
        let trackIdx = session.getTracks().count
        _ = session.addTrack(kind: .webcam)
        _ = session.addClip(trackIndex: trackIdx, startMS: 0, endMS: durationMS, kind: .webcam)
      }

      // Import existing text overlays
      for textClip in overlay.textOverlays {
        let trackIdx: Int
        let tracks = session.getTracks()
        if let existingIdx = tracks.firstIndex(where: { $0.kind == .text }) {
          trackIdx = existingIdx
        } else {
          _ = session.addTrack(kind: .text)
          trackIdx = session.getTracks().count - 1
        }
        if let clipID = session.addClip(trackIndex: trackIdx, startMS: UInt32(textClip.startSeconds * 1000), endMS: UInt32(textClip.endSeconds * 1000), kind: .text) {
          _ = session.setClipText(trackIndex: trackIdx, clipID: clipID, text: textClip.text)
        }
      }

      let state = TimelineState(session: session, durationMS: durationMS)
      self.timelineState = state
      installTimelineToolbar()
    }

    generateTimelineThumbnails()
    updateWindowSubtitle()
    updateTrimLabels()
  }

  private func installPlayerObserver() {
    if let observer = playerTimeObserver {
      player.removeTimeObserver(observer)
      playerTimeObserver = nil
    }

    let interval = CMTime(value: 1, timescale: 30)
    playerTimeObserver = player.addPeriodicTimeObserver(
      forInterval: interval,
      queue: .main
    ) { [weak self] time in
      guard let self, !self.isScrubbingTimeline else {
        return
      }
      let seconds = max(0, time.seconds)
      let ms = UInt32(seconds * 1000)

      // Check trim end from timeline state (video track clip end) or slider
      let trimEndMS: UInt32
      if let state = self.timelineState {
        let videoClips = state.session.getClips(trackIndex: 0)
        trimEndMS = videoClips.first?.endMS ?? UInt32(self.durationSeconds * 1000)
      } else {
        trimEndMS = UInt32(self.endSlider.doubleValue * 1000)
      }
      let trimEnd = Double(trimEndMS) / 1000.0

      if player.timeControlStatus == .playing, seconds >= trimEnd {
        player.pause()
        player.seek(to: CMTime(seconds: trimEnd, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        self.timelineState?.isPlaying = false
      }
      self.currentPlayheadSeconds = min(self.durationSeconds, seconds)
      self.timelineState?.playheadMS = ms
      self.updateToolbarTimecode()
      self.updateToolbarPlayState()
      self.refreshTimelineToolbar()
    }
  }

  private func generateTimelineThumbnails() {
    thumbnailTask?.cancel()
    thumbnailTask = nil
    thumbnailImages = []
    refreshTimelineToolbar()

    let duration = durationSeconds
    let sourceURL = inputURL
    let targetCount = 12
    thumbnailTask = Task.detached(priority: .userInitiated) {
      let generator = AVAssetImageGenerator(asset: AVAsset(url: sourceURL))
      generator.appliesPreferredTrackTransform = true
      generator.maximumSize = CGSize(width: 220, height: 140)
      generator.requestedTimeToleranceAfter = CMTime(seconds: 0.04, preferredTimescale: 600)
      generator.requestedTimeToleranceBefore = CMTime(seconds: 0.04, preferredTimescale: 600)

      var images: [NSImage] = []
      for index in 0 ..< targetCount {
        if Task.isCancelled {
          return
        }
        let progress = targetCount > 1 ? Double(index) / Double(targetCount - 1) : 0
        let seconds = duration * progress
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
          images.append(NSImage(cgImage: cgImage, size: .zero))
        }
      }

      await MainActor.run {
        self.thumbnailImages = images
        self.refreshTimelineToolbar()
      }
    }
  }

  @objc
  private func trimSliderChanged() {
    let minGap = min(0.1, max(0.01, durationSeconds / 1000))
    startSlider.doubleValue = max(0, min(startSlider.doubleValue, durationSeconds))
    endSlider.doubleValue = max(0, min(endSlider.doubleValue, durationSeconds))

    if startSlider.doubleValue >= endSlider.doubleValue - minGap {
      let activeHandle: TrimHandle
      if startSlider.currentEditor() != nil {
        activeHandle = .start
      } else if endSlider.currentEditor() != nil {
        activeHandle = .end
      } else {
        activeHandle = lastEditedTrimHandle
      }

      switch activeHandle {
      case .start:
        endSlider.doubleValue = min(durationSeconds, startSlider.doubleValue + minGap)
      case .end:
        startSlider.doubleValue = max(0, endSlider.doubleValue - minGap)
      case .unknown:
        startSlider.doubleValue = max(0, endSlider.doubleValue - minGap)
      }
    }

    currentPlayheadSeconds = max(startSlider.doubleValue, min(currentPlayheadSeconds, endSlider.doubleValue))
    let seekTime = CMTime(seconds: currentPlayheadSeconds, preferredTimescale: 600)
    player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero)
    updateTrimLabels()
  }

  @objc
  private func playPausePressed() {
    if player.timeControlStatus == .playing {
      player.pause()
      timelineState?.isPlaying = false
    } else {
      // Determine trim boundaries from timeline state if available
      let trimStart: Double
      let trimEnd: Double
      if let state = timelineState {
        let videoClips = state.session.getClips(trackIndex: 0)
        trimStart = Double(videoClips.first?.startMS ?? 0) / 1000.0
        trimEnd = Double(videoClips.first?.endMS ?? state.durationMS) / 1000.0
      } else {
        trimStart = startSlider.doubleValue
        trimEnd = endSlider.doubleValue
      }
      if currentPlayheadSeconds < trimStart || currentPlayheadSeconds >= trimEnd {
        currentPlayheadSeconds = trimStart
        let time = CMTime(seconds: currentPlayheadSeconds, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
      }
      player.play()
      timelineState?.isPlaying = true
    }
    updateToolbarPlayState()
    refreshTimelineToolbar()
  }

  @objc
  private func setInPressed() {
    setTrimStartToPlayhead()
  }

  @objc
  private func setOutPressed() {
    setTrimEndToPlayhead()
  }

  @objc
  private func resetTrimPressed() {
    resetTrimRange()
  }

  @objc
  private func exportMP4Pressed() {
    Task { [weak self] in
      guard let self else {
        return
      }
      await exportMP4()
    }
  }

  @objc
  private func exportGIFPressed() {
    Task { [weak self] in
      guard let self else {
        return
      }
      await exportGIF()
    }
  }

  @objc
  private func donePressed() {
    close()
  }

  private func updateTrimLabels() {
    refreshTimelineToolbar()
  }

  private func updateWindowSubtitle() {
    guard let track = asset.tracks(withMediaType: .video).first else {
      window?.subtitle = String(format: "%.2fs", durationSeconds)
      return
    }

    let transformedSize = track.naturalSize.applying(track.preferredTransform)
    let width = max(1, Int(abs(transformedSize.width).rounded()))
    let height = max(1, Int(abs(transformedSize.height).rounded()))
    let fps = max(1, Int(round(Double(track.nominalFrameRate))))
    window?.subtitle = "\(width)×\(height) • \(fps) fps • " + String(format: "%.2fs", durationSeconds)
  }

  private func refreshTimelineToolbar() {
    guard let state = timelineState else { return }
    timelineToolbarHost?.rootView = makeTimelineToolbarView(state: state)
  }

  private func makeTimelineToolbarView(state: TimelineState) -> TimelineEditorView {
    TimelineEditorView(
      state: state,
      thumbnailImages: thumbnailImages,
      onSeek: { [weak self] ms in self?.seekToMS(ms) },
      isBusy: isExportInFlight,
      onPlayPause: { [weak self] in self?.playPausePressed() },
      onSaveMP4: { [weak self] in self?.exportMP4Pressed() },
      onSaveGIF: { [weak self] in self?.exportGIFPressed() },
      onDone: { [weak self] in self?.donePressed() }
    )
  }

  private func seekToMS(_ ms: UInt32) {
    let time = CMTime(value: CMTimeValue(ms), timescale: 1000)
    player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    currentPlayheadSeconds = Double(ms) / 1000.0
    timelineState?.playheadMS = ms
  }

  private func setTrimStartFromToolbar(_ value: Double) {
    lastEditedTrimHandle = .start
    startSlider.doubleValue = max(0, min(value, durationSeconds))
    trimSliderChanged()
  }

  private func setTrimEndFromToolbar(_ value: Double) {
    lastEditedTrimHandle = .end
    endSlider.doubleValue = max(0, min(value, durationSeconds))
    trimSliderChanged()
  }

  private func setTrimStartToPlayhead() {
    lastEditedTrimHandle = .start
    startSlider.doubleValue = max(0, min(durationSeconds, player.currentTime().seconds))
    currentPlayheadSeconds = startSlider.doubleValue
    trimSliderChanged()
  }

  private func setTrimEndToPlayhead() {
    lastEditedTrimHandle = .end
    endSlider.doubleValue = max(0, min(durationSeconds, player.currentTime().seconds))
    currentPlayheadSeconds = endSlider.doubleValue
    trimSliderChanged()
  }

  private func resetTrimRange() {
    lastEditedTrimHandle = .unknown
    startSlider.doubleValue = 0
    endSlider.doubleValue = durationSeconds
    currentPlayheadSeconds = 0
    trimSliderChanged()
  }

  private func addTextOverlayAtPlayhead() {
    let minDuration = min(2.0, max(0.6, durationSeconds * 0.12))
    var start = max(0, min(durationSeconds, currentPlayheadSeconds))
    var end = min(durationSeconds, start + minDuration)
    if end - start < 0.4 {
      start = max(0, durationSeconds - minDuration)
      end = durationSeconds
    }

    let clip = VideoTextOverlayClip(
      id: UUID(),
      text: "Text",
      startSeconds: start,
      endSeconds: end
    )
    textOverlays.append(clip)
    selectedTextOverlayID = clip.id
    refreshTimelineToolbar()
  }

  private func selectTextOverlay(_ id: UUID?) {
    selectedTextOverlayID = id
    refreshTimelineToolbar()
  }

  private func deleteSelectedTextOverlay() {
    guard let selectedTextOverlayID else {
      return
    }
    textOverlays.removeAll { $0.id == selectedTextOverlayID }
    self.selectedTextOverlayID = textOverlays.first?.id
    refreshTimelineToolbar()
  }

  private func updateTextOverlay(
    id: UUID,
    text: String? = nil,
    startSeconds: Double? = nil,
    endSeconds: Double? = nil
  ) {
    guard let index = textOverlays.firstIndex(where: { $0.id == id }) else {
      return
    }

    var clip = textOverlays[index]
    let minClipDuration = 0.2
    if let text {
      clip.text = String(text.prefix(80))
    }
    if let startSeconds {
      clip.startSeconds = max(0, min(startSeconds, durationSeconds))
    }
    if let endSeconds {
      clip.endSeconds = max(0, min(endSeconds, durationSeconds))
    }
    if clip.endSeconds - clip.startSeconds < minClipDuration {
      if startSeconds != nil {
        clip.endSeconds = min(durationSeconds, clip.startSeconds + minClipDuration)
      } else {
        clip.startSeconds = max(0, clip.endSeconds - minClipDuration)
      }
    }

    clip.startSeconds = min(clip.startSeconds, max(0, durationSeconds - minClipDuration))
    clip.endSeconds = max(clip.endSeconds, clip.startSeconds + minClipDuration)
    clip.endSeconds = min(clip.endSeconds, durationSeconds)

    textOverlays[index] = clip
    refreshTimelineToolbar()
  }

  private var currentTimeRange: CMTimeRange {
    // Read from timeline state if available
    if let state = timelineState {
      let videoClips = state.session.getClips(trackIndex: 0)
      let trimStartSeconds = Double(videoClips.first?.startMS ?? 0) / 1000.0
      let trimEndSeconds = Double(videoClips.first?.endMS ?? state.durationMS) / 1000.0
      let startTime = CMTime(seconds: trimStartSeconds, preferredTimescale: 600)
      let dur = CMTime(seconds: max(0.01, trimEndSeconds - trimStartSeconds), preferredTimescale: 600)
      return CMTimeRange(start: startTime, duration: dur)
    }
    let start = max(0, min(durationSeconds, startSlider.doubleValue))
    let end = max(start, min(durationSeconds, endSlider.doubleValue))
    let startTime = CMTime(seconds: start, preferredTimescale: 600)
    let duration = CMTime(seconds: max(0.01, end - start), preferredTimescale: 600)
    return CMTimeRange(start: startTime, duration: duration)
  }

  private func currentRustExportContext() -> RustVideoExportContext {
    let sourceHasWebcam = overlay.webcamURL != nil
    if let state = timelineState {
      let tracks = state.session.getTracks()
      let audioVisible = tracks.first(where: { $0.kind == .audio })?.visible ?? false
      let webcamVisible = tracks.first(where: { $0.kind == .webcam })?.visible ?? false
      let textCount = tracks
        .filter { $0.kind == .text && $0.visible }
        .reduce(0) { $0 + max(0, $1.clipCount) }
      return RustVideoExportContext(
        sourceHasAudio: hasSourceAudioTrack,
        sourceHasWebcamAsset: sourceHasWebcam,
        audioTrackVisible: audioVisible,
        webcamTrackVisible: webcamVisible,
        textOverlayCount: textCount
      )
    }

    return RustVideoExportContext(
      sourceHasAudio: hasSourceAudioTrack,
      sourceHasWebcamAsset: sourceHasWebcam,
      audioTrackVisible: includeAudioTrack,
      webcamTrackVisible: includeWebcamTrack,
      textOverlayCount: textOverlays.count
    )
  }

  private func syncRustExportPlan(using context: RustVideoExportContext) -> RustVideoExportPlan? {
    guard let rustSession else {
      return nil
    }
    _ = rustSession.setExportContext(context)
    return rustSession.exportPlan()
  }

  private func fallbackOverlayEnhancements(using context: RustVideoExportContext) -> Bool {
    (context.sourceHasWebcamAsset && context.webcamTrackVisible) || !overlay.keyEvents.isEmpty || context.textOverlayCount > 0
  }

  private func fallbackNeedsCustomCompositor(using context: RustVideoExportContext) -> Bool {
    let includeAudio = context.sourceHasAudio && context.audioTrackVisible
    return fallbackOverlayEnhancements(using: context) || (context.sourceHasAudio && !includeAudio)
  }

  private func persistTrimIntoRustModel(_ range: CMTimeRange) {
    let startMS = max(0, Int((range.start.seconds * 1000).rounded()))
    let endMS = max(startMS, Int(((range.start.seconds + range.duration.seconds) * 1000).rounded()))
    _ = rustSession?.setTrim(startMS: startMS, endMS: endMS)
  }

  private var exportOverlay: VideoExportOverlayConfiguration {
    // Collect text overlays from timeline state if available
    var exportTextOverlays: [VideoTextOverlayClip] = textOverlays
    var exportIncludeWebcam = includeWebcamTrack

    if let state = timelineState {
      let tracks = state.session.getTracks()
      exportTextOverlays = []
      for (idx, track) in tracks.enumerated() where track.kind == .text && track.visible {
        let clips = state.session.getClips(trackIndex: idx)
        for clip in clips {
          let text = state.session.getClipText(trackIndex: idx, clipID: clip.id) ?? ""
          exportTextOverlays.append(VideoTextOverlayClip(
            id: UUID(),
            text: text,
            startSeconds: Double(clip.startMS) / 1000.0,
            endSeconds: Double(clip.endMS) / 1000.0
          ))
        }
      }
      exportIncludeWebcam = tracks.first(where: { $0.kind == .webcam })?.visible ?? false
    }

    return VideoExportOverlayConfiguration(
      webcamURL: exportIncludeWebcam ? overlay.webcamURL : nil,
      keyEvents: overlay.keyEvents,
      webcamOverlayShape: overlay.webcamOverlayShape,
      webcamOverlaySize: overlay.webcamOverlaySize,
      textOverlays: exportTextOverlays
    )
  }

  private func exportSummarySuffix() -> String {
    let context = currentRustExportContext()
    guard let plan = syncRustExportPlan(using: context) else {
      return ""
    }
    return " (\(plan.keyEventCount) keys, \(plan.clickEventCount) clicks)"
  }

  private func exportMP4() async {
    if isExportInFlight {
      return
    }

    let panel = NSSavePanel()
    panel.allowedContentTypes = [UTType.mpeg4Movie]
    panel.nameFieldStringValue = "recording-trimmed.mp4"

    guard panel.runModal() == .OK, let outputURL = panel.url else {
      return
    }

    isExportInFlight = true
    refreshTimelineToolbar()
    defer {
      isExportInFlight = false
      refreshTimelineToolbar()
    }

    statusLabel.stringValue = "Exporting MP4…"
    do {
      if FileManager.default.fileExists(atPath: outputURL.path) {
        try FileManager.default.removeItem(at: outputURL)
      }

      let trimRange = currentTimeRange
      persistTrimIntoRustModel(trimRange)

      let exportContext = currentRustExportContext()
      let exportPlan = syncRustExportPlan(using: exportContext)
      let exportIncludeAudio = exportPlan?.includeAudio ?? (exportContext.sourceHasAudio && exportContext.audioTrackVisible)
      let useCustomCompositor = exportPlan?.needsCustomCompositor ?? fallbackNeedsCustomCompositor(using: exportContext)

      if useCustomCompositor {
        try await VideoCompositor.exportCompositeMP4(
          sourceURL: inputURL,
          trimRange: trimRange,
          overlay: exportOverlay,
          includeAudio: exportIncludeAudio,
          outputURL: outputURL
        )
      } else {
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
          throw NSError(
            domain: "com.vivyshot.video",
            code: -40,
            userInfo: [NSLocalizedDescriptionKey: "Unable to create MP4 export session."]
          )
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.timeRange = trimRange
        exportSession.shouldOptimizeForNetworkUse = true
        try await exportSession.vs_export()
      }

      statusLabel.stringValue = "Saved MP4 to \(outputURL.lastPathComponent)\(exportSummarySuffix())"
    } catch {
      statusLabel.stringValue = "MP4 export failed: \(error.localizedDescription)"
    }
  }

  private func exportGIF() async {
    if isExportInFlight {
      return
    }

    let panel = NSSavePanel()
    panel.allowedContentTypes = [UTType.gif]
    panel.nameFieldStringValue = "recording-trimmed.gif"

    guard panel.runModal() == .OK, let outputURL = panel.url else {
      return
    }

    isExportInFlight = true
    refreshTimelineToolbar()
    defer {
      isExportInFlight = false
      refreshTimelineToolbar()
    }

    statusLabel.stringValue = "Exporting GIF…"
    do {
      if FileManager.default.fileExists(atPath: outputURL.path) {
        try FileManager.default.removeItem(at: outputURL)
      }

      let trimRange = currentTimeRange
      persistTrimIntoRustModel(trimRange)
      let exportContext = currentRustExportContext()
      let exportPlan = syncRustExportPlan(using: exportContext)

      var gifSourceURL = inputURL
      var gifStart = trimRange.start.seconds
      var gifEnd = trimRange.start.seconds + trimRange.duration.seconds

      let hasVisualOverlays: Bool
      if let exportPlan {
        hasVisualOverlays = exportPlan.includeWebcam || exportPlan.textOverlayCount > 0 || exportPlan.keyEventCount > 0
      } else {
        hasVisualOverlays = fallbackOverlayEnhancements(using: exportContext)
      }

      if hasVisualOverlays {
        let gifExportIncludeAudio = exportPlan?.includeAudio ?? (exportContext.sourceHasAudio && exportContext.audioTrackVisible)
        let temporaryURL = makeTemporaryExportURL(extension: "mp4")
        try await VideoCompositor.exportCompositeMP4(
          sourceURL: inputURL,
          trimRange: trimRange,
          overlay: exportOverlay,
          includeAudio: gifExportIncludeAudio,
          outputURL: temporaryURL
        )
        gifSourceURL = temporaryURL
        gifStart = 0
        gifEnd = trimRange.duration.seconds
      }

      try await VideoCompositor.renderGIF(
        sourceURL: gifSourceURL,
        outputURL: outputURL,
        startSeconds: gifStart,
        endSeconds: gifEnd
      )
      statusLabel.stringValue = "Saved GIF to \(outputURL.lastPathComponent)\(exportSummarySuffix())"
    } catch {
      statusLabel.stringValue = "GIF export failed: \(error.localizedDescription)"
    }
  }

  private func makeTemporaryExportURL(`extension`: String) -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("vivyshot-recordings", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("export-\(UUID().uuidString).\(`extension`)")
  }

}

// MARK: - TimelineState

@MainActor
final class TimelineState: ObservableObject {
  let session: RustTimelineSession
  let durationMS: UInt32

  @Published var tracks: [TimelineTrackInfo] = []
  @Published var clipsByTrack: [[TimelineClipInfo]] = []
  @Published var playheadMS: UInt32 = 0
  @Published var selectedClipID: UInt32? = nil
  @Published var selectedTrackIndex: Int? = nil
  @Published var zoomLevel: CGFloat = 0.15
  @Published var scrollOffsetMS: CGFloat = 0
  @Published var activeTool: TimelineTool = .select
  @Published var isPlaying: Bool = false

  init(session: RustTimelineSession, durationMS: UInt32) {
    self.session = session
    self.durationMS = durationMS
    refresh()
  }

  func refresh() {
    tracks = session.getTracks()
    clipsByTrack = tracks.indices.map { session.getClips(trackIndex: $0) }
  }

  func msToX(_ ms: UInt32) -> CGFloat {
    return CGFloat(ms) * zoomLevel
  }

  func xToMS(_ x: CGFloat) -> UInt32 {
    return UInt32(max(0, min(x / zoomLevel, CGFloat(durationMS))))
  }

  var totalWidth: CGFloat {
    return CGFloat(durationMS) * zoomLevel
  }

  func addTrack(kind: TimelineTrackKind) {
    _ = session.addTrack(kind: kind)
    refresh()
  }

  func removeTrack(at index: Int) {
    _ = session.removeTrack(at: index)
    if selectedTrackIndex == index { selectedTrackIndex = nil; selectedClipID = nil }
    refresh()
  }

  func toggleTrackVisibility(at index: Int) {
    guard index < tracks.count else { return }
    _ = session.setTrackVisible(at: index, visible: !tracks[index].visible)
    refresh()
  }

  func addClip(trackIndex: Int, startMS: UInt32, endMS: UInt32, kind: TimelineTrackKind) -> UInt32? {
    let clipID = session.addClip(trackIndex: trackIndex, startMS: startMS, endMS: endMS, kind: kind)
    refresh()
    return clipID
  }

  func removeClip(trackIndex: Int, clipID: UInt32) {
    _ = session.removeClip(trackIndex: trackIndex, clipID: clipID)
    if selectedClipID == clipID { selectedClipID = nil }
    refresh()
  }

  func moveClip(trackIndex: Int, clipID: UInt32, newStartMS: UInt32) {
    _ = session.moveClip(trackIndex: trackIndex, clipID: clipID, newStartMS: newStartMS)
    refresh()
  }

  func resizeClip(trackIndex: Int, clipID: UInt32, newStartMS: UInt32, newEndMS: UInt32) {
    _ = session.resizeClip(trackIndex: trackIndex, clipID: clipID, newStartMS: newStartMS, newEndMS: newEndMS)
    refresh()
  }

  func undo() {
    _ = session.undo()
    refresh()
  }

  func redo() {
    _ = session.redo()
    refresh()
  }

  func visibleClips(atTimeMS: UInt32) -> [TimelineClipInfo] {
    return session.getVisibleClips(atTimeMS: atTimeMS)
  }
}

// MARK: - Timeline Colors & Metrics

private enum TimelineColors {
  static let background = Color(nsColor: .controlBackgroundColor)
  static let trackEven = Color(nsColor: .controlBackgroundColor)
  static let trackOdd = Color(nsColor: .separatorColor).opacity(0.05)
  static let headerBackground = Color(nsColor: .windowBackgroundColor)
  static let playhead = Color.red

  static func clipColor(for kind: TimelineTrackKind) -> Color {
    switch kind {
    case .video: return Color(red: 0x4A / 255.0, green: 0x90 / 255.0, blue: 0xD9 / 255.0)
    case .audio: return Color(red: 0x4C / 255.0, green: 0xAF / 255.0, blue: 0x50 / 255.0)
    case .webcam: return Color(red: 0x9C / 255.0, green: 0x27 / 255.0, blue: 0xB0 / 255.0)
    case .text: return Color(red: 0xFF / 255.0, green: 0x98 / 255.0, blue: 0x00 / 255.0)
    case .shape: return Color(red: 0x79 / 255.0, green: 0x79 / 255.0, blue: 0x79 / 255.0)
    case .cursor: return Color(red: 0x00 / 255.0, green: 0xBC / 255.0, blue: 0xD4 / 255.0)
    case .zoom: return Color(red: 0xFF / 255.0, green: 0xEB / 255.0, blue: 0x3B / 255.0)
    }
  }
}

private enum TimelineMetrics {
  static let trackHeight: CGFloat = 44
  static let headerWidth: CGFloat = 100
  static let rulerHeight: CGFloat = 26
  static let playheadWidth: CGFloat = 2
  static let clipCornerRadius: CGFloat = 5
  static let edgeHandle: CGFloat = 8
}

// MARK: - Timeline Editor Views

@MainActor
private struct TimelineEditorView: View {
  @ObservedObject var state: TimelineState
  var thumbnailImages: [NSImage]
  var onSeek: (UInt32) -> Void
  var isBusy: Bool
  var onPlayPause: () -> Void = {}
  var onSaveMP4: () -> Void = {}
  var onSaveGIF: () -> Void = {}
  var onDone: () -> Void = {}

  var body: some View {
    VStack(spacing: 0) {
      inlineToolbar

      Divider()

      ScrollView([.horizontal, .vertical], showsIndicators: true) {
        ZStack(alignment: .topLeading) {
          VStack(spacing: 0) {
            TimeRulerView(state: state, onSeek: onSeek)
              .frame(height: TimelineMetrics.rulerHeight)

            Divider()

            ForEach(Array(state.tracks.enumerated()), id: \.offset) { index, track in
              TrackLaneView(
                state: state,
                trackIndex: index,
                track: track,
                clips: index < state.clipsByTrack.count ? state.clipsByTrack[index] : [],
                thumbnailImages: track.kind == .video ? thumbnailImages : [],
                onSeek: onSeek
              )
              if index < state.tracks.count - 1 {
                Divider()
              }
            }
          }
          .frame(width: max(state.totalWidth + TimelineMetrics.headerWidth, 600))

          PlayheadLineView(state: state)
            .offset(x: TimelineMetrics.headerWidth, y: TimelineMetrics.rulerHeight + 1)
        }
      }
      .background(TimelineColors.background)
      .gesture(
        MagnifyGesture()
          .onChanged { value in
            let newZoom = state.zoomLevel * value.magnification
            state.zoomLevel = min(1.0, max(0.02, newZoom))
          }
      )

      selectedTextClipEditor
    }
    .frame(minHeight: 200)
  }

  private var inlineToolbar: some View {
    HStack(spacing: 8) {
      // Left: tool buttons
      HStack(spacing: 2) {
        inlineToolButton(symbol: "arrow.uturn.up", isActive: state.activeTool == .select) {
          state.activeTool = .select
        }
        inlineToolButton(symbol: "scissors", isActive: state.activeTool == .cut) {
          state.activeTool = .cut
        }
        inlineToolButton(symbol: "hand.raised", isActive: state.activeTool == .hand) {
          state.activeTool = .hand
        }
      }

      Divider().frame(height: 18)

      HStack(spacing: 2) {
        inlineToolButton(symbol: "arrow.uturn.backward") { state.undo() }
        inlineToolButton(symbol: "arrow.uturn.forward") { state.redo() }
      }

      Divider().frame(height: 18)

      HStack(spacing: 2) {
        inlineToolButton(symbol: "textformat") { state.addTrack(kind: .text) }
        inlineToolButton(symbol: "rectangle") { state.addTrack(kind: .shape) }
      }

      Spacer()

      // Center: play + timecode
      HStack(spacing: 6) {
        Button(action: onPlayPause) {
          Image(systemName: (state.isPlaying) ? "pause.fill" : "play.fill")
            .font(.system(size: 12))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(isBusy)

        Text(Self.formatTimeCompact(ms: state.playheadMS) + " / " + Self.formatTimeCompact(ms: state.durationMS))
          .font(.system(size: 10, weight: .medium, design: .monospaced))
          .foregroundStyle(.secondary)
      }

      Spacer()

      // Right: zoom + done dropdown
      HStack(spacing: 2) {
        inlineToolButton(symbol: "minus.magnifyingglass") {
          state.zoomLevel = max(0.02, state.zoomLevel * 0.8)
        }
        inlineToolButton(symbol: "plus.magnifyingglass") {
          state.zoomLevel = min(1.0, state.zoomLevel * 1.25)
        }
      }

      Divider().frame(height: 18)

      Menu {
        Button("Save MP4", action: onSaveMP4)
        Button("Save GIF", action: onSaveGIF)
        Divider()
        Button("Close", action: onDone)
      } label: {
        Text("Done")
          .font(.system(size: 11, weight: .medium))
      }
      .menuStyle(.borderlessButton)
      .fixedSize()
      .disabled(isBusy)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(.ultraThinMaterial)
  }

  private func inlineToolButton(symbol: String, isActive: Bool = false, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 11))
        .frame(width: 24, height: 24)
    }
    .buttonStyle(.bordered)
    .tint(isActive ? .accentColor : nil)
    .controlSize(.small)
    .disabled(isBusy)
  }

  @ViewBuilder
  private var selectedTextClipEditor: some View {
    if let clipID = state.selectedClipID,
       let trackIdx = state.selectedTrackIndex,
       trackIdx < state.tracks.count,
       state.tracks[trackIdx].kind == .text,
       let clip = state.clipsByTrack[safe: trackIdx]?.first(where: { $0.id == clipID })
    {
      let currentText = state.session.getClipText(trackIndex: trackIdx, clipID: clipID) ?? ""
      Divider()
      VStack(spacing: 4) {
        HStack(spacing: 8) {
          TextField(
            "Text overlay",
            text: Binding(
              get: { currentText },
              set: { newValue in
                _ = state.session.setClipText(trackIndex: trackIdx, clipID: clipID, text: String(newValue.prefix(80)))
                state.refresh()
              }
            )
          )
          .textFieldStyle(.roundedBorder)
          .disabled(isBusy)

          Text(TimelineEditorView.formatTimeCompact(ms: clip.startMS) + " - " + TimelineEditorView.formatTimeCompact(ms: clip.endMS))
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)

          Button {
            state.removeClip(trackIndex: trackIdx, clipID: clipID)
          } label: {
            Image(systemName: "trash")
              .font(.system(size: 11))
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .disabled(isBusy)
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .background(.ultraThinMaterial)
    }
  }

  fileprivate static func formatTimeCompact(ms: UInt32) -> String {
    let totalSeconds = Int(ms) / 1000
    let minutes = totalSeconds / 60
    let seconds = totalSeconds % 60
    let frames = (Int(ms) % 1000) / 33
    return String(format: "%02d:%02d:%02d", minutes, seconds, frames)
  }
}

@MainActor
private struct TimeRulerView: View {
  @ObservedObject var state: TimelineState
  var onSeek: (UInt32) -> Void

  var body: some View {
    GeometryReader { geometry in
      Canvas { context, size in
        let headerWidth = TimelineMetrics.headerWidth
        let tickAreaWidth = size.width - headerWidth
        guard tickAreaWidth > 0 else { return }

        let pixelsPerSecond = state.zoomLevel * 1000
        let tickInterval: UInt32
        if pixelsPerSecond > 200 {
          tickInterval = 100
        } else if pixelsPerSecond > 50 {
          tickInterval = 500
        } else if pixelsPerSecond > 20 {
          tickInterval = 1000
        } else if pixelsPerSecond > 5 {
          tickInterval = 5000
        } else {
          tickInterval = 10000
        }

        var ms: UInt32 = 0
        while ms <= state.durationMS {
          let x = headerWidth + state.msToX(ms)
          guard x < size.width else { break }

          let isMajor = ms % (tickInterval * 5) == 0 || ms == 0
          let tickHeight: CGFloat = isMajor ? 12 : 6

          var path = Path()
          path.move(to: CGPoint(x: x, y: size.height))
          path.addLine(to: CGPoint(x: x, y: size.height - tickHeight))
          context.stroke(path, with: .color(.secondary.opacity(isMajor ? 0.6 : 0.25)), lineWidth: 0.5)

          if isMajor {
            let totalSeconds = Int(ms) / 1000
            let label = String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
            let text = Text(label).font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)
            context.draw(text, at: CGPoint(x: x, y: 6))
          }

          ms += tickInterval
        }

        // Playhead triangle
        let playheadX = headerWidth + state.msToX(state.playheadMS)
        var triangle = Path()
        triangle.move(to: CGPoint(x: playheadX - 5, y: 0))
        triangle.addLine(to: CGPoint(x: playheadX + 5, y: 0))
        triangle.addLine(to: CGPoint(x: playheadX, y: 8))
        triangle.closeSubpath()
        context.fill(triangle, with: .color(TimelineColors.playhead))

        // Playhead line through ruler
        var playheadLine = Path()
        playheadLine.move(to: CGPoint(x: playheadX, y: 8))
        playheadLine.addLine(to: CGPoint(x: playheadX, y: size.height))
        context.stroke(playheadLine, with: .color(TimelineColors.playhead), lineWidth: TimelineMetrics.playheadWidth)
      }
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            let ms = state.xToMS(value.location.x - TimelineMetrics.headerWidth)
            state.playheadMS = ms
            onSeek(ms)
          }
      )
    }
  }
}

@MainActor
private struct TrackLaneView: View {
  @ObservedObject var state: TimelineState
  let trackIndex: Int
  let track: TimelineTrackInfo
  let clips: [TimelineClipInfo]
  let thumbnailImages: [NSImage]
  var onSeek: (UInt32) -> Void

  private var trackLabel: String {
    switch track.kind {
    case .video: return "Video"
    case .webcam: return "Webcam"
    case .audio: return "Audio"
    case .text: return "Text"
    case .shape: return "Shape"
    case .cursor: return "Cursor"
    case .zoom: return "Zoom"
    }
  }

  private var trackIcon: String {
    switch track.kind {
    case .video: return "film"
    case .webcam: return "web.camera"
    case .audio: return "waveform"
    case .text: return "textformat"
    case .shape: return "rectangle"
    case .cursor: return "cursorarrow"
    case .zoom: return "magnifyingglass"
    }
  }

  var body: some View {
    HStack(spacing: 0) {
      // Header
      HStack(spacing: 5) {
        Button(action: { state.toggleTrackVisibility(at: trackIndex) }) {
          Image(systemName: track.visible ? "eye.fill" : "eye.slash")
            .font(.system(size: 10))
            .foregroundColor(track.visible ? .primary : .secondary)
        }
        .buttonStyle(.borderless)
        .frame(width: 18)

        Image(systemName: trackIcon)
          .font(.system(size: 10))
          .foregroundColor(TimelineColors.clipColor(for: track.kind))

        Text(trackLabel)
          .font(.system(size: 10, weight: .semibold))
          .foregroundColor(.primary)
          .lineLimit(1)

        Spacer()
      }
      .frame(width: TimelineMetrics.headerWidth)
      .padding(.horizontal, 6)

      Divider()

      // Clip area
      ZStack(alignment: .leading) {
        Rectangle()
          .fill(trackIndex % 2 == 0 ? TimelineColors.trackEven : TimelineColors.trackOdd)

        if track.kind == .video && !thumbnailImages.isEmpty {
          thumbnailStrip
        }

        if track.kind == .audio {
          audioWaveformVisualization
        }

        ForEach(clips, id: \.id) { clip in
          TimelineClipView(state: state, clip: clip, trackIndex: trackIndex)
        }
      }
      .frame(width: state.totalWidth)
      .clipped()
    }
    .frame(height: TimelineMetrics.trackHeight)
    .background(trackIndex % 2 == 0 ? TimelineColors.trackEven : TimelineColors.trackOdd)
  }

  @ViewBuilder
  private var thumbnailStrip: some View {
    if let firstClip = clips.first {
      let clipWidth = state.msToX(firstClip.endMS) - state.msToX(firstClip.startMS)
      HStack(spacing: 0) {
        ForEach(Array(thumbnailImages.enumerated()), id: \.offset) { _, img in
          Image(nsImage: img)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: clipWidth / CGFloat(max(thumbnailImages.count, 1)), height: TimelineMetrics.trackHeight)
            .clipped()
        }
      }
      .offset(x: state.msToX(firstClip.startMS))
      .opacity(0.25)
    }
  }

  private var audioWaveformVisualization: some View {
    Canvas { context, size in
      let barCount = 50
      let barWidth: CGFloat = max(2, size.width / CGFloat(barCount * 2))
      let spacing: CGFloat = barWidth
      let greenTint = TimelineColors.clipColor(for: .audio)

      for i in 0 ..< barCount {
        let x = CGFloat(i) * (barWidth + spacing)
        guard x < size.width else { break }
        let seed = Double(i * 7 + 13)
        let height = size.height * CGFloat(0.15 + 0.6 * abs(sin(seed * 0.37)))
        let y = (size.height - height) / 2
        let rect = CGRect(x: x, y: y, width: barWidth, height: height)
        context.fill(Path(rect), with: .color(greenTint.opacity(0.3)))
      }
    }
  }
}

@MainActor
private struct TimelineClipView: View {
  @ObservedObject var state: TimelineState
  let clip: TimelineClipInfo
  let trackIndex: Int

  @State private var dragOffset: CGFloat = 0
  @State private var isDragging = false
  @State private var leftEdgeDrag: CGFloat = 0
  @State private var rightEdgeDrag: CGFloat = 0

  private var clipColor: Color {
    TimelineColors.clipColor(for: clip.kind)
  }

  private var isSelected: Bool {
    state.selectedClipID == clip.id && state.selectedTrackIndex == trackIndex
  }

  private var clipWidth: CGFloat {
    state.msToX(clip.endMS) - state.msToX(clip.startMS) + leftEdgeDrag + rightEdgeDrag
  }

  private var clipOffset: CGFloat {
    state.msToX(clip.startMS) + dragOffset - leftEdgeDrag
  }

  private var clipHeight: CGFloat {
    TimelineMetrics.trackHeight - 8
  }

  private var fillGradient: LinearGradient {
    let topOpacity: Double = isSelected ? 0.85 : 0.65
    let bottomOpacity: Double = isSelected ? 0.65 : 0.45
    return LinearGradient(
      colors: [clipColor.opacity(topOpacity), clipColor.opacity(bottomOpacity)],
      startPoint: .top,
      endPoint: .bottom
    )
  }

  var body: some View {
    ZStack(alignment: .leading) {
      RoundedRectangle(cornerRadius: TimelineMetrics.clipCornerRadius)
        .fill(fillGradient)
        .overlay(
          RoundedRectangle(cornerRadius: TimelineMetrics.clipCornerRadius)
            .strokeBorder(isSelected ? Color.white.opacity(0.4) : Color.white.opacity(0.1), lineWidth: 1)
        )

      clipLabel
        .font(.system(size: 9, weight: .semibold))
        .foregroundColor(.white.opacity(0.9))
        .lineLimit(1)
        .padding(.leading, 6)

      if isSelected && state.activeTool == .select {
        HStack {
          edgeHandlePill
          Spacer()
          edgeHandlePill
        }
        .padding(.horizontal, 2)
      }

      if isSelected && state.activeTool == .select {
        HStack {
          Rectangle()
            .fill(Color.white.opacity(0.01))
            .frame(width: TimelineMetrics.edgeHandle)
            .onHover { hovering in
              if hovering {
                NSCursor.resizeLeftRight.push()
              } else {
                NSCursor.pop()
              }
            }
            .gesture(leftEdgeGesture)

          Spacer()

          Rectangle()
            .fill(Color.white.opacity(0.01))
            .frame(width: TimelineMetrics.edgeHandle)
            .onHover { hovering in
              if hovering {
                NSCursor.resizeLeftRight.push()
              } else {
                NSCursor.pop()
              }
            }
            .gesture(rightEdgeGesture)
        }
      }
    }
    .frame(width: max(clipWidth, 4), height: clipHeight)
    .offset(x: clipOffset, y: 0)
    .onTapGesture {
      state.selectedClipID = clip.id
      state.selectedTrackIndex = trackIndex
    }
    .gesture(state.activeTool == .select ? moveGesture : nil)
  }

  private var edgeHandlePill: some View {
    RoundedRectangle(cornerRadius: 1.5)
      .fill(Color.white.opacity(0.6))
      .frame(width: 3, height: 16)
  }

  @ViewBuilder
  private var clipLabel: some View {
    switch clip.kind {
    case .text:
      let text = state.session.getClipText(trackIndex: trackIndex, clipID: clip.id) ?? "Text"
      Text(text)
    case .video:
      Text("Video")
    case .webcam:
      Text("Webcam")
    case .audio:
      Text("Audio")
    case .shape:
      Text("Shape")
    case .cursor:
      Text("Cursor")
    case .zoom:
      Text("Zoom")
    }
  }

  private var moveGesture: some Gesture {
    DragGesture()
      .onChanged { value in
        isDragging = true
        dragOffset = value.translation.width
      }
      .onEnded { value in
        isDragging = false
        let deltaMS = Int32(value.translation.width / state.zoomLevel)
        let newStart = UInt32(max(0, Int64(clip.startMS) + Int64(deltaMS)))
        state.moveClip(trackIndex: trackIndex, clipID: clip.id, newStartMS: newStart)
        dragOffset = 0
      }
  }

  private var leftEdgeGesture: some Gesture {
    DragGesture()
      .onChanged { value in
        leftEdgeDrag = -value.translation.width
      }
      .onEnded { value in
        let deltaMS = Int32(value.translation.width / state.zoomLevel)
        let newStart = UInt32(max(0, Int64(clip.startMS) + Int64(deltaMS)))
        state.resizeClip(trackIndex: trackIndex, clipID: clip.id, newStartMS: min(newStart, clip.endMS - 1), newEndMS: clip.endMS)
        leftEdgeDrag = 0
      }
  }

  private var rightEdgeGesture: some Gesture {
    DragGesture()
      .onChanged { value in
        rightEdgeDrag = value.translation.width
      }
      .onEnded { value in
        let deltaMS = Int32(value.translation.width / state.zoomLevel)
        let newEnd = UInt32(max(Int64(clip.startMS) + 1, Int64(clip.endMS) + Int64(deltaMS)))
        state.resizeClip(trackIndex: trackIndex, clipID: clip.id, newStartMS: clip.startMS, newEndMS: newEnd)
        rightEdgeDrag = 0
      }
  }
}

@MainActor
private struct PlayheadLineView: View {
  @ObservedObject var state: TimelineState

  var body: some View {
    Rectangle()
      .fill(TimelineColors.playhead)
      .frame(width: TimelineMetrics.playheadWidth)
      .shadow(color: TimelineColors.playhead.opacity(0.4), radius: 2, x: 0, y: 0)
      .offset(x: state.msToX(state.playheadMS))
      .allowsHitTesting(false)
  }
}

// MARK: - Timeline Preview Overlay

@MainActor
private struct TimelinePreviewOverlay: View {
  @ObservedObject var state: TimelineState

  var body: some View {
    GeometryReader { geometry in
      let clips = state.visibleClips(atTimeMS: state.playheadMS)
      ForEach(clips, id: \.id) { clip in
        switch clip.kind {
        case .text:
          let text = state.session.getClipText(trackIndex: clip.trackIndex, clipID: clip.id) ?? ""
          Text(text)
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.6))
            .cornerRadius(4)
            .position(
              x: geometry.size.width * CGFloat(clip.transform.x + clip.transform.width / 2),
              y: geometry.size.height * CGFloat(clip.transform.y + clip.transform.height / 2)
            )

        case .shape:
          RoundedRectangle(cornerRadius: 8)
            .fill(Color.blue.opacity(0.3))
            .frame(
              width: geometry.size.width * CGFloat(clip.transform.width),
              height: geometry.size.height * CGFloat(clip.transform.height)
            )
            .position(
              x: geometry.size.width * CGFloat(clip.transform.x + clip.transform.width / 2),
              y: geometry.size.height * CGFloat(clip.transform.y + clip.transform.height / 2)
            )

        default:
          EmptyView()
        }
      }
    }
  }
}

// MARK: - Collection safe subscript

private extension Collection {
  subscript(safe index: Index) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}

enum VideoCompositor {
  private struct WebcamOverlayLayout {
    let transform: CGAffineTransform
    let frame: CGRect
  }

  static func exportCompositeMP4(
    sourceURL: URL,
    trimRange: CMTimeRange,
    overlay: VideoExportOverlayConfiguration,
    includeAudio: Bool = true,
    outputURL: URL
  ) async throws {
    let sourceAsset = AVAsset(url: sourceURL)
    guard let sourceVideoTrack = sourceAsset.tracks(withMediaType: .video).first else {
      throw NSError(
        domain: "com.vivyshot.video",
        code: -80,
        userInfo: [NSLocalizedDescriptionKey: "Source recording has no video track."]
      )
    }

    let composition = AVMutableComposition()
    guard let baseTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
      throw NSError(
        domain: "com.vivyshot.video",
        code: -81,
        userInfo: [NSLocalizedDescriptionKey: "Unable to create composition video track."]
      )
    }
    try baseTrack.insertTimeRange(trimRange, of: sourceVideoTrack, at: .zero)
    baseTrack.preferredTransform = sourceVideoTrack.preferredTransform

    if includeAudio {
      for sourceAudioTrack in sourceAsset.tracks(withMediaType: .audio) {
        guard let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
          continue
        }
        try? audioTrack.insertTimeRange(trimRange, of: sourceAudioTrack, at: .zero)
      }
    }

    let renderSize = normalizedRenderSize(of: sourceVideoTrack)
    let instruction = AVMutableVideoCompositionInstruction()
    instruction.timeRange = CMTimeRange(start: .zero, duration: trimRange.duration)

    let baseLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: baseTrack)
    baseLayerInstruction.setTransform(sourceVideoTrack.preferredTransform, at: .zero)

    var layerInstructions: [AVVideoCompositionLayerInstruction] = [baseLayerInstruction]
    var webcamLayout: WebcamOverlayLayout?

    if let webcamURL = overlay.webcamURL,
       FileManager.default.fileExists(atPath: webcamURL.path)
    {
      let webcamAsset = AVAsset(url: webcamURL)
      if let webcamVideoTrack = webcamAsset.tracks(withMediaType: .video).first,
         let webcamCompositionTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
      {
        let webcamDuration = minCMTime(trimRange.duration, webcamAsset.duration)
        if CMTimeCompare(webcamDuration, .zero) > 0 {
          try webcamCompositionTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: webcamDuration),
            of: webcamVideoTrack,
            at: .zero
          )
          let webcamLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: webcamCompositionTrack)
          let layout = webcamOverlayLayout(
            webcamTrack: webcamVideoTrack,
            renderSize: renderSize,
            sizeOption: overlay.webcamOverlaySize,
            shapeOption: overlay.webcamOverlayShape
          )
          webcamLayerInstruction.setTransform(
            layout.transform,
            at: .zero
          )
          // Keep webcam as the top-most layer in the composition.
          layerInstructions.append(webcamLayerInstruction)
          webcamLayout = layout
        }
      }
    }

    instruction.layerInstructions = layerInstructions

    let videoComposition = AVMutableVideoComposition()
    videoComposition.instructions = [instruction]
    videoComposition.renderSize = renderSize
    videoComposition.frameDuration = frameDuration(for: sourceVideoTrack)
    if !overlay.keyEvents.isEmpty || webcamLayout != nil {
      videoComposition.animationTool = makeAnimationTool(
        renderSize: renderSize,
        keyEvents: overlay.keyEvents,
        textOverlays: overlay.textOverlays,
        trimStartSeconds: trimRange.start.seconds,
        webcamLayout: webcamLayout,
        webcamShape: overlay.webcamOverlayShape
      )
    }

    guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
      throw NSError(
        domain: "com.vivyshot.video",
        code: -82,
        userInfo: [NSLocalizedDescriptionKey: "Unable to create compositor export session."]
      )
    }

    exportSession.outputURL = outputURL
    exportSession.outputFileType = .mp4
    exportSession.shouldOptimizeForNetworkUse = true
    exportSession.videoComposition = videoComposition
    try await exportSession.vs_export()
  }

  private static func normalizedRenderSize(of track: AVAssetTrack) -> CGSize {
    let transformed = track.naturalSize.applying(track.preferredTransform)
    let width = max(2, abs(transformed.width).rounded())
    let height = max(2, abs(transformed.height).rounded())
    return CGSize(width: width, height: height)
  }

  private static func frameDuration(for track: AVAssetTrack) -> CMTime {
    let fps = Int(round(Double(track.nominalFrameRate)))
    if fps > 0 {
      return CMTime(value: 1, timescale: CMTimeScale(fps))
    }
    return CMTime(value: 1, timescale: 30)
  }

  private static func webcamOverlayLayout(
    webcamTrack: AVAssetTrack,
    renderSize: CGSize,
    sizeOption: VideoWebcamOverlaySizeOption,
    shapeOption: VideoWebcamOverlayShapeOption
  ) -> WebcamOverlayLayout {
    let webcamSize = normalizedRenderSize(of: webcamTrack)
    let targetWidth = max(108, min(renderSize.width * sizeOption.widthFraction, 420))
    let scale = targetWidth / max(1, webcamSize.width)
    var targetHeight = webcamSize.height * scale
    if shapeOption == .circle {
      targetHeight = targetWidth
    }
    let margin = max(14, renderSize.width * 0.018)
    let targetX = renderSize.width - targetWidth - margin
    let targetY = margin

    var transform = webcamTrack.preferredTransform
    if shapeOption == .circle {
      let scaleY = targetHeight / max(1, webcamSize.height)
      transform = transform.scaledBy(x: scale, y: scaleY)
      transform = transform.translatedBy(
        x: targetX / max(0.01, scale),
        y: targetY / max(0.01, scaleY)
      )
    } else {
      transform = transform.scaledBy(x: scale, y: scale)
      transform = transform.translatedBy(x: targetX / max(0.01, scale), y: targetY / max(0.01, scale))
    }

    return WebcamOverlayLayout(
      transform: transform,
      frame: CGRect(x: targetX, y: targetY, width: targetWidth, height: targetHeight)
    )
  }

  private static func makeAnimationTool(
    renderSize: CGSize,
    keyEvents: [RecordedKeystrokeEvent],
    textOverlays: [VideoTextOverlayClip],
    trimStartSeconds: Double,
    webcamLayout: WebcamOverlayLayout?,
    webcamShape: VideoWebcamOverlayShapeOption
  ) -> AVVideoCompositionCoreAnimationTool {
    let parentLayer = CALayer()
    parentLayer.frame = CGRect(origin: .zero, size: renderSize)
    parentLayer.masksToBounds = true

    let videoLayer = CALayer()
    videoLayer.frame = parentLayer.frame
    parentLayer.addSublayer(videoLayer)

    if let webcamLayout {
      let webcamFrame = webcamLayout.frame.insetBy(dx: 1.5, dy: 1.5)
      let borderLayer = CAShapeLayer()
      borderLayer.frame = parentLayer.frame
      borderLayer.fillColor = NSColor.clear.cgColor
      borderLayer.strokeColor = NSColor(calibratedWhite: 1.0, alpha: 0.9).cgColor
      borderLayer.lineWidth = max(2, webcamFrame.width * 0.012)
      borderLayer.shadowColor = NSColor.black.cgColor
      borderLayer.shadowOpacity = 0.35
      borderLayer.shadowRadius = 4
      borderLayer.shadowOffset = CGSize(width: 0, height: 1.5)
      if webcamShape == .circle {
        borderLayer.path = CGPath(ellipseIn: webcamFrame, transform: nil)
      } else {
        let radius = max(10, webcamFrame.height * 0.16)
        borderLayer.path = CGPath(
          roundedRect: webcamFrame,
          cornerWidth: radius,
          cornerHeight: radius,
          transform: nil
        )
      }
      parentLayer.addSublayer(borderLayer)
    }

    let tokenHeight = max(34, min(58, renderSize.height * 0.085))
    let maxTokenWidth = renderSize.width * 0.72
    let tokenY = max(18, renderSize.height * 0.07)

    for event in keyEvents {
      let eventSeconds = Double(event.timestampNS) / 1_000_000_000 - trimStartSeconds
      if eventSeconds < 0 {
        continue
      }

      let text = event.displayToken
      if text.isEmpty {
        continue
      }

      let estimatedWidth = min(maxTokenWidth, CGFloat(max(84, text.count * 18)))
      let layer = CATextLayer()
      layer.string = text
      layer.fontSize = max(16, tokenHeight * 0.46)
      layer.alignmentMode = .center
      layer.foregroundColor = NSColor.white.cgColor
      layer.backgroundColor = NSColor(calibratedWhite: 0.06, alpha: 0.82).cgColor
      layer.cornerRadius = tokenHeight * 0.26
      layer.frame = CGRect(
        x: (renderSize.width - estimatedWidth) * 0.5,
        y: tokenY,
        width: estimatedWidth,
        height: tokenHeight
      )
      layer.opacity = 0
      layer.contentsScale = 2
      parentLayer.addSublayer(layer)

      let fade = CAKeyframeAnimation(keyPath: "opacity")
      fade.values = [0, 1, 1, 0]
      fade.keyTimes = [0, 0.1, 0.78, 1]
      fade.duration = 0.95
      fade.beginTime = AVCoreAnimationBeginTimeAtZero + eventSeconds
      fade.fillMode = .forwards
      fade.isRemovedOnCompletion = false
      layer.add(fade, forKey: "fade")
    }

    let textMaxWidth = renderSize.width * 0.78
    let textHeight = max(34, min(62, renderSize.height * 0.09))
    let textY = max(20, renderSize.height * 0.12)
    for clip in textOverlays {
      let start = clip.startSeconds - trimStartSeconds
      let end = clip.endSeconds - trimStartSeconds
      let displayStart = max(0, start)
      let displayEnd = max(displayStart, end)
      guard displayEnd - displayStart >= 0.05 else {
        continue
      }

      let text = clip.text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else {
        continue
      }

      let estimatedWidth = min(textMaxWidth, CGFloat(max(90, text.count * 14)))
      let layer = CATextLayer()
      layer.string = text
      layer.fontSize = max(15, textHeight * 0.42)
      layer.alignmentMode = .center
      layer.foregroundColor = NSColor.white.cgColor
      layer.backgroundColor = NSColor.black.withAlphaComponent(0.58).cgColor
      layer.cornerRadius = textHeight * 0.22
      layer.frame = CGRect(
        x: (renderSize.width - estimatedWidth) * 0.5,
        y: textY,
        width: estimatedWidth,
        height: textHeight
      )
      layer.contentsScale = 2
      layer.opacity = 0
      parentLayer.addSublayer(layer)

      let fade = CAKeyframeAnimation(keyPath: "opacity")
      fade.values = [0, 1, 1, 0]
      fade.keyTimes = [0, 0.08, 0.92, 1]
      fade.duration = max(0.1, displayEnd - displayStart)
      fade.beginTime = AVCoreAnimationBeginTimeAtZero + displayStart
      fade.fillMode = .forwards
      fade.isRemovedOnCompletion = false
      layer.add(fade, forKey: "text-fade-\(clip.id.uuidString)")
    }

    return AVVideoCompositionCoreAnimationTool(
      postProcessingAsVideoLayer: videoLayer,
      in: parentLayer
    )
  }

  private static func minCMTime(_ lhs: CMTime, _ rhs: CMTime) -> CMTime {
    if !lhs.isValid {
      return rhs
    }
    if !rhs.isValid {
      return lhs
    }
    return CMTimeCompare(lhs, rhs) <= 0 ? lhs : rhs
  }

  static func renderGIF(
    sourceURL: URL,
    outputURL: URL,
    startSeconds: Double,
    endSeconds: Double
  ) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let frameRate: Double = 12
          let generator = AVAssetImageGenerator(asset: AVAsset(url: sourceURL))
          generator.appliesPreferredTrackTransform = true
          generator.maximumSize = CGSize(width: 960, height: 960)
          generator.requestedTimeToleranceAfter = .zero
          generator.requestedTimeToleranceBefore = .zero

          let frameCount = max(1, Int(ceil((endSeconds - startSeconds) * frameRate)))
          guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.gif.identifier as CFString,
            frameCount,
            nil
          ) else {
            throw NSError(
              domain: "com.vivyshot.video",
              code: -41,
              userInfo: [NSLocalizedDescriptionKey: "Unable to create GIF destination."]
            )
          }

          let gifProps: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
              kCGImagePropertyGIFLoopCount: 0,
            ],
          ]
          CGImageDestinationSetProperties(destination, gifProps as CFDictionary)

          let frameDelay = 1.0 / frameRate
          for index in 0 ..< frameCount {
            let progress = Double(index) / Double(max(1, frameCount - 1))
            let second = startSeconds + (endSeconds - startSeconds) * progress
            let time = CMTime(seconds: second, preferredTimescale: 600)
            let image = try generator.copyCGImage(at: time, actualTime: nil)
            let frameProps: [CFString: Any] = [
              kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: frameDelay,
              ],
            ]
            CGImageDestinationAddImage(destination, image, frameProps as CFDictionary)
          }

          guard CGImageDestinationFinalize(destination) else {
            throw NSError(
              domain: "com.vivyshot.video",
              code: -42,
              userInfo: [NSLocalizedDescriptionKey: "Failed to finalize GIF export."]
            )
          }
          continuation.resume(returning: ())
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }
}

@MainActor
extension AVAssetExportSession {
  func vs_export() async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      exportAsynchronously {
        switch self.status {
        case .completed:
          continuation.resume(returning: ())
        case .failed:
          continuation.resume(throwing: self.error ?? NSError(
            domain: "com.vivyshot.video",
            code: -43,
            userInfo: [NSLocalizedDescriptionKey: "Video export failed."]
          ))
        case .cancelled:
          continuation.resume(throwing: NSError(
            domain: "com.vivyshot.video",
            code: -44,
            userInfo: [NSLocalizedDescriptionKey: "Video export cancelled."]
          ))
        default:
          continuation.resume(throwing: NSError(
            domain: "com.vivyshot.video",
            code: -45,
            userInfo: [NSLocalizedDescriptionKey: "Video export ended in unexpected state."]
          ))
        }
      }
    }
  }
}
