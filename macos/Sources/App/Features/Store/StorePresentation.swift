import AppKit
import SwiftUI

@MainActor
final class PaywallWindowController: NSWindowController, NSWindowDelegate {
  static let shared = PaywallWindowController()
  private static let toolbarTitle = String(localized: "Unlock VivyShot", bundle: AppLocalizer.shared.bundle)
  private static let toolbarSubtitle = String(localized: "Advanced export controls and local capture statistics", bundle: AppLocalizer.shared.bundle)

  private init() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 520, height: 720),
      styleMask: [.titled, .closable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    window.title = Self.toolbarTitle
    window.subtitle = Self.toolbarSubtitle
    window.titleVisibility = .visible
    window.toolbarStyle = .unified
    window.backgroundColor = .windowBackgroundColor
    window.isReleasedWhenClosed = false
    window.center()
    window.setContentSize(NSSize(width: 520, height: 720))
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
    window.title = Self.toolbarTitle
    window.subtitle = Self.toolbarSubtitle
    window.toolbar = makeToolbar()
    window.setContentSize(NSSize(width: 520, height: 720))
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  private func makeToolbar() -> NSToolbar {
    let toolbar = NSToolbar(identifier: "VivyShotPaywallToolbar")
    toolbar.displayMode = .iconOnly
    return toolbar
  }

  private static func makePaywallView() -> some View {
    NavigationStack {
      VivyShotPaywallView()
        .navigationTitle(Self.toolbarTitle)
        .navigationSubtitle(Self.toolbarSubtitle)
    }
      .environment(\.locale, AppLocalizer.shared.locale)
      .onAppear {
        DispatchQueue.main.async {
          guard let window = NSApp.keyWindow else { return }
          window.title = Self.toolbarTitle
          window.subtitle = Self.toolbarSubtitle
          window.toolbarStyle = .unified
        }
      }
  }

  func windowWillClose(_ notification: Notification) {
    guard let window else { return }
    window.orderOut(nil)
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
