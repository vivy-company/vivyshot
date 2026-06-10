import AppKit
import Combine

@MainActor
final class RecordingOverlaySettingsPreviewController: NSWindowController {
  private let kind: RecordingOverlaySettingsPreviewKind
  private let content: RecordingOverlaySettingsPreviewView
  private let onClosed: (RecordingOverlaySettingsPreviewKind) -> Void
  private var settingsChangeCancellable: AnyCancellable?
  private var didClose = false

  init(
    kind: RecordingOverlaySettingsPreviewKind,
    settings: AppSettings,
    onClosed: @escaping (RecordingOverlaySettingsPreviewKind) -> Void
  ) {
    self.kind = kind
    self.onClosed = onClosed
    let mouseLocation = NSEvent.mouseLocation
    let screenFrame = (NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main)?.visibleFrame
      ?? CGRect(x: 0, y: 0, width: 960, height: 540)
    content = RecordingOverlaySettingsPreviewView(
      frame: CGRect(origin: .zero, size: screenFrame.size),
      kind: kind,
      settings: settings
    )

    let panel = NSPanel(
      contentRect: screenFrame,
      styleMask: [.nonactivatingPanel, .borderless],
      backing: .buffered,
      defer: false
    )
    panel.isReleasedWhenClosed = false
    panel.level = .screenSaver
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    panel.hidesOnDeactivate = false
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.contentView = content

    super.init(window: panel)

    content.onClose = { [weak self] in
      self?.close()
    }
    settingsChangeCancellable = settings.videoSettingsChanges
      .sink { [weak self, weak settings] in
        guard let self, let settings else {
          return
        }
        self.content.update(settings: settings)
      }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  func show() {
    window?.orderFrontRegardless()
    content.startPreview()
  }

  override func close() {
    guard !didClose else {
      return
    }
    didClose = true
    settingsChangeCancellable?.cancel()
    settingsChangeCancellable = nil
    content.stopPreview()
    super.close()
    onClosed(kind)
  }
}
