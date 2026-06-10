import CoreGraphics

@MainActor
struct RecordingStartPlan {
  let overlayState: RecordingOverlayState
  let initialWebcamFrame: CGRect
  let microphoneEnabled: Bool
  let webcamEnabled: Bool
  let keystrokesEnabled: Bool
  let keystrokesFeatureAvailable: Bool
  let mouseClickHighlightStyle: MouseClickHighlightStyle?
  let liveControlState: RecordingLiveControlState

  static func make(
    selectionSize: CGSize,
    overlayState providedOverlayState: RecordingOverlayState?,
    settings: AppSettings,
    storeManager: StoreManager,
    runtimePermissions: RecordingRuntimePermissions
  ) -> RecordingStartPlan {
    let overlayState = providedOverlayState ?? RecordingOverlayState.from(settings: settings)
    let initialWebcamFrame = RecordingCoordinator.normalizedWebcamFrameForRecording(
      overlayState.webcamFrame,
      shape: settings.webcamOverlayShape,
      aspectRatio: settings.webcamOverlayAspectRatio,
      in: selectionSize
    )
    let microphoneEnabled = runtimePermissions.captureMicrophoneEnabled
    let webcamEnabled = runtimePermissions.showWebcamEnabled
    let keystrokesEnabled = runtimePermissions.highlightKeystrokesEnabled
    let keystrokesFeatureAvailable = storeManager.canUse(.keystrokeOverlay)
    let mouseClickHighlightStyle = settings.effectiveMouseClickHighlightStyle
    var disabledTools = RecordingToolEntitlements.lockedTools(storeManager: storeManager)
    if !webcamEnabled {
      disabledTools.insert(.webcam)
    }

    return RecordingStartPlan(
      overlayState: overlayState,
      initialWebcamFrame: initialWebcamFrame,
      microphoneEnabled: microphoneEnabled,
      webcamEnabled: webcamEnabled,
      keystrokesEnabled: keystrokesEnabled,
      keystrokesFeatureAvailable: keystrokesFeatureAvailable,
      mouseClickHighlightStyle: mouseClickHighlightStyle,
      liveControlState: RecordingLiveControlState(
        recordSystemAudio: settings.recordSystemAudio,
        recordMicrophone: microphoneEnabled,
        showWebcam: webcamEnabled,
        highlightMouseClicks: mouseClickHighlightStyle != nil,
        highlightKeystrokes: keystrokesEnabled,
        disabledTools: disabledTools
      )
    )
  }
}
