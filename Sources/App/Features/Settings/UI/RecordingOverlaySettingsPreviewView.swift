import AppKit

@MainActor
final class RecordingOverlaySettingsPreviewView: NSView {
  var onClose: (() -> Void)?

  private let kind: RecordingOverlaySettingsPreviewKind
  private let placementView: CaptureOverlayPlacementView
  private let closeButton = SettingsPreviewCloseButton()
  private weak var settings: AppSettings?

  init(frame frameRect: NSRect, kind: RecordingOverlaySettingsPreviewKind, settings: AppSettings) {
    self.kind = kind
    placementView = CaptureOverlayPlacementView(kind: kind == .webcam ? .webcam : .keystroke)
    self.settings = settings
    super.init(frame: frameRect)

    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor

    placementView.translatesAutoresizingMaskIntoConstraints = true
    placementView.onFrameChanged = { [weak self] frame in
      self?.persist(frame: frame)
    }
    addSubview(placementView)

    addSubview(closeButton)

    update(settings: settings)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  override var isOpaque: Bool { false }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    let frame = placementContainerFrame.insetBy(dx: 0.5, dy: 0.5)
    NSColor.systemRed.withAlphaComponent(0.70).setStroke()
    let outline = NSBezierPath(roundedRect: frame, xRadius: 6, yRadius: 6)
    outline.lineWidth = 1.5
    outline.setLineDash([7, 5], count: 2, phase: 0)
    outline.stroke()
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    guard bounds.contains(point) else {
      return nil
    }
    if closeButtonHitFrame.contains(point) {
      return self
    }
    return placementView.hitTest(placementView.convert(point, from: self))
  }

  override func mouseUp(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    if closeButtonHitFrame.contains(point) {
      onClose?()
    }
  }

  override func layout() {
    super.layout()
    let containerFrame = placementContainerFrame
    let closeButtonSize = CGSize(width: 116, height: 30)
    closeButton.frame = CGRect(
      x: containerFrame.maxX - closeButtonSize.width,
      y: min(bounds.maxY - closeButtonSize.height - 12, containerFrame.maxY + 12),
      width: closeButtonSize.width,
      height: closeButtonSize.height
    ).integral

    guard let settings else {
      return
    }
    placementView.containerFrame = containerFrame
    switch kind {
    case .webcam:
      placementView.frame = resolvedWebcamOverlayFrame(settings.webcamOverlayNormalizedFrame, in: containerFrame)
    case .keystroke:
      placementView.frame = resolvedOverlayFrame(settings.keystrokeOverlayNormalizedFrame, in: containerFrame)
    }
  }

  func startPreview() {
    guard let settings, kind == .webcam else {
      return
    }
    placementView.updateWebcamPreview(preferredDeviceID: settings.webcamDeviceID)
  }

  func stopPreview() {
    placementView.stopWebcamPreview()
  }

  func update(settings: AppSettings) {
    self.settings = settings
    switch kind {
    case .webcam:
      placementView.webcamShape = settings.webcamOverlayShape
      placementView.webcamAspectRatio = settings.webcamOverlayAspectRatio
      placementView.updateWebcamPreview(preferredDeviceID: settings.webcamDeviceID)
    case .keystroke:
      placementView.keystrokeStyle = settings.keystrokeOverlayStyle
      placementView.keystrokeSize = settings.keystrokeOverlaySize
    }
    needsLayout = true
  }

  private var closeButtonHitFrame: CGRect {
    closeButton.frame.insetBy(dx: -8, dy: -8)
  }

  private func persist(frame: CGRect) {
    let containerFrame = placementContainerFrame
    guard let settings, containerFrame.width > 0, containerFrame.height > 0 else {
      return
    }
    let normalized = normalizedOverlayFrame(frame, in: containerFrame)
    switch kind {
    case .webcam:
      settings.setWebcamOverlayFrame(normalized)
    case .keystroke:
      settings.setKeystrokeOverlayFrame(normalized)
    }
  }

  private var placementContainerFrame: CGRect {
    let available = bounds.insetBy(dx: 48, dy: 84)
    guard available.width > 0, available.height > 0 else {
      return .zero
    }

    let targetRatio: CGFloat = 16.0 / 9.0
    var width = min(960, available.width)
    var height = width / targetRatio
    if height > available.height {
      height = available.height
      width = height * targetRatio
    }

    return CGRect(
      x: available.midX - width * 0.5,
      y: available.midY - height * 0.5,
      width: width,
      height: height
    ).integral
  }

  private func resolvedOverlayFrame(_ normalized: CGRect, in container: CGRect) -> CGRect {
    RecordingOverlayFrameGeometry.resolvedOverlayFrame(normalized, in: container)
  }

  private func resolvedWebcamOverlayFrame(_ normalized: CGRect, in container: CGRect) -> CGRect {
    guard let settings else {
      return resolvedOverlayFrame(normalized, in: container)
    }

    return RecordingOverlayFrameGeometry.resolvedWebcamOverlayFrame(
      normalized,
      in: container,
      shape: settings.webcamOverlayShape,
      aspectRatio: settings.webcamOverlayAspectRatio
    )
  }

  private func normalizedOverlayFrame(_ frame: CGRect, in container: CGRect) -> CGRect {
    RecordingOverlayFrameGeometry.normalizedOverlayFrame(frame, in: container)
  }
}

private final class SettingsPreviewCloseButton: NSView {
  private let shellView: NSView
  private let iconView = NSImageView()
  private let titleLabel = NSTextField(labelWithString: "Close Preview")

  init() {
    if #available(macOS 26.0, *) {
      let glassView = NSGlassEffectView()
      glassView.style = .regular
      glassView.cornerRadius = 15
      shellView = glassView
    } else {
      let visualEffectView = NSVisualEffectView()
      visualEffectView.blendingMode = .behindWindow
      visualEffectView.material = .hudWindow
      visualEffectView.state = .active
      visualEffectView.wantsLayer = true
      visualEffectView.layer?.cornerRadius = 15
      visualEffectView.layer?.masksToBounds = true
      shellView = visualEffectView
    }

    super.init(frame: .zero)

    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor
    translatesAutoresizingMaskIntoConstraints = true

    shellView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(shellView)

    iconView.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: nil)
    iconView.contentTintColor = .white.withAlphaComponent(0.88)
    iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
    iconView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(iconView)

    titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
    titleLabel.textColor = .white.withAlphaComponent(0.92)
    titleLabel.backgroundColor = .clear
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    addSubview(titleLabel)

    NSLayoutConstraint.activate([
      shellView.leadingAnchor.constraint(equalTo: leadingAnchor),
      shellView.trailingAnchor.constraint(equalTo: trailingAnchor),
      shellView.topAnchor.constraint(equalTo: topAnchor),
      shellView.bottomAnchor.constraint(equalTo: bottomAnchor),

      iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 11),
      iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
      iconView.widthAnchor.constraint(equalToConstant: 14),
      iconView.heightAnchor.constraint(equalToConstant: 14),

      titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
      titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
      titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  override var isOpaque: Bool {
    false
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    true
  }
}
