import AppKit
import ApplicationServices
import Carbon
import CoreImage
import CoreGraphics
import ImageIO
import ScreenCaptureKit
import SwiftUI
import UniformTypeIdentifiers

struct RegionSelectionResult {
  let selectionRectInScreen: CGRect
  let captureType: CaptureContentType
}

@MainActor
final class RegionSelectionOverlayController {
  private let settings: AppSettings
  private var window: RegionSelectionWindow?
  private weak var selectionView: RegionSelectionView?

  init(settings: AppSettings = .shared) {
    self.settings = settings
  }

  func beginSelection(
    onScreenFrame frame: CGRect,
    frozenImage: CGImage,
    onComplete: @escaping (RegionSelectionResult?) -> Void
  ) {
    guard !frame.isNull, !frame.isEmpty else {
      onComplete(nil)
      return
    }

    closeWindow(animated: false)

    let window = RegionSelectionWindow(
      contentRect: frame,
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )
    window.isReleasedWhenClosed = false
    window.level = .screenSaver
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    window.backgroundColor = .clear
    window.isOpaque = false
    window.hasShadow = false
    window.ignoresMouseEvents = false
    window.acceptsMouseMovedEvents = true
    window.animationBehavior = .none

    let selectionView = RegionSelectionView(
      frame: CGRect(origin: .zero, size: frame.size),
      frozenImage: frozenImage,
      settings: settings
    )

    selectionView.onSelectionResult = { [weak self, weak window] localRect, captureType in
      guard let self, let window else {
        onComplete(nil)
        return
      }

      guard let localRect else {
        self.closeWindow {
          onComplete(nil)
        }
        return
      }

      let globalRect = localRect
        .offsetBy(dx: window.frame.origin.x, dy: window.frame.origin.y)
        .standardized

      onComplete(RegionSelectionResult(selectionRectInScreen: globalRect, captureType: captureType))
    }

    selectionView.onCancelRequested = { [weak self] in
      guard let self else {
        onComplete(nil)
        return
      }
      self.closeWindow {
        onComplete(nil)
      }
    }
    selectionView.onCancelRequestedImmediately = { [weak self] in
      guard let self else {
        onComplete(nil)
        return
      }
      self.closeWindow(animated: false) {
        onComplete(nil)
      }
    }

    window.onCancel = { [weak selectionView] in
      selectionView?.handleCancelShortcut()
    }
    window.onUndo = { [weak selectionView] in
      selectionView?.performUndoShortcut()
    }
    window.onRedo = { [weak selectionView] in
      selectionView?.performRedoShortcut()
    }
    window.onCopy = { [weak selectionView] in
      selectionView?.performCopyShortcut()
    }
    window.onSave = { [weak selectionView] in
      selectionView?.performSaveShortcut()
    }
    if selectionView.stitchCaptureFeatureVisible {
      window.onAddStitchSegment = { [weak selectionView] in
        selectionView?.performAddStitchSegmentShortcut()
      }
      window.onResetStitch = { [weak selectionView] in
        selectionView?.performResetStitchShortcut()
      }
    }
    window.onZoomIn = { [weak selectionView] in
      selectionView?.performZoomInShortcut()
    }
    window.onZoomOut = { [weak selectionView] in
      selectionView?.performZoomOutShortcut()
    }
    window.onZoomReset = { [weak selectionView] in
      selectionView?.performZoomResetShortcut()
    }
    window.onSelectToolByShortcutIndex = { [weak selectionView] index in
      selectionView?.performSelectToolShortcut(index: index) ?? false
    }
    window.onCycleTools = { [weak selectionView] reverse in
      selectionView?.performCycleToolShortcut(reverse: reverse) ?? false
    }
    window.onCycleCaptureType = { [weak selectionView] in
      selectionView?.performCycleCaptureTypeShortcut() ?? false
    }
    window.onCycleCaptureModes = { [weak selectionView] reverse in
      selectionView?.performCycleCaptureModeShortcut(reverse: reverse) ?? false
    }
    window.onSelectCaptureMode = { [weak selectionView] captureMode in
      selectionView?.performCaptureModeShortcut(captureMode) ?? false
    }
    window.onToggleVideoSystemAudio = { [weak selectionView] in
      selectionView?.performToggleVideoSystemAudioShortcut() ?? false
    }
    window.onToggleVideoMicrophone = { [weak selectionView] in
      selectionView?.performToggleVideoMicrophoneShortcut() ?? false
    }
    window.onToggleVideoWebcam = { [weak selectionView] in
      selectionView?.performToggleVideoWebcamShortcut() ?? false
    }
    window.onToggleVideoMouseClicks = { [weak selectionView] in
      selectionView?.performToggleVideoMouseClicksShortcut() ?? false
    }
    window.onToggleVideoKeystrokes = { [weak selectionView] in
      selectionView?.performToggleVideoKeystrokesShortcut() ?? false
    }
    window.onCycleVideoCountdown = { [weak selectionView] in
      selectionView?.performCycleVideoCountdownShortcut() ?? false
    }
    window.onToggleVideoRecording = { [weak selectionView] in
      selectionView?.performToggleVideoRecordingShortcut() ?? false
    }

    window.contentView = selectionView
    self.window = window
    self.selectionView = selectionView

    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(selectionView)
    window.invalidateCursorRects(for: selectionView)
    NSCursor.crosshair.set()
    animateCaptureOverlayIn(window)
  }

