import AppKit

final class PostRecordingExportSheetController: NSWindowController {
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
