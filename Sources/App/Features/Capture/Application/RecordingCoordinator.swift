import AppKit
import AVFoundation
import AVKit
import CoreGraphics
import CoreMedia
import ImageIO
import QuartzCore
import ScreenCaptureKit
import UniformTypeIdentifiers
import VideoToolbox

/// Coordinates a full recording session from permissions through capture, overlays, preview, and export handoff.
@MainActor
final class RecordingCoordinator: RegionSelectionRecordingControlling {
  let settings: AppSettings
  let storeManager: StoreManager
  private let proExportTrialStore: ProExportTrialStore
  private let statisticsRecorder: RecordingStatisticsRecorder
  private let toastPresenter: ToastPresenting
  private let dependencies: RecordingCoordinatorDependencies
  var recorder: (any RegionRecordingSession)?
  var webcamRecorder: WebcamRecorder?
  var inputMonitor: RecordingInputMonitor?
  private var hudController: RecordingHUDController?
  var recordingOverlayController: RecordingOverlayController?
  private let postRecordingPresenter: PostRecordingSavePresenter
  private weak var flowHandler: (any RecordingFlowHandling)?
  private var recordingRect: CGRect = .zero
  private var recordingStartUptime: TimeInterval?
  private var webcamPlacementChanges: [OverlayPlacementChange] = []
  private var keystrokePlacementChanges: [OverlayPlacementChange] = []
  var webcamOverlayUsedInSession = false
  var keystrokeOverlayEnabledInSession = false
  var mouseClickHighlightStyleInSession: MouseClickHighlightStyle?
  var systemAudioEnabledInSession = false
  var microphoneEnabledInSession = false
  var liveControlState = RecordingLiveControlState(
    recordSystemAudio: false,
    recordMicrophone: false,
    showWebcam: false,
    highlightMouseClicks: false,
    highlightKeystrokes: false
  )
  private var isStoppingRecording = false
  weak var recordingStateObserver: (any RecordingStateObserving)?

  private(set) var isRecordingActive = false {
    didSet {
      if oldValue != isRecordingActive {
        recordingStateObserver?.recordingStateDidChange(isRecording: isRecordingActive)
      }
    }
  }

  init(
    settings: AppSettings,
    storeManager: StoreManager,
    proExportTrialStore: ProExportTrialStore,
    statisticsStore: StatisticsStore,
    toastPresenter: ToastPresenting,
    presentPaywall: @escaping () -> Void,
    dependencies: RecordingCoordinatorDependencies = .live
  ) {
    self.settings = settings
    self.storeManager = storeManager
    self.proExportTrialStore = proExportTrialStore
    self.statisticsRecorder = RecordingStatisticsRecorder(statisticsStore: statisticsStore)
    self.toastPresenter = toastPresenter
    self.dependencies = dependencies
    postRecordingPresenter = dependencies.makePostRecordingPresenter(
      settings,
      storeManager,
      proExportTrialStore,
      toastPresenter,
      presentPaywall
    )
  }

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

  func stopRecordingFromInlineToolbar() {
    stopRecordingAndOpenEditor()
  }

  func stopRecordingFromStatusBar() {
    stopRecordingAndOpenEditor()
  }

  private func runCountdownIfNeeded() async throws {
    let seconds = settings.recordingCountdown.rawValue
    guard seconds > 0 else {
      return
    }

    for remaining in stride(from: seconds, to: 0, by: -1) {
      toastPresenter.show("Recording starts in \(remaining)…", duration: 0.9)
      try await Task.sleep(nanoseconds: 1_000_000_000)
    }
  }

  private func showHUD() {
    let hud = RecordingHUDController(
      recordSystemAudio: settings.recordSystemAudio,
      recordMicrophone: runtimePermissions.captureMicrophoneEnabled
    ) { [weak self] in
      self?.stopRecordingAndOpenEditor()
    }
    hudController = hud
    hud.show(near: recordingRect)
  }

  private func stopRecordingAndOpenEditor() {
    guard !isStoppingRecording else {
      return
    }
    isStoppingRecording = true
    isRecordingActive = false
    hudController?.close()
    hudController = nil
    let activeOverlayController = recordingOverlayController
    recordingOverlayController = nil

    guard let activeRecorder = recorder else {
      activeOverlayController?.close()
      markCaptureFlowFinished()
      cleanupRecordingSession()
      return
    }
    recorder = nil
    let activeWebcamRecorder = webcamRecorder
    webcamRecorder = nil
    let webcamTimeOffsetSeconds = Self.webcamTimeOffsetSeconds(
      screenStartUptime: recordingStartUptime,
      webcamStartUptime: activeWebcamRecorder?.recordingStartUptime
    )
    let webcamStopTask = Task { @MainActor [activeWebcamRecorder] in
      await Self.stopWebcamRecorder(activeWebcamRecorder)
    }

    Task { [weak self] in
      guard let self else {
        return
      }

      do {
        defer {
          activeOverlayController?.close()
          isStoppingRecording = false
        }
        let monitorResult = inputMonitor?.stop() ?? RecordingInputResult(keyEvents: [], clickEvents: [])
        inputMonitor = nil

        let outputURL: URL
        do {
          outputURL = try await activeRecorder.stop()
        } catch {
          _ = await webcamStopTask.value
          throw error
        }

        let webcamURL: URL?
        switch await webcamStopTask.value {
        case .success(let stoppedURL):
          webcamURL = stoppedURL
        case .failure(let error):
          webcamURL = nil
          toastPresenter.show("Webcam recording unavailable: \(error.localizedDescription)", duration: 2.8)
        }

        let recordingDetails = PostRecordingDetails(
          frameRate: settings.recordingFrameRate.rawValue,
          systemAudioEnabled: systemAudioEnabledInSession,
          microphoneEnabled: microphoneEnabledInSession,
          webcamEnabled: webcamOverlayUsedInSession,
          mouseClicksEnabled: mouseClickHighlightStyleInSession != nil,
          keystrokesEnabled: keystrokeOverlayEnabledInSession,
          keyEventCount: monitorResult.keyEvents.count,
          clickEventCount: monitorResult.clickEvents.count
        )

        // Recording is fully stopped: allow a new capture flow immediately.
        markCaptureFlowFinished()

        let assetInfo = await PostRecordingAssetInfoLoader.load(url: outputURL)
        let videoProject = makeVideoProject(
          assetInfo: assetInfo,
          webcamURL: webcamURL,
          monitorResult: monitorResult
        )
        let project = PostRecordingProject(
          inputURL: outputURL,
          webcamURL: webcamURL,
          webcamTimeOffsetSeconds: webcamURL == nil ? 0 : webcamTimeOffsetSeconds,
          videoProject: videoProject,
          details: recordingDetails,
          durationSeconds: assetInfo.durationSeconds,
          videoSize: assetInfo.videoSize,
          overlaysBurnedIn: webcamOverlayUsedInSession || keystrokeOverlayEnabledInSession
        )

        await self.presentPostRecordingDialog(
          project: project,
          thumbnail: assetInfo.thumbnail
        )
      } catch {
        let activeFlowHandler = self.flowHandler
        self.isStoppingRecording = false
        self.isRecordingActive = false
        cleanupRecordingSession()
        activeFlowHandler?.recordingFlowDidFail(message: "Failed to stop recording: \(error.localizedDescription)")
      }
    }
  }

