import AppKit
import ApplicationServices
import Carbon
import CoreGraphics
import Foundation
import QuartzCore
import ScreenCaptureKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class RegionSelectionView: NSView {
  static let captureCameraCursor: NSCursor = {
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
  var onCancelRequestedImmediately: (() -> Void)?
  var onStartVideoRequested: ((CGRect, @escaping (Bool) -> Void) -> Void)?
  var onStopVideoRequested: (() -> Void)?
  let settings: AppSettings
  var settingsObserver: NSObjectProtocol?

  enum OverlayMode {
    case selecting
    case editing
  }

  var frozenImage: CGImage?

  var mode: OverlayMode = .selecting {
    didSet {
      editingMaskView.isHidden = mode != .editing
      needsDisplay = true
      window?.invalidateCursorRects(for: self)
      needsLayout = true
      updateSelectingHintVisibility(animated: true)
      syncLiveCaptureTargetPickingState()
    }
  }

  var dragStart: CGPoint?
  var dragCurrent: CGPoint?
  var committedSelectionRect: CGRect?

  var activeResizeCorner: ResizeCorner?
  var resizeStartRect: CGRect?
  var resizeHandles: [ResizeCorner: ResizeHandleView] = [:]

  let canvasView = AnnotationCanvasView()
  let editingMaskView = SelectionMaskOverlayView()
  lazy var toolbarHost = NSHostingView(rootView: makeToolbarView())
  lazy var selectingHintHost = NSHostingView(rootView: CaptureHintGlassCard(selectedType: selectedCaptureType))
  lazy var captureTypeHost = NSHostingView(rootView: makeCaptureTypeSidebar())
  var toolbarOffset: CGSize = .zero
  var toolbarDragStartOffset: CGSize?
  var stitchControlPanel: NSPanel?
  var selectedCaptureType: CaptureContentType
  var selectedCaptureMode: CaptureMode = .selection
  var areaCaptureRect: CGRect?
  var windowCapturePickPending = false
  var screenCapturePickPending = false
  var windowCaptureHoverRect: CGRect?
  var videoRecordingActive = false
  var videoRecordingStartPending = false
  var pointerTrackingArea: NSTrackingArea?
  var globalMouseMovedMonitor: Any?
  var globalMouseDownMonitor: Any?

  var session: RustDocumentSession?
  var onEditingDone: ((Bool) -> Void)?
  var stitchModeEnabled = false
  var stitchCaptureInProgress = false
  var stitchPassThroughOverlayActive = false
  var stitchRecordingActive = false
  var stitchSegmentCount = 1
  var stitchCaptureTask: Task<Void, Never>?
  var stitchSession: RustStitchSession?
  var stitchWorkingImage: CGImage?
  var stitchDirectionLocked = false
  var stitchCaptureRectInScreen: CGRect?
  var preStitchImage: CGImage?
  var preStitchSelectionRect: CGRect?
  var postStitchEditorMode = false
  // Keep frame cadence high enough for reliable overlap without overspeeding.
  let stitchCaptureInterval: TimeInterval = 0.12
  var stitchAutoScrollEnabled = true
  var stitchAutoScrollDirectionSign: Int32 = -1
  var stitchAutoScrollNoMotionTicks = 0
  var stitchAutoScrollDidFlipDirection = false
  var stitchAutoScrollPromptAttempted = false
  var stitchAutoScrollTrusted = false
  var stitchTargetApp: NSRunningApplication?
  let stitchAutoScrollStepLines: Int32 = 3
  let stitchAutoScrollSettleInterval: TimeInterval = 0.11

  var annotationColor: NSColor = .systemOrange {
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

  var textStyle = EditorTextStyle(fontSize: 16, color: .systemOrange) {
    didSet {
      canvasView.textStyle = textStyle
    }
  }

  var currentTool: AnnotationTool = .rect {
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

  deinit {
    MainActor.assumeIsolated {
      stitchCaptureTask?.cancel()
      teardownGlobalTargetPickMonitors()
      if let settingsObserver {
        NotificationCenter.default.removeObserver(settingsObserver)
        self.settingsObserver = nil
      }
      hideStitchControlPanel()
    }
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

  override func hitTest(_ point: NSPoint) -> NSView? {
    guard bounds.contains(point) else {
      return nil
    }

    // In live pick mode, route clicks on the capture surface to this view so
    // the picker receives the click instead of the annotation canvas.
    if mode == .editing,
       (windowCapturePickPending || screenCapturePickPending)
    {
      if toolbarHost.frame.contains(point) || captureTypeHost.frame.contains(point) {
        return super.hitTest(point)
      }
      return self
    }

    return super.hitTest(point)
  }

  override func layout() {
    super.layout()
    layoutEditorChrome()
    layoutSelectingHint()
    layoutCaptureTypePanel()
  }

  override func updateTrackingAreas() {
    if let pointerTrackingArea {
      removeTrackingArea(pointerTrackingArea)
    }

    let tracking = NSTrackingArea(
      rect: bounds,
      options: [.inVisibleRect, .activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited],
      owner: self,
      userInfo: nil
    )
    addTrackingArea(tracking)
    pointerTrackingArea = tracking
    super.updateTrackingAreas()
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

  func applyEditingHoverCursor(at point: CGPoint?) {
    guard mode == .editing else {
      return
    }

    if let point,
       (toolbarHost.frame.contains(point) || captureTypeHost.frame.contains(point))
    {
      NSCursor.arrow.set()
      return
    }

    if selectedCaptureMode == .screen || selectedCaptureMode == .window {
      Self.captureCameraCursor.set()
    } else {
      NSCursor.arrow.set()
    }
  }

  override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)

    if mode == .editing {
      if screenCapturePickPending {
        if applyCaptureRect(bounds, as: .screen, rememberAsArea: false),
           selectedCaptureType == .video
        {
          startVideoRecordingFromEditor()
        }
        return
      }
      if windowCapturePickPending {
        if let windowRect = captureRectForWindowPick(at: point) {
          if applyCaptureRect(windowRect, as: .window, rememberAsArea: false),
             selectedCaptureType == .video
          {
            startVideoRecordingFromEditor()
          }
        } else {
          NSSound.beep()
          updateWindowCaptureHover(at: point)
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

  override func mouseMoved(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    updateWindowCaptureHover(at: point)
    applyEditingHoverCursor(at: point)
  }

  override func mouseExited(with _: NSEvent) {
    updateWindowCaptureHover(at: nil)
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

    let liveTargetPickActive = mode == .editing && (windowCapturePickPending || screenCapturePickPending)

    if !liveTargetPickActive, let frozenImage {
      context.interpolationQuality = .high
      context.draw(frozenImage, in: bounds)
    }

    switch mode {
    case .selecting:
      drawSelectingOverlay(in: context)
    case .editing:
      if selectedCaptureMode == .screen {
        drawScreenCaptureOverlay(in: context)
      } else {
        drawWindowCaptureOverlay(in: context)
      }
    }
  }

  func drawScreenCaptureOverlay(in context: CGContext) {
    guard selectedCaptureMode == .screen else {
      return
    }

    context.saveGState()
    context.setFillColor(NSColor.black.withAlphaComponent(0.08).cgColor)
    context.fill(bounds)
    context.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
    context.setLineWidth(1.6)
    context.stroke(bounds.insetBy(dx: 0.5, dy: 0.5))
    context.restoreGState()
  }

  func drawWindowCaptureOverlay(in context: CGContext) {
    guard selectedCaptureMode == .window else {
      return
    }

    let targetRect = (windowCapturePickPending ? windowCaptureHoverRect : committedSelectionRect)?
      .standardized
      .integral
    guard let targetRect, targetRect.width >= 2, targetRect.height >= 2 else {
      return
    }

    let dimPath = CGMutablePath()
    dimPath.addRect(bounds)
    dimPath.addRect(targetRect)

    context.saveGState()
    context.addPath(dimPath)
    context.setFillColor(NSColor.black.withAlphaComponent(windowCapturePickPending ? 0.34 : 0.26).cgColor)
    context.drawPath(using: .eoFill)
    context.restoreGState()

    context.saveGState()
    context.setStrokeColor(NSColor.white.withAlphaComponent(windowCapturePickPending ? 0.94 : 0.8).cgColor)
    context.setLineWidth(windowCapturePickPending ? 2.0 : 1.4)
    context.stroke(targetRect.insetBy(dx: -0.5, dy: -0.5))
    context.restoreGState()
  }

  func drawStitchPassThroughFocus(in context: CGContext) {
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
    session: RustDocumentSession?,
    selectionRect: CGRect,
    initialCaptureType: CaptureContentType,
    onDone: @escaping (Bool) -> Void
  ) {
    let clipped = selectionRect.standardized.intersection(bounds).integral
    guard !clipped.isNull, clipped.width >= 2, clipped.height >= 2 else {
      onDone(true)
      return
    }

    let image: CGImage
    if let session {
      guard let sessionImage = session.currentImage() else {
        onDone(true)
        return
      }
      image = sessionImage
    } else if let frozenImage {
      image = frozenImage
    } else {
      onDone(true)
      return
    }

    onSelectionResult = nil
    onCancelRequested = nil
    onCancelRequestedImmediately = nil
    self.session = session
    onEditingDone = onDone
    selectedCaptureType = initialCaptureType
    selectedCaptureMode = .selection
    videoRecordingActive = false
    videoRecordingStartPending = false
    windowCapturePickPending = false
    screenCapturePickPending = false
    windowCaptureHoverRect = nil
    syncLiveCaptureTargetPickingState()
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
    stitchSession = nil
    stitchWorkingImage = nil
    stitchDirectionLocked = false
    stitchCaptureRectInScreen = nil
    resetStitchAutoScrollState()
    preStitchImage = nil
    preStitchSelectionRect = nil
    postStitchEditorMode = false
    hideStitchControlPanel()

    mode = .editing
    // Editing uses the session-backed canvas image; release the initial frozen frame early.
    frozenImage = nil
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
    canvasView.image = nil
    frozenImage = nil
    canvasView.isHidden = false
    editingMaskView.isHidden = true
    editingMaskView.selectionRect = .zero
    setResizeHandlesHidden(true)
    onSelectionResult = nil
    onCancelRequested = nil
    onCancelRequestedImmediately = nil
    session = nil
    onEditingDone = nil
    onStartVideoRequested = nil
    onStopVideoRequested = nil
    selectedCaptureMode = .selection
    areaCaptureRect = nil
    windowCapturePickPending = false
    screenCapturePickPending = false
    windowCaptureHoverRect = nil
    syncLiveCaptureTargetPickingState()
    videoRecordingActive = false
    videoRecordingStartPending = false
    stitchModeEnabled = false
    stitchCaptureInProgress = false
    stitchPassThroughOverlayActive = false
    stitchRecordingActive = false
    stitchSegmentCount = 1
    stitchCaptureTask?.cancel()
    stitchCaptureTask = nil
    stitchSession = nil
    stitchWorkingImage = nil
    stitchDirectionLocked = false
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
    switch mode {
    case .editing:
      performCopy()
    case .selecting:
      guard canUseHelperQuickScreenshotShortcuts else {
        NSSound.beep()
        return
      }
      quickCopyFullScreenFromSelectingOverlay()
    }
  }

  func performSaveShortcut() {
    switch mode {
    case .editing:
      performSave()
    case .selecting:
      guard canUseHelperQuickScreenshotShortcuts else {
        NSSound.beep()
        return
      }
      quickSaveFullScreenFromSelectingOverlay()
    }
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

  func performSelectToolShortcut(index: Int) -> Bool {
    guard mode == .editing, selectedCaptureType == .screenshot else {
      return false
    }
    let tools = settings.visibleTools
    guard !tools.isEmpty, index >= 1, index <= tools.count else {
      return false
    }
    let targetTool = tools[index - 1]
    if currentTool != targetTool {
      currentTool = targetTool
    }
    return true
  }

  func performCycleToolShortcut(reverse: Bool) -> Bool {
    guard mode == .editing else {
      return false
    }
    guard !videoRecordingActive, !videoRecordingStartPending else {
      return false
    }

    if selectedCaptureType == .screenshot {
      let tools = settings.visibleTools
      guard !tools.isEmpty else {
        return false
      }
      let currentIndex = tools.firstIndex(of: currentTool) ?? 0
      let nextIndex: Int
      if reverse {
        nextIndex = (currentIndex - 1 + tools.count) % tools.count
      } else {
        nextIndex = (currentIndex + 1) % tools.count
      }
      currentTool = tools[nextIndex]
      return true
    }

    let modes = CaptureMode.allCases
    guard let currentIndex = modes.firstIndex(of: selectedCaptureMode) else {
      return false
    }
    let nextIndex: Int
    if reverse {
      nextIndex = (currentIndex - 1 + modes.count) % modes.count
    } else {
      nextIndex = (currentIndex + 1) % modes.count
    }
    setCaptureModeFromToolbar(modes[nextIndex])
    return true
  }

  func performCycleCaptureTypeShortcut() -> Bool {
    guard !videoRecordingActive, !videoRecordingStartPending else {
      return false
    }

    let types = CaptureContentType.allCases
    guard !types.isEmpty,
          let currentIndex = types.firstIndex(of: selectedCaptureType)
    else {
      return false
    }

    let nextIndex = (currentIndex + 1) % types.count
    setSelectedCaptureType(types[nextIndex])
    return true
  }

  func performCycleCaptureModeShortcut(reverse: Bool) -> Bool {
    guard mode == .editing else {
      return false
    }
    guard !videoRecordingActive, !videoRecordingStartPending else {
      return false
    }

    let modes = CaptureMode.allCases
    guard !modes.isEmpty,
          let currentIndex = modes.firstIndex(of: selectedCaptureMode)
    else {
      return false
    }

    let nextIndex: Int
    if reverse {
      nextIndex = (currentIndex - 1 + modes.count) % modes.count
    } else {
      nextIndex = (currentIndex + 1) % modes.count
    }
    setCaptureModeFromToolbar(modes[nextIndex])
    return true
  }

  func performCaptureModeShortcut(_ mode: CaptureMode) -> Bool {
    guard self.mode == .editing else {
      return false
    }
    guard !videoRecordingActive, !videoRecordingStartPending else {
      return false
    }
    setCaptureModeFromToolbar(mode)
    return true
  }

  func performToggleVideoSystemAudioShortcut() -> Bool {
    guard canUseVideoToolbarSettingsShortcut else {
      return false
    }
    settings.setVideoRecordSystemAudio(!settings.videoRecordSystemAudio)
    refreshToolbar()
    return true
  }

  func performToggleVideoMicrophoneShortcut() -> Bool {
    guard canUseVideoToolbarSettingsShortcut else {
      return false
    }
    settings.setVideoRecordMicrophone(!settings.videoRecordMicrophone)
    refreshToolbar()
    return true
  }

  func performToggleVideoWebcamShortcut() -> Bool {
    guard canUseVideoToolbarSettingsShortcut else {
      return false
    }
    settings.setVideoShowWebcam(!settings.videoShowWebcam)
    refreshToolbar()
    return true
  }

  func performToggleVideoMouseClicksShortcut() -> Bool {
    guard canUseVideoToolbarSettingsShortcut else {
      return false
    }
    settings.setVideoHighlightMouseClicks(!settings.videoHighlightMouseClicks)
    refreshToolbar()
    return true
  }

  func performToggleVideoKeystrokesShortcut() -> Bool {
    guard canUseVideoToolbarSettingsShortcut else {
      return false
    }
    settings.setVideoHighlightKeystrokes(!settings.videoHighlightKeystrokes)
    refreshToolbar()
    return true
  }

  func performCycleVideoCountdownShortcut() -> Bool {
    guard canUseVideoToolbarSettingsShortcut else {
      return false
    }

    let options = VideoCountdownOption.allCases
    guard !options.isEmpty else {
      return false
    }

    let currentIndex = options.firstIndex(of: settings.videoCountdown) ?? 0
    let nextIndex = (currentIndex + 1) % options.count
    settings.setVideoCountdown(options[nextIndex])
    refreshToolbar()
    return true
  }

  func performToggleVideoRecordingShortcut() -> Bool {
    guard mode == .editing, selectedCaptureType == .video else {
      return false
    }
    toggleVideoRecordingFromEditor()
    return true
  }

  func quickCopyFullScreenFromSelectingOverlay() {
    guard let frozenImage else {
      NSSound.beep()
      return
    }

    let copied = autoreleasepool { () -> Bool in
      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()

      if let encodedPNG = RustCoreBridge.shared.encodeImage(
        frozenImage,
        format: .png,
        jpegQuality: 100
      ) {
        let item = NSPasteboardItem()
        item.setData(encodedPNG, forType: .png)
        if pasteboard.writeObjects([item]) {
          return true
        }
      }

      let nsImage = NSImage(
        cgImage: frozenImage,
        size: NSSize(width: frozenImage.width, height: frozenImage.height)
      )
      return pasteboard.writeObjects([nsImage])
    }

    guard copied else {
      NSSound.beep()
      return
    }

    if let onCancelRequestedImmediately {
      onCancelRequestedImmediately()
    } else {
      onCancelRequested?()
    }
    TransientToast.show("Copied to Clipboard")
  }

  func quickSaveFullScreenFromSelectingOverlay() {
    guard let frozenImage else {
      NSSound.beep()
      return
    }

    if settings.alwaysSaveToDefaultDirectory,
       let directory = settings.defaultSaveDirectoryURL
    {
      let destination = Self.makeAutoSaveURL(in: directory, ext: "png")
      Self.saveImageToDisk(frozenImage, to: destination)
      onCancelRequested?()
      return
    }

    let suggestedDirectory = settings.defaultSaveDirectoryURL
    let image = frozenImage
    if let onCancelRequestedImmediately {
      onCancelRequestedImmediately()
    } else {
      onCancelRequested?()
    }
    Task { @MainActor [image, suggestedDirectory] in
      await Task.yield()
      Self.presentSavePanel(for: image, suggestedDirectory: suggestedDirectory)
    }
  }

  var canUseHelperQuickScreenshotShortcuts: Bool {
    guard selectedCaptureType == .screenshot else {
      return false
    }
    return mode == .selecting
      && dragStart == nil
      && dragCurrent == nil
      && committedSelectionRect == nil
  }

  var canUseVideoToolbarSettingsShortcut: Bool {
    mode == .editing
      && selectedCaptureType == .video
      && !videoRecordingActive
      && !videoRecordingStartPending
  }

  func drawSelectingOverlay(in context: CGContext) {
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

  func selectionRect() -> CGRect? {
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

  func drawSelectionSize(_ selection: CGRect) {
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

  func drawSelectionCornerGuides(
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

func overlayCocoaRectToCGDisplayRect(_ rect: CGRect) -> CGRect {
  guard let primaryHeight = NSScreen.screens.first?.frame.height else { return rect }
  return CGRect(x: rect.origin.x, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
}

func overlayCGDisplayRectToCocoaRect(_ rect: CGRect) -> CGRect {
  guard let primaryHeight = NSScreen.screens.first?.frame.height else { return rect }
  return CGRect(x: rect.origin.x, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
}
