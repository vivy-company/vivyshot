import AppKit
import Foundation

@MainActor
extension RecordingCoordinator {
  func stopRecordingFromInlineToolbar() {
    stopRecordingAndOpenEditor()
  }

  func stopRecordingFromStatusBar() {
    stopRecordingAndOpenEditor()
  }

  func showHUD() {
    let hud = RecordingHUDController(
      recordSystemAudio: settings.recordSystemAudio,
      recordMicrophone: runtimePermissions.captureMicrophoneEnabled
    ) { [weak self] in
      self?.stopRecordingAndOpenEditor()
    }
    hudController = hud
    hud.show(near: recordingRect)
  }

  func stopRecordingAndOpenEditor() {
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

  func presentPostRecordingDialog(
    project: PostRecordingProject,
    thumbnail: NSImage?
  ) async {
    statisticsRecorder.recordCompletedRecordingIfNeeded(
      inputURL: project.inputURL,
      durationSeconds: project.durationSeconds
    )
    postRecordingPresenter.present(project: project, thumbnail: thumbnail)
  }

  func markCaptureFlowFinished() {
    let activeFlowHandler = flowHandler
    flowHandler = nil
    activeFlowHandler?.recordingFlowDidFinish()
  }

  func reportRecordingError(_ message: String) {
    flowHandler?.recordingFlowDidFail(message: message)
  }

  func cleanupRecordingSession() {
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
}
