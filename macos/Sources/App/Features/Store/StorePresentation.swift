import AppKit
import SwiftUI

@MainActor
final class PaywallWindowController: NSWindowController, NSWindowDelegate {
  static let shared = PaywallWindowController()

  private struct ToolbarCopy {
    let title: String
    let subtitle: String
  }

  private init() {
    let copy = Self.toolbarCopy
    let contentSize = Self.contentSize
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: contentSize.width, height: contentSize.height),
      styleMask: [.titled, .closable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    window.title = copy.title
    window.subtitle = copy.subtitle
    window.titleVisibility = .visible
    window.toolbarStyle = .unified
    window.backgroundColor = .windowBackgroundColor
    window.isReleasedWhenClosed = false
    window.center()
    window.setContentSize(contentSize)
    window.contentView = NSHostingView(rootView: AnyView(Self.makePaywallView(copy: copy)))

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
    let copy = Self.toolbarCopy
    let contentSize = Self.contentSize
    if let hostingView = window.contentView as? NSHostingView<AnyView> {
      hostingView.rootView = AnyView(Self.makePaywallView(copy: copy))
    } else {
      window.contentView = NSHostingView(rootView: AnyView(Self.makePaywallView(copy: copy)))
    }
    window.title = copy.title
    window.subtitle = copy.subtitle
    window.toolbar = makeToolbar()
    window.setContentSize(contentSize)
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  private func makeToolbar() -> NSToolbar {
    let toolbar = NSToolbar(identifier: "VivyShotPaywallToolbar")
    toolbar.displayMode = .iconOnly
    return toolbar
  }

  private static var contentSize: NSSize {
    StoreManager.shared.hasSupporterBadge
      ? NSSize(width: 520, height: 360)
      : NSSize(width: 520, height: 720)
  }

  private static var toolbarCopy: ToolbarCopy {
    let storeManager = StoreManager.shared
    if storeManager.hasSupporterBadge {
      return ToolbarCopy(
        title: String(localized: "License Details", bundle: AppLocalizer.shared.bundle),
        subtitle: String(localized: "Supporter and paid access are already active on this Mac.", bundle: AppLocalizer.shared.bundle)
      )
    }
    if storeManager.hasLifetimeUnlock {
      return ToolbarCopy(
        title: String(localized: "License Options", bundle: AppLocalizer.shared.bundle),
        subtitle: String(localized: "Lifetime access is unlocked.", bundle: AppLocalizer.shared.bundle)
      )
    }
    return ToolbarCopy(
      title: String(localized: "Unlock VivyShot", bundle: AppLocalizer.shared.bundle),
      subtitle: String(localized: "Advanced export controls and local capture statistics", bundle: AppLocalizer.shared.bundle)
    )
  }

  private static func makePaywallView(copy: ToolbarCopy) -> some View {
    NavigationStack {
      VivyShotPaywallView()
        .navigationTitle(copy.title)
        .navigationSubtitle(copy.subtitle)
    }
      .environment(\.locale, AppLocalizer.shared.locale)
      .onAppear {
        DispatchQueue.main.async {
          guard let window = NSApp.keyWindow else { return }
          window.title = copy.title
          window.subtitle = copy.subtitle
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
