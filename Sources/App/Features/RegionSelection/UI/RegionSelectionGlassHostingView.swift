import AppKit
import SwiftUI

/// Glass/material host that lets selection toolbar tooltips overflow without clipping.
@MainActor
final class RegionSelectionGlassHostingView<Content: View>: NSView {
  private let hostingView: NSHostingView<Content>
  private let shellView: NSView

  var rootView: Content {
    get { hostingView.rootView }
    set {
      hostingView.rootView = newValue
      hostingView.invalidateIntrinsicContentSize()
      invalidateIntrinsicContentSize()
      needsLayout = true
    }
  }

  init(rootView: Content, cornerRadius: CGFloat = 26) {
    hostingView = NSHostingView(rootView: rootView)

    if #available(macOS 26.0, *) {
      let glassView = NSGlassEffectView()
      glassView.style = .regular
      glassView.cornerRadius = cornerRadius
      shellView = glassView
    } else {
      let visualEffectView = NSVisualEffectView()
      visualEffectView.blendingMode = .behindWindow
      visualEffectView.material = .hudWindow
      visualEffectView.state = .active
      shellView = visualEffectView
    }

    super.init(frame: .zero)
    configureTransparentHost()
    // The glass shell provides the material; the SwiftUI content sits on top as a sibling rather
    // than the glass's clipped contentView, so hover tooltips can overflow the toolbar bounds
    // instead of being clipped to the glass shape. Forced-dark appearance (set on the overlay
    // window) keeps both the shell and the content legible.
    addSubview(shellView)
    addSubview(hostingView)
  }

  // Allow hover tooltips to draw outside the toolbar/glass bounds.
  override var wantsDefaultClipping: Bool {
    false
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  override var isOpaque: Bool {
    false
  }

  override var fittingSize: NSSize {
    hostingView.fittingSize
  }

  override var intrinsicContentSize: NSSize {
    hostingView.intrinsicContentSize
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    configureTransparentHost()
  }

  override func layout() {
    super.layout()
    shellView.frame = bounds
    hostingView.frame = bounds
  }

  private func configureTransparentHost() {
    translatesAutoresizingMaskIntoConstraints = true
    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor
    layer?.isOpaque = false
    layer?.masksToBounds = false
    hostingView.wantsLayer = true
    hostingView.layer?.backgroundColor = NSColor.clear.cgColor
    hostingView.layer?.isOpaque = false
    hostingView.layer?.masksToBounds = false
  }
}

