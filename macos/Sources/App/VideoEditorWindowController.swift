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
      _ = session.bootstrapCaptureTracks(
        sourceHasAudio: hasSourceAudioTrack,
        sourceHasWebcamAsset: overlay.webcamURL != nil
      )

      for textClip in overlay.textOverlays {
        let startMS = UInt32(max(0, (textClip.startSeconds * 1000).rounded()))
        let endMS = UInt32(max(Double(startMS + 1), (textClip.endSeconds * 1000).rounded()))
        _ = session.addTextClipAutoTrack(startMS: startMS, endMS: endMS, text: textClip.text)
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
    let minGapSeconds = min(0.1, max(0.01, durationSeconds / 1000))
    let minGapMS = UInt32(max(1, (minGapSeconds * 1000).rounded()))
    let durationMS = UInt32(max(1, (durationSeconds * 1000).rounded()))
    let rawStartMS = UInt32(max(0, (startSlider.doubleValue * 1000).rounded()))
    let rawEndMS = UInt32(max(0, (endSlider.doubleValue * 1000).rounded()))

    let activeHandle: RustTrimHandle
    if startSlider.currentEditor() != nil {
      activeHandle = .start
    } else if endSlider.currentEditor() != nil {
      activeHandle = .end
    } else {
      switch lastEditedTrimHandle {
      case .start:
        activeHandle = .start
      case .end:
        activeHandle = .end
      case .unknown:
        activeHandle = .unknown
      }
    }

    if let normalized = RustCoreBridge.shared.normalizeTrimRange(
      durationMS: durationMS,
      startMS: rawStartMS,
      endMS: rawEndMS,
      minGapMS: minGapMS,
      activeHandle: activeHandle
    ) {
      startSlider.doubleValue = Double(normalized.startMS) / 1000.0
      endSlider.doubleValue = Double(normalized.endMS) / 1000.0
    } else {
      startSlider.doubleValue = max(0, min(startSlider.doubleValue, durationSeconds))
      endSlider.doubleValue = max(startSlider.doubleValue + minGapSeconds, min(endSlider.doubleValue, durationSeconds))
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
      if let derived = state.session.deriveExportContext(
        sourceHasAudio: hasSourceAudioTrack,
        sourceHasWebcamAsset: sourceHasWebcam
      ) {
        return derived
      }
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
    let trimRange = currentTimeRange
    let startMS = max(0, Int((trimRange.start.seconds * 1000).rounded()))
    let endMS = max(startMS + 1, Int(((trimRange.start.seconds + trimRange.duration.seconds) * 1000).rounded()))

    if let rustSession {
      _ = rustSession.setExportContext(context)
      return rustSession.exportPlan()
    }

    return RustCoreBridge.shared.computeVideoExportPlan(
      trimStartMS: startMS,
      trimEndMS: endMS,
      keyEventCount: overlay.keyEvents.count,
      clickEventCount: 0,
      context: context
    )
  }

  private func shouldUseCompositeExportPlan(plan: RustVideoExportPlan?) -> Bool {
    guard let plan else { return false }
    return plan.planMode == RustVideoPlanMode.compositeMP4.rawValue || plan.needsCustomCompositor
  }

  private func requiresIntermediateGIF(plan: RustVideoExportPlan?) -> Bool {
    guard let plan else { return false }
    return plan.requiresIntermediateForGIF || plan.planMode == RustVideoPlanMode.compositeMP4.rawValue
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
      exportTextOverlays = []
      for clip in state.session.getTextExportClips() {
        let text = state.session.getClipText(trackIndex: clip.trackIndex, clipID: clip.clipID) ?? ""
        if !text.isEmpty {
          exportTextOverlays.append(VideoTextOverlayClip(
            id: UUID(),
            text: text,
            startSeconds: Double(clip.startMS) / 1000.0,
            endSeconds: Double(clip.endMS) / 1000.0
          ))
        }
      }
      exportIncludeWebcam = state.session.isWebcamTrackVisibleForExport()
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
      let useCustomCompositor = shouldUseCompositeExportPlan(plan: exportPlan)

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

      if requiresIntermediateGIF(plan: exportPlan) {
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
