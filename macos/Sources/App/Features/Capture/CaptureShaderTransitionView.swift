import AppKit
import CoreGraphics
import CoreImage

@MainActor
final class CaptureShaderTransitionView: NSView {
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
      MainActor.assumeIsolated {
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