  func enterEditing(
    session: RustDocumentSession?,
    selectionRectInScreen: CGRect,
    initialCaptureType: CaptureContentType,
    onStartVideo: @escaping (CGRect, @escaping (Bool) -> Void) -> Void,
    onStopVideo: @escaping () -> Void,
    onDone: @escaping () -> Void
  ) {
    guard let window, let selectionView else {
      onDone()
      return
    }

    let localRect = selectionRectInScreen
      .offsetBy(dx: -window.frame.origin.x, dy: -window.frame.origin.y)
      .standardized
      .integral

    selectionView.enterEditing(
      session: session,
      selectionRect: localRect,
      initialCaptureType: initialCaptureType
    ) { [weak self] animateClose in
      guard let self else {
        onDone()
        return
      }
      self.closeWindow(animated: animateClose) {
        onDone()
      }
    }

    selectionView.onStartVideoRequested = { [weak window] localRect, completion in
      guard let window else {
        completion(false)
        return
      }
      let globalRect = localRect
        .offsetBy(dx: window.frame.origin.x, dy: window.frame.origin.y)
        .standardized
      onStartVideo(globalRect, completion)
    }

    selectionView.onStopVideoRequested = { [weak self] in
      self?.closeWindow()
      onStopVideo()
    }

    window.makeFirstResponder(selectionView)
  }

  func closeFlow(animated: Bool = true, completion: (() -> Void)? = nil) {
    closeWindow(animated: animated, completion: completion)
  }

  private func closeWindow(animated: Bool = true, completion: (() -> Void)? = nil) {
    guard let closingWindow = window else {
      selectionView = nil
      completion?()
      return
    }

    let closingSelectionView = selectionView
    window = nil
    selectionView = nil

    guard animated else {
      disposeWindow(closingWindow, selectionView: closingSelectionView)
      completion?()
      return
    }

    animateCaptureOverlayOut(
      closingWindow,
      selectionView: closingSelectionView,
      completion: completion
    )
  }

  private func animateCaptureOverlayIn(_ window: NSWindow) {
    let style = settings.captureTransitionStyle
    let duration = transitionDuration(entering: true, style: style)

    switch style {
    case .none:
      window.alphaValue = 1
    case .fade:
      window.alphaValue = 0
      NSAnimationContext.runAnimationGroup { context in
        context.duration = duration
        context.timingFunction = CAMediaTimingFunction(name: .easeOut)
        window.animator().alphaValue = 1
      }
    case .ripple:
      window.alphaValue = 0
      NSAnimationContext.runAnimationGroup { context in
        context.duration = duration * 0.78
        context.timingFunction = CAMediaTimingFunction(name: .easeOut)
        window.animator().alphaValue = 1
      }
      applyCenterRippleTransition(to: window, entering: true, duration: duration)
    case .liquidDrop, .zoomBlur, .waterWave:
      window.alphaValue = 1
      applyShaderTransition(to: window, style: style, entering: true, duration: duration)
    }
  }

