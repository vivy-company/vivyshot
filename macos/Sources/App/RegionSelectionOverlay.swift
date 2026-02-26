import AppKit
import CoreImage
import CoreGraphics
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

@MainActor
private enum TransientToast {
  private static var panel: NSPanel?
  private static var label: NSTextField?
  private static var hideWorkItem: DispatchWorkItem?

  static func show(_ message: String, duration: TimeInterval = 1.25) {
    hideWorkItem?.cancel()
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

    let hide = DispatchWorkItem {
      Task { @MainActor in
        NSAnimationContext.runAnimationGroup { context in
          context.duration = 0.16
          context.timingFunction = CAMediaTimingFunction(name: .easeIn)
          panel.animator().alphaValue = 0
        } completionHandler: {
          Task { @MainActor in
            panel.orderOut(nil)
          }
        }
      }
    }
    hideWorkItem = hide
    DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: hide)
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
    onComplete: @escaping (CGRect?) -> Void
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

    selectionView.onSelectionResult = { [weak self, weak window] localRect in
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

      onComplete(globalRect)
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

    selectionView.enterEditing(session: session, selectionRect: localRect) { [weak self] in
      self?.closeWindow()
      onDone()
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
      } completionHandler: {
        Task { @MainActor in
          self.disposeWindow(window, selectionView: selectionView)
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
private final class CaptureShaderTransitionView: NSView {
  enum ShaderStyle {
    case liquidDrop
    case zoomBlur
    case waterWave

    init?(captureStyle: CaptureTransitionStyle) {
      switch captureStyle {
      case .liquidDrop:
        self = .liquidDrop
      case .zoomBlur:
        self = .zoomBlur
      case .waterWave:
        self = .waterWave
      case .none, .fade, .ripple:
        return nil
      }
    }
  }

  private let snapshot: CGImage
  private let baseImage: CIImage
  private let glassNoiseTexture: CIImage
  private let rippleShadingTexture: CIImage
  private let style: ShaderStyle
  private let entering: Bool
  private let duration: TimeInterval
  private let intensity: CGFloat
  private let ciContext = CIContext(options: [
    .cacheIntermediates: false,
    .useSoftwareRenderer: false,
  ])
  private var startTime: CFTimeInterval = 0
  private var frameTimer: Timer?
  private var onFinish: (() -> Void)?

  init(
    frame: CGRect,
    snapshot: CGImage,
    style: ShaderStyle,
    entering: Bool,
    duration: TimeInterval,
    intensity: CGFloat,
    onFinish: (() -> Void)?
  ) {
    self.snapshot = snapshot
    baseImage = CIImage(cgImage: snapshot)
    glassNoiseTexture = Self.makeNoiseTexture(extent: baseImage.extent)
    rippleShadingTexture = Self.makeRippleShadingTexture(extent: baseImage.extent)
    self.style = style
    self.entering = entering
    self.duration = max(0.06, duration)
    self.intensity = max(0.2, min(1, intensity))
    self.onFinish = onFinish
    super.init(frame: frame)
    wantsLayer = true
    layer?.contentsGravity = .resize
    layer?.masksToBounds = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  override func viewDidMoveToSuperview() {
    super.viewDidMoveToSuperview()
    if superview == nil {
      stopDisplayLink()
    }
  }

  func start() {
    stopDisplayLink()
    render(progress: 0)
    startTime = CACurrentMediaTime()

    let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
      Task { @MainActor in
        self?.tick(currentTime: CACurrentMediaTime())
      }
    }
    timer.tolerance = 1.0 / 240.0
    frameTimer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  private func stopDisplayLink() {
    frameTimer?.invalidate()
    frameTimer = nil
  }

  private func tick(currentTime: CFTimeInterval) {
    let elapsed = currentTime - startTime
    let progress = min(1, max(0, elapsed / duration))
    render(progress: progress)

    if progress >= 1 {
      stopDisplayLink()
      onFinish?()
      onFinish = nil
      removeFromSuperview()
    }
  }

  private func render(progress: Double) {
    let linearProgress = max(0, min(1, CGFloat(progress)))
    let easedProgress = smoothStep(linearProgress)
    let waveProgress = entering ? easedProgress : 1 - pow(1 - easedProgress, 1.25)
    let distorted = makeDistortedImage(waveProgress: waveProgress).cropped(to: baseImage.extent)

    if let output = ciContext.createCGImage(distorted, from: baseImage.extent) {
      layer?.contents = output
    } else {
      layer?.contents = snapshot
    }

    if entering {
      alphaValue = max(0, 1 - pow(linearProgress, 0.82))
    } else {
      alphaValue = max(0, 1 - pow(linearProgress, 0.72))
    }
  }

  private func makeDistortedImage(waveProgress: CGFloat) -> CIImage {
    let extent = baseImage.extent
    let center = CIVector(x: extent.midX, y: extent.midY)
    let maxDim = max(extent.width, extent.height)
    var output = baseImage

    switch style {
    case .liquidDrop:
      let rippleWidth = max(22, maxDim * (0.045 + 0.08 * intensity))
      let rippleScale = (10 + 28 * (1 - waveProgress)) * intensity
      output = applyRippleTransition(
        image: output,
        extent: extent,
        center: center,
        time: waveProgress,
        width: rippleWidth,
        scale: rippleScale
      )

      let bumpRadius = max(14, maxDim * (0.11 + 0.36 * waveProgress))
      let bumpScale = (0.36 - 0.28 * waveProgress) * intensity
      if let bump = CIFilter(name: "CIBumpDistortion") {
        bump.setValue(output, forKey: kCIInputImageKey)
        bump.setValue(center, forKey: kCIInputCenterKey)
        bump.setValue(bumpRadius, forKey: kCIInputRadiusKey)
        bump.setValue(bumpScale, forKey: kCIInputScaleKey)
        output = bump.outputImage ?? output
      }

      let twirlRadius = max(8, maxDim * (0.1 + 0.38 * waveProgress))
      let twirlAngle = (0.045 * pow(1 - waveProgress, 1.6)) * intensity
      if let twirl = CIFilter(name: "CITwirlDistortion") {
        twirl.setValue(output, forKey: kCIInputImageKey)
        twirl.setValue(center, forKey: kCIInputCenterKey)
        twirl.setValue(twirlRadius, forKey: kCIInputRadiusKey)
        twirl.setValue(twirlAngle, forKey: kCIInputAngleKey)
        output = twirl.outputImage ?? output
      }
      output = mixWithBaseImage(output, amount: 0.78)

    case .zoomBlur:
      if let blur = CIFilter(name: "CIZoomBlur") {
        blur.setValue(output, forKey: kCIInputImageKey)
        blur.setValue(center, forKey: kCIInputCenterKey)
        let amount = (5 + 36 * waveProgress) * intensity
        blur.setValue(amount, forKey: kCIInputAmountKey)
        output = blur.outputImage ?? output
      }
    case .waterWave:
      let primaryWidth = max(40, maxDim * (0.09 + 0.11 * intensity))
      let primaryScale = (11 + 30 * (1 - waveProgress)) * intensity
      output = applyRippleTransition(
        image: output,
        extent: extent,
        center: center,
        time: waveProgress,
        width: primaryWidth,
        scale: primaryScale
      )

      let orbit = CGFloat.pi * 2 * waveProgress
      let drift = maxDim * 0.01 * intensity
      let secondaryCenter = CIVector(
        x: extent.midX + drift * cos(orbit),
        y: extent.midY + drift * sin(orbit)
      )
      output = applyRippleTransition(
        image: output,
        extent: extent,
        center: secondaryCenter,
        time: min(1, waveProgress * 1.08),
        width: primaryWidth * 0.7,
        scale: primaryScale * 0.62
      )

      if let glass = CIFilter(name: "CIGlassDistortion") {
        glass.setValue(output, forKey: kCIInputImageKey)
        glass.setValue(glassNoiseTexture, forKey: "inputTexture")
        glass.setValue(center, forKey: kCIInputCenterKey)
        let scale = (2.2 + 9.5 * (1 - waveProgress)) * intensity
        glass.setValue(scale, forKey: kCIInputScaleKey)
        output = glass.outputImage ?? output
      }

      if let displacement = CIFilter(name: "CIDisplacementDistortion") {
        displacement.setValue(output, forKey: kCIInputImageKey)
        displacement.setValue(glassNoiseTexture, forKey: "inputDisplacementImage")
        let displacementScale = (1.6 + 6.2 * (1 - waveProgress)) * intensity
        displacement.setValue(displacementScale, forKey: kCIInputScaleKey)
        output = displacement.outputImage ?? output
      }
      output = mixWithBaseImage(output, amount: 0.68)
    }

    return output
  }

  private func applyRippleTransition(
    image: CIImage,
    extent: CGRect,
    center: CIVector,
    time: CGFloat,
    width: CGFloat,
    scale: CGFloat
  ) -> CIImage {
    guard let ripple = CIFilter(name: "CIRippleTransition") else {
      return image
    }
    ripple.setValue(image, forKey: kCIInputImageKey)
    ripple.setValue(image, forKey: kCIInputTargetImageKey)
    ripple.setValue(rippleShadingTexture, forKey: "inputShadingImage")
    ripple.setValue(center, forKey: kCIInputCenterKey)
    ripple.setValue(CIVector(cgRect: extent), forKey: "inputExtent")
    ripple.setValue(min(1, max(0, time)), forKey: kCIInputTimeKey)
    ripple.setValue(max(1, width), forKey: "inputWidth")
    ripple.setValue(scale, forKey: kCIInputScaleKey)
    return ripple.outputImage ?? image
  }

  private func smoothStep(_ x: CGFloat) -> CGFloat {
    let t = min(1, max(0, x))
    return t * t * (3 - 2 * t)
  }

  private func mixWithBaseImage(_ effectImage: CIImage, amount: CGFloat) -> CIImage {
    let clamped = max(0, min(1, amount))
    guard clamped < 0.999 else {
      return effectImage
    }
    guard clamped > 0.001 else {
      return baseImage
    }

    guard let alphaMatrix = CIFilter(name: "CIColorMatrix"),
          let composite = CIFilter(name: "CISourceOverCompositing") else {
      return effectImage
    }

    alphaMatrix.setValue(effectImage, forKey: kCIInputImageKey)
    alphaMatrix.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputRVector")
    alphaMatrix.setValue(CIVector(x: 0, y: 1, z: 0, w: 0), forKey: "inputGVector")
    alphaMatrix.setValue(CIVector(x: 0, y: 0, z: 1, w: 0), forKey: "inputBVector")
    alphaMatrix.setValue(CIVector(x: 0, y: 0, z: 0, w: clamped), forKey: "inputAVector")
    alphaMatrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBiasVector")

    let fadedEffect = alphaMatrix.outputImage ?? effectImage
    composite.setValue(fadedEffect, forKey: kCIInputImageKey)
    composite.setValue(baseImage, forKey: kCIInputBackgroundImageKey)
    return composite.outputImage ?? effectImage
  }

  private static func makeNoiseTexture(extent: CGRect) -> CIImage {
    let seed = CIFilter(name: "CIRandomGenerator")?.outputImage
      ?? CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
    return seed
      .applyingFilter("CIColorControls", parameters: [
        kCIInputSaturationKey: 0,
        kCIInputContrastKey: 1.14,
        kCIInputBrightnessKey: -0.03,
      ])
      .cropped(to: extent)
  }

  private static func makeRippleShadingTexture(extent: CGRect) -> CIImage {
    let center = CIVector(x: extent.midX, y: extent.midY)
    let maxRadius = max(extent.width, extent.height)
    let nearRadius = max(8, maxRadius * 0.035)
    let farRadius = max(nearRadius + 4, maxRadius * 0.58)

    let radial = CIFilter(name: "CIRadialGradient", parameters: [
      "inputCenter": center,
      "inputRadius0": nearRadius,
      "inputRadius1": farRadius,
      "inputColor0": CIColor(red: 0.82, green: 0.9, blue: 0.96, alpha: 0.34),
      "inputColor1": CIColor(red: 0.2, green: 0.34, blue: 0.42, alpha: 0.02),
    ])?.outputImage ?? CIImage(color: CIColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1))

    return radial
      .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 2.2])
      .applyingFilter("CIColorControls", parameters: [
        kCIInputSaturationKey: 0.35,
        kCIInputContrastKey: 0.84,
        kCIInputBrightnessKey: -0.02,
      ])
      .cropped(to: extent)
  }
}

@MainActor
private final class RegionSelectionWindow: NSWindow {
  var onUndo: (() -> Void)?
  var onRedo: (() -> Void)?
  var onCopy: (() -> Void)?
  var onSave: (() -> Void)?
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
  var onSelectionResult: ((CGRect?) -> Void)?
  var onCancelRequested: (() -> Void)?
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
  private lazy var toolbarHost = NSHostingView(rootView: makeEditorToolbar())
  private lazy var selectingHintHost = NSHostingView(rootView: CaptureHintGlassCard())
  private var toolbarOffset: CGSize = .zero
  private var toolbarDragStartOffset: CGSize?

  private var session: RustDocumentSession?
  private var onEditingDone: (() -> Void)?

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
  }

  override func resetCursorRects() {
    switch mode {
    case .selecting:
      addCursorRect(bounds, cursor: .crosshair)
    case .editing:
      addCursorRect(bounds, cursor: .arrow)
    }
  }

  override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)

