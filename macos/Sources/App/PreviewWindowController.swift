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
    guard let contentView = window?.contentView else {
      return
    }

    let topBar = makeTopBar()

    canvasView.translatesAutoresizingMaskIntoConstraints = false
    canvasView.tool = currentTool
    canvasView.accentColor = annotationColor
    canvasView.textStyle = textStyle
    updateCanvasPreviewStrokeWidth()
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

    if let editorWindow = window as? EditorWindow {
      editorWindow.onUndo = { [weak self] in
        self?.performUndo()
      }
      editorWindow.onRedo = { [weak self] in
        self?.performRedo()
      }
      editorWindow.onCopy = { [weak self] in
        self?.performCopy()
      }
      editorWindow.onSave = { [weak self] in
        self?.performSave()
      }
      editorWindow.onCancel = { [weak self] in
        self?.window?.orderOut(nil)
      }
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

private enum AnnotationResizeHandle: CaseIterable {
  case topLeft
  case topRight
  case bottomLeft
  case bottomRight
}

@MainActor
final class AnnotationCanvasView: NSView {
  var tool: AnnotationTool = .rect {
    didSet {
      if tool != .text {
        finishInlineTextEditing(commit: true)
      }
      if tool != .move {
        movingAnnotationIndex = nil
        resizingAnnotationIndex = nil
        activeResizeHandle = nil
        resizeStartBoundsInView = nil
        resizeStartPointInView = nil
        selectedAnnotationIndex = nil
        selectedAnnotationBoundsInView = nil
        movingCaptureArea = false
        lastCaptureMovePointInWindow = nil
        captureMoveGestureBegan = false
      }
      if tool != .paint {
        paintPathPointsInView.removeAll(keepingCapacity: false)
      }
      needsDisplay = true
    }
  }

  var textStyle = EditorTextStyle(fontSize: 16, color: .white) {
    didSet {
      updateInlineTextFieldStyle()
      needsDisplay = true
    }
  }

  var image: CGImage? {
    didSet {
      needsDisplay = true
      window?.invalidateCursorRects(for: self)
    }
  }

  var onCommitRect: ((CGRect) -> Void)?
  var onCommitFilledRect: ((CGRect) -> Void)?
  var onCommitCircle: ((CGRect) -> Void)?
  var onCommitFilledCircle: ((CGRect) -> Void)?
  var onCommitLine: ((CGPoint, CGPoint) -> Void)?
  var onCommitArrow: ((CGPoint, CGPoint) -> Void)?
  var onCommitPaintPath: (([CGPoint]) -> Void)?
  var onCommitText: ((String, CGPoint) -> Void)?
  var onCommitPixelateRect: ((CGRect) -> Void)?
  var onCommitBlurRect: ((CGRect) -> Void)?
  var onHitTestAnnotation: ((CGPoint) -> RustAnnotationInfo?)?
  var onMoveAnnotation: ((Int, CGPoint) -> CGImage?)?
  var onResizeAnnotation: ((Int, CGRect) -> CGImage?)?
  var onDeleteAnnotation: ((Int) -> CGImage?)?
  var onBeginMovingCaptureArea: (() -> Void)?
  var onMoveCaptureArea: ((CGPoint) -> Bool)?
  var onFinishMovingCaptureArea: (() -> Void)?

  var accentColor: NSColor = .systemOrange {
    didSet {
      needsDisplay = true
    }
  }

  var previewStrokeWidth: CGFloat = 3.5 {
    didSet {
      needsDisplay = true
    }
  }

  private var dragStart: CGPoint?
  private var dragCurrent: CGPoint?
  private var inlineTextAnchorInView: CGPoint?
  private var inlineTextField: InlineTextField?
  private var selectedAnnotationIndex: Int?
  private var movingAnnotationIndex: Int?
  private var resizingAnnotationIndex: Int?
  private var lastMovePointInImage: CGPoint?
  private var selectedAnnotationBoundsInView: CGRect?
  private var activeResizeHandle: AnnotationResizeHandle?
  private var resizeStartBoundsInView: CGRect?
  private var resizeStartPointInView: CGPoint?
  private var paintPathPointsInView: [CGPoint] = []
  private var movingCaptureArea = false
  private var lastCaptureMovePointInWindow: CGPoint?
  private var captureMoveGestureBegan = false

  override var acceptsFirstResponder: Bool { true }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    guard let context = NSGraphicsContext.current?.cgContext else {
      return
    }

    guard let image, let destination = imageDestinationRect() else {
      return
    }

    context.interpolationQuality = .high
    context.draw(image, in: destination)

    switch tool {
    case .move:
      break
    case .rect:
      guard let previewRect = dragRectInView() else {
        return
      }
      context.setFillColor(accentColor.withAlphaComponent(0.12).cgColor)
      context.fill(previewRect)
      context.setStrokeColor(accentColor.cgColor)
      context.setLineWidth(previewStrokeWidth)
      context.stroke(previewRect)
    case .filledRect:
      guard let previewRect = dragRectInView() else {
        return
      }
      context.setFillColor(accentColor.withAlphaComponent(0.3).cgColor)
      context.fill(previewRect)
      context.setStrokeColor(accentColor.withAlphaComponent(0.9).cgColor)
      context.setLineWidth(max(1.6, previewStrokeWidth * 0.33))
      context.stroke(previewRect)
    case .circle:
      guard let previewRect = dragRectInView() else {
        return
      }
      context.setFillColor(accentColor.withAlphaComponent(0.12).cgColor)
      context.fillEllipse(in: previewRect)
      context.setStrokeColor(accentColor.cgColor)
      context.setLineWidth(previewStrokeWidth)
      context.strokeEllipse(in: previewRect)
    case .filledCircle:
      guard let previewRect = dragRectInView() else {
        return
      }
      context.setFillColor(accentColor.withAlphaComponent(0.3).cgColor)
      context.fillEllipse(in: previewRect)
      context.setStrokeColor(accentColor.withAlphaComponent(0.9).cgColor)
      context.setLineWidth(max(1.6, previewStrokeWidth * 0.33))
      context.strokeEllipse(in: previewRect)
    case .line:
      guard let (start, end) = dragLineInView() else {
        return
      }
      context.setStrokeColor(accentColor.cgColor)
      context.setLineWidth(previewStrokeWidth)
      context.setLineCap(.round)
      context.setLineJoin(.round)
      context.move(to: start)
      context.addLine(to: end)
      context.strokePath()
    case .arrow:
      guard let (start, end) = dragLineInView() else {
        return
      }
      drawArrowPreview(context: context, start: start, end: end, color: accentColor)
    case .paint:
      drawPaintPathPreview(context: context)
    case .text:
      if inlineTextField != nil {
        return
      }
      guard let point = dragCurrent ?? dragStart else {
        return
      }
      drawTextCursorPreview(context: context, point: point, color: textStyle.color)
    case .pixelate:
      guard let previewRect = dragRectInView() else {
        return
      }
      context.setFillColor(accentColor.withAlphaComponent(0.12).cgColor)
      context.fill(previewRect)
      context.setStrokeColor(accentColor.cgColor)
      context.setLineWidth(previewStrokeWidth)
      context.stroke(previewRect)
    case .blur:
      guard let previewRect = dragRectInView() else {
        return
      }
      context.setFillColor(accentColor.withAlphaComponent(0.12).cgColor)
      context.fill(previewRect)
      context.setStrokeColor(accentColor.cgColor)
      context.setLineWidth(previewStrokeWidth)
      context.stroke(previewRect)
    }

    if tool == .move {
      drawMoveSelectionPreview(context: context)
    }
  }

  override func resetCursorRects() {
    if let imageRect = imageDestinationRect() {
      addCursorRect(imageRect, cursor: tool == .move ? .openHand : .crosshair)
    } else {
      addCursorRect(bounds, cursor: .arrow)
    }
  }

  override func keyDown(with event: NSEvent) {
    if tool == .move, isDeleteKey(event) {
      if !deleteSelectedAnnotation() {
        NSSound.beep()
      }
      return
    }
    super.keyDown(with: event)
  }

  override func menu(for event: NSEvent) -> NSMenu? {
    guard tool == .move else {
      return nil
    }

    let point = convert(event.locationInWindow, from: nil)
    guard let (hit, _, selectedBounds) = hitAnnotation(at: point) else {
      return nil
    }

    selectedAnnotationIndex = hit.index
    movingAnnotationIndex = nil
    resizingAnnotationIndex = nil
    activeResizeHandle = nil
    resizeStartBoundsInView = nil
    resizeStartPointInView = nil
    lastMovePointInImage = nil
    selectedAnnotationBoundsInView = selectedBounds
    needsDisplay = true

    let menu = NSMenu(title: "Annotation")
    let deleteItem = NSMenuItem(title: "Delete", action: #selector(handleDeleteFromMenu), keyEquivalent: "")
    deleteItem.target = self
    menu.addItem(deleteItem)
    return menu
  }

  override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)

    if tool == .text {
      if let inlineTextField, inlineTextField.frame.contains(point) {
        window?.makeFirstResponder(inlineTextField)
        return
      }
      finishInlineTextEditing(commit: true)
    }

    guard let imageRect = imageDestinationRect(), imageRect.contains(point) else {
      dragStart = nil
      dragCurrent = nil
      selectedAnnotationIndex = nil
      movingAnnotationIndex = nil
      resizingAnnotationIndex = nil
      activeResizeHandle = nil
      resizeStartBoundsInView = nil
      resizeStartPointInView = nil
      lastMovePointInImage = nil
      selectedAnnotationBoundsInView = nil
      paintPathPointsInView.removeAll(keepingCapacity: false)
      movingCaptureArea = false
      lastCaptureMovePointInWindow = nil
      captureMoveGestureBegan = false
      needsDisplay = true
      return
    }

    if tool == .paint {
      let clamped = clampedToImageRect(point)
      dragStart = clamped
      dragCurrent = clamped
      paintPathPointsInView = [clamped]
      needsDisplay = true
      return
    }

    if tool == .move {
      movingCaptureArea = false
      lastCaptureMovePointInWindow = nil
      captureMoveGestureBegan = false

      if let selectedAnnotationIndex,
         let selectedBounds = selectedAnnotationBoundsInView,
         let handle = resizeHandle(at: point, in: selectedBounds) {
        resizingAnnotationIndex = selectedAnnotationIndex
        movingAnnotationIndex = nil
        lastMovePointInImage = nil
        activeResizeHandle = handle
        resizeStartBoundsInView = selectedBounds
        resizeStartPointInView = point
        needsDisplay = true
        return
      }

      guard let imagePoint = imagePointFromViewPoint(point),
            let hit = onHitTestAnnotation?(imagePoint),
            let selectedBounds = viewRectFromImageRect(hit.bounds) else {
        if onMoveCaptureArea != nil {
          selectedAnnotationIndex = nil
          movingAnnotationIndex = nil
          resizingAnnotationIndex = nil
          activeResizeHandle = nil
          resizeStartBoundsInView = nil
          resizeStartPointInView = nil
          lastMovePointInImage = nil
          selectedAnnotationBoundsInView = nil
          movingCaptureArea = true
          lastCaptureMovePointInWindow = event.locationInWindow
          captureMoveGestureBegan = false
          needsDisplay = true
          return
        }

        selectedAnnotationIndex = nil
        movingAnnotationIndex = nil
        resizingAnnotationIndex = nil
        activeResizeHandle = nil
        resizeStartBoundsInView = nil
        resizeStartPointInView = nil
        lastMovePointInImage = nil
        selectedAnnotationBoundsInView = nil
        movingCaptureArea = false
        lastCaptureMovePointInWindow = nil
        captureMoveGestureBegan = false
        needsDisplay = true
        return
      }

      selectedAnnotationIndex = hit.index
      movingAnnotationIndex = hit.index
      resizingAnnotationIndex = nil
      activeResizeHandle = nil
      resizeStartBoundsInView = nil
      resizeStartPointInView = nil
      lastMovePointInImage = imagePoint
      selectedAnnotationBoundsInView = selectedBounds
      movingCaptureArea = false
      lastCaptureMovePointInWindow = nil
      captureMoveGestureBegan = false
      needsDisplay = true
      return
    }

    dragStart = point
    dragCurrent = point
    needsDisplay = true
  }

  override func mouseDragged(with event: NSEvent) {
    if tool == .text {
      return
    }

    if tool == .paint {
      guard dragStart != nil else {
        return
      }

      let point = clampedToImageRect(convert(event.locationInWindow, from: nil))
      dragCurrent = point
      if let last = paintPathPointsInView.last {
        let distance = hypot(point.x - last.x, point.y - last.y)
        if distance >= 0.8 {
          paintPathPointsInView.append(point)
        } else if paintPathPointsInView.count == 1 {
          paintPathPointsInView.append(point)
        }
      } else {
        paintPathPointsInView.append(point)
      }
      needsDisplay = true
      return
    }

    if tool == .move {
      if let resizingAnnotationIndex,
         let activeResizeHandle,
         let resizeStartBoundsInView,
         let resizeStartPointInView {
        let currentPointInView = clampedToImageRect(convert(event.locationInWindow, from: nil))
        let delta = CGPoint(
          x: currentPointInView.x - resizeStartPointInView.x,
          y: currentPointInView.y - resizeStartPointInView.y
        )
        guard let resizedBoundsInView = resizedAnnotationBounds(
          from: resizeStartBoundsInView,
          handle: activeResizeHandle,
          delta: delta
        ) else {
          return
        }
        guard let resizedBoundsInImage = imageRectFromViewRect(resizedBoundsInView),
              let updatedImage = onResizeAnnotation?(resizingAnnotationIndex, resizedBoundsInImage) else {
          return
        }
        image = updatedImage
        selectedAnnotationBoundsInView = resizedBoundsInView
        needsDisplay = true
        return
      }

      if movingCaptureArea {
        let currentPointInWindow = event.locationInWindow
        guard let previousPointInWindow = lastCaptureMovePointInWindow else {
          lastCaptureMovePointInWindow = currentPointInWindow
          return
        }

        let delta = CGPoint(
          x: currentPointInWindow.x - previousPointInWindow.x,
          y: currentPointInWindow.y - previousPointInWindow.y
        )
        lastCaptureMovePointInWindow = currentPointInWindow

        guard abs(delta.x) >= 0.25 || abs(delta.y) >= 0.25 else {
          return
        }

        if !captureMoveGestureBegan {
          captureMoveGestureBegan = true
          onBeginMovingCaptureArea?()
        }

        if onMoveCaptureArea?(delta) == true {
          needsDisplay = true
        }
        return
      }

      guard let movingAnnotationIndex,
            let previousImagePoint = lastMovePointInImage else {
        return
      }

      let currentPointInView = clampedToImageRect(convert(event.locationInWindow, from: nil))
      guard let currentImagePoint = imagePointFromViewPoint(currentPointInView) else {
        return
      }

      let dx = Int((currentImagePoint.x - previousImagePoint.x).rounded())
      let dy = Int((currentImagePoint.y - previousImagePoint.y).rounded())
      guard dx != 0 || dy != 0 else {
        return
      }

      let delta = CGPoint(x: CGFloat(dx), y: CGFloat(dy))
      guard let updatedImage = onMoveAnnotation?(movingAnnotationIndex, delta) else {
        return
      }

      image = updatedImage
      selectedAnnotationIndex = movingAnnotationIndex
      lastMovePointInImage = CGPoint(
        x: previousImagePoint.x + CGFloat(dx),
        y: previousImagePoint.y + CGFloat(dy)
      )

      if let viewDelta = viewDeltaFromImageDelta(delta), var selected = selectedAnnotationBoundsInView {
        selected.origin.x += viewDelta.x
        selected.origin.y += viewDelta.y
        selectedAnnotationBoundsInView = selected
      }

      needsDisplay = true
      return
    }

    guard dragStart != nil else {
      return
    }

    dragCurrent = clampedToImageRect(convert(event.locationInWindow, from: nil))
    needsDisplay = true
  }

  override func mouseUp(with event: NSEvent) {
    if tool == .move {
      let didMoveCaptureArea = movingCaptureArea && captureMoveGestureBegan
      movingAnnotationIndex = nil
      resizingAnnotationIndex = nil
      activeResizeHandle = nil
      resizeStartBoundsInView = nil
      resizeStartPointInView = nil
      lastMovePointInImage = nil
      movingCaptureArea = false
      lastCaptureMovePointInWindow = nil
      captureMoveGestureBegan = false
      needsDisplay = true
      if didMoveCaptureArea {
        onFinishMovingCaptureArea?()
      }
      return
    }

    guard dragStart != nil else {
      return
    }

    if tool == .paint {
      let point = clampedToImageRect(convert(event.locationInWindow, from: nil))
      dragCurrent = point
      if let last = paintPathPointsInView.last {
        let distance = hypot(point.x - last.x, point.y - last.y)
        if distance >= 0.1 {
          paintPathPointsInView.append(point)
        }
      } else {
        paintPathPointsInView.append(point)
      }

      let committedPath = paintPathPointsInView
      dragStart = nil
      dragCurrent = nil
      paintPathPointsInView.removeAll(keepingCapacity: false)
      needsDisplay = true

      let imagePoints = imagePointsFromViewPoints(committedPath)
      if !imagePoints.isEmpty {
        onCommitPaintPath?(imagePoints)
      }
      return
    }

    dragCurrent = clampedToImageRect(convert(event.locationInWindow, from: nil))
    let committedViewRect = dragRectInView()
    let committedViewLine = dragLineInView()
    let committedViewPoint = dragCurrent
    dragStart = nil
    dragCurrent = nil
    needsDisplay = true

    switch tool {
    case .move:
      return
    case .rect:
      guard let committedViewRect, let imageRect = imageRectFromViewRect(committedViewRect) else {
        return
      }
      onCommitRect?(imageRect)
    case .filledRect:
      guard let committedViewRect, let imageRect = imageRectFromViewRect(committedViewRect) else {
        return
      }
      onCommitFilledRect?(imageRect)
    case .circle:
      guard let committedViewRect, let imageRect = imageRectFromViewRect(committedViewRect) else {
        return
      }
      onCommitCircle?(imageRect)
    case .filledCircle:
      guard let committedViewRect, let imageRect = imageRectFromViewRect(committedViewRect) else {
        return
      }
      onCommitFilledCircle?(imageRect)
    case .line:
      guard let (start, end) = committedViewLine,
            let imageStart = imagePointFromViewPoint(start),
            let imageEnd = imagePointFromViewPoint(end) else {
        return
      }
      onCommitLine?(imageStart, imageEnd)
    case .arrow:
      guard let (start, end) = committedViewLine,
            let imageStart = imagePointFromViewPoint(start),
            let imageEnd = imagePointFromViewPoint(end) else {
        return
      }
      onCommitArrow?(imageStart, imageEnd)
    case .paint:
      return
    case .text:
      guard let pointInView = committedViewPoint,
            let imagePoint = imagePointFromViewPoint(pointInView) else {
        return
      }
      beginInlineTextEditor(at: pointInView, imagePoint: imagePoint)
    case .pixelate:
      guard let committedViewRect, let imageRect = imageRectFromViewRect(committedViewRect) else {
        return
      }
      onCommitPixelateRect?(imageRect)
    case .blur:
      guard let committedViewRect, let imageRect = imageRectFromViewRect(committedViewRect) else {
        return
      }
      onCommitBlurRect?(imageRect)
    }
  }

  @objc
  private func handleDeleteFromMenu(_: Any?) {
    _ = deleteSelectedAnnotation()
  }

  private func deleteSelectedAnnotation() -> Bool {
    guard tool == .move, let selectedAnnotationIndex else {
      return false
    }

    guard let updatedImage = onDeleteAnnotation?(selectedAnnotationIndex) else {
      return false
    }

    image = updatedImage
    movingAnnotationIndex = nil
    resizingAnnotationIndex = nil
    activeResizeHandle = nil
    resizeStartBoundsInView = nil
    resizeStartPointInView = nil
    lastMovePointInImage = nil
    self.selectedAnnotationIndex = nil
    selectedAnnotationBoundsInView = nil
    movingCaptureArea = false
    lastCaptureMovePointInWindow = nil
    captureMoveGestureBegan = false
    needsDisplay = true
    return true
  }

  func selectAnnotation(atImagePoint imagePoint: CGPoint) {
    guard let hit = onHitTestAnnotation?(imagePoint),
          let selectedBounds = viewRectFromImageRect(hit.bounds) else {
      selectedAnnotationIndex = nil
      movingAnnotationIndex = nil
      resizingAnnotationIndex = nil
      activeResizeHandle = nil
      resizeStartBoundsInView = nil
      resizeStartPointInView = nil
      lastMovePointInImage = nil
      selectedAnnotationBoundsInView = nil
      movingCaptureArea = false
      lastCaptureMovePointInWindow = nil
      captureMoveGestureBegan = false
      needsDisplay = true
      return
    }

    selectedAnnotationIndex = hit.index
    movingAnnotationIndex = nil
    resizingAnnotationIndex = nil
    activeResizeHandle = nil
    resizeStartBoundsInView = nil
    resizeStartPointInView = nil
    lastMovePointInImage = nil
    selectedAnnotationBoundsInView = selectedBounds
    movingCaptureArea = false
    lastCaptureMovePointInWindow = nil
    captureMoveGestureBegan = false
    needsDisplay = true
  }

  private func isDeleteKey(_ event: NSEvent) -> Bool {
    guard event.type == .keyDown else {
      return false
    }
    return event.keyCode == 51 || event.keyCode == 117
  }

  private func hitAnnotation(at viewPoint: CGPoint) -> (RustAnnotationInfo, CGPoint, CGRect)? {
    guard let imagePoint = imagePointFromViewPoint(viewPoint),
          let hit = onHitTestAnnotation?(imagePoint),
          let selectedBounds = viewRectFromImageRect(hit.bounds) else {
      return nil
    }
    return (hit, imagePoint, selectedBounds)
  }

  private func dragLineInView() -> (CGPoint, CGPoint)? {
    guard let start = dragStart, let end = dragCurrent else {
      return nil
    }

    let distance = hypot(end.x - start.x, end.y - start.y)
    guard distance >= 2 else {
      return nil
    }

    return (start, end)
  }

  private func dragRectInView() -> CGRect? {
    guard let dragStart, let dragCurrent else {
      return nil
    }

    let raw = CGRect(
      x: min(dragStart.x, dragCurrent.x),
      y: min(dragStart.y, dragCurrent.y),
      width: abs(dragCurrent.x - dragStart.x),
      height: abs(dragCurrent.y - dragStart.y)
    )

    guard raw.width >= 2, raw.height >= 2 else {
      return nil
    }

    guard let imageRect = imageDestinationRect() else {
      return nil
    }

    let clipped = raw.intersection(imageRect)
    guard !clipped.isNull, clipped.width >= 2, clipped.height >= 2 else {
      return nil
    }

    return clipped.integral
  }

  private func imageRectFromViewRect(_ viewRect: CGRect) -> CGRect? {
    guard let image, let destination = imageDestinationRect() else {
      return nil
    }

    let clipped = viewRect.intersection(destination)
    guard !clipped.isNull, clipped.width >= 1, clipped.height >= 1 else {
      return nil
    }

    let scaleX = CGFloat(image.width) / destination.width
    let scaleY = CGFloat(image.height) / destination.height
    let imageHeight = CGFloat(image.height)

    let x0 = (clipped.minX - destination.minX) * scaleX
    let x1 = (clipped.maxX - destination.minX) * scaleX
    let y0FromBottom = (clipped.minY - destination.minY) * scaleY
    let y1FromBottom = (clipped.maxY - destination.minY) * scaleY

    // Rust renderer uses image-space origin at top-left (y grows downward).
    let imageRect = CGRect(
      x: x0,
      y: imageHeight - y1FromBottom,
      width: x1 - x0,
      height: y1FromBottom - y0FromBottom
    ).integral

    guard imageRect.width >= 1, imageRect.height >= 1 else {
      return nil
    }

    return imageRect
  }

  func exportImageRect(fromViewRect viewRect: CGRect) -> CGRect? {
    imageRectFromViewRect(viewRect)
  }

  private func viewRectFromImageRect(_ imageRect: CGRect) -> CGRect? {
    guard let image, let destination = imageDestinationRect() else {
      return nil
    }

    let scaleX = destination.width / CGFloat(image.width)
    let scaleY = destination.height / CGFloat(image.height)
    guard scaleX > 0, scaleY > 0 else {
      return nil
    }

    let x0 = destination.minX + imageRect.minX * scaleX
    let x1 = destination.minX + imageRect.maxX * scaleX

    let yTop = destination.minY + (CGFloat(image.height) - imageRect.minY) * scaleY
    let yBottom = destination.minY + (CGFloat(image.height) - imageRect.maxY) * scaleY

    let rect = CGRect(
      x: min(x0, x1),
      y: min(yBottom, yTop),
      width: abs(x1 - x0),
      height: abs(yTop - yBottom)
    )
    guard rect.width >= 1, rect.height >= 1 else {
      return nil
    }
    return rect.integral
  }

  private func viewDeltaFromImageDelta(_ delta: CGPoint) -> CGPoint? {
    guard let image, let destination = imageDestinationRect() else {
      return nil
    }
    let scaleX = CGFloat(image.width) / destination.width
    let scaleY = CGFloat(image.height) / destination.height
    guard scaleX > 0, scaleY > 0 else {
      return nil
    }
    return CGPoint(
      x: delta.x / scaleX,
      y: -delta.y / scaleY
    )
  }

  private func imagePointsFromViewPoints(_ points: [CGPoint]) -> [CGPoint] {
    var output: [CGPoint] = []
    output.reserveCapacity(points.count)

    var last: CGPoint?
    for point in points {
      guard let imagePoint = imagePointFromViewPoint(point) else {
        continue
      }
      if let last, hypot(last.x - imagePoint.x, last.y - imagePoint.y) < 0.1 {
        continue
      }
      output.append(imagePoint)
      last = imagePoint
    }

    return output
  }

  private func drawMoveSelectionPreview(context: CGContext) {
    guard let selectedAnnotationBoundsInView else {
      return
    }

    context.setStrokeColor(accentColor.withAlphaComponent(0.95).cgColor)
    context.setLineWidth(1.6)
    context.setLineDash(phase: 0, lengths: [6, 4])
    context.stroke(selectedAnnotationBoundsInView.insetBy(dx: -0.5, dy: -0.5))
    context.setLineDash(phase: 0, lengths: [])

    drawResizeHandles(context: context, selection: selectedAnnotationBoundsInView)
  }

  private func drawResizeHandles(context: CGContext, selection: CGRect) {
    let radius: CGFloat = 5.5
    for center in resizeHandleCenters(for: selection).values {
      let handleRect = CGRect(
        x: center.x - radius,
        y: center.y - radius,
        width: radius * 2,
        height: radius * 2
      )
      context.setFillColor(NSColor.black.withAlphaComponent(0.85).cgColor)
      context.fillEllipse(in: handleRect)
      context.setStrokeColor(NSColor.white.withAlphaComponent(0.95).cgColor)
      context.setLineWidth(1.4)
      context.strokeEllipse(in: handleRect.insetBy(dx: 0.5, dy: 0.5))
    }
  }

  private func resizeHandleCenters(for selection: CGRect) -> [AnnotationResizeHandle: CGPoint] {
    [
      .topLeft: CGPoint(x: selection.minX, y: selection.maxY),
      .topRight: CGPoint(x: selection.maxX, y: selection.maxY),
      .bottomLeft: CGPoint(x: selection.minX, y: selection.minY),
      .bottomRight: CGPoint(x: selection.maxX, y: selection.minY),
    ]
  }

  private func resizeHandle(at point: CGPoint, in selection: CGRect) -> AnnotationResizeHandle? {
    let hitRadius: CGFloat = 9
    for (handle, center) in resizeHandleCenters(for: selection) {
      if hypot(point.x - center.x, point.y - center.y) <= hitRadius {
        return handle
      }
    }
    return nil
  }

  private func resizedAnnotationBounds(
    from start: CGRect,
    handle: AnnotationResizeHandle,
    delta: CGPoint
  ) -> CGRect? {
    var minX = start.minX
    var maxX = start.maxX
    var minY = start.minY
    var maxY = start.maxY

    switch handle {
    case .topLeft:
      minX += delta.x
      maxY += delta.y
    case .topRight:
      maxX += delta.x
      maxY += delta.y
    case .bottomLeft:
      minX += delta.x
      minY += delta.y
    case .bottomRight:
      maxX += delta.x
      minY += delta.y
    }

    let minSize: CGFloat = 6
    switch handle {
    case .topLeft:
      minX = min(minX, maxX - minSize)
      maxY = max(maxY, minY + minSize)
    case .topRight:
      maxX = max(maxX, minX + minSize)
      maxY = max(maxY, minY + minSize)
    case .bottomLeft:
      minX = min(minX, maxX - minSize)
      minY = min(minY, maxY - minSize)
    case .bottomRight:
      maxX = max(maxX, minX + minSize)
      minY = min(minY, maxY - minSize)
    }

    guard let imageRect = imageDestinationRect() else {
      return nil
    }
    minX = max(imageRect.minX, minX)
    maxX = min(imageRect.maxX, maxX)
    minY = max(imageRect.minY, minY)
    maxY = min(imageRect.maxY, maxY)

    let width = maxX - minX
    let height = maxY - minY
    guard width >= minSize, height >= minSize else {
      return nil
    }

    return CGRect(x: minX, y: minY, width: width, height: height).integral
  }

  private func drawPaintPathPreview(context: CGContext) {
    guard !paintPathPointsInView.isEmpty else {
      return
    }

    context.setStrokeColor(accentColor.cgColor)
    context.setLineWidth(max(1.8, previewStrokeWidth))
    context.setLineCap(.round)
    context.setLineJoin(.round)

    if paintPathPointsInView.count == 1 {
      let p = paintPathPointsInView[0]
      let radius = max(1.2, previewStrokeWidth * 0.5)
      let dot = CGRect(
        x: p.x - radius,
        y: p.y - radius,
        width: radius * 2,
        height: radius * 2
      )
      context.fillEllipse(in: dot)
      return
    }

    context.beginPath()
    context.move(to: paintPathPointsInView[0])
    for point in paintPathPointsInView.dropFirst() {
      context.addLine(to: point)
    }
    context.strokePath()
  }

  private func imageDestinationRect() -> CGRect? {
    guard let image else {
      return nil
    }

    let imageWidth = CGFloat(image.width)
    let imageHeight = CGFloat(image.height)
    guard imageWidth > 0, imageHeight > 0 else {
      return nil
    }

    guard bounds.width > 0, bounds.height > 0 else {
      return nil
    }

    let scale = min(bounds.width / imageWidth, bounds.height / imageHeight)
    let drawWidth = imageWidth * scale
    let drawHeight = imageHeight * scale

    return CGRect(
      x: bounds.midX - drawWidth * 0.5,
      y: bounds.midY - drawHeight * 0.5,
      width: drawWidth,
      height: drawHeight
    )
  }

  private func clampedToImageRect(_ point: CGPoint) -> CGPoint {
    guard let imageRect = imageDestinationRect() else {
      return point
    }

    return CGPoint(
      x: min(max(point.x, imageRect.minX), imageRect.maxX),
      y: min(max(point.y, imageRect.minY), imageRect.maxY)
    )
  }

  private func imagePointFromViewPoint(_ point: CGPoint) -> CGPoint? {
    guard let image, let destination = imageDestinationRect() else {
      return nil
    }

    let clamped = CGPoint(
      x: min(max(point.x, destination.minX), destination.maxX),
      y: min(max(point.y, destination.minY), destination.maxY)
    )

    let scaleX = CGFloat(image.width) / destination.width
    let scaleY = CGFloat(image.height) / destination.height
    let imageHeight = CGFloat(image.height)

    let x = (clamped.x - destination.minX) * scaleX
    let yFromBottom = (clamped.y - destination.minY) * scaleY
    let y = imageHeight - yFromBottom
    return CGPoint(x: x, y: y)
  }

  func finishInlineTextEditing(commit: Bool) {
    guard let inlineTextField else {
      return
    }

    if commit {
      commitInlineTextEditor(text: inlineTextField.stringValue)
    } else {
      removeInlineTextEditor()
    }
  }

  private func beginInlineTextEditor(at viewPoint: CGPoint, imagePoint: CGPoint) {
    removeInlineTextEditor()

    let editorWidth: CGFloat = 260
    let editorHeight: CGFloat = max(26, textStyle.fontSize + 12)
    let inset: CGFloat = 8
    let x = max(inset, min(viewPoint.x, bounds.width - editorWidth - inset))
    let y = max(inset, min(viewPoint.y, bounds.height - editorHeight - inset))
    let frame = CGRect(x: x, y: y, width: editorWidth, height: editorHeight)

    let field = InlineTextField(frame: frame)
    field.placeholderString = "Type text and press Return"
    field.onCommit = { [weak self] text in
      self?.commitInlineTextEditor(text: text)
    }
    field.onCancel = { [weak self] in
      self?.removeInlineTextEditor()
    }

    inlineTextAnchorInView = imagePoint
    inlineTextField = field
    addSubview(field)
    updateInlineTextFieldStyle()
    window?.makeFirstResponder(field)
    needsDisplay = true
  }

  private func updateInlineTextFieldStyle() {
    guard let inlineTextField else {
      return
    }

    inlineTextField.font = resolvedInlineEditorFont()
    inlineTextField.textColor = textStyle.color
    inlineTextField.backgroundColor = NSColor.black.withAlphaComponent(0.45)
    inlineTextField.setInsertionPointColor(textStyle.color)
  }

  private func resolvedInlineEditorFont() -> NSFont {
    let size = max(8, textStyle.fontSize)
    if textStyle.fontName == AppSettings.systemFontFamilyName {
      return .systemFont(ofSize: size, weight: .regular)
    }

    if let familyFont = NSFontManager.shared.font(
      withFamily: textStyle.fontName,
      traits: [],
      weight: 5,
      size: size
    ) {
      return familyFont
    }

    if let named = NSFont(name: textStyle.fontName, size: size) {
      return named
    }

    return .systemFont(ofSize: size, weight: .regular)
  }

  private func commitInlineTextEditor(text: String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let imagePoint = inlineTextAnchorInView else {
      removeInlineTextEditor()
      return
    }

    removeInlineTextEditor()

    guard !trimmed.isEmpty else {
      return
    }
    onCommitText?(trimmed, imagePoint)
  }

  private func removeInlineTextEditor() {
    inlineTextField?.removeFromSuperview()
    inlineTextField = nil
    inlineTextAnchorInView = nil
    needsDisplay = true
  }

  private func drawArrowPreview(context: CGContext, start: CGPoint, end: CGPoint, color: NSColor) {
    context.setStrokeColor(color.cgColor)
    context.setLineWidth(previewStrokeWidth)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.move(to: start)
    context.addLine(to: end)
    context.strokePath()

    let dx = end.x - start.x
    let dy = end.y - start.y
    let len = hypot(dx, dy)
    guard len > 0.5 else {
      return
    }

    let ux = dx / len
    let uy = dy / len
    let headLen: CGFloat = max(16.0, previewStrokeWidth * 6.0)
    let angle: CGFloat = .pi / 6.0
    let cosA = cos(angle)
    let sinA = sin(angle)

    let rx1 = ux * cosA - uy * sinA
    let ry1 = ux * sinA + uy * cosA
    let rx2 = ux * cosA + uy * sinA
    let ry2 = -ux * sinA + uy * cosA

    let p1 = CGPoint(x: end.x - rx1 * headLen, y: end.y - ry1 * headLen)
    let p2 = CGPoint(x: end.x - rx2 * headLen, y: end.y - ry2 * headLen)

    context.move(to: end)
    context.addLine(to: p1)
    context.move(to: end)
    context.addLine(to: p2)
    context.strokePath()
  }

  private func drawTextCursorPreview(context: CGContext, point: CGPoint, color: NSColor) {
    context.setStrokeColor(color.cgColor)
    context.setLineWidth(2.0)

    let h: CGFloat = 10
    let v: CGFloat = 14
    context.move(to: CGPoint(x: point.x - h, y: point.y))
    context.addLine(to: CGPoint(x: point.x + h, y: point.y))
    context.move(to: CGPoint(x: point.x, y: point.y - v))
    context.addLine(to: CGPoint(x: point.x, y: point.y + v))
    context.strokePath()
  }
}

