import AppKit
import Carbon
import Combine
import CoreGraphics
import Foundation
import SwiftUI

/// Main interactive overlay view for selecting, annotating, saving, recording, and stitching captures.
@MainActor
final class RegionSelectionView: NSView {
  weak var delegate: RegionSelectionViewDelegate?
  weak var recordingController: (any RegionSelectionRecordingControlling)?
  let settings: AppSettings
  let storeManager: StoreManager
  let statisticsStore: StatisticsStore
  let toastPresenter: ToastPresenting
  var settingsCancellables: [AnyCancellable] = []

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

  var interactionState = RegionSelectionInteractionState()

  var activeResizeCorner: ResizeCorner?
  var resizeStartRect: CGRect?
  var resizeHandles: [ResizeCorner: ResizeHandleView] = [:]

  let canvasView = AnnotationCanvasView()
  let editingMaskView = SelectionMaskOverlayView()
  let webcamPlacementView = CaptureOverlayPlacementView(kind: .webcam)
  let keystrokePlacementView = CaptureOverlayPlacementView(kind: .keystroke)
  let captureModeSelectionState = CaptureModeSelectionState()
  let toolbarRefresh = RegionSelectionToolbarRefresh()
  lazy var toolbarHost = RegionSelectionGlassHostingView(
    rootView: RegionSelectionToolbarHost(refresh: toolbarRefresh) { [weak self] glassNamespace in
      guard let self else {
        return AnyView(EmptyView())
      }
      return self.makeToolbarView(glassNamespace: glassNamespace)
    },
    cornerRadius: 28
  )
  lazy var selectingHintHost = RegionSelectionGlassHostingView(
    rootView: CaptureHintGlassCard(selectedType: selectedCaptureType, usesExternalGlassSurface: true),
    cornerRadius: 12
  )
  lazy var captureTypeHost = RegionSelectionGlassHostingView(rootView: makeCaptureTypeSidebar(), cornerRadius: 28)
  var glassChromeRevealTask: Task<Void, Never>?
  var glassBackdropRefreshScheduled = false
  var glassChromeReadyForBackdrop = false
  var floatingChromeState = RegionSelectionFloatingChromeState()
  var toolbarFrameAnimationPending = false
  var recordingPointerPassthroughTimer: Timer?
  var stitchControlPanel: NSPanel?
  var selectedCaptureType: CaptureContentType
  var selectedCaptureMode: CaptureMode = .selection
  var areaCaptureRect: CGRect?
  var windowCapturePickPending = false
  var screenCapturePickPending = false
  var windowCaptureHoverRect: CGRect?
  let smartCaptureDragActivationDistance: CGFloat = 5
  var recordingState = RegionSelectionRecordingState()
  var webcamSourceOptions: [RecordingSourceOption] = []
  var microphoneSourceOptions: [RecordingSourceOption] = []
  var pointerTrackingArea: NSTrackingArea?

  let annotationEditor = AnnotationEditorController()
  var currentScreenshotCaptureID: String?
  var screenshotEditorEnteredAt: Date?
  var stitchState = RegionSelectionStitchState()
  // Keep frame cadence high enough for reliable overlap without overspeeding.
  let stitchCaptureInterval: TimeInterval = 0.12
  let microphoneFeatureVisible = true
  let webcamFeatureVisible = true
  let keystrokesFeatureVisible = true
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

  init(
    frame frameRect: NSRect,
    frozenImage: CGImage,
    settings: AppSettings,
    storeManager: StoreManager,
    statisticsStore: StatisticsStore,
    toastPresenter: ToastPresenting
  ) {
    self.frozenImage = frozenImage
    self.settings = settings
    self.storeManager = storeManager
    self.statisticsStore = statisticsStore
    self.toastPresenter = toastPresenter
    selectedCaptureType = settings.defaultCaptureType
    super.init(frame: frameRect)
    configureEditorSubviews()
    configureCanvasCallbacks()
    refreshRecordingSourceOptions()
    observeSettingsChanges()
    applySettingsFromPreferences()
    updateSelectingHintVisibility(animated: false)
  }

  deinit {
    MainActor.assumeIsolated {
      glassChromeRevealTask?.cancel()
      recordingPointerPassthroughTimer?.invalidate()
      stitchState.captureTask?.cancel()
      settingsCancellables.forEach { $0.cancel() }
      settingsCancellables.removeAll()
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

    if recordingActive {
      return toolbarHost.frame.contains(point) ? super.hitTest(point) : nil
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

    let hitView = super.hitTest(point)
    guard hitView === canvasView else {
      return hitView
    }
    return hitVideoOverlayPlacementView(at: point) ?? hitView
  }

  private func hitVideoOverlayPlacementView(at point: NSPoint) -> NSView? {
    guard mode == .editing,
          selectedCaptureType == .video,
          selectedCaptureMode == .selection,
          !windowCapturePickPending,
          !screenCapturePickPending,
          !recordingActive
    else {
      return nil
    }

    for placementView in [keystrokePlacementView, webcamPlacementView] where !placementView.isHidden {
      let pointInPlacementView = placementView.convert(point, from: self)
      if let hitView = placementView.hitTest(pointInPlacementView) {
        return hitView
      }
    }
    return nil
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
      beginManualSelection(at: point)
      return
    }

    beginSmartSelection(
      at: point,
      windowRect: smartWindowRectForInitialSelection(at: point)
    )
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
      updateManualSelection(to: point)
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

      activateSmartSelectionDrag(from: smartMouseDownPoint)
    }

    updateManualSelection(to: point)
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

      let selection = commitManualSelection(at: convert(event.locationInWindow, from: nil))

      guard let selection, selection.width >= 2, selection.height >= 2 else {
        return
      }

      beginScreenshotStatisticsSessionIfNeeded()
      delegate?.regionSelectionView(
        self,
        didFinishSelection: selection,
        captureType: selectedCaptureType,
        captureMode: .selection
      )
      return
    }

    guard smartMouseDownPoint != nil else {
      return
    }

    let point = convert(event.locationInWindow, from: nil)
    let (committedRect, committedMode) = commitSmartSelection(at: point)

    guard let committedRect, committedRect.width >= 2, committedRect.height >= 2 else {
      updateSmartWindowHover(at: point)
      applySelectingHoverCursor(at: point)
      return
    }

    beginScreenshotStatisticsSessionIfNeeded()
    delegate?.regionSelectionView(
      self,
      didFinishSelection: committedRect,
      captureType: selectedCaptureType,
      captureMode: committedMode
    )
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

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    guard let context = NSGraphicsContext.current?.cgContext else {
      return
    }
    defer {
      scheduleGlassBackdropRefreshIfNeeded()
    }

    if recordingActive, mode == .editing {
      drawRecordingFocusOverlay(in: context)
      return
    }

    if stitchState.passThroughOverlayActive, mode == .editing {
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

}
