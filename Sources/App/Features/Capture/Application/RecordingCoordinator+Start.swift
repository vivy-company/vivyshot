import AVFoundation
import CoreGraphics
import Foundation

@MainActor
extension RecordingCoordinator {
  func startRecording(
    selectionRectInScreen: CGRect,
    overlayState: RecordingOverlayState? = nil,
    showFloatingHUD: Bool = true,
    flowHandler: any RecordingFlowHandling
  ) {
    self.flowHandler = flowHandler
    recordingRect = selectionRectInScreen.standardized

    Task { [weak self] in
      guard let self else {
        return
      }
      do {
        if settings.hideNotificationsBestEffort {
          toastPresenter.show("Tip: Enable Focus for cleaner recordings.", duration: 1.8)
        }
        try await runCountdownIfNeeded()
        try await runtimePermissions.ensureRuntimePermissions()

        let startPlan = RecordingStartPlan.make(
          selectionSize: recordingRect.size,
          overlayState: overlayState,
          settings: settings,
          storeManager: storeManager,
          runtimePermissions: runtimePermissions
        )
        webcamPlacementChanges = [
          OverlayPlacementChange(timestampSeconds: 0, normalizedFrame: startPlan.initialWebcamFrame)
        ]
        keystrokePlacementChanges = [
          OverlayPlacementChange(timestampSeconds: 0, normalizedFrame: startPlan.overlayState.keystrokeFrame)
        ]
        let outputURL = makeTemporaryRecordingURL()
        let microphoneEnabled = startPlan.microphoneEnabled
        let webcamEnabled = startPlan.webcamEnabled
        let keystrokesEnabled = startPlan.keystrokesEnabled
        liveControlState = startPlan.liveControlState
        mouseClickHighlightStyleInSession = startPlan.mouseClickHighlightStyle
        systemAudioEnabledInSession = settings.recordSystemAudio
        microphoneEnabledInSession = microphoneEnabled
        webcamOverlayUsedInSession = webcamEnabled
        var webcamPreviewLayer: AVCaptureVideoPreviewLayer?
        var pendingWebcamRecorder: WebcamRecorder?
        var capturedOverlayWindowIDs: [CGWindowID] = []
        let capturesKeystrokes = keystrokesEnabled && runtimePermissions.isAccessibilityTrusted(promptIfNeeded: false)
        if keystrokesEnabled && !capturesKeystrokes {
          toastPresenter.show("Keystroke overlay visible. Enable Accessibility to show real keys.", duration: 2.4)
        }

        if webcamEnabled {
          await self.flowHandler?.recordingFlowWillStartWebcamCapture()

          let webcamOutputURL = makeTemporaryWebcamURL()
          let webcamRecorder = try dependencies.makeWebcamRecorder(webcamOutputURL, settings.webcamDeviceID)
          self.webcamRecorder = webcamRecorder
          webcamPreviewLayer = webcamRecorder.makePreviewLayer()
          pendingWebcamRecorder = webcamRecorder
        }

        if webcamEnabled || startPlan.keystrokesFeatureAvailable {
          let overlayController = dependencies.makeOverlayController(
            RecordingOverlayControllerRequest(
              captureRectInScreen: recordingRect,
              webcamPreviewLayer: webcamPreviewLayer,
              webcamFrame: startPlan.initialWebcamFrame,
              webcamShape: settings.webcamOverlayShape,
              webcamAspectRatio: settings.webcamOverlayAspectRatio,
              showKeystrokeOverlay: keystrokesEnabled,
              keystrokeFrame: startPlan.overlayState.keystrokeFrame,
              keystrokeStyle: settings.keystrokeOverlayStyle,
              keystrokeSize: settings.keystrokeOverlaySize,
              onWebcamFrameChanged: { [weak self] frame in
                self?.recordWebcamPlacementChange(frame)
              },
              onKeystrokeFrameChanged: { [weak self] frame in
                self?.recordKeystrokePlacementChange(frame)
              }
            )
          )
          overlayController.show()
          recordingOverlayController = overlayController
          if let capturedWindowID = overlayController.capturedWindowID {
            capturedOverlayWindowIDs.append(capturedWindowID)
          }
        }

        let recordingConfig = RecordingConfig(
          encoder: settings.recordingEncoder,
          frameRate: settings.recordingFrameRate.rawValue,
          captureSystemAudio: settings.recordSystemAudio,
          captureMicrophone: microphoneEnabled,
          microphoneDeviceID: settings.microphoneDeviceID,
          capturedOverlayWindowIDs: capturedOverlayWindowIDs
        )
        let recorder = dependencies.makeRegionRecorder(recordingRect, recordingConfig, outputURL)

        if let pendingWebcamRecorder {
          await Task.yield()
          try await pendingWebcamRecorder.start()
        }

        try await recorder.start()
        self.recorder = recorder
        self.recordingStartUptime = ProcessInfo.processInfo.systemUptime

        let monitor = dependencies.makeInputMonitor(
          RecordingInputMonitorRequest(
            captureRectInScreen: recordingRect,
            monitorsKeystrokes: startPlan.keystrokesFeatureAvailable,
            monitorsMouseClicks: true,
            captureKeystrokes: capturesKeystrokes,
            captureMouseClicks: startPlan.mouseClickHighlightStyle != nil,
            onKeyEvent: { [weak self] event in
              Task { @MainActor [weak self] in
                self?.recordingOverlayController?.showKeystroke(event.displayToken)
              }
            }
          )
        )
        monitor.start()
        inputMonitor = monitor
        keystrokeOverlayEnabledInSession = keystrokesEnabled

        self.isRecordingActive = true
        self.flowHandler?.recordingFlowDidStart(liveState: liveControlState)
        if showFloatingHUD {
          showHUD()
        }
      } catch {
        let activeFlowHandler = self.flowHandler
        self.isRecordingActive = false
        cleanupRecordingSession()
        activeFlowHandler?.recordingFlowDidFail(message: "Failed to start video recording: \(error.localizedDescription)")
      }
    }
  }

  func runCountdownIfNeeded() async throws {
    let seconds = settings.recordingCountdown.rawValue
    guard seconds > 0 else {
      return
    }

    for remaining in stride(from: seconds, to: 0, by: -1) {
      toastPresenter.show("Recording starts in \(remaining)…", duration: 0.9)
      try await Task.sleep(nanoseconds: 1_000_000_000)
    }
  }
}