  private func animateCaptureOverlayOut(
    _ window: NSWindow,
    selectionView: RegionSelectionView?,
    completion: (() -> Void)? = nil
  ) {
    let style = settings.captureTransitionStyle
    let duration = transitionDuration(entering: false, style: style)

    switch style {
    case .none:
      disposeWindow(window, selectionView: selectionView)
      completion?()
    case .fade:
      window.alphaValue = 1
      NSAnimationContext.runAnimationGroup { context in
        context.duration = duration
        context.timingFunction = CAMediaTimingFunction(name: .easeIn)
        window.animator().alphaValue = 0
      } completionHandler: { [weak self] in
        MainActor.assumeIsolated {
          self?.disposeWindow(window, selectionView: selectionView)
          completion?()
        }
      }
    case .ripple:
      window.alphaValue = 1
      NSAnimationContext.runAnimationGroup { context in
        context.duration = duration * 0.86
        context.timingFunction = CAMediaTimingFunction(name: .easeIn)
        window.animator().alphaValue = 0
      }
      applyCenterRippleTransition(to: window, entering: false, duration: duration) { [weak self] in
        self?.disposeWindow(window, selectionView: selectionView)
        completion?()
      }
    case .liquidDrop, .zoomBlur, .waterWave:
      window.alphaValue = 1
      NSAnimationContext.runAnimationGroup { context in
        context.duration = duration * 0.9
        context.timingFunction = CAMediaTimingFunction(name: .easeIn)
        window.animator().alphaValue = 0
      }
      applyShaderTransition(to: window, style: style, entering: false, duration: duration) { [weak self] in
        self?.disposeWindow(window, selectionView: selectionView)
        completion?()
      }
    }
  }

  private func disposeWindow(_ window: NSWindow, selectionView: RegionSelectionView?) {
    selectionView?.prepareForClose()
    window.contentView = nil
    window.orderOut(nil)
    window.close()
  }

  private func transitionDuration(entering: Bool, style: CaptureTransitionStyle) -> TimeInterval {
    let speed = max(0.8, min(2.4, settings.captureTransitionSpeed))
    let effectiveSpeed = 0.9 + speed * 0.7
    let base: TimeInterval
    switch style {
    case .none:
      return 0
    case .fade:
      base = entering ? 0.12 : 0.1
    case .ripple:
      base = entering ? 0.24 : 0.2
    case .liquidDrop:
      base = entering ? 0.3 : 0.25
    case .zoomBlur:
      base = entering ? 0.2 : 0.17
    case .waterWave:
      base = entering ? 0.33 : 0.28
    }
    return max(0.06, base / effectiveSpeed)
  }

  private func applyShaderTransition(
    to window: NSWindow,
    style: CaptureTransitionStyle,
    entering: Bool,
    duration: TimeInterval,
    completion: (() -> Void)? = nil
  ) {
    guard let contentView = window.contentView else {
      completion?()
      return
    }

    contentView.layoutSubtreeIfNeeded()
    guard let snapshot = snapshotImage(of: contentView),
          let shaderStyle = CaptureShaderTransitionView.ShaderStyle(captureStyle: style)
    else {
      completion?()
      return
    }

    for subview in contentView.subviews where subview is CaptureShaderTransitionView {
      subview.removeFromSuperview()
    }

    let overlay = CaptureShaderTransitionView(
      frame: contentView.bounds,
      snapshot: snapshot,
      style: shaderStyle,
      entering: entering,
      duration: duration,
      intensity: CGFloat(max(0.2, min(1, settings.captureTransitionIntensity))),
      onFinish: completion
    )
    overlay.autoresizingMask = [.width, .height]
    contentView.addSubview(overlay, positioned: .above, relativeTo: nil)
    overlay.start()
  }

