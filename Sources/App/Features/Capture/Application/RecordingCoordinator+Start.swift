import AVFoundation
import CoreGraphics
import Foundation
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.vivyshot", category: "Recording")

@MainActor
extension RecordingCoordinator {
  func startRecording(
    selectionRectInScreen: CGRect,
    windowID: CGWindowID? = nil,
    overlayState: RecordingOverlayState? = nil,
    showFloatingHUD: Bool = true,
    flowHandler: any RecordingFlowHandling
  ) {
    self.flowHandler = flowHandler
    recordingRect = selectionRectInScreen.standardized
    logger.info("Recording start requested: \(Int(self.recordingRect.width))x\(Int(self.recordingRect.height))")

    startTask?.cancel()
    startTask = Task { [weak self] in
      guard let self else {
        return
      }
      do {
        if settings.hideNotificationsBestEffort {
          toastPresenter.show("Tip: Enable Focus for cleaner recordings.", duration: 1.8)
        }
        try await runCountdownIfNeeded()
        try await runtimePermissions.ensureRuntimePermissions()
        try Task.checkCancellation()

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
          try Task.checkCancellation()

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
          colorProfile: settings.recordingColorProfile,
          captureResolution: settings.recordingCaptureResolution,
          captureBuffering: settings.recordingCaptureBuffering,
          showsPointer: settings.recordingShowsPointer,
          showsSystemClickRings: settings.recordingShowsSystemClickRings,
          captureSystemAudio: settings.recordSystemAudio,
          captureMicrophone: microphoneEnabled,
          microphoneDeviceID: settings.microphoneDeviceID,
          includesAppAudio: settings.recordingIncludesAppAudio,
          windowID: settings.recordingWindowCaptureStyle == .selectedWindowOnly ? windowID : nil,
          capturedOverlayWindowIDs: capturedOverlayWindowIDs
        )
        let recorder = dependencies.makeRegionRecorder(recordingRect, recordingConfig, outputURL)

        if let pendingWebcamRecorder {
          await Task.yield()
          try await pendingWebcamRecorder.start()
        }
        try Task.checkCancellation()

        try await recorder.start()
        if Task.isCancelled {
          // A stop raced this start after capture began: tear the capture down
          // instead of leaving an orphaned stream recording with no UI.
          _ = try? await recorder.stop()
          try? FileManager.default.removeItem(at: outputURL)
          throw CancellationError()
        }
        recorder.onStreamStopped = { [weak self] in
          logger.error("Stream stopped externally; finishing recording flow")
          self?.stopRecordingAndOpenEditor()
        }
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

        self.startTask = nil
        self.isRecordingActive = true
        self.flowHandler?.recordingFlowDidStart(liveState: liveControlState)
        logger.info("Recording started")
        if showFloatingHUD {
          showHUD()
        }
      } catch is CancellationError {
        // A stop raced this start; the stop path already cleaned up session state.
        logger.info("Recording start cancelled by stop")
      } catch {
        logger.error("Recording start failed: \(error.localizedDescription, privacy: .public)")
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
