import AppKit
import SwiftUI

@MainActor
final class PaywallWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
  static let shared = PaywallWindowController()

  private init() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 720, height: 660),
      styleMask: [.titled, .closable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    window.title = "Upgrade VivyShot"
    window.subtitle = "Lifetime access or support the project"
    window.titleVisibility = .visible
    window.titlebarAppearsTransparent = true
    window.toolbarStyle = .unified
    window.backgroundColor = .windowBackgroundColor
    window.isReleasedWhenClosed = false
    window.center()
    window.setContentSize(NSSize(width: 720, height: 660))
    window.contentView = NSHostingView(rootView: VivyShotPaywallView())

    super.init(window: window)
    let toolbar = NSToolbar(identifier: "VivyShotPaywallToolbar")
    toolbar.delegate = self
    toolbar.displayMode = .iconOnly
    toolbar.showsBaselineSeparator = false
    window.toolbar = toolbar
    window.delegate = self
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  func show() {
    guard let window else { return }
    if let hostingView = window.contentView as? NSHostingView<VivyShotPaywallView> {
      hostingView.rootView = VivyShotPaywallView()
    } else {
      window.contentView = NSHostingView(rootView: VivyShotPaywallView())
    }
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func windowWillClose(_ notification: Notification) {
    guard let window else { return }
    window.orderOut(nil)
  }

  func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    []
  }

  func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    []
  }

  func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    []
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