  private func snapshotImage(of view: NSView) -> CGImage? {
    let bounds = view.bounds.integral
    guard bounds.width > 2, bounds.height > 2 else {
      return nil
    }

    guard let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: Int(bounds.width),
      pixelsHigh: Int(bounds.height),
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0
    ) else {
      return nil
    }

    view.cacheDisplay(in: bounds, to: bitmap)
    return bitmap.cgImage
  }

  private func applyCenterRippleTransition(
    to window: NSWindow,
    entering: Bool,
    duration: TimeInterval,
    completion: (() -> Void)? = nil
  ) {
    guard let contentView = window.contentView else {
      completion?()
      return
    }

    contentView.layoutSubtreeIfNeeded()
    contentView.wantsLayer = true
    guard let layer = contentView.layer else {
      completion?()
      return
    }

    let intensity = CGFloat(max(0.2, min(1, settings.captureTransitionIntensity)))
    let bounds = layer.bounds
    guard bounds.width > 2, bounds.height > 2 else {
      completion?()
      return
    }

    let center = CGPoint(x: bounds.midX, y: bounds.midY)
    let maxRadius = hypot(bounds.width * 0.5, bounds.height * 0.5) * 1.06
    let minRadius = max(1.5, maxRadius * 0.012)
    let overshootRadius = maxRadius * (1 + 0.018 * intensity)
    let pullInRadius = max(minRadius + 2, maxRadius * (0.925 - 0.04 * intensity))

    let maskLayer = CAShapeLayer()
    maskLayer.frame = bounds
    maskLayer.fillColor = NSColor.black.cgColor
    layer.mask = maskLayer

    let pathAnimation = CAKeyframeAnimation(keyPath: "path")
    pathAnimation.duration = duration
    pathAnimation.isRemovedOnCompletion = true

    if entering {
      pathAnimation.values = [
        rippleCirclePath(center: center, radius: minRadius),
        rippleCirclePath(center: center, radius: maxRadius * 0.9),
        rippleCirclePath(center: center, radius: overshootRadius),
        rippleCirclePath(center: center, radius: maxRadius),
      ]
      pathAnimation.keyTimes = [0, 0.7, 0.9, 1]
      pathAnimation.timingFunctions = [
        CAMediaTimingFunction(name: .easeOut),
        CAMediaTimingFunction(name: .easeOut),
        CAMediaTimingFunction(name: .easeInEaseOut),
      ]
      maskLayer.path = rippleCirclePath(center: center, radius: maxRadius)
    } else {
      pathAnimation.values = [
        rippleCirclePath(center: center, radius: maxRadius),
        rippleCirclePath(center: center, radius: pullInRadius),
        rippleCirclePath(center: center, radius: minRadius),
      ]
      pathAnimation.keyTimes = [0, 0.34, 1]
      pathAnimation.timingFunctions = [
        CAMediaTimingFunction(name: .easeInEaseOut),
        CAMediaTimingFunction(name: .easeIn),
      ]
      maskLayer.path = rippleCirclePath(center: center, radius: minRadius)
    }

    let subtleScale = CAKeyframeAnimation(keyPath: "transform")
    subtleScale.duration = duration
    subtleScale.isRemovedOnCompletion = true
    if entering {
      subtleScale.values = [
        CATransform3DMakeScale(0.994, 0.994, 1),
        CATransform3DMakeScale(1.002 + 0.002 * intensity, 1.002 + 0.002 * intensity, 1),
        CATransform3DIdentity,
      ]
      subtleScale.keyTimes = [0, 0.62, 1]
      subtleScale.timingFunctions = [
        CAMediaTimingFunction(name: .easeOut),
        CAMediaTimingFunction(name: .easeInEaseOut),
      ]
    } else {
      subtleScale.values = [
        CATransform3DIdentity,
        CATransform3DMakeScale(0.996, 0.996, 1),
        CATransform3DMakeScale(0.99 - 0.006 * intensity, 0.99 - 0.006 * intensity, 1),
      ]
      subtleScale.keyTimes = [0, 0.4, 1]
      subtleScale.timingFunctions = [
        CAMediaTimingFunction(name: .easeInEaseOut),
        CAMediaTimingFunction(name: .easeIn),
      ]
    }

    CATransaction.begin()
    CATransaction.setCompletionBlock { [weak layer] in
      layer?.mask = nil
      completion?()
    }
    maskLayer.add(pathAnimation, forKey: entering ? "capture.centerRipple.in" : "capture.centerRipple.out")
    layer.add(subtleScale, forKey: entering ? "capture.centerRipple.scale.in" : "capture.centerRipple.scale.out")
    CATransaction.commit()
  }

  private func rippleCirclePath(center: CGPoint, radius: CGFloat) -> CGPath {
    let clampedRadius = max(1, radius)
    let rect = CGRect(
      x: center.x - clampedRadius,
      y: center.y - clampedRadius,
      width: clampedRadius * 2,
      height: clampedRadius * 2
    )
    return CGPath(ellipseIn: rect, transform: nil)
  }
}
final class RegionSelectionWindow: NSWindow {
  var onUndo: (() -> Void)?
  var onRedo: (() -> Void)?
  var onCopy: (() -> Void)?
  var onSave: (() -> Void)?
  var onAddStitchSegment: (() -> Void)?
  var onResetStitch: (() -> Void)?
  var onZoomIn: (() -> Void)?
  var onZoomOut: (() -> Void)?
  var onZoomReset: (() -> Void)?
  var onSelectToolByShortcutIndex: ((Int) -> Bool)?
  var onCycleTools: ((Bool) -> Bool)?
  var onCycleCaptureType: (() -> Bool)?
  var onCycleCaptureModes: ((Bool) -> Bool)?
  var onSelectCaptureMode: ((CaptureMode) -> Bool)?
  var onToggleVideoSystemAudio: (() -> Bool)?
  var onToggleVideoMicrophone: (() -> Bool)?
  var onToggleVideoWebcam: (() -> Bool)?
  var onToggleVideoMouseClicks: (() -> Bool)?
  var onToggleVideoKeystrokes: (() -> Bool)?
  var onCycleVideoCountdown: (() -> Bool)?
  var onToggleVideoRecording: (() -> Bool)?
  var onCancel: (() -> Void)?

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if handleCommandShortcuts(event) {
      return true
    }
    return super.performKeyEquivalent(with: event)
  }

  override func keyDown(with event: NSEvent) {
    if event.keyCode == 53 { // Esc
      onCancel?()
      return
    }
    if event.keyCode == UInt16(kVK_Tab) {
      let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
      let allowedFlags: NSEvent.ModifierFlags = [.shift, .control]
      if flags.subtracting(allowedFlags).isEmpty {
        if flags.contains(.control) {
          let reverse = flags.contains(.shift)
          if onCycleCaptureModes?(reverse) == true {
            return
          }
        } else if flags.contains(.shift) {
          if onCycleCaptureType?() == true {
            return
          }
        } else if onCycleTools?(false) == true {
          return
        }
      }
    }
    if handleCommandShortcuts(event) {
      return
    }
    super.keyDown(with: event)
  }

  private func handleCommandShortcuts(_ event: NSEvent) -> Bool {
    guard event.type == .keyDown else {
      return false
    }

    guard let key = event.charactersIgnoringModifiers?.lowercased() else {
      return false
    }

    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    guard flags.contains(.command) else {
      return false
    }

    let allowedFlags: NSEvent.ModifierFlags = [.command, .shift, .option]
    if !flags.subtracting(allowedFlags).isEmpty {
      return false
    }

    if flags == .command,
       let index = shortcutIndexForToolSelection(from: event)
    {
      if onSelectToolByShortcutIndex?(index) == true {
        return true
      }
    }

    if flags == [.command, .option] {
      switch event.keyCode {
      case UInt16(kVK_ANSI_A):
        return onToggleVideoSystemAudio?() == true
      case UInt16(kVK_ANSI_M):
        return onToggleVideoMicrophone?() == true
      case UInt16(kVK_ANSI_W):
        return onToggleVideoWebcam?() == true
      case UInt16(kVK_ANSI_L):
        return onToggleVideoMouseClicks?() == true
      case UInt16(kVK_ANSI_K):
        return onToggleVideoKeystrokes?() == true
      case UInt16(kVK_ANSI_T):
        return onCycleVideoCountdown?() == true
      case UInt16(kVK_ANSI_R):
        return onToggleVideoRecording?() == true
      default:
        break
      }
    }

    switch key {
    case "z":
      if flags == [.command, .shift] {
        onRedo?()
        return true
      }
      if flags == .command {
        onUndo?()
        return true
      }
    case "c":
      if flags == .command {
        onCopy?()
        return true
      }
    case "s":
      if flags == .command {
        onSave?()
        return true
      }
    case "n":
      if flags == .command,
         let onAddStitchSegment
      {
        onAddStitchSegment()
        return true
      }
    case "r":
      if flags == .command,
         let onResetStitch
      {
        onResetStitch()
        return true
      }
    case "+", "=":
      if flags == .command || flags == [.command, .shift] {
        onZoomIn?()
        return true
      }
    case "-":
      if flags == .command {
        onZoomOut?()
        return true
      }
    case "0":
      if flags == .command {
        onZoomReset?()
        return true
      }
    default:
      break
    }

    return false
  }

  private func shortcutIndexForToolSelection(from event: NSEvent) -> Int? {
    let keyCode = event.keyCode

    if keyCode >= UInt16(kVK_ANSI_1), keyCode <= UInt16(kVK_ANSI_9) {
      return Int(keyCode - UInt16(kVK_ANSI_1) + 1)
    }

    if keyCode >= UInt16(kVK_ANSI_Keypad1), keyCode <= UInt16(kVK_ANSI_Keypad9) {
      return Int(keyCode - UInt16(kVK_ANSI_Keypad1) + 1)
    }

    if let chars = event.charactersIgnoringModifiers,
       let value = Int(chars),
       (1...9).contains(value)
    {
      return value
    }

    return nil
  }
}

