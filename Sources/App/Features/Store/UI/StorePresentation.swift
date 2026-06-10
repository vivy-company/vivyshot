import AppKit
import SwiftUI

@MainActor
final class PaywallWindowController: NSWindowController, NSWindowDelegate {
  private let localizer: AppLocalizer
  private let storeManager: StoreManager

  private struct ToolbarCopy {
    let title: String
    let subtitle: String
  }

  init(localizer: AppLocalizer, storeManager: StoreManager) {
    self.localizer = localizer
    self.storeManager = storeManager
    let copy = Self.toolbarCopy(storeManager: storeManager, localizer: localizer)
    let contentSize = Self.contentSize(storeManager: storeManager)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: contentSize.width, height: contentSize.height),
      styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
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
    window.contentMinSize = Self.minimumContentSize(storeManager: storeManager)
    window.contentView = NSHostingView(rootView: AnyView(Self.makePaywallView(
      copy: copy,
      localizer: localizer,
      storeManager: storeManager,
      dismissPaywall: { [weak window] in
        window?.close()
      }
    )))

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
    let copy = Self.toolbarCopy(storeManager: storeManager, localizer: localizer)
    let contentSize = Self.contentSize(storeManager: storeManager)
    if let hostingView = window.contentView as? NSHostingView<AnyView> {
      hostingView.rootView = AnyView(Self.makePaywallView(
        copy: copy,
        localizer: localizer,
        storeManager: storeManager,
        dismissPaywall: { [weak window] in
          window?.close()
        }
      ))
    } else {
      window.contentView = NSHostingView(rootView: AnyView(Self.makePaywallView(
        copy: copy,
        localizer: localizer,
        storeManager: storeManager,
        dismissPaywall: { [weak window] in
          window?.close()
        }
      )))
    }
    window.title = copy.title
    window.subtitle = copy.subtitle
    window.toolbar = makeToolbar()
    window.contentMinSize = Self.minimumContentSize(storeManager: storeManager)
    if !window.isVisible {
      window.setContentSize(contentSize)
      window.center()
    }
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  private func makeToolbar() -> NSToolbar {
    let toolbar = NSToolbar(identifier: "VivyShotPaywallToolbar")
    toolbar.displayMode = .iconOnly
    return toolbar
  }

  private static func contentSize(storeManager: StoreManager) -> NSSize {
    storeManager.hasSupporterBadge
      ? NSSize(width: 520, height: 360)
      : NSSize(width: 520, height: 720)
  }

  private static func minimumContentSize(storeManager: StoreManager) -> NSSize {
    storeManager.hasSupporterBadge
      ? NSSize(width: 520, height: 360)
      : NSSize(width: 520, height: 560)
  }

  private static func toolbarCopy(storeManager: StoreManager, localizer: AppLocalizer) -> ToolbarCopy {
    if storeManager.hasSupporterBadge {
      return ToolbarCopy(
        title: String(localized: "License Details", bundle: localizer.bundle),
        subtitle: String(localized: "Supporter and paid access are already active on this Mac.", bundle: localizer.bundle)
      )
    }
    if storeManager.hasLifetimeUnlock {
      return ToolbarCopy(
        title: String(localized: "License Options", bundle: localizer.bundle),
        subtitle: String(localized: "Lifetime access is unlocked.", bundle: localizer.bundle)
      )
    }
    return ToolbarCopy(
      title: String(localized: "Unlock VivyShot", bundle: localizer.bundle),
      subtitle: String(localized: "Advanced export controls and local capture statistics", bundle: localizer.bundle)
    )
  }

  private static func makePaywallView(
    copy: ToolbarCopy,
    localizer: AppLocalizer,
    storeManager: StoreManager,
    dismissPaywall: @escaping () -> Void
  ) -> some View {
    NavigationStack {
      PaywallView(storeManager: storeManager, dismissPaywall: dismissPaywall)
        .navigationTitle(copy.title)
        .navigationSubtitle(copy.subtitle)
    }
      .environment(\.locale, localizer.locale)
  }

  func windowWillClose(_ notification: Notification) {
    guard let window else { return }
    window.orderOut(nil)
  }

}
