import AppKit
import CoreGraphics
import QuartzCore

@MainActor
final class RegionSelectionTransitionAnimator {
  private let settings: AppSettings

  init(settings: AppSettings) {
    self.settings = settings
  }

  func animateIn(_ window: NSWindow, style: CaptureTransitionStyle) {
    let duration = transitionDuration(entering: true, style: style)

    switch style {
    case .none:
      window.alphaValue = 1
    case .fade:
      window.alphaValue = 1
    case .ripple:
      window.alphaValue = 1
      applyCenterRippleTransition(to: window, entering: true, duration: duration)
    case .liquidDrop, .zoomBlur, .waterWave:
      window.alphaValue = 1
      applyShaderTransition(to: window, style: style, entering: true, duration: duration)
    }
  }

  func animateOut(
    _ window: NSWindow,
    selectionView: RegionSelectionView?,
    style: CaptureTransitionStyle,
    completion: (() -> Void)? = nil
  ) {
    nonisolated(unsafe) let completion = completion
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

  func disposeWindow(_ window: NSWindow, selectionView: RegionSelectionView?) {
    selectionView?.prepareForClose()
    window.contentView = nil
    window.orderOut(nil)
    window.close()
  }

  func transitionDuration(entering: Bool, style: CaptureTransitionStyle) -> TimeInterval {
    let speed = max(0.5, min(2.4, settings.captureTransitionSpeed))
    let base: TimeInterval
    switch style {
    case .none:
      return 0
    case .fade:
      base = entering ? 0.24 : 0.2
    case .ripple:
      base = entering ? 0.44 : 0.36
    case .liquidDrop:
      base = entering ? 0.52 : 0.44
    case .zoomBlur:
      base = entering ? 0.38 : 0.32
    case .waterWave:
      base = entering ? 0.58 : 0.48
    }
    return max(0.12, base / speed)
  }

  func glassChromeRevealDelay(style: CaptureTransitionStyle) -> TimeInterval {
    switch style {
    case .fade, .ripple:
      return transitionDuration(entering: true, style: style) + 0.016
    case .none, .liquidDrop, .zoomBlur, .waterWave:
      return 0.032
    }
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