enum ResizeCorner: CaseIterable {
  case topLeft
  case top
  case topRight
  case right
  case bottom
  case left
  case bottomLeft
  case bottomRight

  var cursor: NSCursor {
    .openHand
  }

  var isCorner: Bool {
    switch self {
    case .topLeft, .topRight, .bottomLeft, .bottomRight:
      return true
    case .top, .right, .bottom, .left:
      return false
    }
  }
}

@MainActor
final class ResizeHandleView: NSView {
  let corner: ResizeCorner

  var onDragStart: ((ResizeCorner) -> Void)?
  var onDragChanged: ((ResizeCorner, CGPoint) -> Void)?
  var onDragEnd: ((ResizeCorner, CGPoint) -> Void)?

  private var startPointInWindow: CGPoint?
  private var pushedClosedHandCursor = false

  init(corner: ResizeCorner) {
    self.corner = corner
    super.init(frame: .zero)
    wantsLayer = false
    isHidden = true
    alphaValue = 1
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  override var acceptsFirstResponder: Bool {
    false
  }

  override var isOpaque: Bool {
    false
  }

  override func resetCursorRects() {
    addCursorRect(bounds, cursor: corner.cursor)
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    let diameter: CGFloat = corner.isCorner ? 9.8 : 8.6
    let rect = CGRect(
      x: (bounds.width - diameter) * 0.5,
      y: (bounds.height - diameter) * 0.5,
      width: diameter,
      height: diameter
    )

    NSColor.black.withAlphaComponent(0.76).setFill()
    NSBezierPath(ovalIn: rect).fill()

    NSColor.white.withAlphaComponent(0.96).setStroke()
    let stroke = NSBezierPath(ovalIn: rect.insetBy(dx: 0.35, dy: 0.35))
    stroke.lineWidth = 1.1
    stroke.stroke()
  }

  override func mouseDown(with event: NSEvent) {
    startPointInWindow = event.locationInWindow
    NSCursor.closedHand.push()
    pushedClosedHandCursor = true
    onDragStart?(corner)
  }

  override func mouseDragged(with event: NSEvent) {
    guard let startPointInWindow else {
      return
    }
    let current = event.locationInWindow
    let delta = CGPoint(x: current.x - startPointInWindow.x, y: current.y - startPointInWindow.y)
    onDragChanged?(corner, delta)
  }

  override func mouseUp(with event: NSEvent) {
    defer {
      if pushedClosedHandCursor {
        NSCursor.pop()
        pushedClosedHandCursor = false
      }
      startPointInWindow = nil
    }
    guard let startPointInWindow else {
      return
    }
    let current = event.locationInWindow
    let delta = CGPoint(x: current.x - startPointInWindow.x, y: current.y - startPointInWindow.y)
    onDragEnd?(corner, delta)
  }
}

@MainActor
final class SelectionMaskOverlayView: NSView {
  enum DisplayStyle: Equatable {
    case selection
    case windowHighlight
  }

