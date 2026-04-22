import AppKit
import SwiftUI

@MainActor
final class StatisticsWindowController: NSWindowController, NSWindowDelegate {
  static let shared = StatisticsWindowController()

  private init() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 780, height: 680),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    window.titleVisibility = .visible
    window.toolbarStyle = .unified
    window.backgroundColor = .windowBackgroundColor
    window.isReleasedWhenClosed = false
    window.center()
    window.setContentSize(NSSize(width: 780, height: 680))
    window.contentMinSize = NSSize(width: 660, height: 560)

    let toolbar = NSToolbar(identifier: "VivyShotStatisticsToolbar")
    toolbar.displayMode = .iconOnly
    window.toolbar = toolbar

    window.contentView = NSHostingView(
      rootView: VivyShotStatisticsView(presentation: .window)
        .environment(\.locale, AppLocalizer.shared.locale)
        .frame(minWidth: 660, minHeight: 560)
    )

    super.init(window: window)
    window.delegate = self
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  func show() {
    guard let window else { return }
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
}

@MainActor
func presentStatisticsWindow() {
  StatisticsWindowController.shared.show()
}