    if mode == .editing {
      super.mouseDown(with: event)
      return
    }

    dragStart = point
    dragCurrent = point
    updateSelectingHintVisibility(animated: true)
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
    needsDisplay = true

    guard let selection, selection.width >= 2, selection.height >= 2 else {
      NSSound.beep()
      return
    }

    onSelectionResult?(selection)
  }

  override func keyDown(with event: NSEvent) {
    if event.keyCode == 53 { // Esc
      handleCancelShortcut()
      return
    }

    super.keyDown(with: event)
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    guard let context = NSGraphicsContext.current?.cgContext else {
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

  func enterEditing(
    session: RustDocumentSession,
    selectionRect: CGRect,
    onDone: @escaping () -> Void
  ) {
    let clipped = selectionRect.standardized.intersection(bounds).integral
    guard !clipped.isNull, clipped.width >= 2, clipped.height >= 2 else {
      onDone()
      return
    }

    guard let image = session.currentImage() else {
      onDone()
      return
    }

    self.session = session
    onEditingDone = onDone
    committedSelectionRect = clipped
    activeResizeCorner = nil
    resizeStartRect = nil
    toolbarOffset = .zero
    toolbarDragStartOffset = nil

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
  }

  func handleCancelShortcut() {
    switch mode {
    case .selecting:
      onCancelRequested?()
    case .editing:
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

    toolbarHost.translatesAutoresizingMaskIntoConstraints = true
    toolbarHost.isHidden = true
    addSubview(toolbarHost)

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
        Task { @MainActor in
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

  private func configureCanvasCallbacks() {
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
      self?.moveCapturedSelection(by: delta) ?? false
    }
    canvasView.onFinishMovingCaptureArea = { [weak self] in
      self?.finishMovingCapturedSelection()
    }
  }

  private func layoutEditorChrome() {
    guard mode == .editing, let selection = committedSelectionRect else {
      editingMaskView.isHidden = true
      setResizeHandlesHidden(true)
      return
    }

    canvasView.frame = bounds
    editingMaskView.frame = bounds
    editingMaskView.selectionRect = selection
    editingMaskView.isHidden = false
    updateCanvasPreviewStrokeWidth()

    toolbarHost.layoutSubtreeIfNeeded()
    var toolbarSize = toolbarHost.fittingSize
    if toolbarSize.width < 300 || toolbarSize.height < 30 {
      toolbarSize = CGSize(width: 430, height: 54)
    }

    let padding: CGFloat = 12
    let maxX = max(padding, bounds.width - toolbarSize.width - padding)
    let maxY = max(padding, bounds.height - toolbarSize.height - padding)

    let defaultX = min(max(padding, selection.midX - toolbarSize.width * 0.5), maxX)

    let proposedBelow = selection.minY - toolbarSize.height - 14
    let defaultY: CGFloat
    if proposedBelow >= padding {
      defaultY = proposedBelow
    } else {
      defaultY = min(maxY, selection.maxY + 14)
    }

    let unclampedX = defaultX + toolbarOffset.width
    let unclampedY = defaultY + toolbarOffset.height
    let x = min(max(padding, unclampedX), maxX)
    let y = min(max(padding, unclampedY), maxY)
    toolbarOffset = CGSize(width: x - defaultX, height: y - defaultY)

    toolbarHost.frame = CGRect(
      x: x,
      y: y,
      width: toolbarSize.width,
      height: toolbarSize.height
    ).integral

    layoutResizeHandles(for: selection)
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
      handle.alphaValue = 1
      handle.needsDisplay = true
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
    guard mode == .editing else {
      return
    }
    guard let committedSelectionRect else {
      return
    }

    activeResizeCorner = corner
    resizeStartRect = committedSelectionRect
  }

  private func updateResizingSelection(corner: ResizeCorner, delta: CGPoint) {
    guard mode == .editing else {
      return
    }
    guard activeResizeCorner == corner, let startRect = resizeStartRect else {
      return
    }

    guard let resized = resizedSelectionRect(from: startRect, corner: corner, delta: delta) else {
      return
    }

    committedSelectionRect = resized
    needsLayout = true
    needsDisplay = true
  }

  private func finishResizingSelection(corner: ResizeCorner, delta: CGPoint) {
    defer {
      activeResizeCorner = nil
      resizeStartRect = nil
    }

    guard mode == .editing else {
      return
    }

    guard activeResizeCorner == corner else {
      return
    }

    updateResizingSelection(corner: corner, delta: delta)
  }

  private func beginMovingCapturedSelectionPreview() {
    guard mode == .editing else {
      return
    }
  }

  private func moveCapturedSelection(by delta: CGPoint) -> Bool {
    guard mode == .editing, activeResizeCorner == nil else {
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

  private func makeEditorToolbar() -> EditorGlassToolbar {
    EditorGlassToolbar(
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

  private func setAnnotationColor(_ color: Color) {
    let nsColor = NSColor(color)
    guard let rgb = nsColor.usingColorSpace(.deviceRGB) else {
      return
    }
    annotationColor = rgb
  }

  private func refreshToolbar() {
    toolbarHost.rootView = makeEditorToolbar()
    needsLayout = true
  }

  private func observeSettingsChanges() {
    settingsObserver = NotificationCenter.default.addObserver(
      forName: .vivyShotSettingsDidChange,
      object: settings,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
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
      return
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

  private func finishEditing() {
    canvasView.finishInlineTextEditing(commit: true)
    let callback = onEditingDone
    onEditingDone = nil
    callback?()
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

    let hostLevel = window?.level.rawValue ?? NSWindow.Level.modalPanel.rawValue
    finishEditing()
    presentSavePanel(for: image, hostLevel: hostLevel)
  }

  private func presentSavePanel(for image: CGImage, hostLevel: Int) {
    let panel = NSSavePanel()
    panel.title = "Save Annotation"
    panel.nameFieldStringValue = "vivyshot.png"
    panel.canCreateDirectories = true
    panel.allowedContentTypes = [.png, .jpeg]
    panel.allowsOtherFileTypes = false

    panel.level = NSWindow.Level(rawValue: max(NSWindow.Level.modalPanel.rawValue, hostLevel + 1))
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.orderFrontRegardless()
    NSApp.activate(ignoringOtherApps: true)
    panel.begin { [weak self, panel] response in
      guard response == .OK, let url = panel.url else {
        return
      }
      self?.saveImage(image, to: url)
    }
  }

  private func exportImageForCurrentSelection() -> CGImage? {
    guard let image = canvasView.image else {
      return nil
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

  private func saveImage(_ image: CGImage, to url: URL) {
    let extType = UTType(filenameExtension: url.pathExtension.lowercased())
    let selectedType: UTType = (extType == .jpeg) ? .jpeg : .png

    guard let destination = CGImageDestinationCreateWithURL(
      url as CFURL,
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
