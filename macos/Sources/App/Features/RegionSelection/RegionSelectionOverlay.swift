import AppKit
import ApplicationServices
import AVFoundation
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

  var onSelectionResult: ((CGRect?, CaptureContentType, CaptureMode) -> Void)?
  var onCancelRequested: (() -> Void)?
  var onCancelRequestedImmediately: (() -> Void)?
  var onStartVideoRequested: ((CGRect, VideoCaptureOverlayState, @escaping (Bool) -> Void) -> Void)?
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
  let videoWebcamPlacementView = CaptureOverlayPlacementView(kind: .webcam)
  let videoKeystrokePlacementView = CaptureOverlayPlacementView(kind: .keystroke)
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
  let smartCaptureDragActivationDistance: CGFloat = 5
  var smartMouseDownPoint: CGPoint?
  var smartMouseDownWindowRect: CGRect?
  var smartDragActivated = false
  var smartWindowHoverRect: CGRect?
  var videoRecordingActive = false
  var videoRecordingStartPending = false
  var pointerTrackingArea: NSTrackingArea?

  var session: RustDocumentSession?
  var onEditingDone: ((Bool) -> Void)?
  var currentScreenshotCaptureID: String?
  var screenshotEditorEnteredAt: Date?
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
  // TODO(vivyshot): Re-enable scrolling capture once auto-scroll is production-ready.
  let stitchCaptureFeatureVisible = false
  let videoMicrophoneFeatureVisible = true
  let videoWebcamFeatureVisible = true
  let videoKeystrokesFeatureVisible = true
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

  func applySelectingHoverCursor(at point: CGPoint?) {
    guard mode == .selecting else {
      return
    }

    if let point, captureTypeHost.frame.contains(point) {
      NSCursor.arrow.set()
      return
    }

    if smartWindowHoverRect != nil, !smartDragActivated {
      Self.captureCameraCursor.set()
    } else {
      NSCursor.crosshair.set()
    }
  }

  func resetSmartSelectionState() {
    smartMouseDownPoint = nil
    smartMouseDownWindowRect = nil
    smartDragActivated = false
    smartWindowHoverRect = nil
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

    guard settings.captureSmartWindowSelectionEnabled else {
      resetSmartSelectionState()
      dragStart = point
      dragCurrent = point
      committedSelectionRect = nil
      updateSelectingHintVisibility(animated: true)
      needsLayout = true
      needsDisplay = true
      return
    }

    smartMouseDownPoint = point
    smartMouseDownWindowRect = smartWindowRectForInitialSelection(at: point)
    smartWindowHoverRect = smartMouseDownWindowRect
    smartDragActivated = false
    dragStart = nil
    dragCurrent = nil
    committedSelectionRect = nil
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

    guard settings.captureSmartWindowSelectionEnabled else {
      guard dragStart != nil else {
        return
      }
      dragCurrent = point
      needsLayout = true
      needsDisplay = true
      return
    }

    guard let smartMouseDownPoint else {
      return
    }

    if !smartDragActivated {
      let dx = point.x - smartMouseDownPoint.x
      let dy = point.y - smartMouseDownPoint.y
      let threshold = smartCaptureDragActivationDistance
      guard dx * dx + dy * dy >= threshold * threshold else {
        return
      }

      smartDragActivated = true
      smartWindowHoverRect = nil
      smartMouseDownWindowRect = nil
      dragStart = smartMouseDownPoint
      updateSelectingHintVisibility(animated: true)
    }

    dragCurrent = point
    needsLayout = true
    needsDisplay = true
  }

  override func mouseMoved(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    switch mode {
    case .selecting:
      if settings.captureSmartWindowSelectionEnabled {
        updateSmartWindowHover(at: point)
      } else {
        updateSmartWindowHover(at: nil)
      }
      applySelectingHoverCursor(at: point)
    case .editing:
      updateWindowCaptureHover(at: point)
      applyEditingHoverCursor(at: point)
    }
  }

  override func mouseExited(with _: NSEvent) {
    updateWindowCaptureHover(at: nil)
    updateSmartWindowHover(at: nil)
  }

  override func mouseUp(with event: NSEvent) {
    if mode == .editing {
      super.mouseUp(with: event)
      return
    }

    guard settings.captureSmartWindowSelectionEnabled else {
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
        return
      }

      beginScreenshotStatisticsSessionIfNeeded()
      onSelectionResult?(selection, selectedCaptureType, .selection)
      return
    }

    guard smartMouseDownPoint != nil else {
      return
    }

    let point = convert(event.locationInWindow, from: nil)
    let committedMode: CaptureMode
    let committedRect: CGRect?

    if smartDragActivated {
      dragCurrent = point
      committedMode = .selection
      committedRect = selectionRect().map { $0.integral }
    } else {
      committedMode = .window
      committedRect = smartWindowRectForInitialSelection(at: point) ?? smartMouseDownWindowRect
    }

    resetSmartSelectionState()
    dragStart = nil
    dragCurrent = nil
    committedSelectionRect = committedRect
    updateSelectingHintVisibility(animated: true)
    needsLayout = true
    needsDisplay = true

    guard let committedRect, committedRect.width >= 2, committedRect.height >= 2 else {
      updateSmartWindowHover(at: point)
      applySelectingHoverCursor(at: point)
      return
    }

    beginScreenshotStatisticsSessionIfNeeded()
    onSelectionResult?(committedRect, selectedCaptureType, committedMode)
  }

  override func keyDown(with event: NSEvent) {
    if event.keyCode == 53 { // Esc
      handleCancelShortcut()
      return
    }

    if isPlainReturnKeyEvent(event), performDefaultCaptureActionShortcut() {
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

  private func isPlainReturnKeyEvent(_ event: NSEvent) -> Bool {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    let disallowedFlags: NSEvent.ModifierFlags = [.shift, .control, .option, .command]
    guard flags.intersection(disallowedFlags).isEmpty else {
      return false
    }

    switch event.keyCode {
    case UInt16(kVK_Return), UInt16(kVK_ANSI_KeypadEnter):
      return true
    default:
      return false
    }
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

    drawWindowCaptureHighlight(in: context, targetRect: targetRect, active: windowCapturePickPending)
  }

  func drawWindowCaptureHighlight(in context: CGContext, targetRect: CGRect, active: Bool) {
    let dimPath = CGMutablePath()
    dimPath.addRect(bounds)
    dimPath.addRect(targetRect)

    context.saveGState()
    context.addPath(dimPath)
    context.setFillColor(NSColor.black.withAlphaComponent(active ? 0.34 : 0.26).cgColor)
    context.drawPath(using: .eoFill)
    context.restoreGState()

    context.saveGState()
    context.setStrokeColor(NSColor.white.withAlphaComponent(active ? 0.94 : 0.8).cgColor)
    context.setLineWidth(active ? 2.0 : 1.4)
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
    initialCaptureMode: CaptureMode,
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
    selectedCaptureMode = initialCaptureMode
    videoRecordingActive = false
    videoRecordingStartPending = false
    windowCapturePickPending = false
    screenCapturePickPending = false
    windowCaptureHoverRect = nil
    resetSmartSelectionState()
    syncLiveCaptureTargetPickingState()
    if selectedCaptureType == .video {
      currentTool = .move
    }
    committedSelectionRect = clipped
    areaCaptureRect = initialCaptureMode == .selection ? clipped : nil
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
    currentScreenshotCaptureID = nil
    screenshotEditorEnteredAt = nil
    videoWebcamPlacementView.stopWebcamPreview()
    onStartVideoRequested = nil
    onStopVideoRequested = nil
    selectedCaptureMode = .selection
    areaCaptureRect = nil
    windowCapturePickPending = false
    screenCapturePickPending = false
    windowCaptureHoverRect = nil
    resetSmartSelectionState()
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

  func performDefaultCaptureActionShortcut() -> Bool {
    guard mode == .editing else {
      return false
    }

    switch selectedCaptureType {
    case .screenshot:
      switch settings.screenshotMainAction {
      case .copy:
        performCopy()
      case .save:
        performSave()
      }
      return true
    case .video:
      guard !videoRecordingActive else {
        return false
      }
      guard !videoRecordingStartPending else {
        return true
      }
      guard resolvePendingVideoCaptureTargetForDefaultAction() else {
        return true
      }
      startVideoRecordingFromEditor()
      return true
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
    guard videoMicrophoneFeatureVisible else {
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
    guard videoWebcamFeatureVisible else {
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
    guard videoKeystrokesFeatureVisible else {
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

    recordStandaloneScreenshotCapture(frozenImage)
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

    recordStandaloneScreenshotCapture(frozenImage)

    if settings.alwaysSaveToDefaultDirectory,
       let directory = settings.defaultSaveDirectoryURL
    {
      let destination = Self.makeAutoSaveURL(in: directory, ext: "png")
      _ = Self.saveImageToDisk(frozenImage, to: destination)
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
      && smartMouseDownPoint == nil
      && !smartDragActivated
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
    if activeSelection == nil, let smartWindowHoverRect {
      drawWindowCaptureHighlight(
        in: context,
        targetRect: smartWindowHoverRect.standardized.integral,
        active: true
      )
      return
    }

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

enum CaptureOverlayPlacementKind {
  case webcam
  case keystroke
}

@MainActor
final class CaptureOverlayPlacementView: NSView {
  let kind: CaptureOverlayPlacementKind
  var containerFrame: CGRect = .zero
  var onFrameChanged: ((CGRect) -> Void)?
  var webcamShape: VideoWebcamOverlayShapeOption = .roundedRect {
    didSet { needsDisplay = true }
  }
  var webcamAspectRatio: VideoWebcamOverlayAspectRatioOption = .square {
    didSet { needsLayout = true }
  }
  var keystrokeStyle: VideoKeystrokeOverlayStyleOption = .glass {
    didSet {
      updateKeystrokeHostingView()
      needsDisplay = true
    }
  }
  var keystrokeSize: VideoKeystrokeOverlaySizeOption = .medium {
    didSet {
      updateKeystrokeHostingView()
    }
  }

  private var dragStartFrame: CGRect = .zero
  private var dragStartLocation: CGPoint = .zero
  private var activeInteraction: OverlayFrameInteraction = .move
  private var previewSession: AVCaptureSession?
  private var previewSessionRunner: CaptureSessionRunner?
  private var previewLayer: AVCaptureVideoPreviewLayer?
  private var previewDeviceID: String?
  private var previewAccessRequestActive = false
  private var keystrokeHostingView: NSHostingView<KeystrokeOverlayGlassCapsule>?

  private enum OverlayFrameInteraction {
    case move
    case resize(ResizeCorner)
  }

  init(kind: CaptureOverlayPlacementKind) {
    self.kind = kind
    super.init(frame: .zero)
    wantsLayer = true
    layer?.cornerRadius = kind == .webcam ? 18 : 14
    layer?.masksToBounds = false
    layer?.shadowColor = NSColor.black.cgColor
    layer?.shadowOpacity = 0.22
    layer?.shadowRadius = 10
    layer?.shadowOffset = CGSize(width: 0, height: -2)
    if kind == .keystroke {
      let host = NSHostingView(
        rootView: KeystrokeOverlayGlassCapsule(
          text: "⌘K",
          style: keystrokeStyle,
          size: keystrokeSize,
          showsResizeGrip: true
        )
      )
      host.translatesAutoresizingMaskIntoConstraints = true
      host.wantsLayer = true
      host.layer?.backgroundColor = NSColor.clear.cgColor
      addSubview(host)
      keystrokeHostingView = host
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  override func resetCursorRects() {
    addCursorRect(bounds, cursor: .openHand)
  }

  override func mouseDown(with event: NSEvent) {
    dragStartFrame = frame
    dragStartLocation = window?.convertPoint(toScreen: event.locationInWindow) ?? .zero
    let localPoint = convert(event.locationInWindow, from: nil)
    activeInteraction = resizeCorner(at: localPoint).map(OverlayFrameInteraction.resize) ?? .move
    NSCursor.closedHand.set()
  }

  override func mouseDragged(with event: NSEvent) {
    let location = window?.convertPoint(toScreen: event.locationInWindow) ?? .zero
    let delta = CGSize(width: location.x - dragStartLocation.x, height: location.y - dragStartLocation.y)
    let proposed: CGRect
    switch activeInteraction {
    case .move:
      proposed = dragStartFrame.offsetBy(dx: delta.width, dy: delta.height)
    case .resize(let corner):
      proposed = resizedFrame(from: dragStartFrame, corner: corner, delta: delta)
    }
    frame = clampedFrame(proposed)
    onFrameChanged?(frame)
  }

  override func mouseUp(with _: NSEvent) {
    NSCursor.openHand.set()
    onFrameChanged?(frame)
  }

  override func layout() {
    super.layout()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    previewLayer?.frame = bounds
    layer?.cornerRadius = kind == .webcam && webcamShape == .circle ? min(bounds.width, bounds.height) * 0.5 : (kind == .webcam ? 18 : 14)
    CATransaction.commit()
    keystrokeHostingView?.frame = bounds
  }

  func updateWebcamPreview(preferredDeviceID: String) {
    guard kind == .webcam else {
      return
    }
    guard previewSession == nil || previewDeviceID != preferredDeviceID else {
      return
    }
    stopWebcamPreview()

    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      configureWebcamPreview(preferredDeviceID: preferredDeviceID)
    case .notDetermined:
      guard !previewAccessRequestActive else {
        return
      }
      previewAccessRequestActive = true
      Task { @MainActor [weak self] in
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        guard let self else {
          return
        }
        self.previewAccessRequestActive = false
        if granted {
          self.configureWebcamPreview(preferredDeviceID: preferredDeviceID)
        }
      }
    case .denied, .restricted:
      return
    @unknown default:
      return
    }
  }

  func stopWebcamPreview() {
    let runner = clearWebcamPreview()
    runner?.stopDetached()
  }

  func stopWebcamPreviewForRecordingStart() async {
    let runner = clearWebcamPreview()
    if let runner {
      await runner.stop()
    }
  }

  private func clearWebcamPreview() -> CaptureSessionRunner? {
    previewLayer?.removeFromSuperlayer()
    previewLayer = nil
    let runner = previewSessionRunner
    previewSession = nil
    previewSessionRunner = nil
    previewDeviceID = nil
    needsDisplay = true
    return runner
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    if kind == .keystroke, keystrokeHostingView != nil {
      return
    }

    let rect = bounds.insetBy(dx: 1, dy: 1)
    let path: NSBezierPath
    switch kind {
    case .webcam:
      if webcamShape == .circle {
        path = NSBezierPath(ovalIn: rect)
      } else {
        path = NSBezierPath(roundedRect: rect, xRadius: 18, yRadius: 18)
      }
    case .keystroke:
      path = NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14)
    }

    let fillAlpha: CGFloat = kind == .keystroke && keystrokeStyle == .compact ? 0.68 : 0.46
    if kind == .keystroke && keystrokeStyle == .glass {
      drawGlassFill(in: rect, clippedTo: path)
    } else {
      NSColor.black.withAlphaComponent(fillAlpha).setFill()
      path.fill()
    }

    NSColor.white.withAlphaComponent(kind == .keystroke && keystrokeStyle == .glass ? 0.42 : 0.34).setStroke()
    path.lineWidth = 1
    path.stroke()

    if kind == .webcam || kind == .keystroke {
      drawResizeGrip(in: rect)
    }

    if kind == .webcam, previewLayer != nil {
      return
    }

    let symbolName: String
    let title: String
    switch kind {
    case .webcam:
      symbolName = "video.fill"
      title = String(localized: "Webcam", bundle: AppLocalizer.shared.bundle)
    case .keystroke:
      symbolName = "keyboard"
      title = "⌘K"
    }

    if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
      let size: CGFloat = kind == .webcam ? 18 : 16
      symbol.draw(
        in: CGRect(x: rect.midX - size * 0.5, y: rect.midY + 2, width: size, height: size),
        from: .zero,
        operation: .sourceOver,
        fraction: 0.92
      )
    }

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: kind == .webcam ? 13 : 16, weight: .semibold),
      .foregroundColor: NSColor.white.withAlphaComponent(0.92),
      .paragraphStyle: paragraph
    ]
    NSString(string: title).draw(
      in: CGRect(x: rect.minX + 6, y: rect.midY - 20, width: rect.width - 12, height: 18),
      withAttributes: attrs
    )
  }

  private func drawGlassFill(in rect: CGRect, clippedTo path: NSBezierPath) {
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    let gradient = NSGradient(colors: [
      NSColor.white.withAlphaComponent(0.30),
      NSColor.controlAccentColor.withAlphaComponent(0.18),
      NSColor.black.withAlphaComponent(0.30)
    ])
    gradient?.draw(in: rect, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    let shine = NSBezierPath(roundedRect: rect.insetBy(dx: 2.5, dy: 2.5), xRadius: min(rect.height * 0.5, 14), yRadius: min(rect.height * 0.5, 14))
    NSColor.white.withAlphaComponent(0.08).setStroke()
    shine.lineWidth = 1
    shine.stroke()
  }

  private func drawResizeGrip(in rect: CGRect) {
    let grip = CGRect(x: rect.maxX - 18, y: rect.minY + 5, width: 12, height: 12)
    let path = NSBezierPath()
    for offset in stride(from: CGFloat(4), through: CGFloat(12), by: CGFloat(4)) {
      path.move(to: CGPoint(x: grip.maxX - offset, y: grip.minY))
      path.line(to: CGPoint(x: grip.maxX, y: grip.minY + offset))
    }
    NSColor.white.withAlphaComponent(0.42).setStroke()
    path.lineWidth = 1.2
    path.stroke()
  }

  private func resizeCorner(at point: CGPoint) -> ResizeCorner? {
    let hitSlop: CGFloat = 14
    let nearLeft = point.x <= hitSlop
    let nearRight = point.x >= bounds.maxX - hitSlop
    let nearBottom = point.y <= hitSlop
    let nearTop = point.y >= bounds.maxY - hitSlop

    switch (nearLeft, nearRight, nearBottom, nearTop) {
    case (true, false, false, true): return .topLeft
    case (false, true, false, true): return .topRight
    case (true, false, true, false): return .bottomLeft
    case (false, true, true, false): return .bottomRight
    case (true, false, false, false): return .left
    case (false, true, false, false): return .right
    case (false, false, true, false): return .bottom
    case (false, false, false, true): return .top
    default: return nil
    }
  }

  private func resizedFrame(from start: CGRect, corner: ResizeCorner, delta: CGSize) -> CGRect {
    var rect = start.standardized
    let minSize = minimumFrameSize

    switch corner {
    case .topLeft, .left, .bottomLeft:
      let maxX = rect.maxX
      rect.origin.x = min(maxX - minSize.width, rect.minX + delta.width)
      rect.size.width = maxX - rect.minX
    case .topRight, .right, .bottomRight:
      rect.size.width = max(minSize.width, rect.width + delta.width)
    case .top, .bottom:
      break
    }

    switch corner {
    case .bottomLeft, .bottom, .bottomRight:
      let maxY = rect.maxY
      rect.origin.y = min(maxY - minSize.height, rect.minY + delta.height)
      rect.size.height = maxY - rect.minY
    case .topLeft, .top, .topRight:
      rect.size.height = max(minSize.height, rect.height + delta.height)
    case .left, .right:
      break
    }

    return rect
  }

  private var minimumFrameSize: CGSize {
    switch kind {
    case .webcam:
      return CGSize(width: 84, height: 84)
    case .keystroke:
      return CGSize(width: 112, height: 42)
    }
  }

  private func clampedFrame(_ proposed: CGRect) -> CGRect {
    guard !containerFrame.isNull, !containerFrame.isEmpty else {
      return proposed
    }
    let minimum = minimumFrameSize
    if kind == .webcam {
      let aspectRatio = webcamShape == .circle ? VideoWebcamOverlayAspectRatioOption.square : webcamAspectRatio
      return aspectRatio.constrainedFrame(proposed, in: containerFrame, minimumSize: minimum)
    }
    let width = max(min(minimum.width, containerFrame.width), min(proposed.width, containerFrame.width))
    let height = max(min(minimum.height, containerFrame.height), min(proposed.height, containerFrame.height))
    let x = min(max(containerFrame.minX, proposed.minX), containerFrame.maxX - width)
    let y = min(max(containerFrame.minY, proposed.minY), containerFrame.maxY - height)
    return CGRect(x: x, y: y, width: width, height: height).integral
  }

  private func updateKeystrokeHostingView() {
    keystrokeHostingView?.rootView = KeystrokeOverlayGlassCapsule(
      text: "⌘K",
      style: keystrokeStyle,
      size: keystrokeSize,
      showsResizeGrip: true
    )
  }

  private func configureWebcamPreview(preferredDeviceID: String) {
    guard kind == .webcam else {
      return
    }

    var deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
    if #available(macOS 14.0, *) {
      deviceTypes.append(.external)
    } else {
      deviceTypes.append(.externalUnknown)
    }
    if #available(macOS 15.0, *) {
      deviceTypes.append(.continuityCamera)
    }

    let devices = AVCaptureDevice.DiscoverySession(
      deviceTypes: deviceTypes,
      mediaType: .video,
      position: .unspecified
    ).devices
    let selectedDevice = devices.first(where: { $0.uniqueID == preferredDeviceID })
    guard let device = selectedDevice ?? AVCaptureDevice.default(for: .video) ?? devices.first,
          let input = try? AVCaptureDeviceInput(device: device)
    else {
      return
    }

    let session = AVCaptureSession()
    session.beginConfiguration()
    session.sessionPreset = .medium
    if session.canAddInput(input) {
      session.addInput(input)
    }
    session.commitConfiguration()
    guard !session.inputs.isEmpty else {
      return
    }

    let layer = AVCaptureVideoPreviewLayer(session: session)
    layer.videoGravity = .resizeAspectFill
    let runner = CaptureSessionRunner(
      session: session,
      label: "com.vivyshot.webcam-placement-preview.session"
    )
    self.layer?.insertSublayer(layer, at: 0)
    previewSession = session
    previewSessionRunner = runner
    previewLayer = layer
    previewDeviceID = preferredDeviceID
    needsDisplay = true
    needsLayout = true
    runner.startDetached()
  }
}
