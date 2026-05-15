import AppKit
import AVFoundation
import AVKit
import CoreMedia
import SwiftUI
import UniformTypeIdentifiers

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
  case saveVideo(
    PostRecordingExportOptions,
    PostRecordingExportState,
    container: PostRecordingVideoSaveContainer?,
    consumesFreeProExportTrial: Bool
  )
  case saveGIF(PostRecordingExportState, consumesFreeProExportTrial: Bool)
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

struct PostRecordingExportState: Equatable {
  var trimStartMS: UInt32
  var trimEndMS: UInt32
  var includesAudio: Bool

  func trimRange(durationSeconds: Double) -> CMTimeRange {
    let durationMS = UInt32(max(1, Int((max(0, durationSeconds) * 1000).rounded())))
    let start = min(trimStartMS, durationMS - 1)
    let end = min(max(trimEndMS, start + 1), durationMS)
    return CMTimeRange(
      start: CMTime(value: CMTimeValue(start), timescale: 1000),
      duration: CMTime(value: CMTimeValue(end - start), timescale: 1000)
    )
  }

  var trimmedDurationSeconds: Double {
    Double(max(1, trimEndMS - trimStartMS)) / 1000.0
  }
}

struct PostRecordingReviewEditState: Equatable {
  var trimStartMS: UInt32
  var trimEndMS: UInt32
  var isTrimModeActive: Bool
  var isOutputAudioEnabled: Bool

  var exportState: PostRecordingExportState {
    PostRecordingExportState(
      trimStartMS: trimStartMS,
      trimEndMS: trimEndMS,
      includesAudio: isOutputAudioEnabled
    )
  }
}

@MainActor
final class PostRecordingReviewState: ObservableObject {
  @Published private(set) var editState: PostRecordingReviewEditState

  let durationMS: UInt32
  let hasAudio: Bool

  private var minGapMS: UInt32 {
    min(500, max(1, durationMS))
  }

  init(durationSeconds: Double, hasAudio: Bool) {
    durationMS = UInt32(max(1, Int((max(0, durationSeconds) * 1000).rounded())))
    self.hasAudio = hasAudio
    editState = PostRecordingReviewEditState(
      trimStartMS: 0,
      trimEndMS: durationMS,
      isTrimModeActive: false,
      isOutputAudioEnabled: hasAudio
    )
  }

  var durationSeconds: Double {
    Double(durationMS) / 1000.0
  }

  func setTrimModeActive(_ isActive: Bool) {
    editState.isTrimModeActive = isActive
  }

  func toggleOutputAudio() {
    guard hasAudio else {
      return
    }
    editState.isOutputAudioEnabled.toggle()
  }

  func resetTrim() {
    editState.trimStartMS = 0
    editState.trimEndMS = durationMS
  }

  func updateTrim(startMS: UInt32, endMS: UInt32, activeHandle: RustTrimHandle) {
    let normalized = RustCoreBridge.shared.normalizeTrimRange(
      durationMS: durationMS,
      startMS: startMS,
      endMS: endMS,
      minGapMS: minGapMS,
      activeHandle: activeHandle
    )

    editState.trimStartMS = normalized?.startMS ?? min(startMS, max(0, durationMS - minGapMS))
    editState.trimEndMS = normalized?.endMS ?? max(endMS, min(durationMS, editState.trimStartMS + minGapMS))
  }

  func exportState() -> PostRecordingExportState {
    editState.exportState
  }
}

enum PostRecordingExportTarget {
  case video
  case gif
}

enum PostRecordingVideoSaveContainer: String, CaseIterable {
  case mp4
  case mov

  var title: String {
    switch self {
    case .mp4:
      return String(localized: "Save as MP4", bundle: AppLocalizer.shared.bundle)
    case .mov:
      return String(localized: "Save as MOV", bundle: AppLocalizer.shared.bundle)
    }
  }

  var contentType: UTType {
    switch self {
    case .mp4:
      return .mpeg4Movie
    case .mov:
      return .quickTimeMovie
    }
  }

  var fileType: AVFileType {
    switch self {
    case .mp4:
      return .mp4
    case .mov:
      return .mov
    }
  }