  var selectionRect: CGRect = .zero {
    didSet {
      if oldValue != selectionRect {
        needsDisplay = true
      }
    }
  }
  var displayStyle: DisplayStyle = .selection {
    didSet {
      if oldValue != displayStyle {
        needsDisplay = true
      }
    }
  }

  override var isOpaque: Bool {
    false
  }

  override func hitTest(_: NSPoint) -> NSView? {
    nil
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    guard let context = NSGraphicsContext.current?.cgContext else {
      return
    }

    guard !selectionRect.isNull, !selectionRect.isEmpty else {
      return
    }

    let selection = selectionRect.standardized.integral

    let dimPath = CGMutablePath()
    dimPath.addRect(bounds)
    dimPath.addRect(selection)

    context.setFillColor(NSColor.black.withAlphaComponent(displayStyle == .windowHighlight ? 0.46 : 0.5).cgColor)
    context.addPath(dimPath)
    context.drawPath(using: .eoFill)

    if displayStyle == .windowHighlight {
      context.setStrokeColor(NSColor.white.withAlphaComponent(0.94).cgColor)
      context.setLineWidth(2.1)
      context.stroke(selection.insetBy(dx: -0.5, dy: -0.5))
    } else {
      context.setStrokeColor(NSColor.white.withAlphaComponent(0.86).cgColor)
      context.setLineWidth(1.4)
      context.setLineDash(phase: 0, lengths: [6, 4])
      context.stroke(selection.insetBy(dx: -0.5, dy: -0.5))
      context.setLineDash(phase: 0, lengths: [])
      drawHandleDots(in: context, selection: selection)
    }
  }

