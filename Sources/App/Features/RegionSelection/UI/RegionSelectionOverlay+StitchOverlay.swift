import AppKit
import CoreGraphics
import SwiftUI

@MainActor
extension RegionSelectionView {
  func captureFrameForStitchRecording(
    screenFrame: CGRect,
    captureRectInScreen: CGRect
  ) async -> CGImage? {
    guard let capturedImage = await captureScreenImage(frame: screenFrame) else {
      return nil
    }

    return ScreenshotImage.cropScreenRect(
      from: capturedImage,
      captureRectInScreen: captureRectInScreen,
      screenFrame: screenFrame
    )
  }

  func restoreOverlayWindowAfterStitchCapture(_ overlayWindow: NSWindow?) {
    stitchState.passThroughOverlayActive = false
    guard let overlayWindow else {
      needsLayout = true
      needsDisplay = true
      return
    }
    overlayWindow.ignoresMouseEvents = false
    NSApp.activate(ignoringOtherApps: true)
    overlayWindow.makeKeyAndOrderFront(nil)
    overlayWindow.makeFirstResponder(self)
    overlayWindow.invalidateCursorRects(for: self)
    needsLayout = true
    needsDisplay = true
  }

  func beginStitchPassThroughOverlay(on overlayWindow: NSWindow, captureRectInScreen: CGRect) {
    stitchState.passThroughOverlayActive = true
    overlayWindow.ignoresMouseEvents = true
    canvasView.finishInlineTextEditing(commit: true)
    setResizeHandlesHidden(true)
    needsLayout = true
    needsDisplay = true
    overlayWindow.invalidateCursorRects(for: self)

    if stitchState.autoScrollEnabled, stitchState.autoScrollTrusted {
      if stitchState.targetApp == nil || stitchState.targetApp?.isTerminated == true {
        let targetPoint = CGPoint(x: captureRectInScreen.midX, y: captureRectInScreen.midY)
        stitchState.targetApp = resolveStitchTargetApp(at: targetPoint)
      }
      stitchState.targetApp?.activate(options: [])
    }
  }

  func showStitchControlPanel() {
    guard stitchState.recordingActive, let overlayWindow = window else {
      return
    }

    let host = NSHostingView(
      rootView: StitchRecordingFloatingBar(
        onStop: { [weak self] in
          self?.stopStitchRecording(applyResult: true)
        }
      )
    )
    host.layoutSubtreeIfNeeded()
    var panelSize = host.fittingSize
    if panelSize.width < 150 || panelSize.height < 40 {
      panelSize = CGSize(width: 164, height: 44)
    }
    host.frame = CGRect(origin: .zero, size: panelSize)

    let panel: NSPanel
    if let existing = stitchControlPanel {
      panel = existing
      panel.setContentSize(panelSize)
    } else {
      panel = NSPanel(
        contentRect: CGRect(origin: .zero, size: panelSize),
        styleMask: [.nonactivatingPanel, .borderless],
        backing: .buffered,
        defer: false
      )
      panel.isReleasedWhenClosed = false
      panel.isOpaque = false
      panel.backgroundColor = .clear
      panel.hasShadow = true
      panel.level = NSWindow.Level(rawValue: max(NSWindow.Level.statusBar.rawValue, overlayWindow.level.rawValue + 2))
      panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
      panel.hidesOnDeactivate = false
      panel.ignoresMouseEvents = false
      panel.isMovable = false
      panel.isMovableByWindowBackground = false
      stitchControlPanel = panel
    }

    panel.contentView = host
    positionStitchControlPanel(panel, relativeTo: overlayWindow)
    panel.orderFrontRegardless()
  }

  func positionStitchControlPanel(_ panel: NSPanel, relativeTo overlayWindow: NSWindow) {
    let panelSize = panel.frame.size
    let anchor = committedSelectionRect ?? CGRect(
      x: bounds.midX - 140,
      y: bounds.midY - 80,
      width: 280,
      height: 160
    )

    let margin: CGFloat = 14
    let maxX = max(margin, bounds.width - panelSize.width - margin)
    var localX = anchor.midX - panelSize.width * 0.5
    localX = min(max(margin, localX), maxX)

    var localY = anchor.minY - panelSize.height - 12
    if localY < margin {
      let maxY = max(margin, bounds.height - panelSize.height - margin)
      localY = min(max(margin, anchor.maxY + 12), maxY)
    }

    panel.setFrame(
      CGRect(
        x: overlayWindow.frame.minX + localX,
        y: overlayWindow.frame.minY + localY,
        width: panelSize.width,
        height: panelSize.height
      ).integral,
      display: false
    )
  }

  func hideStitchControlPanel() {
    stitchControlPanel?.orderOut(nil)
    stitchControlPanel = nil
  }

  func captureScreenImage(frame: CGRect) async -> CGImage? {
    await ScreenCaptureSnapshot.captureImageIfAvailable(inCocoaScreenRect: frame)
  }
}