  var fileExtension: String {
    switch self {
    case .mp4:
      return "mp4"
    case .mov:
      return "mov"
    }
  }
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
    target: PostRecordingExportTarget,
    includesAudio: Bool = true
  ) -> ProExportRequirement {
    var reasons = project.rustProject.proRequirement(target: target, options: options) ?? []
    if !includesAudio {
      reasons.removeAll { $0 == .microphoneAudio }
    }
    return ProExportRequirement(
      reasons: reasons
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

  var hasAudio: Bool {
    systemAudioEnabled || microphoneEnabled
  }

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
  private let reviewState: PostRecordingReviewState
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
    self.reviewState = PostRecordingReviewState(durationSeconds: durationSeconds, hasAudio: details.hasAudio)
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
      reviewState: reviewState,
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
        label: String(localized: "Export...", bundle: AppLocalizer.shared.bundle),
        symbolName: "square.and.arrow.up",
        tintColor: .labelColor,
        prominent: false,
        action: #selector(exportVideoRecording)
      )
    case .saveVideoRecording:
      return saveMenuToolbarItem(identifier: itemIdentifier)
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

  private func saveMenuToolbarItem(identifier: NSToolbarItem.Identifier) -> NSToolbarItem {
    let label = String(localized: "Save", bundle: AppLocalizer.shared.bundle)
    let item = NSToolbarItem(itemIdentifier: identifier)
    item.label = label
    item.paletteLabel = label
    item.toolTip = label

    let button = NSPopUpButton(frame: .zero, pullsDown: true)
    button.bezelStyle = .rounded
    button.controlSize = .regular
    button.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
    button.contentTintColor = .white
    button.bezelColor = .controlAccentColor
    button.target = self
    button.action = #selector(saveRecordingFormatSelected(_:))
    button.addItem(withTitle: label)
    if let titleItem = button.itemArray.first {
      titleItem.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: label)
    }

    button.menu?.addItem(NSMenuItem.separator())
    for container in PostRecordingVideoSaveContainer.allCases {
      let menuItem = NSMenuItem(title: container.title, action: nil, keyEquivalent: "")
      menuItem.representedObject = container.rawValue
      button.menu?.addItem(menuItem)
    }
    let gifItem = NSMenuItem(
      title: String(localized: "Save as GIF", bundle: AppLocalizer.shared.bundle),
      action: nil,
      keyEquivalent: ""
    )
    gifItem.representedObject = "gif"
    button.menu?.addItem(gifItem)
    button.sizeToFit()
    let fittedSize = button.frame.size
    button.frame.size = CGSize(width: fittedSize.width + 24, height: max(36, fittedSize.height))
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
    case .saveVideo(let options, let exportState, container: let container, consumesFreeProExportTrial: _):
      guard let consumesTrial = proExportGateDecision(
        target: .video,
        options: options,
        includesAudio: exportState.includesAudio
      ) else {
        return nil
      }
      return .saveVideo(options, exportState, container: container, consumesFreeProExportTrial: consumesTrial)
    case .saveGIF(let exportState, _):
      guard let consumesTrial = proExportGateDecision(target: .gif, options: nil, includesAudio: false) else {
        return nil
      }
      return .saveGIF(exportState, consumesFreeProExportTrial: consumesTrial)
    case .discard:
      return action
    }
  }

  private func proExportGateDecision(
    target: PostRecordingExportTarget,
    options: PostRecordingExportOptions?,
    includesAudio: Bool
  ) -> Bool? {
    let requirement = ProExportRequirement.evaluate(
      project: project,
      options: options,
      target: target,
      includesAudio: includesAudio
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
      guard let self else { return }
      performAction(.saveVideo(options, reviewState.exportState(), container: nil, consumesFreeProExportTrial: false))
    } onSaveGIF: { [weak self] in
      guard let self else { return }
      performAction(.saveGIF(reviewState.exportState(), consumesFreeProExportTrial: false))
    }
    exportSheetController = controller
    controller.presentSheet(for: window)
  }

  @objc
  private func saveRecordingFormatSelected(_ sender: NSPopUpButton) {
    guard let rawFormat = sender.selectedItem?.representedObject as? String else {
      sender.selectItem(at: 0)
      return
    }
    performSaveRecording(rawFormat: rawFormat)
    sender.selectItem(at: 0)
  }

  private func performSaveRecording(rawFormat: String) {
    if rawFormat == "gif" {
      performAction(.saveGIF(reviewState.exportState(), consumesFreeProExportTrial: false))
      return
    }
    guard let container = PostRecordingVideoSaveContainer(rawValue: rawFormat) else {
      return
    }
    performAction(
      .saveVideo(
        quickSaveVideoOptions(),
        reviewState.exportState(),
        container: container,
        consumesFreeProExportTrial: false
      )
    )
  }

  private func defaultExportOptions() -> PostRecordingExportOptions {
    PostRecordingExportOptions.defaultOptions(settings: .shared)
  }

  private func quickSaveVideoOptions() -> PostRecordingExportOptions {
    let defaults = defaultExportOptions()
    return PostRecordingExportOptions(
      codec: .h264,
      frameRate: defaults.frameRate,
      quality: .standard,
      scale: .full,
      bitrate: .standard
    )
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
  @ObservedObject var reviewState: PostRecordingReviewState
  let thumbnail: NSImage?
  @StateObject private var playbackState = PostRecordingPreviewPlaybackState()

  init(
    project: PostRecordingProject,
    reviewState: PostRecordingReviewState,
    thumbnail: NSImage?
  ) {
    self.project = project
    self.reviewState = reviewState
    self.thumbnail = thumbnail
  }

  var body: some View {
    ZStack {
      Color.black

      if FileManager.default.fileExists(atPath: project.inputURL.path) {
        VStack(spacing: 0) {
          PostRecordingPlayerPreview(
            url: project.inputURL,
            playbackState: playbackState,
            isMuted: !reviewState.editState.isOutputAudioEnabled
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)

          PostRecordingPlaybackControls(
            reviewState: reviewState,
            playbackState: playbackState
          )
        }
        .onAppear {
          playbackState.configure(
            durationSeconds: project.durationSeconds,
            exportState: reviewState.exportState()
          )
        }
        .onChange(of: reviewState.editState) { _, newValue in
          playbackState.configure(
            durationSeconds: project.durationSeconds,
            exportState: newValue.exportState
          )
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
  @Published private(set) var trimStartSeconds: Double = 0
  @Published private(set) var trimEndSeconds: Double = 0

  weak var player: AVPlayer?

  var selectedDurationSeconds: Double {
    max(0, activeTrimEndSeconds - activeTrimStartSeconds)
  }

  private var activeTrimStartSeconds: Double {
    max(0, min(durationSeconds, trimStartSeconds))
  }

  private var activeTrimEndSeconds: Double {
    let fallbackEnd = durationSeconds > 0 ? durationSeconds : trimEndSeconds
    let end = trimEndSeconds > trimStartSeconds ? trimEndSeconds : fallbackEnd
    let upperBound = durationSeconds > 0 ? durationSeconds : end
    return max(activeTrimStartSeconds, min(upperBound, end))
  }

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

  func configure(durationSeconds: Double, exportState: PostRecordingExportState) {
    let safeDuration = max(0, durationSeconds)
    self.durationSeconds = safeDuration
    trimStartSeconds = Double(exportState.trimStartMS) / 1000.0
    trimEndSeconds = Double(exportState.trimEndMS) / 1000.0

    if currentSeconds < activeTrimStartSeconds {
      seek(to: activeTrimStartSeconds)
    } else if currentSeconds > activeTrimEndSeconds {
      seek(to: activeTrimEndSeconds)
    }
  }

  func updateFromPlayer(seconds: Double, isPlaying: Bool) {
    let safeSeconds = seconds.isFinite ? max(0, seconds) : 0
    currentSeconds = safeSeconds
    self.isPlaying = isPlaying

    guard isPlaying, safeSeconds >= activeTrimEndSeconds - 0.015 else {
      return
    }
    player?.pause()
    self.isPlaying = false
    seek(to: activeTrimEndSeconds)
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
    if currentSeconds < activeTrimStartSeconds || currentSeconds >= activeTrimEndSeconds - 0.05 {
      seek(to: activeTrimStartSeconds)
    }
    player.play()
    isPlaying = true
  }

  func seek(to seconds: Double) {
    let upper = activeTrimEndSeconds > activeTrimStartSeconds ? activeTrimEndSeconds : durationSeconds
    let clamped = max(activeTrimStartSeconds, min(upper, seconds))
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
  @ObservedObject var reviewState: PostRecordingReviewState
  @ObservedObject var playbackState: PostRecordingPreviewPlaybackState
  @State private var isScrubbing = false
  @State private var scrubbedTrimmedSeconds = 0.0

  private var isTrimModeActive: Bool {
    reviewState.editState.isTrimModeActive
  }

  private var selectedDurationSeconds: Double {
    max(0, playbackState.selectedDurationSeconds)
  }

  private var trimmedCurrentSeconds: Double {
    let current = playbackState.currentSeconds - playbackState.trimStartSeconds
    return max(0, min(selectedDurationSeconds, current))
  }

  private var displayedTrimmedSeconds: Double {
    isScrubbing ? scrubbedTrimmedSeconds : trimmedCurrentSeconds
  }

  var body: some View {
    VStack(spacing: isTrimModeActive ? 8 : 0) {
      if isTrimModeActive {
        trimSummary
      }

      HStack(spacing: 12) {
        Button {
          playbackState.skip(by: -5)
        } label: {
          Image(systemName: "gobackward.5")
        }
        .help(String(localized: "Back 5 seconds", bundle: AppLocalizer.shared.bundle))

        Button {
          playbackState.togglePlayback()
        } label: {
          Image(systemName: playbackState.isPlaying ? "pause.fill" : "play.fill")
            .font(.system(size: 16, weight: .semibold))
            .frame(width: 28, height: 28)
        }
        .help(playbackState.isPlaying
          ? String(localized: "Pause", bundle: AppLocalizer.shared.bundle)
          : String(localized: "Play", bundle: AppLocalizer.shared.bundle))

        Button {
          playbackState.skip(by: 5)
        } label: {
          Image(systemName: "goforward.5")
        }
        .help(String(localized: "Forward 5 seconds", bundle: AppLocalizer.shared.bundle))

        Text(Self.formatTime(isTrimModeActive ? playbackState.currentSeconds : displayedTrimmedSeconds))
          .font(.system(size: 12, weight: .medium, design: .monospaced))
          .foregroundStyle(.white.opacity(0.78))
          .frame(width: 46, alignment: .trailing)

        if isTrimModeActive {
          PostRecordingTrimTimeline(
            reviewState: reviewState,
            playbackState: playbackState,
            isTrimModeActive: true
          )
          .frame(height: 42)
          .disabled(playbackState.durationSeconds <= 0)
        } else {
          Slider(
            value: Binding(
              get: { displayedTrimmedSeconds },
              set: { value in
                scrubbedTrimmedSeconds = value
                if !isScrubbing {
                  seekWithinTrimmedClip(to: value)
                }
              }
            ),
            in: 0...max(0.1, selectedDurationSeconds),
            onEditingChanged: { editing in
              isScrubbing = editing
              if editing {
                scrubbedTrimmedSeconds = trimmedCurrentSeconds
              } else {
                seekWithinTrimmedClip(to: scrubbedTrimmedSeconds)
              }
            }
          )
          .disabled(playbackState.durationSeconds <= 0 || selectedDurationSeconds <= 0)
        }

        Text(Self.formatTime(isTrimModeActive ? playbackState.selectedDurationSeconds : selectedDurationSeconds))
          .font(.system(size: 12, weight: .medium, design: .monospaced))
          .foregroundStyle(.white.opacity(0.55))
          .frame(width: 46, alignment: .leading)

        Button {
          reviewState.setTrimModeActive(!isTrimModeActive)
        } label: {
          Image(systemName: "scissors")
            .frame(width: 24, height: 24)
            .foregroundStyle(isTrimModeActive ? Color.accentColor : Color.white.opacity(0.86))
        }
        .help(String(localized: "Trim", bundle: AppLocalizer.shared.bundle))

        if reviewState.hasAudio {
          Button {
            reviewState.toggleOutputAudio()
          } label: {
            Image(systemName: reviewState.editState.isOutputAudioEnabled ? "speaker.wave.2" : "speaker.slash")
              .frame(width: 24, height: 24)
          }
          .help(reviewState.editState.isOutputAudioEnabled
            ? String(localized: "Mute final output", bundle: AppLocalizer.shared.bundle)
            : String(localized: "Include sound in final output", bundle: AppLocalizer.shared.bundle))
        }
      }
    }
    .buttonStyle(.plain)
    .foregroundStyle(.white.opacity(0.86))
    .padding(.horizontal, 16)
    .padding(.vertical, isTrimModeActive ? 12 : 0)
    .frame(minHeight: isTrimModeActive ? 88 : 52)
    .background(Color.black)
  }

  private var trimSummary: some View {
    HStack(spacing: 8) {
      Image(systemName: "scissors")
        .foregroundStyle(Color.accentColor)
      Text(trimRangeText)
        .font(.system(size: 12, weight: .medium, design: .monospaced))
        .foregroundStyle(.white.opacity(0.75))
      Spacer()

      Button(String(localized: "Reset Trim", bundle: AppLocalizer.shared.bundle)) {
        reviewState.resetTrim()
        playbackState.configure(durationSeconds: reviewState.durationSeconds, exportState: reviewState.exportState())
        playbackState.seek(to: 0)
      }
      .buttonStyle(.plain)
      .font(.system(size: 12, weight: .semibold))
      .foregroundStyle(Color.accentColor)

      Button(String(localized: "Done", bundle: AppLocalizer.shared.bundle)) {
        reviewState.setTrimModeActive(false)
        playbackState.seek(to: playbackState.trimStartSeconds)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.small)
    }
  }

  private func seekWithinTrimmedClip(to seconds: Double) {
    let clamped = max(0, min(selectedDurationSeconds, seconds))
    playbackState.seek(to: playbackState.trimStartSeconds + clamped)
  }

  private var trimRangeText: String {
    let state = reviewState.exportState()
    return "\(Self.formatTime(Double(state.trimStartMS) / 1000.0)) - \(Self.formatTime(Double(state.trimEndMS) / 1000.0)) · \(Self.formatTime(state.trimmedDurationSeconds))"
  }

  static func formatTime(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds > 0 else {
      return "00:00"
    }
    let total = Int(seconds.rounded(.down))
    return String(format: "%02d:%02d", total / 60, total % 60)
  }
}

private enum PostRecordingTimelineDragTarget {
  case start
  case end
  case playhead
}

private struct PostRecordingTrimTimeline: View {
  @ObservedObject var reviewState: PostRecordingReviewState
  @ObservedObject var playbackState: PostRecordingPreviewPlaybackState
  let isTrimModeActive: Bool

  @State private var dragTarget: PostRecordingTimelineDragTarget?

  var body: some View {
    GeometryReader { proxy in
      let width = max(1, proxy.size.width)
      let height = proxy.size.height
      let startX = xPosition(forMS: reviewState.editState.trimStartMS, width: width)
      let endX = xPosition(forMS: reviewState.editState.trimEndMS, width: width)
      let playheadX = xPosition(forSeconds: playbackState.currentSeconds, width: width)

      ZStack(alignment: .leading) {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
          .fill(Color.white.opacity(0.16))
          .frame(height: isTrimModeActive ? 26 : 6)
          .frame(maxHeight: .infinity)

        if isTrimModeActive {
          Rectangle()
            .fill(Color.black.opacity(0.48))
            .frame(width: max(0, startX), height: 26)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

          Rectangle()
            .fill(Color.black.opacity(0.48))
            .frame(width: max(0, width - endX), height: 26)
            .offset(x: endX)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.accentColor.opacity(0.24))
            .overlay(
              RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.accentColor.opacity(0.9), lineWidth: 1.5)
            )
            .frame(width: max(2, endX - startX), height: 30)
            .offset(x: startX)

          trimHandle
            .offset(x: max(0, startX - 6))
          trimHandle
            .offset(x: min(width - 12, endX - 6))
        } else {
          RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Color.accentColor.opacity(0.72))
            .frame(width: max(0, min(width, playheadX)), height: 6)
        }

        Rectangle()
          .fill(Color.white)
          .frame(width: 2, height: isTrimModeActive ? 36 : 16)
          .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
          .offset(x: min(width - 1, max(0, playheadX - 1)))
      }
      .frame(width: width, height: height)
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            handleDragChanged(value, width: width, startX: startX, endX: endX)
          }
          .onEnded { _ in
            dragTarget = nil
          }
      )
    }
  }

  private var trimHandle: some View {
    RoundedRectangle(cornerRadius: 3, style: .continuous)
      .fill(Color.white)
      .frame(width: 12, height: 34)
      .shadow(color: .black.opacity(0.34), radius: 3, x: 0, y: 1)
      .overlay(
        RoundedRectangle(cornerRadius: 1, style: .continuous)
          .fill(Color.black.opacity(0.34))
          .frame(width: 2, height: 16)
      )
  }

  private func handleDragChanged(
    _ value: DragGesture.Value,
    width: CGFloat,
    startX: CGFloat,
    endX: CGFloat
  ) {
    let locationX = min(max(0, value.location.x), width)
    let target = dragTarget ?? dragTargetForInitialLocation(locationX, startX: startX, endX: endX)
    dragTarget = target

    let targetMS = UInt32((Double(locationX / width) * Double(reviewState.durationMS)).rounded())
    switch target {
    case .start:
      reviewState.updateTrim(
        startMS: targetMS,
        endMS: reviewState.editState.trimEndMS,
        activeHandle: .start
      )
      playbackState.configure(durationSeconds: reviewState.durationSeconds, exportState: reviewState.exportState())
      playbackState.seek(to: Double(reviewState.editState.trimStartMS) / 1000.0)
    case .end:
      reviewState.updateTrim(
        startMS: reviewState.editState.trimStartMS,
        endMS: targetMS,
        activeHandle: .end
      )
      playbackState.configure(durationSeconds: reviewState.durationSeconds, exportState: reviewState.exportState())
    case .playhead:
      playbackState.seek(to: Double(targetMS) / 1000.0)
    }
  }

  private func dragTargetForInitialLocation(
    _ x: CGFloat,
    startX: CGFloat,
    endX: CGFloat
  ) -> PostRecordingTimelineDragTarget {
    guard isTrimModeActive else {
      return .playhead
    }
    if abs(x - startX) <= 24 {
      return .start
    }
    if abs(x - endX) <= 24 {
      return .end
    }
    return .playhead
  }

  private func xPosition(forMS milliseconds: UInt32, width: CGFloat) -> CGFloat {
    let progress = Double(milliseconds) / Double(max(1, reviewState.durationMS))
    return min(width, max(0, width * CGFloat(progress)))
  }

  private func xPosition(forSeconds seconds: Double, width: CGFloat) -> CGFloat {
    guard reviewState.durationSeconds > 0 else {
      return 0
    }
    let progress = seconds / reviewState.durationSeconds
    return min(width, max(0, width * CGFloat(progress)))
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
              webcamOverlay(
                url: webcamURL,
                seconds: playbackState.currentSeconds + project.webcamTimeOffsetSeconds,
                rect: itemRect,
                shape: webcamShape(for: item)
              )
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
  private func webcamOverlay(
    url: URL,
    seconds: Double,
    rect: CGRect,
    shape: VideoWebcamOverlayShapeOption
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
      contentRect: CGRect(x: 0, y: 0, width: 408, height: 318),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.title = String(localized: "Export Recording", bundle: AppLocalizer.shared.bundle)
    window.titleVisibility = .hidden
    window.isReleasedWhenClosed = false

    super.init(window: window)

    let viewController = PostRecordingExportSheetViewController(
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
    window.contentViewController = viewController
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

private enum PostRecordingExportSheetTarget {
  case video
  case gif
}

@MainActor
private final class PostRecordingExportSheetViewController: NSViewController {
  private let storeManager: StoreManager
  private var target: PostRecordingExportSheetTarget = .video
  private var options: PostRecordingExportOptions
  private let onCancel: () -> Void
  private let onSave: (PostRecordingExportOptions) -> Void
  private let onSaveGIF: () -> Void

  private let contentWidth: CGFloat = 360
  private let labelWidth: CGFloat = 112
  private let controlWidth: CGFloat = 190
  private let formStack = NSStackView()

  private let formatPopup = NSPopUpButton(frame: .zero, pullsDown: false)
  private let codecPopup = NSPopUpButton(frame: .zero, pullsDown: false)
  private let frameRatePopup = NSPopUpButton(frame: .zero, pullsDown: false)
  private let qualityPopup = NSPopUpButton(frame: .zero, pullsDown: false)
  private let scalePopup = NSPopUpButton(frame: .zero, pullsDown: false)
  private let bitratePopup = NSPopUpButton(frame: .zero, pullsDown: false)
  private let primaryButton = NSButton()

  init(
    initialOptions: PostRecordingExportOptions,
    storeManager: StoreManager,
    onCancel: @escaping () -> Void,
    onSave: @escaping (PostRecordingExportOptions) -> Void,
    onSaveGIF: @escaping () -> Void
  ) {
    self.storeManager = storeManager
    self.options = initialOptions
    self.onCancel = onCancel
    self.onSave = onSave
    self.onSaveGIF = onSaveGIF
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  override func loadView() {
    let rootView = NSView(frame: CGRect(origin: .zero, size: contentSize))
    rootView.wantsLayer = true
    rootView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    view = rootView

    configurePopups()
    configureButtons()

    let rootStack = NSStackView()
    rootStack.orientation = .vertical
    rootStack.alignment = .leading
    rootStack.spacing = 16
    rootStack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 18, right: 24)
    rootStack.translatesAutoresizingMaskIntoConstraints = false
    rootView.addSubview(rootStack)

    let titleLabel = NSTextField(labelWithString: String(localized: "Export Recording", bundle: AppLocalizer.shared.bundle))
    titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize + 2, weight: .semibold)
    titleLabel.textColor = .labelColor

    let detailLabel = NSTextField(labelWithString: String(localized: "Choose how this recording should be exported.", bundle: AppLocalizer.shared.bundle))
    detailLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    detailLabel.textColor = .secondaryLabelColor
    detailLabel.lineBreakMode = .byWordWrapping
    detailLabel.maximumNumberOfLines = 2
    detailLabel.preferredMaxLayoutWidth = contentWidth

    let headerStack = NSStackView(views: [titleLabel, detailLabel])
    headerStack.orientation = .vertical
    headerStack.alignment = .leading
    headerStack.spacing = 3
    headerStack.translatesAutoresizingMaskIntoConstraints = false
    headerStack.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
    rootStack.addArrangedSubview(headerStack)

    formStack.orientation = .vertical
    formStack.alignment = .leading
    formStack.spacing = 8
    formStack.translatesAutoresizingMaskIntoConstraints = false
    formStack.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
    rootStack.addArrangedSubview(formStack)

    let buttonRow = NSStackView()
    buttonRow.orientation = .horizontal
    buttonRow.alignment = .centerY
    buttonRow.spacing = 8
    buttonRow.translatesAutoresizingMaskIntoConstraints = false
    buttonRow.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true

    let spacer = NSView()
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    let cancelButton = NSButton(
      title: String(localized: "Cancel", bundle: AppLocalizer.shared.bundle),
      target: self,
      action: #selector(cancelButtonPressed)
    )
    cancelButton.bezelStyle = .rounded
    cancelButton.keyEquivalent = "\u{1b}"

    buttonRow.addArrangedSubview(spacer)
    buttonRow.addArrangedSubview(cancelButton)
    buttonRow.addArrangedSubview(primaryButton)
    rootStack.addArrangedSubview(buttonRow)

    NSLayoutConstraint.activate([
      rootStack.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
      rootStack.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
      rootStack.topAnchor.constraint(equalTo: rootView.topAnchor),
      rootStack.bottomAnchor.constraint(equalTo: rootView.bottomAnchor)
    ])

    rebuildFormRows()
    preferredContentSize = contentSize
  }

  private var gifFormatTitle: String {
    storeManager.hasPaidAccess
      ? String(localized: "GIF", bundle: AppLocalizer.shared.bundle)
      : String(localized: "GIF (Pro)", bundle: AppLocalizer.shared.bundle)
  }

  private var exportButtonTitle: String {
    switch target {
    case .video:
      return String(localized: "Export", bundle: AppLocalizer.shared.bundle)
    case .gif:
      return storeManager.hasPaidAccess
        ? String(localized: "Export GIF", bundle: AppLocalizer.shared.bundle)
        : String(localized: "Export GIF (Pro)", bundle: AppLocalizer.shared.bundle)
    }
  }

  private var contentSize: CGSize {
    switch target {
    case .video:
      return CGSize(width: 408, height: 318)
    case .gif:
      return CGSize(width: 408, height: 284)
    }
  }

  private func configurePopups() {
    configurePopup(
      formatPopup,
      titles: [String(localized: "Video", bundle: AppLocalizer.shared.bundle), gifFormatTitle],
      selectedIndex: 0,
      action: #selector(formatChanged)
    )
    configurePopup(
      codecPopup,
      titles: PostRecordingExportCodec.allCases.map(menuTitle(for:)),
      selectedIndex: PostRecordingExportCodec.allCases.firstIndex(of: options.codec) ?? 0,
      action: #selector(codecChanged)
    )
    configurePopup(
      frameRatePopup,
      titles: PostRecordingExportFrameRate.allCases.map(menuTitle(for:)),
      selectedIndex: PostRecordingExportFrameRate.allCases.firstIndex(of: options.frameRate) ?? 0,
      action: #selector(frameRateChanged)
    )
    configurePopup(
      qualityPopup,
      titles: PostRecordingExportQuality.allCases.map(menuTitle(for:)),
      selectedIndex: PostRecordingExportQuality.allCases.firstIndex(of: options.quality) ?? 0,
      action: #selector(qualityChanged)
    )
    configurePopup(
      scalePopup,
      titles: PostRecordingExportScale.allCases.map(menuTitle(for:)),
      selectedIndex: PostRecordingExportScale.allCases.firstIndex(of: options.scale) ?? 0,
      action: #selector(scaleChanged)
    )
    configurePopup(
      bitratePopup,
      titles: PostRecordingExportBitratePreset.allCases.map(menuTitle(for:)),
      selectedIndex: PostRecordingExportBitratePreset.allCases.firstIndex(of: options.bitrate) ?? 0,
      action: #selector(bitrateChanged)
    )
  }

  private func configurePopup(_ popup: NSPopUpButton, titles: [String], selectedIndex: Int, action: Selector) {
    popup.removeAllItems()
    popup.addItems(withTitles: titles)
    popup.selectItem(at: selectedIndex)
    popup.target = self
    popup.action = action
    popup.controlSize = .regular
    popup.bezelStyle = .rounded
    popup.translatesAutoresizingMaskIntoConstraints = false
    popup.widthAnchor.constraint(equalToConstant: controlWidth).isActive = true
  }

  private func configureButtons() {
    primaryButton.title = exportButtonTitle
    primaryButton.target = self
    primaryButton.action = #selector(exportButtonPressed)
    primaryButton.bezelStyle = .rounded
    primaryButton.keyEquivalent = "\r"
  }

  private func rebuildFormRows() {
    for row in formStack.arrangedSubviews {
      formStack.removeArrangedSubview(row)
      row.removeFromSuperview()
    }

    formStack.addArrangedSubview(formRow(label: "Format", control: formatPopup))

    switch target {
    case .video:
      formStack.addArrangedSubview(formRow(label: "Codec", control: codecPopup))
      formStack.addArrangedSubview(formRow(label: "Frame Rate", control: frameRatePopup))
      formStack.addArrangedSubview(formRow(label: "Quality", control: qualityPopup))
      formStack.addArrangedSubview(formRow(label: "Scale", control: scalePopup))
      formStack.addArrangedSubview(formRow(label: "Bitrate", control: bitratePopup))
    case .gif:
      formStack.addArrangedSubview(formRow(label: "Type", control: valueLabel("Animated GIF")))
      formStack.addArrangedSubview(formRow(label: "Frame Rate", control: valueLabel("12 fps", localized: false)))
      formStack.addArrangedSubview(formRow(label: "Max Size", control: valueLabel("960 px", localized: false)))
      formStack.addArrangedSubview(formRow(label: "Audio", control: valueLabel("No audio")))
    }
  }

  private func formRow(label key: String, control: NSView) -> NSStackView {
    let row = NSStackView()
    row.orientation = .horizontal
    row.alignment = .firstBaseline
    row.spacing = 14
    row.translatesAutoresizingMaskIntoConstraints = false

    let label = NSTextField(labelWithString: String(localized: String.LocalizationValue(key), bundle: AppLocalizer.shared.bundle))
    label.alignment = .right
    label.font = .systemFont(ofSize: NSFont.systemFontSize)
    label.textColor = .secondaryLabelColor
    label.translatesAutoresizingMaskIntoConstraints = false
    label.widthAnchor.constraint(equalToConstant: labelWidth).isActive = true

    row.addArrangedSubview(label)
    row.addArrangedSubview(control)
    row.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
    return row
  }

  private func valueLabel(_ key: String, localized: Bool = true) -> NSTextField {
    let title = localized ? String(localized: String.LocalizationValue(key), bundle: AppLocalizer.shared.bundle) : key
    let label = NSTextField(labelWithString: title)
    label.font = .systemFont(ofSize: NSFont.systemFontSize)
    label.textColor = .labelColor
    label.translatesAutoresizingMaskIntoConstraints = false
    label.widthAnchor.constraint(equalToConstant: controlWidth).isActive = true
    return label
  }

  private func updateContentSize() {
    let size = contentSize
    preferredContentSize = size
    view.setFrameSize(size)
    view.window?.setContentSize(size)
  }

  @objc
  private func cancelButtonPressed() {
    onCancel()
  }

  @objc
  private func exportButtonPressed() {
    switch target {
    case .video:
      onSave(options)
    case .gif:
      onSaveGIF()
    }
  }

  @objc
  private func formatChanged() {
    target = formatPopup.indexOfSelectedItem == 1 ? .gif : .video
    primaryButton.title = exportButtonTitle
    rebuildFormRows()
    updateContentSize()
  }

  @objc
  private func codecChanged() {
    let values = PostRecordingExportCodec.allCases
    guard values.indices.contains(codecPopup.indexOfSelectedItem) else {
      return
    }
    options.codec = values[codecPopup.indexOfSelectedItem]
  }

  @objc
  private func frameRateChanged() {
    let values = PostRecordingExportFrameRate.allCases
    guard values.indices.contains(frameRatePopup.indexOfSelectedItem) else {
      return
    }
    options.frameRate = values[frameRatePopup.indexOfSelectedItem]
  }

  @objc
  private func qualityChanged() {
    let values = PostRecordingExportQuality.allCases
    guard values.indices.contains(qualityPopup.indexOfSelectedItem) else {
      return
    }
    options.quality = values[qualityPopup.indexOfSelectedItem]
  }

  @objc
  private func scaleChanged() {
    let values = PostRecordingExportScale.allCases
    guard values.indices.contains(scalePopup.indexOfSelectedItem) else {
      return
    }
    options.scale = values[scalePopup.indexOfSelectedItem]
  }

  @objc
  private func bitrateChanged() {
    let values = PostRecordingExportBitratePreset.allCases
    guard values.indices.contains(bitratePopup.indexOfSelectedItem) else {
      return
    }
    options.bitrate = values[bitratePopup.indexOfSelectedItem]
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
  let isMuted: Bool

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
        playbackState.updateFromPlayer(seconds: seconds, isPlaying: (player?.rate ?? 0) != 0)
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
    player.isMuted = isMuted
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
      player.isMuted = isMuted
      nsView.player = player
      context.coordinator.player = player
      playbackState.attach(player: player)
      context.coordinator.installTimeObserver(on: player)
      return
    }

    guard currentURL != url else {
      nsView.player?.isMuted = isMuted
      return
    }

    nsView.player?.pause()
    let player = AVPlayer(url: url)
    player.actionAtItemEnd = .pause
    player.isMuted = isMuted
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
