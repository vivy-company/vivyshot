import AppKit
import CoreGraphics

/// Completed region-selection output in screen coordinates.
struct RegionSelectionResult {
  let selectionRectInScreen: CGRect
  let captureType: CaptureContentType
  let captureMode: CaptureMode
  let windowID: CGWindowID?
}

struct RegionSelectionCommandRouting {
  var includesStitchCommands = false
  var onlyHandlesCancel = false
}

/// Presents one full-screen selection overlay and converts local selection state into capture requests.
@MainActor
final class RegionSelectionOverlayController {
  private let settings: AppSettings
  private let storeManager: StoreManager
  private let statisticsStore: StatisticsStore
  private let toastPresenter: ToastPresenting
  private let transitionAnimator: RegionSelectionTransitionAnimator
  var window: RegionSelectionWindow?
  weak var selectionView: RegionSelectionView?
  private var selectionCompletion: ((RegionSelectionResult?) -> Void)?
  weak var editingDelegate: (any RegionSelectionOverlayEditingDelegate)?
  var transitionPreviewActive = false
  private var transitionPreviewStyleOverride: CaptureTransitionStyle?
  private var transitionPreviewTask: Task<Void, Never>?
  var commandRouting = RegionSelectionCommandRouting()

  init(
    settings: AppSettings,
    storeManager: StoreManager,
    statisticsStore: StatisticsStore,
    toastPresenter: ToastPresenting
  ) {
    self.settings = settings
    self.storeManager = storeManager
    self.statisticsStore = statisticsStore
    self.toastPresenter = toastPresenter
    transitionAnimator = RegionSelectionTransitionAnimator(settings: settings)
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

    let previouslyFrontmostApp = NSWorkspace.shared.frontmostApplication
    closeWindow(animated: false)
    clearFlowCallbacks()
    transitionPreviewActive = false

    let window = makeOverlayWindow(
      onScreenFrame: frame,
      passthroughActivationApp: previouslyFrontmostApp
    )
    let selectionView = makeSelectionView(onScreenFrame: frame, frozenImage: frozenImage)
    selectionView.delegate = self
    selectionCompletion = onComplete

    installCommandHandler(for: window, includesStitchCommands: RegionSelectionFeatureFlags.stitchCaptureEnabled)

    presentOverlayWindow(window, selectionView: selectionView)
  }

  func enterEditing(
    session: AnnotationSession?,
    selectionRectInScreen: CGRect,
    initialCaptureType: CaptureContentType,
    initialCaptureMode: CaptureMode,
    initialWindowID: CGWindowID? = nil,
    editsWholeImageCapture: Bool = false,
    recordingController: (any RegionSelectionRecordingControlling)?,
    delegate: any RegionSelectionOverlayEditingDelegate
  ) {
    guard let window, let selectionView else {
      delegate.regionSelectionOverlayDidFinishEditing(self)
      return
    }

    editingDelegate = delegate

    let localRect = selectionRectInScreen
      .offsetBy(dx: -window.frame.origin.x, dy: -window.frame.origin.y)
      .standardized
      .integral

    var finishedSynchronously = false
    selectionView.enterEditing(
      session: session,
      selectionRect: localRect,
      initialCaptureType: initialCaptureType,
      initialCaptureMode: initialCaptureMode,
      initialWindowID: initialWindowID,
      editsWholeImageCapture: editsWholeImageCapture
    ) { [weak self] animateClose in
      finishedSynchronously = true
      guard let self else {
        return
      }
      let delegate = self.editingDelegate
      self.clearFlowCallbacks()
      self.closeWindow(animated: animateClose) {
        delegate?.regionSelectionOverlayDidFinishEditing(self)
      }
    }
    guard !finishedSynchronously else {
      return
    }

    selectionView.delegate = self
    selectionView.recordingController = recordingController

    window.makeFirstResponder(selectionView)
  }

  func previewCaptureTransition(onScreenFrame frame: CGRect, frozenImage: CGImage) {
    guard !frame.isNull, !frame.isEmpty, settings.captureTransitionStyle != .none else {
      return
    }

    transitionPreviewTask?.cancel()
    transitionPreviewTask = nil
    transitionPreviewStyleOverride = nil
    closeWindow(animated: false)
    clearFlowCallbacks()
    transitionPreviewActive = true
    transitionPreviewStyleOverride = settings.captureTransitionStyle

    let window = makeOverlayWindow(onScreenFrame: frame)
    let selectionView = makeSelectionView(onScreenFrame: frame, frozenImage: frozenImage)
    selectionView.delegate = self
    installPreviewCommandHandler(for: window)

    presentOverlayWindow(window, selectionView: selectionView)

    let holdDuration = transitionAnimator.transitionDuration(entering: true, style: settings.captureTransitionStyle) + 0.7
    transitionPreviewTask = Task { @MainActor in
      try? await Task.sleep(nanoseconds: UInt64(holdDuration * 1_000_000_000))
      guard !Task.isCancelled else {
        return
      }
      closeTransitionPreview(animated: true)
    }
  }

