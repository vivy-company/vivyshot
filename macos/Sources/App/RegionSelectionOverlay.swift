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
        self.closeWindow()
        onComplete(nil)
        return
      }

      let globalRect = localRect
        .offsetBy(dx: window.frame.origin.x, dy: window.frame.origin.y)
        .standardized

      onComplete(RegionSelectionResult(selectionRectInScreen: globalRect, captureType: captureType))
    }

    selectionView.onCancelRequested = { [weak self] in
      self?.closeWindow()
      onComplete(nil)
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
    window.onAddStitchSegment = { [weak selectionView] in
      selectionView?.performAddStitchSegmentShortcut()
    }
    window.onResetStitch = { [weak selectionView] in
      selectionView?.performResetStitchShortcut()
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
    session: RustDocumentSession,
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
      self?.closeWindow(animated: animateClose)
      onDone()
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

  func closeFlow() {
    closeWindow()
  }

  private func closeWindow(animated: Bool = true) {
    guard let closingWindow = window else {
      selectionView = nil
      return
    }

    let closingSelectionView = selectionView
    window = nil
    selectionView = nil

    guard animated else {
      disposeWindow(closingWindow, selectionView: closingSelectionView)
      return
    }

    animateCaptureOverlayOut(closingWindow, selectionView: closingSelectionView)
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

  private func animateCaptureOverlayOut(_ window: NSWindow, selectionView: RegionSelectionView?) {
    let style = settings.captureTransitionStyle
    let duration = transitionDuration(entering: false, style: style)

    switch style {
    case .none:
      disposeWindow(window, selectionView: selectionView)
    case .fade:
      window.alphaValue = 1
      NSAnimationContext.runAnimationGroup { context in
        context.duration = duration
        context.timingFunction = CAMediaTimingFunction(name: .easeIn)
        window.animator().alphaValue = 0
      } completionHandler: { [weak self] in
        MainActor.assumeIsolated {
          self?.disposeWindow(window, selectionView: selectionView)
        }
      }
    case .ripple:
      window.alphaValue = 1
      NSAnimationContext.runAnimationGroup { context in
        context.duration = duration * 0.86
        context.timingFunction = CAMediaTimingFunction(name: .easeIn)
        window.animator().alphaValue = 0
      }
      applyCenterRippleTransition(to: window, entering: false, duration: duration) {
        self.disposeWindow(window, selectionView: selectionView)
      }
    case .liquidDrop, .zoomBlur, .waterWave:
      window.alphaValue = 1
      NSAnimationContext.runAnimationGroup { context in
        context.duration = duration * 0.9
        context.timingFunction = CAMediaTimingFunction(name: .easeIn)
        window.animator().alphaValue = 0
      }
      applyShaderTransition(to: window, style: style, entering: false, duration: duration) {
        self.disposeWindow(window, selectionView: selectionView)
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

@MainActor
private final class RegionSelectionWindow: NSWindow {
  var onUndo: (() -> Void)?
  var onRedo: (() -> Void)?
  var onCopy: (() -> Void)?
  var onSave: (() -> Void)?
  var onAddStitchSegment: (() -> Void)?
  var onResetStitch: (() -> Void)?
  var onZoomIn: (() -> Void)?
  var onZoomOut: (() -> Void)?
  var onZoomReset: (() -> Void)?
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

    let allowedFlags: NSEvent.ModifierFlags = [.command, .shift]
    if !flags.subtracting(allowedFlags).isEmpty {
      return false
    }

    switch key {
    case "z":
      if flags.contains(.shift) {
        onRedo?()
      } else {
        onUndo?()
      }
      return true
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
      if flags == .command {
        onAddStitchSegment?()
        return true
      }
    case "r":
      if flags == .command {
        onResetStitch?()
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
}

private enum ResizeCorner: CaseIterable {
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
private final class ResizeHandleView: NSView {
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
private final class SelectionMaskOverlayView: NSView {
  var selectionRect: CGRect = .zero {
    didSet {
      if oldValue != selectionRect {
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

    context.setFillColor(NSColor.black.withAlphaComponent(0.5).cgColor)
    context.addPath(dimPath)
    context.drawPath(using: .eoFill)

    context.setStrokeColor(NSColor.white.withAlphaComponent(0.86).cgColor)
    context.setLineWidth(1.4)
    context.setLineDash(phase: 0, lengths: [6, 4])
    context.stroke(selection.insetBy(dx: -0.5, dy: -0.5))
    context.setLineDash(phase: 0, lengths: [])

    drawHandleDots(in: context, selection: selection)
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

@MainActor
private final class RegionSelectionView: NSView {
  private static let captureCameraCursor: NSCursor = {
    let size = NSSize(width: 28, height: 28)
    let image = NSImage(size: size)
    image.lockFocus()

    let circleRect = NSRect(x: 1, y: 1, width: 26, height: 26)
    NSColor.black.withAlphaComponent(0.68).setFill()
    NSBezierPath(ovalIn: circleRect).fill()

    NSColor.white.withAlphaComponent(0.18).setStroke()
    let strokePath = NSBezierPath(ovalIn: circleRect.insetBy(dx: 0.5, dy: 0.5))
    strokePath.lineWidth = 1
    strokePath.stroke()

    if let baseSymbol = NSImage(systemSymbolName: "camera.fill", accessibilityDescription: nil) {
      let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
      let symbol = baseSymbol.withSymbolConfiguration(config) ?? baseSymbol
      NSColor.white.set()
      symbol.draw(in: NSRect(x: 7.5, y: 7.5, width: 13, height: 13))
    }

    image.unlockFocus()
    return NSCursor(image: image, hotSpot: NSPoint(x: size.width * 0.5, y: size.height * 0.5))
  }()

  var onSelectionResult: ((CGRect?, CaptureContentType) -> Void)?
  var onCancelRequested: (() -> Void)?
  var onStartVideoRequested: ((CGRect, @escaping (Bool) -> Void) -> Void)?
  var onStopVideoRequested: (() -> Void)?
  private let settings: AppSettings
  private var settingsObserver: NSObjectProtocol?

  private enum OverlayMode {
    case selecting
    case editing
  }

  private let frozenImage: CGImage

  private var mode: OverlayMode = .selecting {
    didSet {
      editingMaskView.isHidden = mode != .editing
      needsDisplay = true
      window?.invalidateCursorRects(for: self)
      needsLayout = true
      updateSelectingHintVisibility(animated: true)
    }
  }

  private var dragStart: CGPoint?
  private var dragCurrent: CGPoint?
  private var committedSelectionRect: CGRect?

  private var activeResizeCorner: ResizeCorner?
  private var resizeStartRect: CGRect?
  private var resizeHandles: [ResizeCorner: ResizeHandleView] = [:]

  private let canvasView = AnnotationCanvasView()
  private let editingMaskView = SelectionMaskOverlayView()
  private lazy var toolbarHost = NSHostingView(rootView: makeToolbarView())
  private lazy var selectingHintHost = NSHostingView(rootView: CaptureHintGlassCard())
  private lazy var captureTypeHost = NSHostingView(rootView: makeCaptureTypeSidebar())
  private var toolbarOffset: CGSize = .zero
  private var toolbarDragStartOffset: CGSize?
  private var stitchControlPanel: NSPanel?
  private var selectedCaptureType: CaptureContentType
  private var selectedCaptureMode: CaptureMode = .selection
  private var areaCaptureRect: CGRect?
  private var windowCapturePickPending = false
  private var videoRecordingActive = false
  private var videoRecordingStartPending = false

  private var session: RustDocumentSession?
  private var onEditingDone: ((Bool) -> Void)?
  private var stitchModeEnabled = false
  private var stitchCaptureInProgress = false
  private var stitchPassThroughOverlayActive = false
  private var stitchRecordingActive = false
  private var stitchSegmentCount = 1
  private var stitchCaptureTask: Task<Void, Never>?
  private var stitchWorkingImage: CGImage?
  private var stitchLastFrame: CGImage?
  private var stitchDirection: StitchStripSide?
  private var stitchExpectedDeltaRows: Int?
  private var stitchCaptureRectInScreen: CGRect?
  private var preStitchImage: CGImage?
  private var preStitchSelectionRect: CGRect?
  private var postStitchEditorMode = false
  // Keep frame cadence high enough for reliable overlap without overspeeding.
  private let stitchCaptureInterval: TimeInterval = 0.12
  private var stitchAutoScrollEnabled = true
  private var stitchAutoScrollDirectionSign: Int32 = -1
  private var stitchAutoScrollNoMotionTicks = 0
  private var stitchAutoScrollDidFlipDirection = false
  private var stitchAutoScrollPromptAttempted = false
  private var stitchAutoScrollTrusted = false
  private var stitchTargetApp: NSRunningApplication?
  private let stitchAutoScrollStepLines: Int32 = 3
  private let stitchAutoScrollSettleInterval: TimeInterval = 0.11

  private var annotationColor: NSColor = .systemOrange {
    didSet {
      canvasView.accentColor = annotationColor
      textStyle = EditorTextStyle(
        fontSize: textStyle.fontSize,
        color: annotationColor,
        fontName: textStyle.fontName
      )
      refreshToolbar()
      needsDisplay = true
    }
  }

  private var textStyle = EditorTextStyle(fontSize: 16, color: .systemOrange) {
    didSet {
      canvasView.textStyle = textStyle
    }
  }

  private var currentTool: AnnotationTool = .rect {
    didSet {
      canvasView.tool = currentTool
      updateCanvasPreviewStrokeWidth()
      refreshToolbar()
      if currentTool != .text {
        canvasView.finishInlineTextEditing(commit: true)
      }
    }
  }

  init(frame frameRect: NSRect, frozenImage: CGImage, settings: AppSettings) {
    self.frozenImage = frozenImage
    self.settings = settings
    selectedCaptureType = settings.defaultCaptureType
    super.init(frame: frameRect)
    configureEditorSubviews()
    configureCanvasCallbacks()
    observeSettingsChanges()
    applySettingsFromPreferences()
    updateSelectingHintVisibility(animated: false)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  override var acceptsFirstResponder: Bool {
    true
  }

  override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
    true
  }

  override func layout() {
    super.layout()
    layoutEditorChrome()
    layoutSelectingHint()
    layoutCaptureTypePanel()
  }

  override func resetCursorRects() {
    switch mode {
    case .selecting:
      addCursorRect(bounds, cursor: .crosshair)
    case .editing:
      if selectedCaptureMode == .screen || selectedCaptureMode == .window {
        addCursorRect(bounds, cursor: Self.captureCameraCursor)
      } else {
        addCursorRect(bounds, cursor: .arrow)
      }
    }
  }

  override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)

    if mode == .editing {
      if windowCapturePickPending {
        windowCapturePickPending = false
        window?.invalidateCursorRects(for: self)
        if let windowRect = captureRectForWindowPick(at: point) {
          _ = applyCaptureRect(windowRect, as: .window, rememberAsArea: false)
        } else {
          NSSound.beep()
          refreshToolbar()
        }
        return
      }
      super.mouseDown(with: event)
      return
    }

    dragStart = point
    dragCurrent = point
    updateSelectingHintVisibility(animated: true)
    needsLayout = true
    needsDisplay = true
  }

  override func mouseDragged(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)

    if mode == .editing {
      super.mouseDragged(with: event)
      return
    }

    guard dragStart != nil else {
      return
    }

    dragCurrent = point
    needsLayout = true
    needsDisplay = true
  }

  override func mouseUp(with event: NSEvent) {
    if mode == .editing {
      super.mouseUp(with: event)
      return
    }

    guard dragStart != nil else {
      return
    }

    dragCurrent = convert(event.locationInWindow, from: nil)
    let selection = selectionRect().map { $0.integral }

    dragStart = nil
    dragCurrent = nil
    committedSelectionRect = selection
    updateSelectingHintVisibility(animated: true)
    needsLayout = true
    needsDisplay = true

    guard let selection, selection.width >= 2, selection.height >= 2 else {
      NSSound.beep()
      return
    }

    onSelectionResult?(selection, selectedCaptureType)
  }

  override func keyDown(with event: NSEvent) {
    if event.keyCode == 53 { // Esc
      handleCancelShortcut()
      return
    }

    if mode == .selecting {
      switch event.keyCode {
      case UInt16(kVK_ANSI_1):
        setSelectedCaptureType(.screenshot)
        return
      case UInt16(kVK_ANSI_2):
        setSelectedCaptureType(.video)
        return
      default:
        break
      }
    }

    super.keyDown(with: event)
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    guard let context = NSGraphicsContext.current?.cgContext else {
      return
    }

    if stitchPassThroughOverlayActive, mode == .editing {
      drawStitchPassThroughFocus(in: context)
      return
    }

    context.interpolationQuality = .high
    context.draw(frozenImage, in: bounds)

    switch mode {
    case .selecting:
      drawSelectingOverlay(in: context)
    case .editing:
      break
    }
  }

  private func drawStitchPassThroughFocus(in context: CGContext) {
    guard let selection = committedSelectionRect?.standardized.integral else {
      return
    }

    let dimPath = CGMutablePath()
    dimPath.addRect(bounds)
    dimPath.addRect(selection)

    context.saveGState()
    context.addPath(dimPath)
    context.setFillColor(NSColor.black.withAlphaComponent(0.34).cgColor)
    context.drawPath(using: .eoFill)
    context.restoreGState()
  }

  func enterEditing(
    session: RustDocumentSession,
    selectionRect: CGRect,
    initialCaptureType: CaptureContentType,
    onDone: @escaping (Bool) -> Void
  ) {
    let clipped = selectionRect.standardized.intersection(bounds).integral
    guard !clipped.isNull, clipped.width >= 2, clipped.height >= 2 else {
      onDone(true)
      return
    }

    guard let image = session.currentImage() else {
      onDone(true)
      return
    }

    self.session = session
    onEditingDone = onDone
    selectedCaptureType = initialCaptureType
    selectedCaptureMode = .selection
    videoRecordingActive = false
    videoRecordingStartPending = false
    windowCapturePickPending = false
    if selectedCaptureType == .video {
      currentTool = .move
    }
    committedSelectionRect = clipped
    areaCaptureRect = clipped
    activeResizeCorner = nil
    resizeStartRect = nil
    toolbarOffset = .zero
    toolbarDragStartOffset = nil
    stitchModeEnabled = false
    stitchCaptureInProgress = false
    stitchPassThroughOverlayActive = false
    stitchRecordingActive = false
    stitchSegmentCount = 1
    stitchCaptureTask?.cancel()
    stitchCaptureTask = nil
    stitchWorkingImage = nil
    stitchLastFrame = nil
    stitchDirection = nil
    stitchExpectedDeltaRows = nil
    stitchCaptureRectInScreen = nil
    resetStitchAutoScrollState()
    preStitchImage = nil
    preStitchSelectionRect = nil
    postStitchEditorMode = false
    hideStitchControlPanel()

    mode = .editing
    canvasView.image = image
    canvasView.tool = currentTool
    canvasView.accentColor = annotationColor
    updateCanvasPreviewStrokeWidth()
    canvasView.textStyle = textStyle
    canvasView.isHidden = false

    editingMaskView.selectionRect = clipped
    editingMaskView.isHidden = false
    toolbarHost.isHidden = false
    refreshCaptureTypeSidebar()
    refreshToolbar()
    layoutEditorChrome()
    needsLayout = true
    needsDisplay = true
  }

  func prepareForClose() {
    canvasView.finishInlineTextEditing(commit: true)
    canvasView.isHidden = false
    editingMaskView.isHidden = true
    editingMaskView.selectionRect = .zero
    setResizeHandlesHidden(true)
    session = nil
    onEditingDone = nil
    onStartVideoRequested = nil
    onStopVideoRequested = nil
    selectedCaptureMode = .selection
    areaCaptureRect = nil
    windowCapturePickPending = false
    videoRecordingActive = false
    videoRecordingStartPending = false
    stitchModeEnabled = false
    stitchCaptureInProgress = false
    stitchPassThroughOverlayActive = false
    stitchRecordingActive = false
    stitchSegmentCount = 1
    stitchCaptureTask?.cancel()
    stitchCaptureTask = nil
    stitchWorkingImage = nil
    stitchLastFrame = nil
    stitchDirection = nil
    stitchExpectedDeltaRows = nil
    stitchCaptureRectInScreen = nil
    resetStitchAutoScrollState()
    preStitchImage = nil
    preStitchSelectionRect = nil
    postStitchEditorMode = false
    window?.ignoresMouseEvents = false
    hideStitchControlPanel()
  }

  func handleCancelShortcut() {
    switch mode {
    case .selecting:
      onCancelRequested?()
    case .editing:
      if videoRecordingActive {
        stopVideoRecordingFromEditor()
        return
      }
      finishEditing()
    }
  }

  func performUndoShortcut() {
    guard mode == .editing else { return }
    performUndo()
  }

  func performRedoShortcut() {
    guard mode == .editing else { return }
    performRedo()
  }

  func performCopyShortcut() {
    guard mode == .editing else { return }
    performCopy()
  }

  func performSaveShortcut() {
    guard mode == .editing else { return }
    performSave()
  }

  func performAddStitchSegmentShortcut() {
    guard mode == .editing else { return }
    addStitchSegment()
  }

  func performResetStitchShortcut() {
    guard mode == .editing else { return }
    resetStitch()
  }

  func performZoomInShortcut() {
    guard mode == .editing else { return }
    canvasView.zoomIn()
    updateCanvasPreviewStrokeWidth()
  }

  func performZoomOutShortcut() {
    guard mode == .editing else { return }
    canvasView.zoomOut()
    updateCanvasPreviewStrokeWidth()
  }

  func performZoomResetShortcut() {
    guard mode == .editing else { return }
    canvasView.resetZoomAndPan()
    updateCanvasPreviewStrokeWidth()
  }

  private func drawSelectingOverlay(in context: CGContext) {
    let activeSelection = selectionRect() ?? committedSelectionRect
    let dimPath = CGMutablePath()
    dimPath.addRect(bounds)
    if let activeSelection {
      dimPath.addRect(activeSelection)
    }

    context.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor)
    context.addPath(dimPath)
    context.drawPath(using: .eoFill)

    guard let selection = activeSelection else {
      return
    }

    context.setStrokeColor(NSColor.white.withAlphaComponent(0.92).cgColor)
    context.setLineWidth(1.6)
    context.setLineDash(phase: 0, lengths: [6, 4])
    context.stroke(selection)
    context.setLineDash(phase: 0, lengths: [])

    drawSelectionSize(selection)
    drawSelectionCornerGuides(in: context, selection: selection, alpha: 0.96)
  }

  private func configureEditorSubviews() {
    canvasView.translatesAutoresizingMaskIntoConstraints = true
    canvasView.isHidden = true
    canvasView.accentColor = annotationColor
    updateCanvasPreviewStrokeWidth()
    addSubview(canvasView)

    editingMaskView.translatesAutoresizingMaskIntoConstraints = true
    editingMaskView.isHidden = true
    addSubview(editingMaskView)

    selectingHintHost.translatesAutoresizingMaskIntoConstraints = true
    selectingHintHost.alphaValue = 0
    selectingHintHost.isHidden = true
    addSubview(selectingHintHost)

    captureTypeHost.translatesAutoresizingMaskIntoConstraints = true
    captureTypeHost.alphaValue = 1
    captureTypeHost.isHidden = true
    addSubview(captureTypeHost)

    for corner in ResizeCorner.allCases {
      let handle = ResizeHandleView(corner: corner)
      handle.translatesAutoresizingMaskIntoConstraints = true
      handle.isHidden = true
      handle.onDragStart = { [weak self] corner in
        self?.startResizingSelection(corner: corner)
      }
      handle.onDragChanged = { [weak self] corner, delta in
        self?.updateResizingSelection(corner: corner, delta: delta)
      }
      handle.onDragEnd = { [weak self] corner, delta in
        self?.finishResizingSelection(corner: corner, delta: delta)
      }
      resizeHandles[corner] = handle
      addSubview(handle)
    }

    toolbarHost.translatesAutoresizingMaskIntoConstraints = true
    toolbarHost.isHidden = true
    addSubview(toolbarHost)
  }

  private func layoutSelectingHint() {
    selectingHintHost.layoutSubtreeIfNeeded()
    let targetSize = selectingHintHost.fittingSize
    guard targetSize.width > 0, targetSize.height > 0 else {
      return
    }

    let maxWidth = max(240, bounds.width - 40)
    let width = min(targetSize.width, maxWidth)
    let x = floor((bounds.width - width) * 0.5)
    let y = floor((bounds.height - targetSize.height) * 0.5)
    selectingHintHost.frame = CGRect(x: x, y: y, width: width, height: targetSize.height).integral
  }

  private func updateSelectingHintVisibility(animated: Bool) {
    let shouldShow = settings.captureShowHelper
      && mode == .selecting
      && dragStart == nil
      && dragCurrent == nil
      && committedSelectionRect == nil

    if shouldShow {
      layoutSelectingHint()
      if selectingHintHost.isHidden {
        selectingHintHost.alphaValue = 0
        selectingHintHost.isHidden = false
      }
    }

    let targetAlpha: CGFloat = shouldShow ? 1 : 0

    if animated {
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.14
        context.timingFunction = CAMediaTimingFunction(name: .easeOut)
        selectingHintHost.animator().alphaValue = targetAlpha
      } completionHandler: { [weak self] in
        MainActor.assumeIsolated {
          guard let self else {
            return
          }
          if !shouldShow {
            self.selectingHintHost.isHidden = true
          }
        }
      }
      return
    }

    selectingHintHost.alphaValue = targetAlpha
    selectingHintHost.isHidden = !shouldShow
  }

  private func layoutCaptureTypePanel() {
    let activeSelection = (selectionRect() ?? committedSelectionRect)?.standardized
    let hasSelection = {
      guard let activeSelection else {
        return false
      }
      return activeSelection.width >= 2 && activeSelection.height >= 2
    }()
    let shouldShow = (mode == .selecting || mode == .editing) && hasSelection

    guard shouldShow else {
      captureTypeHost.isHidden = true
      return
    }

    captureTypeHost.layoutSubtreeIfNeeded()
    let fit = captureTypeHost.fittingSize
    let panelWidth = max(56, fit.width)
    let panelHeight = max(104, fit.height)

    let padding: CGFloat = 10
    let minX = padding
    let maxX = max(minX, bounds.width - panelWidth - padding)

    let x: CGFloat
    let centeredY: CGFloat
    if let activeSelection {
      var candidateX = activeSelection.minX - panelWidth - 6
      if candidateX < minX {
        candidateX = min(maxX, activeSelection.maxX + 6)
      }
      x = candidateX
      centeredY = activeSelection.midY - panelHeight * 0.5
    } else {
      x = minX
      centeredY = bounds.midY - panelHeight * 0.5
    }

    let y = min(max(padding, centeredY), max(padding, bounds.height - panelHeight - padding))

    captureTypeHost.frame = CGRect(x: x, y: y, width: panelWidth, height: panelHeight).integral
    captureTypeHost.isHidden = false
  }

  private func configureCanvasCallbacks() {
    canvasView.onViewportChanged = { [weak self] in
      self?.updateCanvasPreviewStrokeWidth()
    }
    canvasView.onCommitRect = { [weak self] rect in
      self?.commitRect(rect)
    }
    canvasView.onCommitFilledRect = { [weak self] rect in
      self?.commitFilledRect(rect)
    }
    canvasView.onCommitCircle = { [weak self] rect in
      self?.commitCircle(rect)
    }
    canvasView.onCommitFilledCircle = { [weak self] rect in
      self?.commitFilledCircle(rect)
    }
    canvasView.onCommitLine = { [weak self] start, end in
      self?.commitLine(from: start, to: end)
    }
    canvasView.onCommitArrow = { [weak self] start, end in
      self?.commitArrow(from: start, to: end)
    }
    canvasView.onCommitPaintPath = { [weak self] points in
      self?.commitPaintPath(points)
    }
    canvasView.onCommitText = { [weak self] text, point in
      self?.commitText(text, at: point)
    }
    canvasView.onCommitPixelateRect = { [weak self] rect in
      self?.commitPixelate(rect)
    }
    canvasView.onCommitBlurRect = { [weak self] rect in
      self?.commitBlur(rect)
    }
    canvasView.onHitTestAnnotation = { [weak self] point in
      self?.session?.hitTestAnnotation(at: point)
    }
    canvasView.onMoveAnnotation = { [weak self] index, delta in
      self?.session?.moveAnnotation(index: index, delta: delta)
    }
    canvasView.onResizeAnnotation = { [weak self] index, imageRect in
      self?.session?.resizeAnnotation(index: index, imageRect: imageRect)
    }
    canvasView.onDeleteAnnotation = { [weak self] index in
      self?.session?.removeAnnotation(index: index)
    }
    canvasView.onBeginMovingCaptureArea = { [weak self] in
      self?.beginMovingCapturedSelectionPreview()
    }
    canvasView.onMoveCaptureArea = { [weak self] delta in
      guard let self, !self.stitchModeEnabled else {
        return false
      }
      return self.moveCapturedSelection(by: delta)
    }
    canvasView.onFinishMovingCaptureArea = { [weak self] in
      self?.finishMovingCapturedSelection()
    }
  }

  private func layoutEditorChrome() {
    guard mode == .editing else {
      canvasView.isHidden = true
      toolbarHost.isHidden = true
      editingMaskView.isHidden = true
      setResizeHandlesHidden(true)
      return
    }

    if stitchPassThroughOverlayActive {
      canvasView.isHidden = true
      editingMaskView.isHidden = true
      toolbarHost.isHidden = true
      setResizeHandlesHidden(true)
      return
    }

    let selection = committedSelectionRect?.standardized.integral
    let hidesSelectionFrame = selectedCaptureMode == .screen
    let toolbarAnchorSelection = hidesSelectionFrame ? nil : selection
    let isPostStitchEditor = postStitchEditorMode && selection == nil
    let topChromeHeight: CGFloat = isPostStitchEditor ? 68 : 0
    let canvasFrame = CGRect(
      x: bounds.minX,
      y: bounds.minY,
      width: bounds.width,
      height: max(1, bounds.height - topChromeHeight)
    ).integral

    canvasView.frame = canvasFrame
    editingMaskView.frame = bounds

    canvasView.isHidden = false
    toolbarHost.isHidden = false
    updateCanvasPreviewStrokeWidth()

    if let selection, !hidesSelectionFrame {
      editingMaskView.selectionRect = selection
      editingMaskView.isHidden = false
    } else {
      editingMaskView.selectionRect = .zero
      editingMaskView.isHidden = true
    }

    toolbarHost.layoutSubtreeIfNeeded()
    var toolbarSize = toolbarHost.fittingSize
    if toolbarSize.width < 300 || toolbarSize.height < 30 {
      toolbarSize = CGSize(width: 430, height: 54)
    }

    let padding: CGFloat = 12
    let maxX = max(padding, bounds.width - toolbarSize.width - padding)

    let defaultX: CGFloat
    let defaultY: CGFloat
    let minY: CGFloat
    let maxY: CGFloat
    if let selection = toolbarAnchorSelection {
      minY = padding
      maxY = max(padding, bounds.height - toolbarSize.height - padding)
      defaultX = min(max(padding, selection.midX - toolbarSize.width * 0.5), maxX)
      let proposedBelow = selection.minY - toolbarSize.height - 14
      if proposedBelow >= padding {
        defaultY = proposedBelow
      } else {
        defaultY = min(maxY, selection.maxY + 14)
      }
    } else if hidesSelectionFrame {
      // Full-screen mode: keep controls centered near the bottom edge.
      minY = padding
      maxY = max(padding, bounds.height - toolbarSize.height - padding)
      defaultX = min(max(padding, bounds.midX - toolbarSize.width * 0.5), maxX)
      defaultY = min(maxY, padding + 18)
    } else if isPostStitchEditor {
      // Default to top-right for long stitched screenshots.
      minY = padding
      maxY = max(padding, bounds.height - toolbarSize.height - padding)
      defaultX = maxX - 4
      defaultY = maxY
    } else {
      minY = padding
      maxY = max(padding, bounds.height - toolbarSize.height - padding)
      defaultX = min(max(padding, bounds.midX - toolbarSize.width * 0.5), maxX)
      defaultY = maxY
    }

    let unclampedX = defaultX + toolbarOffset.width
    let unclampedY = defaultY + toolbarOffset.height
    let x = min(max(padding, unclampedX), maxX)
    let y = min(max(minY, unclampedY), maxY)
    toolbarOffset = CGSize(width: x - defaultX, height: y - defaultY)

    toolbarHost.frame = CGRect(
      x: x,
      y: y,
      width: toolbarSize.width,
      height: toolbarSize.height
    ).integral

    if stitchModeEnabled || selection == nil || hidesSelectionFrame {
      setResizeHandlesHidden(true)
    } else if let selection {
      layoutResizeHandles(for: selection)
    }
  }

  private func setResizeHandlesHidden(_ hidden: Bool) {
    for handle in resizeHandles.values {
      handle.isHidden = hidden
    }
  }

  private func layoutResizeHandles(for selection: CGRect) {
    let size: CGFloat = 20
    let half = size * 0.5

    let positions = selectionHandlePoints(for: selection)

    for (corner, handle) in resizeHandles {
      guard let point = positions[corner] else {
        continue
      }

      handle.frame = CGRect(x: point.x - half, y: point.y - half, width: size, height: size).integral
      handle.isHidden = false
      handle.alphaValue = 0.001
      handle.needsDisplay = false
    }
  }

  private func selectionHandlePoints(for selection: CGRect) -> [ResizeCorner: CGPoint] {
    let minX = selection.minX
    let maxX = selection.maxX
    let minY = selection.minY
    let maxY = selection.maxY
    let midX = selection.midX
    let midY = selection.midY

    return [
      .topLeft: CGPoint(x: minX, y: maxY),
      .top: CGPoint(x: midX, y: maxY),
      .topRight: CGPoint(x: maxX, y: maxY),
      .right: CGPoint(x: maxX, y: midY),
      .bottomRight: CGPoint(x: maxX, y: minY),
      .bottom: CGPoint(x: midX, y: minY),
      .bottomLeft: CGPoint(x: minX, y: minY),
      .left: CGPoint(x: minX, y: midY),
    ]
  }

  private func startResizingSelection(corner: ResizeCorner) {
    guard mode == .editing, !stitchModeEnabled else {
      return
    }
    guard let committedSelectionRect else {
      return
    }

    activeResizeCorner = corner
    resizeStartRect = committedSelectionRect
  }

  private func updateResizingSelection(corner: ResizeCorner, delta: CGPoint) {
    guard mode == .editing, !stitchModeEnabled else {
      return
    }
    guard activeResizeCorner == corner, let startRect = resizeStartRect else {
      return
    }

    guard let resized = resizedSelectionRect(from: startRect, corner: corner, delta: delta) else {
      return
    }

    committedSelectionRect = resized
    areaCaptureRect = resized
    if selectedCaptureMode != .selection {
      selectedCaptureMode = .selection
      refreshToolbar()
    }
    needsLayout = true
    needsDisplay = true
  }

  private func finishResizingSelection(corner: ResizeCorner, delta: CGPoint) {
    defer {
      activeResizeCorner = nil
      resizeStartRect = nil
    }

    guard mode == .editing, !stitchModeEnabled else {
      return
    }

    guard activeResizeCorner == corner else {
      return
    }

    updateResizingSelection(corner: corner, delta: delta)
  }

  private func beginMovingCapturedSelectionPreview() {
    guard mode == .editing, !stitchModeEnabled else {
      return
    }
  }

  private func moveCapturedSelection(by delta: CGPoint) -> Bool {
    guard mode == .editing, !stitchModeEnabled, activeResizeCorner == nil else {
      return false
    }
    guard let current = committedSelectionRect?.standardized else {
      return false
    }

    let width = current.width
    let height = current.height
    guard width >= 2, height >= 2 else {
      return false
    }

    let minX = bounds.minX
    let maxX = max(minX, bounds.maxX - width)
    let minY = bounds.minY
    let maxY = max(minY, bounds.maxY - height)

    let candidateX = min(max(minX, current.minX + delta.x), maxX)
    let candidateY = min(max(minY, current.minY + delta.y), maxY)
    let candidate = CGRect(x: candidateX, y: candidateY, width: width, height: height).standardized

    guard abs(candidate.minX - current.minX) > 0.01 || abs(candidate.minY - current.minY) > 0.01 else {
      return false
    }

    committedSelectionRect = candidate
    areaCaptureRect = candidate.integral
    if selectedCaptureMode != .selection {
      selectedCaptureMode = .selection
      refreshToolbar()
    }
    needsLayout = true
    needsDisplay = true
    return true
  }

  private func finishMovingCapturedSelection() {
    guard mode == .editing else {
      return
    }
    needsLayout = true
    needsDisplay = true
  }

  private func resizedSelectionRect(from start: CGRect, corner: ResizeCorner, delta: CGPoint) -> CGRect? {
    var minX = start.minX
    var maxX = start.maxX
    var minY = start.minY
    var maxY = start.maxY

    switch corner {
    case .topLeft:
      minX += delta.x
      maxY += delta.y
    case .top:
      maxY += delta.y
    case .topRight:
      maxX += delta.x
      maxY += delta.y
    case .right:
      maxX += delta.x
    case .bottom:
      minY += delta.y
    case .left:
      minX += delta.x
    case .bottomLeft:
      minX += delta.x
      minY += delta.y
    case .bottomRight:
      maxX += delta.x
      minY += delta.y
    }

    let minWidth: CGFloat = 80
    let minHeight: CGFloat = 60

    switch corner {
    case .topLeft:
      minX = min(minX, maxX - minWidth)
      maxY = max(maxY, minY + minHeight)
    case .top:
      maxY = max(maxY, minY + minHeight)
    case .topRight:
      maxX = max(maxX, minX + minWidth)
      maxY = max(maxY, minY + minHeight)
    case .right:
      maxX = max(maxX, minX + minWidth)
    case .bottom:
      minY = min(minY, maxY - minHeight)
    case .left:
      minX = min(minX, maxX - minWidth)
    case .bottomLeft:
      minX = min(minX, maxX - minWidth)
      minY = min(minY, maxY - minHeight)
    case .bottomRight:
      maxX = max(maxX, minX + minWidth)
      minY = min(minY, maxY - minHeight)
    }

    minX = max(bounds.minX, minX)
    maxX = min(bounds.maxX, maxX)
    minY = max(bounds.minY, minY)
    maxY = min(bounds.maxY, maxY)

    let width = maxX - minX
    let height = maxY - minY
    guard width >= minWidth, height >= minHeight else {
      return nil
    }

    return CGRect(x: minX, y: minY, width: width, height: height).integral
  }

  private func makeToolbarView() -> AnyView {
    if mode == .editing, selectedCaptureType == .video {
      return AnyView(makeVideoToolbar())
    }
    return AnyView(makeScreenshotToolbar())
  }

  private func makeScreenshotToolbar() -> EditorGlassToolbar {
    EditorGlassToolbar(
      selectedCaptureMode: selectedCaptureMode,
      onSelectCaptureMode: { [weak self] captureMode in
        self?.setCaptureModeFromToolbar(captureMode)
      },
      onCloseCapture: { [weak self] in
        self?.finishEditing()
      },
      selectedTool: currentTool,
      toolOrder: settings.visibleTools,
      selectedColor: Color(annotationColor),
      onSelectTool: { [weak self] tool in
        self?.currentTool = tool
      },
      onColorChange: { [weak self] color in
        self?.setAnnotationColor(color)
      },
      onUndo: { [weak self] in
        self?.performUndo()
      },
      onRedo: { [weak self] in
        self?.performRedo()
      },
      onCopy: { [weak self] in
        self?.performCopy()
      },
      onSave: { [weak self] in
        self?.performSave()
      },
      onAddStitchSegment: { [weak self] in
        self?.addStitchSegment()
      },
      onResetStitch: stitchModeEnabled ? { [weak self] in
        self?.resetStitch()
      } : nil,
      isStitchRecordingActive: stitchRecordingActive,
      isStitchCaptureInProgress: stitchCaptureInProgress,
      onDone: { [weak self] in
        self?.finishEditing()
      },
      onToolbarDrag: { [weak self] translation in
        self?.updateToolbarDrag(translation)
      },
      onToolbarDragEnd: { [weak self] in
        self?.finishToolbarDrag()
      }
    )
  }

  private func makeVideoToolbar() -> VideoEditorGlassToolbar {
    VideoEditorGlassToolbar(
      selectedCaptureMode: selectedCaptureMode,
      onSelectCaptureMode: { [weak self] captureMode in
        self?.setCaptureModeFromToolbar(captureMode)
      },
      onCloseCapture: { [weak self] in
        guard let self else { return }
        guard !self.videoRecordingStartPending else { return }
        self.finishEditing()
      },
      recordSystemAudio: settings.videoRecordSystemAudio,
      recordMicrophone: settings.videoRecordMicrophone,
      showWebcam: settings.videoShowWebcam,
      highlightMouseClicks: settings.videoHighlightMouseClicks,
      highlightKeystrokes: settings.videoHighlightKeystrokes,
      isRecordingActive: videoRecordingActive,
      isRecordingPending: videoRecordingStartPending,
      countdown: settings.videoCountdown,
      onToggleSystemAudio: { [weak self] in
        guard let self else { return }
        guard !self.videoRecordingActive, !self.videoRecordingStartPending else { return }
        self.settings.setVideoRecordSystemAudio(!self.settings.videoRecordSystemAudio)
        self.refreshToolbar()
      },
      onToggleMicrophone: { [weak self] in
        guard let self else { return }
        guard !self.videoRecordingActive, !self.videoRecordingStartPending else { return }
        self.settings.setVideoRecordMicrophone(!self.settings.videoRecordMicrophone)
        self.refreshToolbar()
      },
      onToggleWebcam: { [weak self] in
        guard let self else { return }
        guard !self.videoRecordingActive, !self.videoRecordingStartPending else { return }
        self.settings.setVideoShowWebcam(!self.settings.videoShowWebcam)
        self.refreshToolbar()
      },
      onToggleMouseClicks: { [weak self] in
        guard let self else { return }
        guard !self.videoRecordingActive, !self.videoRecordingStartPending else { return }
        self.settings.setVideoHighlightMouseClicks(!self.settings.videoHighlightMouseClicks)
        self.refreshToolbar()
      },
      onToggleKeystrokes: { [weak self] in
        guard let self else { return }
        guard !self.videoRecordingActive, !self.videoRecordingStartPending else { return }
        self.settings.setVideoHighlightKeystrokes(!self.settings.videoHighlightKeystrokes)
        self.refreshToolbar()
      },
      onSelectCountdown: { [weak self] countdown in
        guard let self else { return }
        guard !self.videoRecordingActive, !self.videoRecordingStartPending else { return }
        self.settings.setVideoCountdown(countdown)
        self.refreshToolbar()
      },
      onToggleRecording: { [weak self] in
        self?.toggleVideoRecordingFromEditor()
      },
      onToolbarDrag: { [weak self] translation in
        self?.updateToolbarDrag(translation)
      },
      onToolbarDragEnd: { [weak self] in
        self?.finishToolbarDrag()
      }
    )
  }

  private func setCaptureModeFromToolbar(_ captureMode: CaptureMode) {
    guard mode == .editing else {
      return
    }
    guard !videoRecordingActive, !videoRecordingStartPending else {
      return
    }

    switch captureMode {
    case .screen:
      windowCapturePickPending = false
      _ = applyCaptureRect(bounds.insetBy(dx: 1, dy: 1), as: .screen, rememberAsArea: false)
    case .window:
      selectedCaptureMode = .window
      windowCapturePickPending = true
      refreshToolbar()
      window?.invalidateCursorRects(for: self)
      TransientToast.show("Click a window to capture")
    case .selection:
      windowCapturePickPending = false
      if let areaCaptureRect {
        _ = applyCaptureRect(areaCaptureRect, as: .selection, rememberAsArea: true)
      } else if let committedSelectionRect {
        _ = applyCaptureRect(committedSelectionRect, as: .selection, rememberAsArea: true)
      }
    }
  }

  @discardableResult
  private func applyCaptureRect(
    _ rect: CGRect,
    as captureMode: CaptureMode,
    rememberAsArea: Bool
  ) -> Bool {
    let clipped = rect.standardized.intersection(bounds).integral
    guard !clipped.isNull, clipped.width >= 2, clipped.height >= 2 else {
      return false
    }

    committedSelectionRect = clipped
    selectedCaptureMode = captureMode
    windowCapturePickPending = false
    window?.invalidateCursorRects(for: self)
    if rememberAsArea {
      areaCaptureRect = clipped
    }
    activeResizeCorner = nil
    resizeStartRect = nil
    refreshToolbar()
    needsLayout = true
    needsDisplay = true
    return true
  }

  private func captureRectForWindowPick(at localPoint: CGPoint) -> CGRect? {
    guard let hostWindow = window else {
      return nil
    }
    let screenPoint = CGPoint(
      x: hostWindow.frame.minX + localPoint.x,
      y: hostWindow.frame.minY + localPoint.y
    )

    let selfPID = ProcessInfo.processInfo.processIdentifier
    guard let windowInfo = CGWindowListCopyWindowInfo(
      [.optionOnScreenOnly, .excludeDesktopElements],
      kCGNullWindowID
    ) as? [[String: Any]]
    else {
      return nil
    }

    for info in windowInfo {
      guard let ownerPIDNumber = info[kCGWindowOwnerPID as String] as? NSNumber else {
        continue
      }
      if ownerPIDNumber.int32Value == selfPID {
        continue
      }

      if let layer = info[kCGWindowLayer as String] as? NSNumber, layer.intValue != 0 {
        continue
      }

      guard let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
            let screenBounds = CGRect(dictionaryRepresentation: boundsDict),
            screenBounds.width >= 40,
            screenBounds.height >= 30
      else {
        continue
      }

      guard screenBounds.contains(screenPoint) else {
        continue
      }

      return screenBounds
        .offsetBy(dx: -hostWindow.frame.minX, dy: -hostWindow.frame.minY)
        .integral
    }

    return nil
  }

  private func makeCaptureTypeSidebar() -> CaptureTypeSidebar {
    CaptureTypeSidebar(
      selectedType: selectedCaptureType,
      onSelectType: { [weak self] type in
        self?.setSelectedCaptureType(type)
      }
    )
  }

  private func refreshCaptureTypeSidebar() {
    captureTypeHost.rootView = makeCaptureTypeSidebar()
    needsLayout = true
  }

  private func setSelectedCaptureType(_ type: CaptureContentType) {
    guard !videoRecordingActive, !videoRecordingStartPending else {
      return
    }
    guard selectedCaptureType != type else {
      return
    }
    selectedCaptureType = type
    if mode == .editing, type == .video {
      currentTool = .move
      canvasView.finishInlineTextEditing(commit: true)
    }
    settings.setDefaultCaptureType(type)
    refreshCaptureTypeSidebar()
    refreshToolbar()
  }

  private func toggleVideoRecordingFromEditor() {
    if videoRecordingStartPending {
      return
    }
    if videoRecordingActive {
      stopVideoRecordingFromEditor()
    } else {
      startVideoRecordingFromEditor()
    }
  }

  private func startVideoRecordingFromEditor() {
    guard mode == .editing else {
      return
    }
    guard !videoRecordingActive, !videoRecordingStartPending else {
      return
    }
    guard let selection = committedSelectionRect?.standardized.integral,
          selection.width >= 2,
          selection.height >= 2
    else {
      NSSound.beep()
      return
    }
    videoRecordingStartPending = true
    refreshToolbar()
    settings.setDefaultCaptureType(.video)
    onStartVideoRequested?(selection) { [weak self] started in
      guard let self else {
        return
      }
      self.videoRecordingStartPending = false
      self.videoRecordingActive = started
      self.refreshToolbar()
    }
  }

  private func stopVideoRecordingFromEditor() {
    guard videoRecordingActive else {
      return
    }
    videoRecordingActive = false
    videoRecordingStartPending = false
    refreshToolbar()
    onStopVideoRequested?()
  }

  private func setAnnotationColor(_ color: Color) {
    let nsColor = NSColor(color)
    guard let rgb = nsColor.usingColorSpace(.deviceRGB) else {
      return
    }
    annotationColor = rgb
  }

  private func refreshToolbar() {
    toolbarHost.rootView = makeToolbarView()
    needsLayout = true
  }

  private func observeSettingsChanges() {
    settingsObserver = NotificationCenter.default.addObserver(
      forName: .vivyShotSettingsDidChange,
      object: settings,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.applySettingsFromPreferences()
      }
    }
  }

  private func applySettingsFromPreferences() {
    let configuredFontSize = CGFloat(settings.textFontSize)
    let configuredFontName = settings.textFontName
    if abs(textStyle.fontSize - configuredFontSize) > .ulpOfOne || textStyle.fontName != configuredFontName {
      textStyle = EditorTextStyle(
        fontSize: configuredFontSize,
        color: textStyle.color,
        fontName: configuredFontName
      )
    }

    let visibleTools = settings.visibleTools
    if !visibleTools.contains(currentTool) {
      currentTool = visibleTools.first ?? .move
    }

    if mode == .selecting, dragStart == nil, dragCurrent == nil, committedSelectionRect == nil {
      selectedCaptureType = settings.defaultCaptureType
      refreshCaptureTypeSidebar()
    }

    refreshToolbar()
    updateSelectingHintVisibility(animated: false)
  }

  private func updateToolbarDrag(_ translation: CGSize) {
    guard mode == .editing else {
      return
    }

    if toolbarDragStartOffset == nil {
      toolbarDragStartOffset = toolbarOffset
    }

    let start = toolbarDragStartOffset ?? .zero
    toolbarOffset = CGSize(
      width: start.width + translation.width,
      height: start.height + translation.height
    )
    needsLayout = true
  }

  private func finishToolbarDrag() {
    toolbarDragStartOffset = nil
  }

  private func finishEditing(animatedClose: Bool = true) {
    canvasView.finishInlineTextEditing(commit: true)
    stitchCaptureTask?.cancel()
    stitchCaptureTask = nil
    stitchRecordingActive = false
    stitchCaptureInProgress = false
    stitchPassThroughOverlayActive = false
    stitchDirection = nil
    stitchExpectedDeltaRows = nil
    resetStitchAutoScrollState()
    window?.ignoresMouseEvents = false
    hideStitchControlPanel()
    let callback = onEditingDone
    onEditingDone = nil
    callback?(animatedClose)
  }

  private func currentTextAnnotationStyle() -> TextAnnotationStyle {
    TextAnnotationStyle(
      fontSize: textStyle.fontSize,
      color: textStyle.color
    )
  }

  private func scaledTextAnnotationStyle() -> TextAnnotationStyle {
    TextAnnotationStyle(
      fontSize: textStyle.fontSize * canvasPixelScale(),
      color: textStyle.color
    )
  }

  private func scaledStrokeWidth(base: CGFloat) -> UInt32 {
    UInt32(max(1, Int((base * canvasPixelScale()).rounded())))
  }

  private func displayedStrokeWidth(base: CGFloat) -> CGFloat {
    let scale = max(1, canvasPixelScale())
    let committedWidth = CGFloat(scaledStrokeWidth(base: base))
    return max(1, committedWidth / scale)
  }

  private func baseStrokeWidth(for tool: AnnotationTool) -> CGFloat {
    switch tool {
    case .arrow:
      return 5
    case .paint:
      return 6
    default:
      return 4
    }
  }

  private func updateCanvasPreviewStrokeWidth() {
    canvasView.previewStrokeWidth = displayedStrokeWidth(base: baseStrokeWidth(for: currentTool))
  }

  private func canvasPixelScale() -> CGFloat {
    guard let image = canvasView.image else {
      return 1
    }

    guard canvasView.bounds.width > 0, canvasView.bounds.height > 0 else {
      return 1
    }

    let scaleX = CGFloat(image.width) / canvasView.bounds.width
    let scaleY = CGFloat(image.height) / canvasView.bounds.height
    return max(1, (scaleX + scaleY) * 0.5)
  }

  private func commitRect(_ imageRect: CGRect) {
    guard let session else {
      NSSound.beep()
      return
    }

    guard let image = session.addRect(
      imageRect: imageRect,
      color: annotationColor,
      strokeWidth: scaledStrokeWidth(base: 4)
    ) else {
      NSSound.beep()
      return
    }

    canvasView.image = image
    updateCanvasPreviewStrokeWidth()
    needsLayout = true
  }

  private func commitFilledRect(_ imageRect: CGRect) {
    guard let session else {
      NSSound.beep()
      return
    }

    guard let image = session.addFilledRect(
      imageRect: imageRect,
      color: annotationColor
    ) else {
      NSSound.beep()
      return
    }

    canvasView.image = image
    updateCanvasPreviewStrokeWidth()
    needsLayout = true
  }

  private func commitCircle(_ imageRect: CGRect) {
    guard let session else {
      NSSound.beep()
      return
    }

    guard let image = session.addCircle(
      imageRect: imageRect,
      color: annotationColor,
      strokeWidth: scaledStrokeWidth(base: 4)
    ) else {
      NSSound.beep()
      return
    }

    canvasView.image = image
    updateCanvasPreviewStrokeWidth()
    needsLayout = true
  }

  private func commitFilledCircle(_ imageRect: CGRect) {
    guard let session else {
      NSSound.beep()
      return
    }

    guard let image = session.addFilledCircle(
      imageRect: imageRect,
      color: annotationColor
    ) else {
      NSSound.beep()
      return
    }

    canvasView.image = image
    updateCanvasPreviewStrokeWidth()
    needsLayout = true
  }

  private func commitLine(from start: CGPoint, to end: CGPoint) {
    guard let session else {
      NSSound.beep()
      return
    }

    guard let image = session.addLine(
      from: start,
      to: end,
      color: annotationColor,
      strokeWidth: scaledStrokeWidth(base: 4)
    ) else {
      NSSound.beep()
      return
    }

    canvasView.image = image
    updateCanvasPreviewStrokeWidth()
    needsLayout = true
  }

  private func commitArrow(from start: CGPoint, to end: CGPoint) {
    guard let session else {
      NSSound.beep()
      return
    }

    guard let image = session.addArrow(
      from: start,
      to: end,
      color: annotationColor,
      strokeWidth: scaledStrokeWidth(base: 5)
    ) else {
      NSSound.beep()
      return
    }

    canvasView.image = image
    updateCanvasPreviewStrokeWidth()
    needsLayout = true
  }

  private func commitPaintPath(_ points: [CGPoint]) {
    guard let session else {
      NSSound.beep()
      return
    }

    guard let image = session.addPath(
      points,
      color: annotationColor,
      strokeWidth: scaledStrokeWidth(base: 6)
    ) else {
      NSSound.beep()
      return
    }

    canvasView.image = image
    updateCanvasPreviewStrokeWidth()
    needsLayout = true
  }

  private func commitText(_ text: String, at point: CGPoint) {
    guard let session else {
      NSSound.beep()
      return
    }

    guard let image = session.addText(text, at: point, style: scaledTextAnnotationStyle()) else {
      NSSound.beep()
      return
    }

    canvasView.image = image
    currentTool = .move
    canvasView.selectAnnotation(atImagePoint: point)
    updateCanvasPreviewStrokeWidth()
    needsLayout = true
  }

  private func commitPixelate(_ imageRect: CGRect) {
    guard let session else {
      NSSound.beep()
      return
    }

    guard let image = session.addPixelate(imageRect: imageRect) else {
      NSSound.beep()
      return
    }

    canvasView.image = image
    updateCanvasPreviewStrokeWidth()
    needsLayout = true
  }

  private func commitBlur(_ imageRect: CGRect) {
    guard let session else {
      NSSound.beep()
      return
    }

    guard let image = session.addBlur(imageRect: imageRect) else {
      NSSound.beep()
      return
    }

    canvasView.image = image
    updateCanvasPreviewStrokeWidth()
    needsLayout = true
  }

  private func performUndo() {
    canvasView.finishInlineTextEditing(commit: true)

    guard let session else {
      NSSound.beep()
      return
    }

    guard let image = session.undo() else {
      NSSound.beep()
      return
    }

    canvasView.image = image
    updateCanvasPreviewStrokeWidth()
  }

  private func performRedo() {
    canvasView.finishInlineTextEditing(commit: true)

    guard let session else {
      NSSound.beep()
      return
    }

    guard let image = session.redo() else {
      NSSound.beep()
      return
    }

    canvasView.image = image
    updateCanvasPreviewStrokeWidth()
  }

  private func addStitchSegment() {
    if stitchRecordingActive {
      stopStitchRecording(applyResult: true)
      return
    }
    startStitchRecording()
  }

  private func startStitchRecording() {
    canvasView.finishInlineTextEditing(commit: true)

    guard mode == .editing, !stitchRecordingActive else {
      return
    }
    guard let overlayWindow = window else {
      NSSound.beep()
      return
    }

    let screenFrame = overlayWindow.frame
    let captureRectInScreen: CGRect
    let baseImage: CGImage

    if stitchModeEnabled {
      guard let storedRect = stitchCaptureRectInScreen,
            let existingImage = canvasView.image
      else {
        NSSound.beep()
        return
      }
      captureRectInScreen = storedRect
      baseImage = existingImage
    } else {
      guard let currentSelection = committedSelectionRect?.standardized,
            currentSelection.width >= 2,
            currentSelection.height >= 2,
            let selectedImage = exportImageForCurrentSelection(),
            let currentCanvasImage = canvasView.image
      else {
        NSSound.beep()
        return
      }

      captureRectInScreen = currentSelection
        .offsetBy(dx: screenFrame.minX, dy: screenFrame.minY)
        .standardized
      stitchCaptureRectInScreen = captureRectInScreen
      preStitchImage = currentCanvasImage
      preStitchSelectionRect = committedSelectionRect
      stitchSegmentCount = 1
      stitchModeEnabled = true
      activeResizeCorner = nil
      resizeStartRect = nil
      toolbarOffset = .zero
      toolbarDragStartOffset = nil
      if let previousSelection = preStitchSelectionRect {
        committedSelectionRect = previousSelection.standardized.integral
      }
      baseImage = selectedImage
    }

    stitchWorkingImage = baseImage
    stitchLastFrame = nil
    stitchDirection = nil
    stitchExpectedDeltaRows = nil
    stitchCaptureInProgress = false
    resetStitchAutoScrollState()
    refreshAutoScrollTrust(promptIfNeeded: stitchAutoScrollEnabled)
    if stitchAutoScrollEnabled, !stitchAutoScrollTrusted {
      TransientToast.show("Auto-scroll requires Accessibility permission")
    }
    stitchTargetApp = resolveStitchTargetAppUnderCursor()
    stitchRecordingActive = true
    refreshToolbar()
    beginStitchPassThroughOverlay(on: overlayWindow, captureRectInScreen: captureRectInScreen)
    showStitchControlPanel()

    let captureRect = captureRectInScreen

    stitchCaptureTask?.cancel()
    stitchCaptureTask = Task { [weak self] in
      guard let self else {
        return
      }
      await self.runStitchRecordingLoop(
        screenFrame: screenFrame,
        captureRectInScreen: captureRect
      )
    }
  }

  private func stopStitchRecording(applyResult: Bool) {
    guard stitchRecordingActive || stitchPassThroughOverlayActive else {
      return
    }

    stitchRecordingActive = false
    stitchCaptureTask?.cancel()
    stitchCaptureTask = nil
    stitchCaptureInProgress = false
    hideStitchControlPanel()
    restoreOverlayWindowAfterStitchCapture(window)

    if applyResult {
      finalizeStitchWorkingImage()
    } else {
      stitchWorkingImage = nil
      stitchLastFrame = nil
      stitchDirection = nil
      stitchExpectedDeltaRows = nil
      resetStitchAutoScrollState()
    }

    if applyResult {
      resetStitchAutoScrollState()
    }
    refreshToolbar()
  }

  private func runStitchRecordingLoop(
    screenFrame: CGRect,
    captureRectInScreen: CGRect
  ) async {
    while stitchRecordingActive, mode == .editing {
      let didAutoScrollTick = performAutoScrollTickIfNeeded(captureRectInScreen: captureRectInScreen)
      if didAutoScrollTick {
        let settleDelay = UInt64(max(0.03, stitchAutoScrollSettleInterval) * 1_000_000_000)
        try? await Task.sleep(nanoseconds: settleDelay)
      }

      stitchCaptureInProgress = true
      refreshToolbar()

      let frame = await captureFrameForStitchRecording(
        screenFrame: screenFrame,
        captureRectInScreen: captureRectInScreen
      )

      stitchCaptureInProgress = false
      refreshToolbar()

      if !stitchRecordingActive || mode != .editing {
        break
      }

      var merged = false
      if let frame {
        merged = processStitchCapturedFrame(frame)
      }

      if didAutoScrollTick {
        updateAutoScrollFeedback(didMerge: merged)
      }

      let interval = didAutoScrollTick ? max(0.08, stitchCaptureInterval * 0.85) : max(0.08, stitchCaptureInterval)
      let delay = UInt64(interval * 1_000_000_000)
      try? await Task.sleep(nanoseconds: delay)
    }
  }

  private func resetStitchAutoScrollState() {
    stitchAutoScrollDirectionSign = -1
    stitchAutoScrollNoMotionTicks = 0
    stitchAutoScrollDidFlipDirection = false
    stitchAutoScrollTrusted = false
    stitchTargetApp = nil
  }

  private func refreshAutoScrollTrust(promptIfNeeded: Bool) {
    guard stitchAutoScrollEnabled else {
      stitchAutoScrollTrusted = false
      return
    }

    if promptIfNeeded, !stitchAutoScrollPromptAttempted {
      stitchAutoScrollPromptAttempted = true
      let options = ["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary
      stitchAutoScrollTrusted = AXIsProcessTrustedWithOptions(options)
    } else {
      stitchAutoScrollTrusted = AXIsProcessTrusted()
    }
  }

  private func resolveStitchTargetAppUnderCursor() -> NSRunningApplication? {
    resolveStitchTargetApp(at: NSEvent.mouseLocation)
  }

  private func resolveStitchTargetApp(at point: CGPoint) -> NSRunningApplication? {
    guard let windowInfo = CGWindowListCopyWindowInfo(
      [.optionOnScreenOnly, .excludeDesktopElements],
      kCGNullWindowID
    ) as? [[String: Any]]
    else {
      return nil
    }

    let selfPID = ProcessInfo.processInfo.processIdentifier
    for info in windowInfo {
      guard let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
            let bounds = CGRect(dictionaryRepresentation: boundsDict),
            bounds.contains(point),
            let ownerPIDNumber = info[kCGWindowOwnerPID as String] as? NSNumber
      else {
        continue
      }

      let ownerPID = ownerPIDNumber.int32Value
      if ownerPID == selfPID {
        continue
      }
      if let app = NSRunningApplication(processIdentifier: ownerPID), !app.isTerminated {
        return app
      }
    }
    return nil
  }

  private func performAutoScrollTickIfNeeded(captureRectInScreen: CGRect) -> Bool {
    guard stitchAutoScrollEnabled else {
      return false
    }

    guard stitchAutoScrollTrusted else {
      return false
    }

    if stitchTargetApp == nil || stitchTargetApp?.isTerminated == true {
      let targetPoint = CGPoint(x: captureRectInScreen.midX, y: captureRectInScreen.midY)
      stitchTargetApp = resolveStitchTargetApp(at: targetPoint)
    }

    let delta = max(1, stitchAutoScrollStepLines) * stitchAutoScrollDirectionSign
    guard let scrollEvent = CGEvent(
      scrollWheelEvent2Source: nil,
      units: .line,
      wheelCount: 1,
      wheel1: delta,
      wheel2: 0,
      wheel3: 0
      ) else {
      return false
    }

    if let targetApp = stitchTargetApp, !targetApp.isTerminated {
      if !targetApp.isActive {
        targetApp.activate(options: [])
      }
      scrollEvent.postToPid(targetApp.processIdentifier)
    } else {
      scrollEvent.post(tap: .cghidEventTap)
    }

    return true
  }

  private func updateAutoScrollFeedback(didMerge: Bool) {
    guard stitchAutoScrollEnabled else {
      return
    }

    if didMerge {
      stitchAutoScrollNoMotionTicks = 0
      return
    }

    stitchAutoScrollNoMotionTicks += 1
    guard stitchDirection == nil,
          !stitchAutoScrollDidFlipDirection,
          stitchAutoScrollNoMotionTicks >= 4
    else {
      return
    }

    stitchAutoScrollDidFlipDirection = true
    stitchAutoScrollNoMotionTicks = 0
    stitchAutoScrollDirectionSign *= -1
  }

  private func processStitchCapturedFrame(_ frame: CGImage) -> Bool {
    guard stitchRecordingActive else {
      return false
    }

    guard let previous = stitchLastFrame else {
      stitchLastFrame = frame
      return false
    }

    guard let working = stitchWorkingImage else {
      stitchLastFrame = frame
      return false
    }

    defer {
      stitchLastFrame = frame
    }

    let strictDelta = estimateStitchDelta(
      previous: previous,
      current: frame,
      preferredSide: stitchDirection,
      expectedRows: stitchExpectedDeltaRows,
      relaxed: false
    )

    let delta = strictDelta ?? estimateStitchDelta(
      previous: previous,
      current: frame,
      preferredSide: stitchDirection,
      expectedRows: stitchExpectedDeltaRows,
      relaxed: true
    )

    guard let delta,
          delta.rows >= 4,
          let strip = extractStrip(from: frame, rows: delta.rows, side: delta.side),
          let stitched = mergeSegment(base: working, segment: strip, side: delta.side)
    else {
      return false
    }

    if stitchDirection == nil, stitchAutoScrollEnabled {
      stitchAutoScrollDirectionSign = (delta.side == .bottom) ? -1 : 1
    }
    stitchDirection = stitchDirection ?? delta.side
    if let previousExpected = stitchExpectedDeltaRows {
      let blended = Int((Double(previousExpected) * 0.65 + Double(delta.rows) * 0.35).rounded())
      stitchExpectedDeltaRows = max(4, blended)
    } else {
      stitchExpectedDeltaRows = delta.rows
    }
    stitchWorkingImage = stitched
    stitchSegmentCount += 1
    return true
  }

  private func finalizeStitchWorkingImage() {
    defer {
      stitchWorkingImage = nil
      stitchLastFrame = nil
      stitchDirection = nil
      stitchExpectedDeltaRows = nil
      resetStitchAutoScrollState()
      needsLayout = true
      needsDisplay = true
    }

    guard let stitched = stitchWorkingImage else {
      return
    }

    guard let stitchedSession = RustCoreBridge.shared.makeSession(image: stitched) else {
      NSSound.beep()
      TransientToast.show("Failed to finalize stitched capture")
      return
    }

    session = stitchedSession
    canvasView.image = stitched
    postStitchEditorMode = isLikelyLongScrollImage(stitched)
    if postStitchEditorMode {
      canvasView.configureForScrollingCaptureEditing()
    }
    updateCanvasPreviewStrokeWidth()
    stitchModeEnabled = false
    stitchCaptureRectInScreen = nil
    preStitchImage = nil
    preStitchSelectionRect = nil
    committedSelectionRect = nil
    activeResizeCorner = nil
    resizeStartRect = nil
    toolbarOffset = .zero
    toolbarDragStartOffset = nil

    if stitchSegmentCount > 1 {
      TransientToast.show("Captured \(stitchSegmentCount) segments")
    } else {
      TransientToast.show("No scrolling movement captured")
    }
  }

  private func isLikelyLongScrollImage(_ image: CGImage) -> Bool {
    let width = CGFloat(image.width)
    let height = CGFloat(image.height)
    guard width > 0, height > 0 else {
      return false
    }
    return height >= width * 1.6
  }

  private func resetStitch() {
    guard mode == .editing, stitchModeEnabled else {
      NSSound.beep()
      return
    }

    if stitchRecordingActive || stitchPassThroughOverlayActive {
      stopStitchRecording(applyResult: false)
    }

    canvasView.finishInlineTextEditing(commit: true)

    guard let preStitchImage,
          let preStitchSelectionRect,
          let restoredSession = RustCoreBridge.shared.makeSession(image: preStitchImage)
    else {
      NSSound.beep()
      return
    }

    session = restoredSession
    canvasView.image = preStitchImage
    committedSelectionRect = preStitchSelectionRect.standardized.integral
    stitchModeEnabled = false
    stitchCaptureRectInScreen = nil
    stitchSegmentCount = 1
    stitchCaptureTask?.cancel()
    stitchCaptureTask = nil
    stitchRecordingActive = false
    stitchCaptureInProgress = false
    stitchWorkingImage = nil
    stitchLastFrame = nil
    stitchDirection = nil
    stitchExpectedDeltaRows = nil
    resetStitchAutoScrollState()
    stitchPassThroughOverlayActive = false
    postStitchEditorMode = false
    window?.ignoresMouseEvents = false
    hideStitchControlPanel()
    activeResizeCorner = nil
    resizeStartRect = nil
    updateCanvasPreviewStrokeWidth()
    refreshToolbar()
    needsLayout = true
    needsDisplay = true
    TransientToast.show("Stitch reset")
  }

  private func captureFrameForStitchRecording(
    screenFrame: CGRect,
    captureRectInScreen: CGRect
  ) async -> CGImage? {
    guard let capturedImage = await captureScreenImage(frame: screenFrame) else {
      return nil
    }

    return cropSegment(
      from: capturedImage,
      captureRectInScreen: captureRectInScreen,
      screenFrame: screenFrame
    )
  }

  private func restoreOverlayWindowAfterStitchCapture(_ overlayWindow: NSWindow?) {
    stitchPassThroughOverlayActive = false
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

  private func beginStitchPassThroughOverlay(on overlayWindow: NSWindow, captureRectInScreen: CGRect) {
    stitchPassThroughOverlayActive = true
    overlayWindow.ignoresMouseEvents = true
    canvasView.finishInlineTextEditing(commit: true)
    setResizeHandlesHidden(true)
    needsLayout = true
    needsDisplay = true
    overlayWindow.invalidateCursorRects(for: self)

    if stitchAutoScrollEnabled, stitchAutoScrollTrusted {
      if stitchTargetApp == nil || stitchTargetApp?.isTerminated == true {
        let targetPoint = CGPoint(x: captureRectInScreen.midX, y: captureRectInScreen.midY)
        stitchTargetApp = resolveStitchTargetApp(at: targetPoint)
      }
      stitchTargetApp?.activate(options: [])
    }
  }

  private func showStitchControlPanel() {
    guard stitchRecordingActive, let overlayWindow = window else {
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

  private func positionStitchControlPanel(_ panel: NSPanel, relativeTo overlayWindow: NSWindow) {
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

  private func hideStitchControlPanel() {
    stitchControlPanel?.orderOut(nil)
    stitchControlPanel = nil
  }

  private enum StitchStripSide {
    case top
    case bottom
  }

  private struct StitchDeltaEstimate {
    let rows: Int
    let side: StitchStripSide
    let score: Double
  }

  private func estimateStitchDelta(
    previous: CGImage,
    current: CGImage,
    preferredSide: StitchStripSide?,
    expectedRows: Int?,
    relaxed: Bool
  ) -> StitchDeltaEstimate? {
    guard let prev = makeBGRARaster(from: previous),
          let curr = makeBGRARaster(from: current),
          prev.width == curr.width,
          prev.height == curr.height
    else {
      return nil
    }

    let width = prev.width
    let height = prev.height
    guard width >= 32, height >= 24 else {
      return nil
    }

    // Allow large jumps (fast scrolling) while still requiring some overlap.
    let minOverlapRows = max(24, Int((Double(height) * 0.14).rounded()))
    let maxShift = max(4, min(height - 4, height - minOverlapRows))

    // Ignore static UI chrome (sticky header/footer/scrollbar edges) when matching.
    let xInset = max(8, width / 16)
    let yInset = max(10, height / 8)
    let sampleMinX = xInset
    let sampleMaxX = max(sampleMinX + 8, width - xInset)
    let sampleSpanX = max(8, sampleMaxX - sampleMinX)
    let stepX = max(2, sampleSpanX / 74)
    var best = StitchDeltaEstimate(rows: 0, side: .bottom, score: .greatestFiniteMagnitude)
    var secondBestScore = Double.greatestFiniteMagnitude

    func considerCandidate(_ candidate: StitchDeltaEstimate) {
      if candidate.score < best.score {
        secondBestScore = best.score
        best = candidate
      } else if candidate.score < secondBestScore {
        secondBestScore = candidate.score
      }
    }

    var searchStart = 2
    var searchEnd = maxShift
    if let expectedRows {
      let band = max(10, Int((Double(max(6, expectedRows)) * (relaxed ? 1.05 : 0.65)).rounded()))
      searchStart = max(2, expectedRows - band)
      searchEnd = min(maxShift, expectedRows + band)
      if searchStart >= searchEnd {
        searchStart = 2
        searchEnd = maxShift
      }
    }

    for shift in searchStart ... searchEnd {
      let overlap = height - shift
      if overlap < 10 {
        continue
      }
      let sampleMinY = yInset
      let sampleMaxY = max(sampleMinY + 8, overlap - yInset)
      let sampleSpanY = sampleMaxY - sampleMinY
      if sampleSpanY < 8 {
        continue
      }
      let stepY = max(2, sampleSpanY / 64)

      var diffBottom: UInt64 = 0
      var diffTop: UInt64 = 0
      var samples: UInt64 = 0

      var y = sampleMinY
      while y < sampleMaxY {
        let prevBottomRow = y + shift
        let currBottomRow = y
        let prevTopRow = y
        let currTopRow = y + shift

        let prevBottomBase = prevBottomRow * prev.stride
        let currBottomBase = currBottomRow * curr.stride
        let prevTopBase = prevTopRow * prev.stride
        let currTopBase = currTopRow * curr.stride

        var x = sampleMinX
        while x < sampleMaxX {
          let prevBottomIndex = prevBottomBase + x * 4
          let currBottomIndex = currBottomBase + x * 4
          diffBottom += pixelDiff(prev.pixels, prevBottomIndex, curr.pixels, currBottomIndex)

          let prevTopIndex = prevTopBase + x * 4
          let currTopIndex = currTopBase + x * 4
          diffTop += pixelDiff(prev.pixels, prevTopIndex, curr.pixels, currTopIndex)

          samples += 1
          x += stepX
        }
        y += stepY
      }

      guard samples > 0 else {
        continue
      }

      if preferredSide == nil || preferredSide == .bottom {
        let bottomScore = Double(diffBottom) / Double(samples)
        considerCandidate(StitchDeltaEstimate(rows: shift, side: .bottom, score: bottomScore))
      }

      if preferredSide == nil || preferredSide == .top {
        let topScore = Double(diffTop) / Double(samples)
        considerCandidate(StitchDeltaEstimate(rows: shift, side: .top, score: topScore))
      }
    }

    guard best.rows >= 4 else {
      return nil
    }

    // Empirical threshold for BGRA sum error on sampled pixels.
    let scoreThreshold: Double
    if relaxed {
      scoreThreshold = (preferredSide == nil) ? 82 : 94
    } else {
      scoreThreshold = (preferredSide == nil) ? 56 : 62
    }
    guard best.score < scoreThreshold else {
      return nil
    }

    // Reject ambiguous matches that are too close to the runner-up score.
    if !relaxed, secondBestScore.isFinite {
      let separation = (secondBestScore - best.score) / max(1, secondBestScore)
      let minimumSeparation: Double = (preferredSide == nil) ? 0.08 : 0.055
      guard separation >= minimumSeparation else {
        return nil
      }
    }

    return best
  }

  private func pixelDiff(_ a: [UInt8], _ ai: Int, _ b: [UInt8], _ bi: Int) -> UInt64 {
    let db = abs(Int(a[ai + 0]) - Int(b[bi + 0]))
    let dg = abs(Int(a[ai + 1]) - Int(b[bi + 1]))
    let dr = abs(Int(a[ai + 2]) - Int(b[bi + 2]))
    return UInt64(dr + dg + db)
  }

  private func extractStrip(from image: CGImage, rows: Int, side: StitchStripSide) -> CGImage? {
    let clampedRows = max(1, min(rows, image.height - 1))
    let cropRect: CGRect
    switch side {
    case .bottom:
      cropRect = CGRect(x: 0, y: 0, width: image.width, height: clampedRows)
    case .top:
      cropRect = CGRect(x: 0, y: image.height - clampedRows, width: image.width, height: clampedRows)
    }
    return image.cropping(to: cropRect.integral)
  }

  private func makeBGRARaster(from image: CGImage) -> (width: Int, height: Int, stride: Int, pixels: [UInt8])? {
    let width = image.width
    let height = image.height
    guard width >= 1, height >= 1 else {
      return nil
    }

    let stride = width * 4
    var pixels = [UInt8](repeating: 0, count: stride * height)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue

    let ok = pixels.withUnsafeMutableBytes { raw -> Bool in
      guard let base = raw.baseAddress else {
        return false
      }
      guard let context = CGContext(
        data: base,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: stride,
        space: colorSpace,
        bitmapInfo: bitmapInfo
      ) else {
        return false
      }
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }

    guard ok else {
      return nil
    }
    return (width, height, stride, pixels)
  }

  private func captureScreenImage(frame: CGRect) async -> CGImage? {
    guard #available(macOS 15.2, *) else {
      return nil
    }

    return await withCheckedContinuation { continuation in
      SCScreenshotManager.captureImage(in: frame) { image, _ in
        continuation.resume(returning: image)
      }
    }
  }

  private func cropSegment(
    from image: CGImage,
    captureRectInScreen: CGRect,
    screenFrame: CGRect
  ) -> CGImage? {
    let clippedSelection = captureRectInScreen.standardized.intersection(screenFrame)
    guard !clippedSelection.isNull, clippedSelection.width >= 2, clippedSelection.height >= 2 else {
      return nil
    }

    let localRect = clippedSelection.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
    let scaleX = CGFloat(image.width) / screenFrame.width
    let scaleY = CGFloat(image.height) / screenFrame.height

    let x = localRect.minX * scaleX
    let yTop = CGFloat(image.height) - (localRect.maxY * scaleY)
    let width = localRect.width * scaleX
    let height = localRect.height * scaleY

    var cropRect = CGRect(
      x: floor(x),
      y: floor(yTop),
      width: ceil(width),
      height: ceil(height)
    )

    let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    cropRect = cropRect.intersection(imageBounds)

    guard !cropRect.isNull, cropRect.width >= 2, cropRect.height >= 2 else {
      return nil
    }

    return image.cropping(to: cropRect.integral)
  }

  private func mergeSegment(base: CGImage, segment: CGImage, side: StitchStripSide) -> CGImage? {
    switch side {
    case .bottom:
      return appendSegment(base: base, segment: segment)
    case .top:
      return prependSegment(base: base, segment: segment)
    }
  }

  private func appendSegment(base: CGImage, segment: CGImage) -> CGImage? {
    let targetWidth = base.width
    guard targetWidth >= 2, base.height >= 2, segment.width >= 2, segment.height >= 2 else {
      return nil
    }

    guard let normalizedSegment = normalizedSegmentWidth(segment, targetWidth: targetWidth) else {
      return nil
    }

    let totalHeight = base.height + normalizedSegment.height
    guard let context = CGContext(
      data: nil,
      width: targetWidth,
      height: totalHeight,
      bitsPerComponent: 8,
      bytesPerRow: targetWidth * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    ) else {
      return nil
    }

    context.interpolationQuality = .high
    context.draw(
      base,
      in: CGRect(x: 0, y: normalizedSegment.height, width: targetWidth, height: base.height)
    )
    context.draw(
      normalizedSegment,
      in: CGRect(x: 0, y: 0, width: targetWidth, height: normalizedSegment.height)
    )

    return context.makeImage()
  }

  private func prependSegment(base: CGImage, segment: CGImage) -> CGImage? {
    let targetWidth = base.width
    guard targetWidth >= 2, base.height >= 2, segment.width >= 2, segment.height >= 2 else {
      return nil
    }

    guard let normalizedSegment = normalizedSegmentWidth(segment, targetWidth: targetWidth) else {
      return nil
    }

    let totalHeight = base.height + normalizedSegment.height
    guard let context = CGContext(
      data: nil,
      width: targetWidth,
      height: totalHeight,
      bitsPerComponent: 8,
      bytesPerRow: targetWidth * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    ) else {
      return nil
    }

    context.interpolationQuality = .high
    context.draw(base, in: CGRect(x: 0, y: 0, width: targetWidth, height: base.height))
    context.draw(
      normalizedSegment,
      in: CGRect(x: 0, y: base.height, width: targetWidth, height: normalizedSegment.height)
    )
    return context.makeImage()
  }

  private func normalizedSegmentWidth(_ segment: CGImage, targetWidth: Int) -> CGImage? {
    if segment.width == targetWidth {
      return segment
    }

    let scale = CGFloat(targetWidth) / CGFloat(segment.width)
    let targetHeight = max(1, Int((CGFloat(segment.height) * scale).rounded()))

    guard let context = CGContext(
      data: nil,
      width: targetWidth,
      height: targetHeight,
      bitsPerComponent: 8,
      bytesPerRow: targetWidth * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    ) else {
      return nil
    }

    context.interpolationQuality = .high
    context.draw(segment, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
    return context.makeImage()
  }

  private func performCopy() {
    canvasView.finishInlineTextEditing(commit: true)

    guard let image = exportImageForCurrentSelection() else {
      NSSound.beep()
      return
    }

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    guard pasteboard.writeObjects([nsImage]) else {
      NSSound.beep()
      return
    }

    finishEditing()
    TransientToast.show("Copied to Clipboard")
  }

  private func performSave() {
    canvasView.finishInlineTextEditing(commit: true)

    guard let image = exportImageForCurrentSelection() else {
      NSSound.beep()
      return
    }

    if settings.alwaysSaveToDefaultDirectory,
       let directory = settings.defaultSaveDirectoryURL
    {
      finishEditing(animatedClose: false)
      let destination = Self.makeAutoSaveURL(in: directory, ext: "png")
      Self.saveImageToDisk(image, to: destination)
      return
    }

    let suggestedDirectory = settings.defaultSaveDirectoryURL
    finishEditing(animatedClose: false)
    DispatchQueue.main.async {
      Self.presentSavePanel(for: image, suggestedDirectory: suggestedDirectory)
    }
  }

  private static func presentSavePanel(for image: CGImage, suggestedDirectory: URL?) {
    let panel = NSSavePanel()
    panel.title = "Save Annotation"
    panel.canCreateDirectories = true
    panel.allowedContentTypes = [.png, .jpeg]
    panel.allowsOtherFileTypes = false
    let defaultExt = "png"
    if let directory = suggestedDirectory {
      let suggested = Self.makeAutoSaveURL(in: directory, ext: defaultExt)
      panel.directoryURL = directory
      panel.nameFieldStringValue = suggested.lastPathComponent
    } else {
      panel.nameFieldStringValue = "\(Self.makeTimestampedBaseName()).\(defaultExt)"
    }

    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    NSApp.activate(ignoringOtherApps: true)
    let response = panel.runModal()
    defer {
      panel.orderOut(nil)
      panel.close()
    }

    guard response == .OK, let url = panel.url else {
      return
    }

    Self.saveImageToDisk(image, to: url)
  }

  private func exportImageForCurrentSelection() -> CGImage? {
    guard let image = canvasView.image else {
      return nil
    }

    if stitchModeEnabled {
      return image
    }

    guard let selection = committedSelectionRect?.standardized else {
      return image
    }

    let selectionInCanvas = convert(selection, to: canvasView)
    guard let imageRect = canvasView.exportImageRect(fromViewRect: selectionInCanvas) else {
      return image
    }

    let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    let cropRect = imageRect.standardized.integral.intersection(imageBounds)
    guard !cropRect.isNull, cropRect.width >= 1, cropRect.height >= 1 else {
      return image
    }

    return image.cropping(to: cropRect) ?? image
  }

  private static func saveImageToDisk(_ image: CGImage, to url: URL) {
    let ext = url.pathExtension.lowercased()
    let extType = UTType(filenameExtension: ext)
    let selectedType: UTType = (extType == .jpeg || ext == "jpg") ? .jpeg : .png
    let targetURL: URL

    if ext.isEmpty, let preferredExt = selectedType.preferredFilenameExtension {
      targetURL = url.appendingPathExtension(preferredExt)
    } else {
      targetURL = url
    }

    guard let destination = CGImageDestinationCreateWithURL(
      targetURL as CFURL,
      selectedType.identifier as CFString,
      1,
      nil
    ) else {
      NSSound.beep()
      return
    }

    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
      NSSound.beep()
      return
    }

    TransientToast.show("Saved")
  }

  private static func makeAutoSaveURL(in directory: URL, ext: String) -> URL {
    let baseName = makeTimestampedBaseName()
    let normalizedExt = ext.lowercased()

    var candidate = directory.appendingPathComponent(baseName).appendingPathExtension(normalizedExt)
    var suffix = 2
    while FileManager.default.fileExists(atPath: candidate.path) {
      candidate = directory
        .appendingPathComponent("\(baseName)-\(suffix)")
        .appendingPathExtension(normalizedExt)
      suffix += 1
    }
    return candidate
  }

  private static func makeTimestampedBaseName() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
    let timestamp = formatter.string(from: Date())
    return "vivyshot_\(timestamp)"
  }

  private func selectionRect() -> CGRect? {
    guard let dragStart, let dragCurrent else {
      return nil
    }

    let raw = CGRect(
      x: min(dragStart.x, dragCurrent.x),
      y: min(dragStart.y, dragCurrent.y),
      width: abs(dragCurrent.x - dragStart.x),
      height: abs(dragCurrent.y - dragStart.y)
    )

    if raw.width < 2 || raw.height < 2 {
      return nil
    }

    return raw.intersection(bounds).integral
  }

  private func drawSelectionSize(_ selection: CGRect) {
    let sizeText = "\(Int(selection.width)) × \(Int(selection.height))"
    let textAttributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
      .foregroundColor: NSColor.white,
    ]
    let attributedSizeText = NSAttributedString(string: sizeText, attributes: textAttributes)
    let textSize = attributedSizeText.size()
    let backgroundPadding: CGFloat = 6
    var originX = selection.minX
    var originY = selection.maxY + 8
    if originY + textSize.height + backgroundPadding * 2 > bounds.maxY {
      originY = selection.minY - textSize.height - backgroundPadding * 2 - 8
    }
    originX = min(max(8, originX), bounds.maxX - textSize.width - backgroundPadding * 2 - 8)

    let backgroundRect = CGRect(
      x: originX,
      y: originY,
      width: textSize.width + backgroundPadding * 2,
      height: textSize.height + backgroundPadding * 2
    )

    NSColor.black.withAlphaComponent(0.62).setFill()
    NSBezierPath(roundedRect: backgroundRect, xRadius: 6, yRadius: 6).fill()

    attributedSizeText.draw(
      at: CGPoint(x: backgroundRect.minX + backgroundPadding, y: backgroundRect.minY + backgroundPadding),
    )
  }

  private func drawSelectionCornerGuides(
    in context: CGContext,
    selection: CGRect,
    alpha: CGFloat
  ) {
    let displayScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    let pixel = 1.0 / max(displayScale, 1)
    func snapped(_ value: CGFloat) -> CGFloat {
      (value * displayScale).rounded() / displayScale
    }

    let snappedSelection = CGRect(
      x: snapped(selection.minX),
      y: snapped(selection.minY),
      width: snapped(selection.width),
      height: snapped(selection.height)
    )
    let points = selectionHandlePoints(for: snappedSelection)
    let cornerRadius: CGFloat = 4.9
    let edgeRadius: CGFloat = 4.3

    context.saveGState()
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)

    func drawHandle(at point: CGPoint, radius: CGFloat) {
      let diameter = radius * 2
      let rect = CGRect(
        x: snapped(point.x - radius),
        y: snapped(point.y - radius),
        width: diameter,
        height: diameter
      )

      context.setFillColor(NSColor.black.withAlphaComponent(0.76 * alpha).cgColor)
      context.fillEllipse(in: rect)
      context.setStrokeColor(NSColor.white.withAlphaComponent(alpha).cgColor)
      context.setLineWidth(max(1.0, pixel + 0.45))
      context.strokeEllipse(in: rect.insetBy(dx: pixel * 0.35, dy: pixel * 0.35))
    }

    for (corner, point) in points {
      drawHandle(at: point, radius: corner.isCorner ? cornerRadius : edgeRadius)
    }

    context.restoreGState()
  }
}
