import AppKit
import SwiftUI

@MainActor
final class PaywallWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
  static let shared = PaywallWindowController()
  private static let titleItemIdentifier = NSToolbarItem.Identifier("VivyShotPaywallTitleItem")

  private init() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 720, height: 660),
      styleMask: [.titled, .closable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    window.title = String(localized: "VivyShot License", bundle: AppLocalizer.shared.bundle)
    window.subtitle = String(localized: "Lifetime access or support the project", bundle: AppLocalizer.shared.bundle)
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.toolbarStyle = .unified
    window.backgroundColor = .windowBackgroundColor
    window.isReleasedWhenClosed = false
    window.center()
    window.setContentSize(NSSize(width: 720, height: 660))
    window.contentView = NSHostingView(rootView: AnyView(Self.makePaywallView()))

    super.init(window: window)
    window.toolbar = makeToolbar()
    window.delegate = self
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  func show() {
    guard let window else { return }
    if let hostingView = window.contentView as? NSHostingView<AnyView> {
      hostingView.rootView = AnyView(Self.makePaywallView())
    } else {
      window.contentView = NSHostingView(rootView: AnyView(Self.makePaywallView()))
    }
    window.title = String(localized: "VivyShot License", bundle: AppLocalizer.shared.bundle)
    window.subtitle = String(localized: "Lifetime access or support the project", bundle: AppLocalizer.shared.bundle)
    window.toolbar = makeToolbar()
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  private func makeToolbar() -> NSToolbar {
    let toolbar = NSToolbar(identifier: "VivyShotPaywallToolbar")
    toolbar.delegate = self
    toolbar.displayMode = .default
    return toolbar
  }

  private static func makePaywallView() -> some View {
    VivyShotPaywallView()
      .environment(\.locale, AppLocalizer.shared.locale)
  }

  func windowWillClose(_ notification: Notification) {
    guard let window else { return }
    window.orderOut(nil)
  }

  func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    [Self.titleItemIdentifier, .flexibleSpace]
  }

  func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    [Self.titleItemIdentifier, .flexibleSpace]
  }

  func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    []
  }

  func toolbar(
    _ toolbar: NSToolbar,
    itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
    willBeInsertedIntoToolbar flag: Bool
  ) -> NSToolbarItem? {
    guard itemIdentifier == Self.titleItemIdentifier else {
      return nil
    }

    let item = NSToolbarItem(itemIdentifier: itemIdentifier)
    item.isBordered = false
    item.view = titleToolbarView()
    return item
  }

  private func titleToolbarView() -> NSView {
    let titleLabel = NSTextField(labelWithString: String(localized: "VivyShot License", bundle: AppLocalizer.shared.bundle))
    titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
    titleLabel.alignment = .left
    titleLabel.textColor = .labelColor

    let subtitleLabel = NSTextField(labelWithString: String(localized: "Lifetime access or support the project", bundle: AppLocalizer.shared.bundle))
    subtitleLabel.font = .systemFont(ofSize: 11)
    subtitleLabel.alignment = .left
    subtitleLabel.textColor = .secondaryLabelColor
    subtitleLabel.lineBreakMode = .byTruncatingTail

    let stack = NSStackView(views: [titleLabel, subtitleLabel])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 0
    stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

    let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 32))
    stack.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(stack)

    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
      stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor)
    ])

    return container
  }
}

@MainActor
func presentPaywallWindow() {
  PaywallWindowController.shared.show()
}

@MainActor
func dismissPaywallWindow() {
  PaywallWindowController.shared.close()
}