@MainActor
private final class InlineTextField: NSTextField, NSTextFieldDelegate {
  var onCommit: ((String) -> Void)?
  var onCancel: (() -> Void)?

  private var finalized = false
  private var desiredInsertionPointColor: NSColor = .white

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    isEditable = true
    isSelectable = true
    isBezeled = true
    isBordered = true
    bezelStyle = .roundedBezel
    drawsBackground = true
    focusRingType = .none
    delegate = self
    font = .systemFont(ofSize: 16, weight: .regular)
    textColor = .white
    backgroundColor = NSColor.black.withAlphaComponent(0.45)
    translatesAutoresizingMaskIntoConstraints = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  override func textDidBeginEditing(_ notification: Notification) {
    super.textDidBeginEditing(notification)
    if let editor = currentEditor() as? NSTextView {
      editor.insertionPointColor = desiredInsertionPointColor
    }
  }

  override func textDidEndEditing(_ notification: Notification) {
    super.textDidEndEditing(notification)
    finalizeCommit()
  }

  func control(
    _ control: NSControl,
    textView: NSTextView,
    doCommandBy commandSelector: Selector
  ) -> Bool {
    if commandSelector == #selector(NSResponder.insertNewline(_:)) {
      finalizeCommit()
      return true
    }
    if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
      finalizeCancel()
      return true
    }
    return false
  }

  func setInsertionPointColor(_ color: NSColor) {
    desiredInsertionPointColor = color
    if let editor = currentEditor() as? NSTextView {
      editor.insertionPointColor = color
    }
  }

  private func finalizeCommit() {
    guard !finalized else {
      return
    }
    finalized = true
    onCommit?(stringValue)
  }

  private func finalizeCancel() {
    guard !finalized else {
      return
    }
    finalized = true
    onCancel?()
  }
}
