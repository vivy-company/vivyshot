import AppKit
import CoreGraphics
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct EditorTextStyle {
  var fontSize: CGFloat
  var color: NSColor
  var fontName: String

  init(fontSize: CGFloat, color: NSColor, fontName: String = "System") {
    self.fontSize = fontSize
    self.color = color
    self.fontName = fontName
  }
}

@MainActor
final class PreviewWindowController: NSWindowController {
  private let settings = AppSettings.shared
  private let canvasView = AnnotationCanvasView()
  private lazy var toolbarHost = NSHostingView(rootView: makeToolbarRootView())
  private var settingsObserver: NSObjectProtocol?

  private var session: RustDocumentSession?
  private var annotationColor: NSColor = .systemOrange {
    didSet {
      canvasView.accentColor = annotationColor
      textStyle = EditorTextStyle(
        fontSize: textStyle.fontSize,
        color: annotationColor,
        fontName: textStyle.fontName
      )
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

  init() {
    let window = EditorWindow(
      contentRect: NSRect(x: 120, y: 120, width: 800, height: 500),
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )

    window.backgroundColor = .clear
    window.isOpaque = false
    window.hasShadow = true
    window.level = .statusBar
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    window.isReleasedWhenClosed = false

    super.init(window: window)
    configure()
    observeSettingsChanges()
    applySettingsFromPreferences()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  func show(session: RustDocumentSession, selectionRectInScreen: CGRect) {
    self.session = session
    if let image = session.currentImage() {
      canvasView.image = image
      updateCanvasPreviewStrokeWidth()
    }

    let frame = selectionRectInScreen.standardized.integral
    if frame.width >= 80, frame.height >= 80 {
      window?.setFrame(frame, display: false)
    }

    showWindow(nil)
    window?.makeKeyAndOrderFront(nil)
    window?.makeFirstResponder(canvasView)
    NSApp.activate(ignoringOtherApps: true)
  }

  private func configure() {
    if let editorWindow = window as? EditorWindow {
      configureWindowShortcuts(editorWindow)
    }

    guard let contentView = window?.contentView else {
      return
    }

    let topBar = makeTopBar()

    canvasView.translatesAutoresizingMaskIntoConstraints = false
    canvasView.tool = currentTool
    canvasView.accentColor = annotationColor
    canvasView.textStyle = textStyle
    updateCanvasPreviewStrokeWidth()
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

    contentView.addSubview(canvasView)
    contentView.addSubview(topBar)

    NSLayoutConstraint.activate([
      canvasView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      canvasView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      canvasView.topAnchor.constraint(equalTo: contentView.topAnchor),
      canvasView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
      topBar.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
      topBar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
    ])

    refreshToolbar()
  }

  private func configureWindowShortcuts(_ editorWindow: EditorWindow) {
    editorWindow.onUndo = { [weak self] in self?.performUndo() }
    editorWindow.onRedo = { [weak self] in self?.performRedo() }
    editorWindow.onCopy = { [weak self] in self?.performCopy() }
    editorWindow.onSave = { [weak self] in self?.performSave() }
    editorWindow.onZoomIn = { [weak self] in
      self?.canvasView.zoomIn()
    }
    editorWindow.onZoomOut = { [weak self] in
      self?.canvasView.zoomOut()
    }
    editorWindow.onZoomReset = { [weak self] in
      self?.canvasView.resetZoomAndPan()
    }
    editorWindow.onCancel = { [weak self] in
      self?.window?.orderOut(nil)
    }
  }

  private func makeTopBar() -> NSView {
    let container = NSView()
    container.translatesAutoresizingMaskIntoConstraints = false

    toolbarHost.translatesAutoresizingMaskIntoConstraints = false
    toolbarHost.layer?.cornerRadius = 16
    toolbarHost.layer?.masksToBounds = false

    container.addSubview(toolbarHost)
    NSLayoutConstraint.activate([
      toolbarHost.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      toolbarHost.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      toolbarHost.topAnchor.constraint(equalTo: container.topAnchor),
      toolbarHost.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])

    return container
  }

  private func makeToolbarRootView() -> EditorGlassToolbar {
    EditorGlassToolbar(
      selectedCaptureMode: .selection,
      onSelectCaptureMode: { _ in },
      onCloseCapture: { [weak self] in
        self?.window?.orderOut(nil)
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
      onAddStitchSegment: nil,
      onResetStitch: nil,
      isStitchRecordingActive: false,
      isStitchCaptureInProgress: false,
      onDone: { [weak self] in
        self?.window?.orderOut(nil)
      },
      onToolbarDrag: nil,
      onToolbarDragEnd: nil
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
    toolbarHost.rootView = makeToolbarRootView()
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
      return
    }

    refreshToolbar()
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

    guard let image = canvasView.image else {
      NSSound.beep()
      return
    }

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    if !pasteboard.writeObjects([nsImage]) {
      NSSound.beep()
    }
  }

  private func performSave() {
    canvasView.finishInlineTextEditing(commit: true)

    guard let image = canvasView.image else {
      NSSound.beep()
      return
    }

    let panel = NSSavePanel()
    panel.title = "Save Annotation"
    panel.nameFieldStringValue = "vivyshot.png"
    panel.canCreateDirectories = true
    panel.allowedContentTypes = [.png, .jpeg]
    panel.allowsOtherFileTypes = false

    let hostLevel = window?.level.rawValue ?? NSWindow.Level.modalPanel.rawValue
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
  }
}

@MainActor
private final class EditorWindow: NSWindow {
  var onUndo: (() -> Void)?
  var onRedo: (() -> Void)?
  var onCopy: (() -> Void)?
  var onSave: (() -> Void)?
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
