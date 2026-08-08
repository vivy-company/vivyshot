import AppKit
import AVKit
import SwiftUI
import UniformTypeIdentifiers

private enum PostRecordingReviewShortcut {
  case copyVideo
  case exportOptions
  case saveGIF
  case saveMP4
  case saveMOV
}

private enum PostRecordingSaveMenuAction {
  static let copyVideo = "copy-video"
  static let gif = "gif"
}

private final class PostRecordingReviewWindow: NSWindow {
  var shortcutHandler: ((PostRecordingReviewShortcut) -> Bool)?

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if let shortcut = postRecordingShortcut(for: event),
       shortcutHandler?(shortcut) == true {
      return true
    }
    return super.performKeyEquivalent(with: event)
  }

  private func postRecordingShortcut(for event: NSEvent) -> PostRecordingReviewShortcut? {
    guard event.type == .keyDown else {
      return nil
    }

    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    guard flags.contains(.command), !flags.contains(.control) else {
      return nil
    }

    let hasShift = flags.contains(.shift)
    let hasOption = flags.contains(.option)
    guard let key = event.charactersIgnoringModifiers?.lowercased() else {
      return nil
    }

    switch (key, hasShift, hasOption) {
    case ("c", false, false):
      return .copyVideo
    case ("e", false, false):
      return .exportOptions
    case ("g", false, true):
      return .saveGIF
    case ("s", false, false):
      return .saveMP4
    case ("s", true, false):
      return .saveMOV
    default:
      return nil
    }
  }
}

final class PostRecordingActionPanel: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
  private let inputURL: URL
  private let project: PostRecordingProject
  private let reviewState: PostRecordingReviewState
  private let settings: AppSettings
  private let storeManager: StoreManager
  private let proExportTrialStore: ProExportTrialStore
  private let presentPaywall: () -> Void
  private let onAction: (PostRecordingAction) -> Void
  var onWindowClosed: (() -> Void)?
  private var didPickAction = false
  private var exportSheetController: PostRecordingExportSheetController?
  private var dockPresenceReason: AppDockPresenceReason {
    .postRecordingReview(ObjectIdentifier(self))
  }

  init(
    inputURL: URL,
    project: PostRecordingProject,
    details: PostRecordingDetails,
    durationSeconds: Double,
    thumbnail: NSImage?,
    videoSize: CGSize?,
    settings: AppSettings,
    storeManager: StoreManager,
    proExportTrialStore: ProExportTrialStore,
    presentPaywall: @escaping () -> Void,
    onAction: @escaping (PostRecordingAction) -> Void
  ) {
    self.inputURL = inputURL
    self.project = project
    self.reviewState = PostRecordingReviewState(durationSeconds: durationSeconds, hasAudio: details.hasAudio)
    self.settings = settings
    self.storeManager = storeManager
    self.proExportTrialStore = proExportTrialStore
    self.presentPaywall = presentPaywall
    self.onAction = onAction

    let panel = PostRecordingReviewWindow(
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
    // The review panel must reach the user even when the recording was stopped
    // from a fullscreen app's Space.
    panel.collectionBehavior.insert([.moveToActiveSpace, .fullScreenAuxiliary])

    super.init(window: panel)
    panel.delegate = self
    panel.shortcutHandler = { [weak self] shortcut in
      self?.handlePostRecordingShortcut(shortcut) ?? false
    }
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
    guard let window else {
      return
    }
    AppDockPresence.track(dockPresenceReason, window: window)
    window.center()
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    // Cooperative activation can be refused while another app is frontmost;
    // order the panel above regardless so the recording is never reviewable-but-invisible.
    window.orderFrontRegardless()
  }

  func windowWillClose(_ notification: Notification) {
    AppDockPresence.release(dockPresenceReason)
    onWindowClosed?()
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
    let copyItem = NSMenuItem(
      title: String(localized: "Copy Video", bundle: AppLocalizer.shared.bundle),
      action: nil,
      keyEquivalent: "c"
    )
    copyItem.keyEquivalentModifierMask = [.command]
    copyItem.representedObject = PostRecordingSaveMenuAction.copyVideo
    button.menu?.addItem(copyItem)
    button.menu?.addItem(NSMenuItem.separator())
    for container in PostRecordingVideoSaveContainer.allCases {
      let menuItem = NSMenuItem(title: container.title, action: nil, keyEquivalent: "")
      switch container {
      case .mp4:
        menuItem.keyEquivalent = "s"
        menuItem.keyEquivalentModifierMask = [.command]
      case .mov:
        menuItem.keyEquivalent = "s"
        menuItem.keyEquivalentModifierMask = [.command, .shift]
      }
      menuItem.representedObject = container.rawValue
      button.menu?.addItem(menuItem)
    }
    let gifItem = NSMenuItem(
      title: String(localized: "Save as GIF", bundle: AppLocalizer.shared.bundle),
      action: nil,
      keyEquivalent: "g"
    )
    gifItem.keyEquivalentModifierMask = [.command, .option]
    gifItem.representedObject = PostRecordingSaveMenuAction.gif
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
    case .copyVideo(let options, let exportState, container: let container, consumesFreeProExportTrial: _):
      guard let consumesTrial = proExportGateDecision(
        target: .video,
        options: options,
        includesAudio: exportState.includesAudio
      ) else {
        return nil
      }
      return .copyVideo(options, exportState, container: container, consumesFreeProExportTrial: consumesTrial)
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
    guard requirement.requiresPro, !requirement.isSatisfied(canUse: storeManager.canUse) else {
      return false
    }

    if proExportTrialStore.isAvailable {
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
      presentPaywall()
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
      presentPaywall()
    }
  }

  private func handlePostRecordingShortcut(_ shortcut: PostRecordingReviewShortcut) -> Bool {
    guard window?.attachedSheet == nil else {
      return false
    }

    switch shortcut {
    case .copyVideo:
      performSaveRecording(rawFormat: PostRecordingSaveMenuAction.copyVideo)
    case .exportOptions:
      exportVideoRecording()
    case .saveGIF:
      performSaveRecording(rawFormat: PostRecordingSaveMenuAction.gif)
    case .saveMP4:
      performSaveRecording(rawFormat: PostRecordingVideoSaveContainer.mp4.rawValue)
    case .saveMOV:
      performSaveRecording(rawFormat: PostRecordingVideoSaveContainer.mov.rawValue)
    }
    return true
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
    if rawFormat == PostRecordingSaveMenuAction.copyVideo {
      performAction(
        .copyVideo(
          quickSaveVideoOptions(),
          reviewState.exportState(),
          container: .mp4,
          consumesFreeProExportTrial: false
        )
      )
      return
    }
    if rawFormat == PostRecordingSaveMenuAction.gif {
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
    PostRecordingExportOptions.defaultOptions(settings: settings)
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
}

private extension NSToolbarItem.Identifier {
  static let exportVideoRecording = NSToolbarItem.Identifier("com.vivyshot.post-recording.export-video")
  static let saveVideoRecording = NSToolbarItem.Identifier("com.vivyshot.post-recording.save-video")
}