  private func presentPostRecordingDialog(
    project: PostRecordingProject,
    thumbnail: NSImage?
  ) async {
    statisticsRecorder.recordCompletedRecordingIfNeeded(
      inputURL: project.inputURL,
      durationSeconds: project.durationSeconds
    )
    postRecordingPresenter.present(project: project, thumbnail: thumbnail)
  }

  private func markCaptureFlowFinished() {
    let activeFlowHandler = flowHandler
    flowHandler = nil
    activeFlowHandler?.recordingFlowDidFinish()
  }

  func reportRecordingError(_ message: String) {
    flowHandler?.recordingFlowDidFail(message: message)
  }

  private func cleanupRecordingSession() {
    isRecordingActive = false
    hudController?.close()
    hudController = nil
    recorder = nil
    webcamRecorder?.cancel()
    webcamRecorder = nil
    inputMonitor = nil
    recordingOverlayController?.close()
    recordingOverlayController = nil
    recordingStartUptime = nil
    flowHandler = nil
    webcamPlacementChanges = []
    keystrokePlacementChanges = []
    webcamOverlayUsedInSession = false
    keystrokeOverlayEnabledInSession = false
    mouseClickHighlightStyleInSession = nil
    systemAudioEnabledInSession = false
    microphoneEnabledInSession = false
    liveControlState = RecordingLiveControlState(
      recordSystemAudio: false,
      recordMicrophone: false,
      showWebcam: false,
      highlightMouseClicks: false,
      highlightKeystrokes: false
    )
    isStoppingRecording = false
  }

  private func makeVideoProject(
    assetInfo: PostRecordingAssetInfo,
    webcamURL: URL?,
    monitorResult: RecordingInputResult
  ) -> RecordingProject {
    RecordingProjectBuilder(
      fallbackSize: recordingRect.size,
      frameRate: settings.recordingFrameRate.rawValue,
      systemAudioEnabled: systemAudioEnabledInSession,
      microphoneEnabled: microphoneEnabledInSession,
      webcamAssetAvailable: webcamURL != nil,
      webcamOverlayEnabled: webcamOverlayUsedInSession,
      webcamShape: settings.webcamOverlayShape,
      webcamAspectRatio: settings.webcamOverlayAspectRatio,
      webcamPlacementChanges: webcamPlacementChanges,
      keystrokeOverlayEnabled: keystrokeOverlayEnabledInSession,
      keystrokeStyle: settings.keystrokeOverlayStyle,
      keystrokeSize: settings.keystrokeOverlaySize,
      keystrokePlacementChanges: keystrokePlacementChanges,
      mouseClickHighlightStyle: mouseClickHighlightStyleInSession,
      monitorResult: monitorResult
    ).makeProject(
      durationSeconds: assetInfo.durationSeconds,
      videoSize: assetInfo.videoSize
    )
  }

  private func recordWebcamPlacementChange(_ frame: CGRect) {
    let timestamp = currentRecordingOverlayTimestamp()
    settings.setWebcamOverlayFrame(frame)
    webcamPlacementChanges.append(OverlayPlacementChange(timestampSeconds: timestamp, normalizedFrame: frame))
  }

  private func recordKeystrokePlacementChange(_ frame: CGRect) {
    let timestamp = currentRecordingOverlayTimestamp()
    settings.setKeystrokeOverlayFrame(frame)
    keystrokePlacementChanges.append(OverlayPlacementChange(timestampSeconds: timestamp, normalizedFrame: frame))
  }

  private func currentRecordingOverlayTimestamp() -> TimeInterval {
    guard let recordingStartUptime else {
      return 0
    }
    return max(0, ProcessInfo.processInfo.systemUptime - recordingStartUptime)
  }

  private func makeTemporaryRecordingURL() -> URL {
    CaptureTemporaryFiles.recordingURL()
  }

  private func makeTemporaryWebcamURL() -> URL {
    CaptureTemporaryFiles.webcamURL()
  }

  var runtimePermissions: RecordingRuntimePermissions {
    RecordingRuntimePermissions(settings: settings, storeManager: storeManager)
  }

}
