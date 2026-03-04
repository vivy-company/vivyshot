import AppKit

@MainActor
enum TransientToast {
  private static var panel: NSPanel?
  private static var label: NSTextField?
  private static var hideTask: Task<Void, Never>?

  static func show(_ message: String, duration: TimeInterval = 1.25) {
    hideTask?.cancel()
    hideTask = nil
    let panel = ensurePanel()
    guard let label else {
      return
    }

    label.stringValue = message
    label.sizeToFit()

    let horizontalPadding: CGFloat = 16
    let verticalPadding: CGFloat = 9
    let width = max(160, label.frame.width + horizontalPadding * 2)
    let height = max(34, label.frame.height + verticalPadding * 2)

    panel.contentView?.frame = CGRect(x: 0, y: 0, width: width, height: height)
    label.frame = CGRect(
      x: floor((width - label.frame.width) * 0.5),
      y: floor((height - label.frame.height) * 0.5),
      width: label.frame.width,
      height: label.frame.height
    )

    let anchorScreen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
      ?? NSScreen.main
      ?? NSScreen.screens.first
    if let screen = anchorScreen {
      let frame = screen.visibleFrame
      let origin = CGPoint(
        x: frame.midX - width * 0.5,
        y: frame.midY - height * 0.5
      )
      panel.setFrame(CGRect(origin: origin, size: CGSize(width: width, height: height)).integral, display: false)
    }

    if panel.isVisible {
      panel.orderFrontRegardless()
    } else {
      panel.alphaValue = 0
      panel.orderFrontRegardless()
    }

    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.14
      context.timingFunction = CAMediaTimingFunction(name: .easeOut)
      panel.animator().alphaValue = 1
    }

    let delay = max(0, duration)
    hideTask = Task { @MainActor in
      do {
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
      } catch {
        return
      }

      guard !Task.isCancelled, let panel = self.panel else {
        hideTask = nil
        return
      }

      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.16
        context.timingFunction = CAMediaTimingFunction(name: .easeIn)
        panel.animator().alphaValue = 0
      } completionHandler: {
        panel.orderOut(nil)
      }
      hideTask = nil
    }
  }

  private static func ensurePanel() -> NSPanel {
    if let panel {
      return panel
    }

    let panel = NSPanel(
      contentRect: CGRect(x: 0, y: 0, width: 220, height: 40),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.isReleasedWhenClosed = false
    panel.isOpaque = false
    panel.hasShadow = true
    panel.backgroundColor = .clear
    panel.level = .statusBar
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    panel.hidesOnDeactivate = false
    panel.ignoresMouseEvents = true

    let visual = NSVisualEffectView(frame: panel.contentView?.bounds ?? .zero)
    visual.autoresizingMask = [.width, .height]
    visual.material = .hudWindow
    visual.blendingMode = .behindWindow
    visual.state = .active
    visual.wantsLayer = true
    visual.layer?.cornerRadius = 12
    visual.layer?.masksToBounds = true

    let text = NSTextField(labelWithString: "")
    text.font = .systemFont(ofSize: 13, weight: .semibold)
    text.textColor = NSColor.white
    text.backgroundColor = .clear
    text.isBezeled = false
    text.alignment = .center

    visual.addSubview(text)
    panel.contentView = visual

    self.panel = panel
    self.label = text
    return panel
  }
}
