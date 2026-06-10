import AppKit
import Foundation
import SwiftUI

@MainActor
final class RecordingKeystrokeOverlayView: RecordingDraggableOverlayView {
  private let style: KeystrokeStyle
  private let size: KeystrokeSize
  private let hostingView: NSHostingView<KeystrokeOverlayGlassCapsule>
  private var currentToken = "⌘K"
  private var restoreTimer: Timer?

  override var allowsResizing: Bool { true }
  override var minimumFrameSize: CGSize { CGSize(width: 112, height: 42) }

  init(
    normalizedFrame: CGRect,
    style: KeystrokeStyle,
    size: KeystrokeSize
  ) {
    self.style = style
    self.size = size
    hostingView = NSHostingView(
      rootView: KeystrokeOverlayGlassCapsule(
        text: "⌘K",
        style: style,
        size: size,
        showsResizeGrip: true
      )
    )
    super.init(normalizedFrame: normalizedFrame)
    layer?.masksToBounds = false
    hostingView.translatesAutoresizingMaskIntoConstraints = true
    hostingView.wantsLayer = true
    hostingView.layer?.backgroundColor = NSColor.clear.cgColor
    addSubview(hostingView)
  }

  func showToken(_ token: String) {
    currentToken = token.isEmpty ? "Key" : token
    refreshHostedView()
    restoreTimer?.invalidate()
    restoreTimer = Timer.scheduledTimer(withTimeInterval: 1.35, repeats: false) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.currentToken = "⌘K"
        self?.refreshHostedView()
      }
    }
  }

  override func layout() {
    super.layout()
    hostingView.frame = bounds
  }

  private func refreshHostedView() {
    hostingView.rootView = KeystrokeOverlayGlassCapsule(
      text: currentToken,
      style: style,
      size: size,
      showsResizeGrip: true
    )
  }
}