  func closeFlow(animated: Bool = true, completion: (() -> Void)? = nil) {
    closeWindow(animated: animated, completion: completion)
  }

  func stopVideoWebcamPreviewForRecordingStart() async {
    if let selectionView {
      await selectionView.stopVideoWebcamPreviewForRecordingStart()
    }
  }

  private func installCommandHandler(
    for window: RegionSelectionWindow,
    includesStitchCommands: Bool
  ) {
    commandRouting = RegionSelectionCommandRouting(includesStitchCommands: includesStitchCommands)
    window.commandHandler = self
  }

  private func installPreviewCommandHandler(for window: RegionSelectionWindow) {
    commandRouting = RegionSelectionCommandRouting(onlyHandlesCancel: true)
    window.commandHandler = self
  }

  private func makeOverlayWindow(
    onScreenFrame frame: CGRect,
    passthroughActivationApp: NSRunningApplication? = nil
  ) -> RegionSelectionWindow {
    let window = RegionSelectionWindow(
      contentRect: frame,
      styleMask: [.nonactivatingPanel, .borderless],
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
    window.acceptsMouseMovedEvents = true
    window.animationBehavior = .none

    if passthroughActivationApp?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
      window.passthroughActivationApp = passthroughActivationApp
    }
    return window
  }

  private func makeSelectionView(onScreenFrame frame: CGRect, frozenImage: CGImage) -> RegionSelectionView {
    RegionSelectionView(
      frame: CGRect(origin: .zero, size: frame.size),
      frozenImage: frozenImage,
      settings: settings,
      storeManager: storeManager,
      statisticsStore: statisticsStore,
      toastPresenter: toastPresenter
    )
  }

  private func presentOverlayWindow(
    _ window: RegionSelectionWindow,
    selectionView: RegionSelectionView
  ) {
    window.contentView = selectionView
    self.window = window
    self.selectionView = selectionView

    selectionView.prepareGlassChromeForFirstDisplay()
    window.alphaValue = 1
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(selectionView)
    window.invalidateCursorRects(for: selectionView)
    NSCursor.crosshair.set()
    selectionView.primeGlassChromeAfterFirstDisplay(revealDelay: glassChromeRevealDelayForFirstDisplay)
    transitionAnimator.animateIn(window, style: effectiveCaptureTransitionStyle)
  }

  func closeTransitionPreview(animated: Bool) {
    transitionPreviewTask?.cancel()
    transitionPreviewTask = nil
    transitionPreviewActive = false
    closeWindow(animated: animated) { [weak self] in
      self?.transitionPreviewStyleOverride = nil
    }
  }

  func closeWindow(animated: Bool = true, completion: (() -> Void)? = nil) {
    guard let closingWindow = window else {
      selectionView = nil
      completion?()
      return
    }

    let closingSelectionView = selectionView
    window = nil
    selectionView = nil

    guard animated else {
      transitionAnimator.disposeWindow(closingWindow, selectionView: closingSelectionView)
      completion?()
      return
    }

    transitionAnimator.animateOut(
      closingWindow,
      selectionView: closingSelectionView,
      style: effectiveCaptureTransitionStyle,
      completion: completion
    )
  }

  private var glassChromeRevealDelayForFirstDisplay: TimeInterval {
    transitionAnimator.glassChromeRevealDelay(style: effectiveCaptureTransitionStyle)
  }

  private var effectiveCaptureTransitionStyle: CaptureTransitionStyle {
    if let transitionPreviewStyleOverride {
      return transitionPreviewStyleOverride
    }
    guard storeManager.canUse(.captureTransitions) else {
      return .none
    }
    return settings.captureTransitionStyle
  }

  func finishSelection(with result: RegionSelectionResult?) {
    let completion = selectionCompletion
    selectionCompletion = nil
    completion?(result)
  }

  func clearFlowCallbacks() {
    selectionCompletion = nil
    editingDelegate = nil
  }
}
