import AppKit
import SwiftUI

@MainActor
final class StatisticsWindowController: NSWindowController, NSWindowDelegate {
  private let localizer: AppLocalizer
  private let storeManager: StoreManager
  private var dockPresenceReason: AppDockPresenceReason {
    .statistics(ObjectIdentifier(self))
  }

  init(
    localizer: AppLocalizer,
    storeManager: StoreManager,
    statisticsStore: StatisticsStore,
    presentPaywall: @escaping () -> Void
  ) {
    self.localizer = localizer
    self.storeManager = storeManager
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 780, height: 680),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    window.titleVisibility = .visible
    window.toolbarStyle = .unified
    window.title = String(localized: "Statistics", bundle: localizer.bundle)
    window.subtitle = Self.windowSubtitle(storeManager: storeManager, localizer: localizer)
    window.backgroundColor = .windowBackgroundColor
    window.isReleasedWhenClosed = false
    window.center()
    window.setContentSize(NSSize(width: 780, height: 680))
    window.contentMinSize = NSSize(width: 660, height: 560)

    let toolbar = NSToolbar(identifier: "VivyShotStatisticsToolbar")
    toolbar.displayMode = .iconOnly
    window.toolbar = toolbar

    window.contentView = NSHostingView(
      rootView: StatisticsView(
        presentation: .window,
        storeManager: storeManager,
        statisticsStore: statisticsStore,
        onUpgrade: presentPaywall
      )
        .environment(\.locale, localizer.locale)
        .frame(minWidth: 660, minHeight: 560)
    )

    super.init(window: window)
    window.delegate = self
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  func show() {
    guard let window else { return }
    AppDockPresence.acquire(dockPresenceReason)
    window.title = String(localized: "Statistics", bundle: localizer.bundle)
    window.subtitle = Self.windowSubtitle(storeManager: storeManager, localizer: localizer)
    window.toolbarStyle = .unified
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func windowWillClose(_ notification: Notification) {
    AppDockPresence.release(dockPresenceReason)
  }

  private static func windowSubtitle(storeManager: StoreManager?, localizer: AppLocalizer) -> String {
    if storeManager?.canUse(.statistics) == true {
      return String(localized: "Local capture totals, streaks, history, and milestones for this Mac.", bundle: localizer.bundle)
    }
    return String(localized: "Local capture totals and recent activity for this Mac.", bundle: localizer.bundle)
  }
}