  private func drawHandleDots(in context: CGContext, selection: CGRect) {
    let minX = selection.minX
    let midX = selection.midX
    let maxX = selection.maxX
    let minY = selection.minY
    let midY = selection.midY
    let maxY = selection.maxY

    let points: [(CGPoint, Bool)] = [
      (CGPoint(x: minX, y: maxY), true),
      (CGPoint(x: midX, y: maxY), false),
      (CGPoint(x: maxX, y: maxY), true),
      (CGPoint(x: maxX, y: midY), false),
      (CGPoint(x: maxX, y: minY), true),
      (CGPoint(x: midX, y: minY), false),
      (CGPoint(x: minX, y: minY), true),
      (CGPoint(x: minX, y: midY), false),
    ]

    for (point, isCorner) in points {
      let radius: CGFloat = isCorner ? 5.2 : 4.7
      let rect = CGRect(
        x: point.x - radius,
        y: point.y - radius,
        width: radius * 2,
        height: radius * 2
      )
      context.setFillColor(NSColor.black.withAlphaComponent(0.76).cgColor)
      context.fillEllipse(in: rect)
      context.setStrokeColor(NSColor.white.withAlphaComponent(0.96).cgColor)
      context.setLineWidth(1.1)
      context.strokeEllipse(in: rect.insetBy(dx: 0.35, dy: 0.35))
    }
  }
}
