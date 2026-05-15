import AppKit
import ApplicationServices
import AVFoundation
import AVKit
import CoreGraphics
import CoreMedia
import ImageIO
import QuartzCore
import ScreenCaptureKit
import SwiftUI
import UniformTypeIdentifiers
import VivyShotKit

@MainActor
final class VideoCaptureCoordinator {
  private let videoMicrophoneFeatureEnabled = true
  private let videoWebcamFeatureEnabled = true
  private let videoKeystrokesFeatureEnabled = true
  private let settings: AppSettings
  private var recorder: ScreenRegionRecorder?
  private var webcamRecorder: WebcamRecorder?
  private var inputMonitor: RecordingInputMonitor?
  private var hudController: VideoRecordingHUDController?
  private var recordingOverlayController: RecordingOverlayController?
  private var postRecordingPanels: [PostRecordingActionPanel] = []
  private var onDone: (() -> Void)?
  private var onError: ((String) -> Void)?
  private var recordingRect: CGRect = .zero
  private var recordingStartUptime: TimeInterval?
  private var webcamPlacementChanges: [VideoOverlayPlacementChange] = []
  private var keystrokePlacementChanges: [VideoOverlayPlacementChange] = []
  private var webcamOverlayEnabledInSession = false
  private var keystrokeOverlayEnabledInSession = false
  private var isStoppingRecording = false
  var onRecordingStateChanged: ((Bool) -> Void)?

  private(set) var isRecordingActive = false {
    didSet {
      if oldValue != isRecordingActive {
        onRecordingStateChanged?(isRecordingActive)
      }
    }
  }

  init(settings: AppSettings) {
    self.settings = settings
  }

  func startRecording(
    selectionRectInScreen: CGRect,
    overlayState: VideoCaptureOverlayState? = nil,
    showFloatingHUD: Bool = true,
    onBeforeWebcamCaptureStart: (() async -> Void)? = nil,
    onStarted: (() -> Void)? = nil,
    onDone: @escaping () -> Void,
    onError: @escaping (String) -> Void
  ) {
    self.onDone = onDone
    self.onError = onError
    recordingRect = selectionRectInScreen.standardized

    Task { [weak self] in
      guard let self else {
        return
      }
      do {
        let initialOverlayState = overlayState ?? VideoCaptureOverlayState.from(settings: settings)
        let initialWebcamFrame = Self.normalizedWebcamFrameForRecording(
          initialOverlayState.webcamFrame,
          shape: settings.videoWebcamOverlayShape,
          aspectRatio: settings.videoWebcamOverlayAspectRatio,
          in: recordingRect.size
        )
        webcamPlacementChanges = [
          VideoOverlayPlacementChange(timestampSeconds: 0, normalizedFrame: initialWebcamFrame)
        ]
        keystrokePlacementChanges = [
          VideoOverlayPlacementChange(timestampSeconds: 0, normalizedFrame: initialOverlayState.keystrokeFrame)
        ]
        if settings.videoHideNotificationsBestEffort {
          TransientToast.show("Tip: Enable Focus for cleaner recordings.", duration: 1.8)
        }
        try await runCountdownIfNeeded()
        try await ensureRuntimePermissions()

        let outputURL = makeTemporaryRecordingURL()
        let microphoneEnabled = effectiveCaptureMicrophoneEnabled
        let webcamEnabled = effectiveShowWebcamEnabled
        let keystrokesEnabled = effectiveHighlightKeystrokesEnabled
        webcamOverlayEnabledInSession = webcamEnabled
        var webcamPreviewLayer: AVCaptureVideoPreviewLayer?
        var pendingWebcamRecorder: WebcamRecorder?
        var capturedOverlayWindowIDs: [CGWindowID] = []
        let capturesKeystrokes = keystrokesEnabled && isAccessibilityTrusted(promptIfNeeded: false)
        if keystrokesEnabled && !capturesKeystrokes {
          TransientToast.show("Keystroke overlay visible. Enable Accessibility to show real keys.", duration: 2.4)
        }

        if webcamEnabled {
          await onBeforeWebcamCaptureStart?()

          let webcamOutputURL = makeTemporaryWebcamURL()
          let webcamRecorder = try WebcamRecorder(
            outputURL: webcamOutputURL,
            preferredDeviceID: settings.videoWebcamDeviceID
          )
          self.webcamRecorder = webcamRecorder
          webcamPreviewLayer = webcamRecorder.makePreviewLayer()
          pendingWebcamRecorder = webcamRecorder
        }

        if webcamEnabled || keystrokesEnabled {
          let overlayController = RecordingOverlayController(
            captureRectInScreen: recordingRect,
            webcamPreviewLayer: webcamPreviewLayer,
            webcamFrame: initialWebcamFrame,
            webcamShape: settings.videoWebcamOverlayShape,
            webcamAspectRatio: settings.videoWebcamOverlayAspectRatio,
            showKeystrokeOverlay: keystrokesEnabled,
            keystrokeFrame: initialOverlayState.keystrokeFrame,
            keystrokeStyle: settings.videoKeystrokeOverlayStyle,
            keystrokeSize: settings.videoKeystrokeOverlaySize,
            onWebcamFrameChanged: { [weak self] frame in
              self?.recordWebcamPlacementChange(frame)
            },
            onKeystrokeFrameChanged: { [weak self] frame in
              self?.recordKeystrokePlacementChange(frame)
            }
          )
          overlayController.show()
          recordingOverlayController = overlayController
          if let capturedWindowID = overlayController.capturedWindowID {
            capturedOverlayWindowIDs.append(capturedWindowID)
          }
        }

        let recordingConfig = VideoRecordingConfig(
          codec: settings.videoCodec,
          frameRate: settings.videoFrameRate.rawValue,
          highlightMouseClicks: settings.videoHighlightMouseClicks,
          captureSystemAudio: settings.videoRecordSystemAudio,
          captureMicrophone: microphoneEnabled,
          capturedOverlayWindowIDs: capturedOverlayWindowIDs
        )
        let recorder = ScreenRegionRecorder(
          selectionRectInScreen: recordingRect,
          config: recordingConfig,
          outputURL: outputURL
        )

        if let pendingWebcamRecorder {
          await Task.yield()
          try await pendingWebcamRecorder.start()
        }

        try await recorder.start()
        self.recorder = recorder
        self.recordingStartUptime = ProcessInfo.processInfo.systemUptime

        let monitor = RecordingInputMonitor(
          captureRectInScreen: recordingRect,
          captureKeystrokes: capturesKeystrokes,
          captureMouseClicks: settings.videoHighlightMouseClicks,
          onKeyEvent: { [weak self] event in
            Task { @MainActor [weak self] in
              self?.recordingOverlayController?.showKeystroke(event.displayToken)
            }
          }
        )
        monitor.start()
        inputMonitor = monitor
        keystrokeOverlayEnabledInSession = keystrokesEnabled

        onStarted?()
        self.isRecordingActive = true
        if showFloatingHUD {
          showHUD()
        }
      } catch {
        self.isRecordingActive = false
        cleanupRecordingSession()
        onError("Failed to start video recording: \(error.localizedDescription)")
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
    let seconds = settings.videoCountdown.rawValue
    guard seconds > 0 else {
      return
    }

    for remaining in stride(from: seconds, to: 0, by: -1) {
      TransientToast.show("Recording starts in \(remaining)…", duration: 0.9)
      try await Task.sleep(nanoseconds: 1_000_000_000)
    }
  }

  private func showHUD() {
    let hud = VideoRecordingHUDController(
      recordSystemAudio: settings.videoRecordSystemAudio,
      recordMicrophone: effectiveCaptureMicrophoneEnabled
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
          TransientToast.show("Webcam recording unavailable: \(error.localizedDescription)", duration: 2.8)
        }

        let recordingDetails = PostRecordingDetails(
          frameRate: settings.videoFrameRate.rawValue,
          systemAudioEnabled: settings.videoRecordSystemAudio,
          microphoneEnabled: effectiveCaptureMicrophoneEnabled,
          webcamEnabled: webcamOverlayEnabledInSession,
          mouseClicksEnabled: settings.videoHighlightMouseClicks,
          keystrokesEnabled: keystrokeOverlayEnabledInSession,
          keyEventCount: monitorResult.keyEvents.count,
          clickEventCount: monitorResult.clickEvents.count
        )

        // Recording is fully stopped: allow a new capture flow immediately.
        markCaptureFlowFinished()

        let assetInfo = await PostRecordingActionPanel.loadAssetInfo(url: outputURL)
        let rustProject = makeRustVideoProject(
          assetInfo: assetInfo,
          webcamURL: webcamURL,
          monitorResult: monitorResult
        )
        let project = PostRecordingProject(
          inputURL: outputURL,
          webcamURL: webcamURL,
          webcamTimeOffsetSeconds: webcamURL == nil ? 0 : webcamTimeOffsetSeconds,
          rustProject: rustProject,
          details: recordingDetails,
          durationSeconds: assetInfo.durationSeconds,
          videoSize: assetInfo.videoSize,
          overlaysBurnedIn: webcamOverlayEnabledInSession || keystrokeOverlayEnabledInSession
        )

        await self.presentPostRecordingDialog(
          project: project,
          thumbnail: assetInfo.thumbnail
        )
      } catch {
        self.isStoppingRecording = false
        self.isRecordingActive = false
        cleanupRecordingSession()
        onError?("Failed to stop recording: \(error.localizedDescription)")
      }
    }
  }

  private func presentPostRecordingDialog(
    project: PostRecordingProject,
    thumbnail: NSImage?
  ) async {
    recordRecordingStatisticsIfNeeded(inputURL: project.inputURL, durationSeconds: project.durationSeconds)
    var panelRef: PostRecordingActionPanel?
    let panel = PostRecordingActionPanel(
      inputURL: project.inputURL,
      project: project,
      details: project.details,
      durationSeconds: project.durationSeconds,
      thumbnail: thumbnail,
      videoSize: project.videoSize
    ) { [self] action in
      if let panelRef {
        postRecordingPanels.removeAll(where: { $0 === panelRef })
      }
      switch action {
      case .saveVideo(let options, let exportState, container: let container, consumesFreeProExportTrial: let consumesTrial):
        quickSaveVideo(
          project: project,
          options: options,
          exportState: exportState,
          container: container,
          consumesFreeProExportTrial: consumesTrial
        )
      case .saveGIF(let exportState, let consumesTrial):
        quickSaveGIF(
          project: project,
          exportState: exportState,
          consumesFreeProExportTrial: consumesTrial
        )
      case .discard:
        discardTemporaryRecording(project: project)
      }
    }
    panelRef = panel
    postRecordingPanels.append(panel)
    panel.present()
  }

  private func recordRecordingStatisticsIfNeeded(inputURL: URL, durationSeconds: Double) {
    let recordingID = inputURL.deletingPathExtension().lastPathComponent
    guard !recordingID.isEmpty else {
      return
    }

    let fileSize = (try? inputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
    let durationMS = Int64(max(0, durationSeconds) * 1000.0)
    Task {
      await CaptureStatisticsStore.shared.recordRecordingCompleted(
        recordingID: recordingID,
        occurredAt: Date(),
        bytesProduced: fileSize,
        durationMS: durationMS
      )
    }
  }

  private func quickSaveVideo(
    project: PostRecordingProject,
    options: PostRecordingExportOptions,
    exportState: PostRecordingExportState,
    container: PostRecordingVideoSaveContainer?,
    consumesFreeProExportTrial: Bool
  ) {
    let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
      .replacingOccurrences(of: ":", with: "-")
    let contentType = container?.contentType ?? RustCoreBridge.shared.preferredVideoSaveContentType(codec: options.codec)
    let defaultName = "VivyShot \(timestamp).\(container?.fileExtension ?? contentType.preferredFilenameExtension ?? "mp4")"

    let panel = NSSavePanel()
    panel.allowedContentTypes = container.map { [$0.contentType] }
      ?? RustCoreBridge.shared.allowedVideoSaveContentTypes(codec: options.codec)
    panel.nameFieldStringValue = defaultName
    panel.canCreateDirectories = true
    panel.isExtensionHidden = false

    guard panel.runModal() == .OK, let outputURL = panel.url else { return }

    Task {
      do {
        let exportPlan = project.rustProject.exportPlan()
        let shouldUseCustomCompositor = !project.overlaysBurnedIn
          && (exportPlan?.needsCustomCompositor ?? project.hasNativeCompositedOverlays)
        if shouldUseCustomCompositor {
          try await PostRecordingProjectExporter.exportCompositedVideo(
            project: project,
            options: options,
            exportState: exportState,
            container: container,
            outputURL: outputURL
          )
          markProExportTrialConsumedIfNeeded(consumesFreeProExportTrial)
          cleanupTemporaryAssets(project: project)
          TransientToast.show("Saved video to \(outputURL.lastPathComponent)", duration: 2.5)
          return
        }

        try await exportSourceRecordingVideo(
          project: project,
          options: options,
          exportState: exportState,
          container: container,
          outputURL: outputURL
        )
        markProExportTrialConsumedIfNeeded(consumesFreeProExportTrial)
        cleanupTemporaryAssets(project: project)
        TransientToast.show("Saved video to \(outputURL.lastPathComponent)", duration: 2.5)
      } catch {
        TransientToast.show("Video save failed: \(error.localizedDescription)", duration: 2.5)
      }
    }
  }

  private func exportSourceRecordingVideo(
    project: PostRecordingProject,
    options: PostRecordingExportOptions,
    exportState: PostRecordingExportState,
    container: PostRecordingVideoSaveContainer?,
    outputURL: URL
  ) async throws {
    if FileManager.default.fileExists(atPath: outputURL.path) {
      try FileManager.default.removeItem(at: outputURL)
    }

    let asset = AVURLAsset(url: project.inputURL)
    let durationTime = try await asset.load(.duration)
    let durationSeconds = max(0, CMTimeGetSeconds(durationTime))
    let trimRange = exportState.trimRange(durationSeconds: durationSeconds)

    if exportState.includesAudio {
      let presetName = RustCoreBridge.shared.bestVideoExportPreset(
        codec: options.codec,
        quality: options.quality,
        compatiblePresets: AVAssetExportSession.exportPresets(compatibleWith: asset)
      )

      guard let exportSession = AVAssetExportSession(asset: asset, presetName: presetName) else {
        throw NSError(
          domain: "VivyShot.Export",
          code: -201,
          userInfo: [NSLocalizedDescriptionKey: "Unable to create video export session."]
        )
      }

      let outputFileType = RustCoreBridge.shared.bestVideoSaveFileType(
        codec: options.codec,
        supportedTypes: exportSession.supportedFileTypes,
        preferredContainer: container
      )
      exportSession.outputURL = outputURL
      exportSession.outputFileType = outputFileType
      exportSession.shouldOptimizeForNetworkUse = true
      exportSession.timeRange = trimRange
      if let videoComposition = try await makePostRecordingVideoComposition(asset: asset, options: options) {
        exportSession.videoComposition = videoComposition
      }
      if let fileLengthLimit = RustCoreBridge.shared.estimatedVideoFileLengthLimit(
        durationSeconds: exportState.trimmedDurationSeconds,
        options: options
      ) {
        exportSession.fileLengthLimit = fileLengthLimit
      }
      try await exportSession.vs_export()
      return
    }

    let composition = AVMutableComposition()
    guard let sourceVideoTrack = try await asset.loadTracks(withMediaType: .video).first,
          let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
          )
    else {
      throw NSError(
        domain: "VivyShot.Export",
        code: -202,
        userInfo: [NSLocalizedDescriptionKey: "Recording video track is missing."]
      )
    }

    let naturalSize = try await sourceVideoTrack.load(.naturalSize)
    let preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
    compositionVideoTrack.preferredTransform = preferredTransform
    try compositionVideoTrack.insertTimeRange(trimRange, of: sourceVideoTrack, at: .zero)

    let presetName = RustCoreBridge.shared.bestVideoExportPreset(
      codec: options.codec,
      quality: options.quality,
      compatiblePresets: AVAssetExportSession.exportPresets(compatibleWith: composition)
    )
    guard let exportSession = AVAssetExportSession(asset: composition, presetName: presetName) else {
      throw NSError(
        domain: "VivyShot.Export",
        code: -203,
        userInfo: [NSLocalizedDescriptionKey: "Unable to create muted video export session."]
      )
    }

    let outputFileType = RustCoreBridge.shared.bestVideoSaveFileType(
      codec: options.codec,
      supportedTypes: exportSession.supportedFileTypes,
      preferredContainer: container
    )
    exportSession.outputURL = outputURL
    exportSession.outputFileType = outputFileType
    exportSession.shouldOptimizeForNetworkUse = true
    exportSession.timeRange = CMTimeRange(start: .zero, duration: trimRange.duration)
    if let videoComposition = makePostRecordingVideoComposition(
      videoTrack: compositionVideoTrack,
      naturalSize: naturalSize,
      preferredTransform: preferredTransform,
      duration: trimRange.duration,
      options: options
    ) {
      exportSession.videoComposition = videoComposition
    }
    if let fileLengthLimit = RustCoreBridge.shared.estimatedVideoFileLengthLimit(
      durationSeconds: exportState.trimmedDurationSeconds,
      options: options
    ) {
      exportSession.fileLengthLimit = fileLengthLimit
    }
    nonisolated(unsafe) let unsafeExportSession = exportSession
    try await unsafeExportSession.vs_export()
  }

  private func makePostRecordingVideoComposition(
    asset: AVAsset,
    options: PostRecordingExportOptions
  ) async throws -> AVMutableVideoComposition? {
    let tracks = try await asset.loadTracks(withMediaType: .video)
    guard let videoTrack = tracks.first else {
      return nil
    }

    let naturalSize = try await videoTrack.load(.naturalSize)
    let preferredTransform = try await videoTrack.load(.preferredTransform)
    let duration = try await asset.load(.duration)

    return makePostRecordingVideoComposition(
      videoTrack: videoTrack,
      naturalSize: naturalSize,
      preferredTransform: preferredTransform,
      duration: duration,
      options: options
    )
  }

  private func makePostRecordingVideoComposition(
    videoTrack: AVAssetTrack,
    naturalSize: CGSize,
    preferredTransform: CGAffineTransform,
    duration: CMTime,
    options: PostRecordingExportOptions
  ) -> AVMutableVideoComposition? {
    guard let plan = RustCoreBridge.shared.postRecordingVideoCompositionPlan(
      naturalSize: naturalSize,
      preferredTransform: preferredTransform,
      scale: options.scale
    ) else {
      return nil
    }

    let instruction = AVMutableVideoCompositionInstruction()
    instruction.timeRange = CMTimeRange(start: .zero, duration: duration)

    let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
    layerInstruction.setTransform(plan.transform, at: .zero)
    instruction.layerInstructions = [layerInstruction]

    let composition = AVMutableVideoComposition()
    composition.instructions = [instruction]
    composition.renderSize = plan.renderSize
    composition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(options.frameRate.rawValue))
    return composition
  }

  private func quickSaveGIF(
    project: PostRecordingProject,
    exportState: PostRecordingExportState,
    consumesFreeProExportTrial: Bool
  ) {
    let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
      .replacingOccurrences(of: ":", with: "-")

    let panel = NSSavePanel()
    panel.allowedContentTypes = [.gif]
    panel.nameFieldStringValue = "VivyShot \(timestamp).gif"
    panel.canCreateDirectories = true
    panel.isExtensionHidden = false

    guard panel.runModal() == .OK, let outputURL = panel.url else { return }

    Task {
      do {
        try await PostRecordingProjectExporter.exportGIF(
          project: project,
          exportState: exportState,
          outputURL: outputURL
        )
        markProExportTrialConsumedIfNeeded(consumesFreeProExportTrial)
        cleanupTemporaryAssets(project: project)
        TransientToast.show("Saved GIF to \(outputURL.lastPathComponent)", duration: 2.5)
      } catch {
        TransientToast.show("GIF save failed: \(error.localizedDescription)", duration: 2.8)
      }
    }
  }

  private func markProExportTrialConsumedIfNeeded(_ shouldConsume: Bool) {
    guard shouldConsume else {
      return
    }
    AppSettings.shared.markProExportTrialConsumed()
  }

  private func cleanupTemporaryAssets(project: PostRecordingProject) {
    if FileManager.default.fileExists(atPath: project.inputURL.path) {
      try? FileManager.default.removeItem(at: project.inputURL)
    }
    if let webcamURL = project.webcamURL, FileManager.default.fileExists(atPath: webcamURL.path) {
      try? FileManager.default.removeItem(at: webcamURL)
    }
  }

  private func discardTemporaryRecording(project: PostRecordingProject) {
    Task {
      do {
        if FileManager.default.fileExists(atPath: project.inputURL.path) {
          try FileManager.default.removeItem(at: project.inputURL)
        }
        if let webcamURL = project.webcamURL, FileManager.default.fileExists(atPath: webcamURL.path) {
          try FileManager.default.removeItem(at: webcamURL)
        }
        TransientToast.show("Recording discarded.", duration: 2.0)
      } catch {
        TransientToast.show("Unable to discard recording: \(error.localizedDescription)", duration: 2.5)
      }
    }
  }

  private func markCaptureFlowFinished() {
    let done = onDone
    onDone = nil
    onError = nil
    done?()
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
    webcamPlacementChanges = []
    keystrokePlacementChanges = []
    webcamOverlayEnabledInSession = false
    keystrokeOverlayEnabledInSession = false
    isStoppingRecording = false
  }

  private func makeRustVideoProject(
    assetInfo: (durationSeconds: Double, thumbnail: NSImage?, videoSize: CGSize?),
    webcamURL: URL?,
    monitorResult: RecordingInputResult
  ) -> RustVideoProjectSession {
    let fallbackSize = recordingRect.size
    let videoSize = assetInfo.videoSize ?? fallbackSize
    let durationMS = UInt32(max(1, min(Double(UInt32.max), (assetInfo.durationSeconds * 1000).rounded())))
    let rustProject = RustVideoProjectSession(
      recordingInfo: RustVideoProjectRecordingInfo(
        durationMS: durationMS,
        width: UInt32(max(1, Int(videoSize.width.rounded()))),
        height: UInt32(max(1, Int(videoSize.height.rounded()))),
        frameRate: UInt32(max(1, settings.videoFrameRate.rawValue)),
        hasAudio: settings.videoRecordSystemAudio || effectiveCaptureMicrophoneEnabled,
        hasWebcamAsset: webcamURL != nil,
        hasMicrophoneAudio: effectiveCaptureMicrophoneEnabled
      )
    )

    guard let rustProject else {
      // The recording has a valid fallback size/duration above, so this should not fail.
      preconditionFailure("Unable to create Rust video project")
    }

    _ = rustProject.setWebcamOverlay(
      enabled: webcamOverlayEnabledInSession,
      shape: settings.videoWebcamOverlayShape,
      aspectRatio: settings.videoWebcamOverlayAspectRatio
    )
    for change in webcamPlacementChanges.sorted(by: { $0.timestampSeconds < $1.timestampSeconds }) {
      _ = rustProject.pushWebcamPlacement(
        timestampMS: Self.milliseconds(fromSeconds: change.timestampSeconds),
        frame: change.normalizedFrame
      )
    }

    _ = rustProject.setKeystrokeOverlay(
      enabled: keystrokeOverlayEnabledInSession,
      style: settings.videoKeystrokeOverlayStyle,
      size: settings.videoKeystrokeOverlaySize
    )
    for change in keystrokePlacementChanges.sorted(by: { $0.timestampSeconds < $1.timestampSeconds }) {
      _ = rustProject.pushKeystrokePlacement(
        timestampMS: Self.milliseconds(fromSeconds: change.timestampSeconds),
        frame: change.normalizedFrame
      )
    }

    for keyEvent in monitorResult.keyEvents {
      _ = rustProject.addKeyEvent(
        timestampMS: Self.milliseconds(fromNanoseconds: keyEvent.timestampNS),
        token: keyEvent.displayToken
      )
    }

    for clickEvent in monitorResult.clickEvents {
      _ = rustProject.addClickEvent(
        timestampMS: Self.milliseconds(fromNanoseconds: clickEvent.timestampNS),
        normalizedX: clickEvent.normalizedX,
        normalizedY: clickEvent.normalizedY,
        button: clickEvent.button
      )
    }

    return rustProject
  }

  private static func milliseconds(fromSeconds seconds: Double) -> UInt32 {
    guard seconds.isFinite, seconds > 0 else {
      return 0
    }
    return UInt32(min(Double(UInt32.max), (seconds * 1000).rounded()))
  }

  private static func milliseconds(fromNanoseconds nanoseconds: UInt64) -> UInt32 {
    UInt32(min(UInt64(UInt32.max), nanoseconds / 1_000_000))
  }

  private static func webcamTimeOffsetSeconds(
    screenStartUptime: TimeInterval?,
    webcamStartUptime: TimeInterval?
  ) -> Double {
    guard let screenStartUptime, let webcamStartUptime else {
      return 0
    }
    return max(0, screenStartUptime - webcamStartUptime)
  }

  private static func stopWebcamRecorder(_ recorder: WebcamRecorder?) async -> Result<URL?, Error> {
    guard let recorder else {
      return .success(nil)
    }

    do {
      return .success(try await recorder.stop())
    } catch {
      recorder.cancel()
      return .failure(error)
    }
  }

  private static func normalizedWebcamFrameForRecording(
    _ frame: CGRect,
    shape: VideoWebcamOverlayShapeOption,
    aspectRatio: VideoWebcamOverlayAspectRatioOption,
    in recordingSize: CGSize
  ) -> CGRect {
    let normalized = VideoCaptureOverlayState.normalizedFrame(frame)
    guard recordingSize.width > 0, recordingSize.height > 0 else {
      return normalized
    }

    let bounds = CGRect(origin: .zero, size: recordingSize)
    let denormalized = CGRect(
      x: bounds.minX + normalized.minX * bounds.width,
      y: bounds.minY + normalized.minY * bounds.height,
      width: normalized.width * bounds.width,
      height: normalized.height * bounds.height
    ).integral
    let constrained = (shape == .circle ? VideoWebcamOverlayAspectRatioOption.square : aspectRatio)
      .constrainedFrame(denormalized, in: bounds, minimumSize: CGSize(width: 84, height: 84))
    return VideoCaptureOverlayState.normalizedFrame(
      CGRect(
        x: (constrained.minX - bounds.minX) / bounds.width,
        y: (constrained.minY - bounds.minY) / bounds.height,
        width: constrained.width / bounds.width,
        height: constrained.height / bounds.height
      )
    )
  }

  private func recordWebcamPlacementChange(_ frame: CGRect) {
    let timestamp = currentRecordingOverlayTimestamp()
    settings.setVideoWebcamOverlayNormalizedFrame(frame)
    webcamPlacementChanges.append(VideoOverlayPlacementChange(timestampSeconds: timestamp, normalizedFrame: frame))
  }

  private func recordKeystrokePlacementChange(_ frame: CGRect) {
    let timestamp = currentRecordingOverlayTimestamp()
    settings.setVideoKeystrokeOverlayNormalizedFrame(frame)
    keystrokePlacementChanges.append(VideoOverlayPlacementChange(timestampSeconds: timestamp, normalizedFrame: frame))
  }

  private func currentRecordingOverlayTimestamp() -> TimeInterval {
    guard let recordingStartUptime else {
      return 0
    }
    return max(0, ProcessInfo.processInfo.systemUptime - recordingStartUptime)
  }

  private func makeTemporaryRecordingURL() -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("vivyshot-recordings", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("capture-\(UUID().uuidString).mp4")
  }

  private func makeTemporaryWebcamURL() -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("vivyshot-recordings", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("webcam-\(UUID().uuidString).mov")
  }

  private func ensureRuntimePermissions() async throws {
    if effectiveCaptureMicrophoneEnabled {
      try await ensureMediaAccess(
        for: .audio,
        errorTitle: "Microphone permission is required when microphone recording is enabled."
      )
    }

    if effectiveShowWebcamEnabled {
      try await ensureMediaAccess(
        for: .video,
        errorTitle: "Camera permission is required when webcam recording is enabled."
      )
    }

    if effectiveHighlightKeystrokesEnabled, !isAccessibilityTrusted(promptIfNeeded: true) {
      return
    }
  }

  private func ensureMediaAccess(for mediaType: AVMediaType, errorTitle: String) async throws {
    let status = AVCaptureDevice.authorizationStatus(for: mediaType)
    switch status {
    case .authorized:
      return
    case .notDetermined:
      let granted = await AVCaptureDevice.requestAccess(for: mediaType)
      if granted {
        return
      }
      throw NSError(
        domain: "com.vivyshot.video",
        code: -57,
        userInfo: [NSLocalizedDescriptionKey: errorTitle]
      )
    case .denied, .restricted:
      throw NSError(
        domain: "com.vivyshot.video",
        code: -58,
        userInfo: [NSLocalizedDescriptionKey: errorTitle]
      )
    @unknown default:
      throw NSError(
        domain: "com.vivyshot.video",
        code: -59,
        userInfo: [NSLocalizedDescriptionKey: errorTitle]
      )
    }
  }

  private func isAccessibilityTrusted(promptIfNeeded: Bool) -> Bool {
    if promptIfNeeded {
      let options = ["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary
      return AXIsProcessTrustedWithOptions(options)
    }
    return AXIsProcessTrusted()
  }

  private var effectiveCaptureMicrophoneEnabled: Bool {
    videoMicrophoneFeatureEnabled && settings.videoRecordMicrophone
  }

  private var effectiveShowWebcamEnabled: Bool {
    videoWebcamFeatureEnabled && settings.videoShowWebcam
  }

  private var effectiveHighlightKeystrokesEnabled: Bool {
    videoKeystrokesFeatureEnabled && settings.videoHighlightKeystrokes
  }
}

struct VideoRecordingConfig {
  let codec: VideoCodecOption
  let frameRate: Int
  let highlightMouseClicks: Bool
  let captureSystemAudio: Bool
  let captureMicrophone: Bool
  let capturedOverlayWindowIDs: [CGWindowID]
}

struct VideoCaptureOverlayState {
  var webcamFrame: CGRect
  var keystrokeFrame: CGRect

  @MainActor
  static func from(settings: AppSettings) -> VideoCaptureOverlayState {
    VideoCaptureOverlayState(
      webcamFrame: settings.videoWebcamOverlayNormalizedFrame,
      keystrokeFrame: settings.videoKeystrokeOverlayNormalizedFrame
    )
  }

  static func normalizedFrame(_ frame: CGRect) -> CGRect {
    let source = frame.isNull || frame.isEmpty ? CGRect(x: 0, y: 0, width: 0.2, height: 0.2) : frame.standardized
    let width = max(0.04, min(1, source.width))
    let height = max(0.04, min(1, source.height))
    let x = max(0, min(1 - width, source.minX))
    let y = max(0, min(1 - height, source.minY))
    return CGRect(x: x, y: y, width: width, height: height)
  }
}

struct VideoOverlayPlacementChange: Equatable {
  let timestampSeconds: Double
  let normalizedFrame: CGRect
}

struct PostRecordingProject {
  let inputURL: URL
  let webcamURL: URL?
  let webcamTimeOffsetSeconds: Double
  let rustProject: RustVideoProjectSession
  let details: PostRecordingDetails
  let durationSeconds: Double
  let videoSize: CGSize?
  let overlaysBurnedIn: Bool

  var hasNativeCompositedOverlays: Bool {
    !overlaysBurnedIn && webcamURL != nil
  }
}

struct RecordedKeystrokeEvent {
  let timestampNS: UInt64
  let displayToken: String
}

struct RecordedMouseClickEvent {
  let timestampNS: UInt64
  let normalizedX: CGFloat
  let normalizedY: CGFloat
  let button: UInt32
}

struct RecordingInputResult {
  let keyEvents: [RecordedKeystrokeEvent]
  let clickEvents: [RecordedMouseClickEvent]
}

final class RecordingInputMonitor {
  private let captureRectInScreen: CGRect
  private let captureKeystrokes: Bool
  private let captureMouseClicks: Bool
  private let onKeyEvent: ((RecordedKeystrokeEvent) -> Void)?
  private let stateLock = NSLock()

  private var startUptime: TimeInterval = 0
  private var globalKeyMonitorToken: Any?
  private var localKeyMonitorToken: Any?
  private var globalClickMonitorToken: Any?
  private var localClickMonitorToken: Any?
  private var keyEvents: [RecordedKeystrokeEvent] = []
  private var clickEvents: [RecordedMouseClickEvent] = []
  private var lastKeyEventSignature: (timestampNS: UInt64, token: String)?
  private var lastClickEventSignature: (timestampNS: UInt64, button: UInt32, x: CGFloat, y: CGFloat)?

  init(
    captureRectInScreen: CGRect,
    captureKeystrokes: Bool,
    captureMouseClicks: Bool,
    onKeyEvent: ((RecordedKeystrokeEvent) -> Void)? = nil
  ) {
    self.captureRectInScreen = captureRectInScreen.standardized
    self.captureKeystrokes = captureKeystrokes
    self.captureMouseClicks = captureMouseClicks
    self.onKeyEvent = onKeyEvent
  }

  deinit {
    stopObservers()
  }

  func start() {
    startUptime = ProcessInfo.processInfo.systemUptime

    if captureKeystrokes {
      globalKeyMonitorToken = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
        self?.handleKeyDown(event)
      }
      localKeyMonitorToken = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        self?.handleKeyDown(event)
        return event
      }
    }

    if captureMouseClicks {
      let clickMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
      globalClickMonitorToken = NSEvent.addGlobalMonitorForEvents(matching: clickMask) { [weak self] event in
        self?.handleMouseDown(event)
      }
      localClickMonitorToken = NSEvent.addLocalMonitorForEvents(matching: clickMask) { [weak self] event in
        self?.handleMouseDown(event)
        return event
      }
    }
  }

  func stop() -> RecordingInputResult {
    stopObservers()
    stateLock.lock()
    defer { stateLock.unlock() }
    return RecordingInputResult(
      keyEvents: keyEvents,
      clickEvents: clickEvents
    )
  }

  private func stopObservers() {
    if let globalKeyMonitorToken {
      NSEvent.removeMonitor(globalKeyMonitorToken)
      self.globalKeyMonitorToken = nil
    }

    if let localKeyMonitorToken {
      NSEvent.removeMonitor(localKeyMonitorToken)
      self.localKeyMonitorToken = nil
    }

    if let globalClickMonitorToken {
      NSEvent.removeMonitor(globalClickMonitorToken)
      self.globalClickMonitorToken = nil
    }

    if let localClickMonitorToken {
      NSEvent.removeMonitor(localClickMonitorToken)
      self.localClickMonitorToken = nil
    }
  }

  private func handleKeyDown(_ event: NSEvent) {
    let token = displayToken(for: event)
    guard !token.isEmpty else {
      return
    }
    let timestampNS = elapsedTimestampNS(for: event)
    stateLock.lock()
    defer { stateLock.unlock() }
    if let last = lastKeyEventSignature,
       RustCoreBridge.isDuplicateKeyEventPortable(
         lastTimestampNS: last.timestampNS,
         lastToken: last.token,
         timestampNS: timestampNS,
         token: token
       )
    {
      return
    }
    lastKeyEventSignature = (timestampNS: timestampNS, token: token)

    let event = RecordedKeystrokeEvent(
      timestampNS: timestampNS,
      displayToken: token
    )
    keyEvents.append(event)
    onKeyEvent?(event)
  }

  private func handleMouseDown(_ event: NSEvent) {
    guard captureRectInScreen.width > 0, captureRectInScreen.height > 0 else {
      return
    }

    let point = NSEvent.mouseLocation
    guard captureRectInScreen.contains(point) else {
      return
    }

    let nx = (point.x - captureRectInScreen.minX) / captureRectInScreen.width
    let ny = (point.y - captureRectInScreen.minY) / captureRectInScreen.height
    guard let normalized = RustCoreBridge.normalizeClickPointPortable(x: nx, y: ny) else {
      return
    }
    let normalizedX = normalized.x
    let normalizedY = normalized.y

    let button: UInt32
    switch event.type {
    case .leftMouseDown:
      button = 0
    case .rightMouseDown:
      button = 1
    default:
      button = 2
    }
    let timestampNS = elapsedTimestampNS(for: event)
    stateLock.lock()
    defer { stateLock.unlock() }
    if let last = lastClickEventSignature,
       RustCoreBridge.isDuplicateClickEventPortable(
         lastTimestampNS: last.timestampNS,
         lastButton: last.button,
         lastX: last.x,
         lastY: last.y,
         timestampNS: timestampNS,
         button: button,
         x: normalizedX,
         y: normalizedY
       )
    {
      return
    }
    lastClickEventSignature = (
      timestampNS: timestampNS,
      button: button,
      x: normalizedX,
      y: normalizedY
    )

    clickEvents.append(
      RecordedMouseClickEvent(
        timestampNS: timestampNS,
        normalizedX: normalizedX,
        normalizedY: normalizedY,
        button: button
      )
    )
  }

  private func elapsedTimestampNS(for event: NSEvent) -> UInt64 {
    let elapsed = max(0, event.timestamp - startUptime)
    return UInt64((elapsed * 1_000_000_000).rounded())
  }

  private func displayToken(for event: NSEvent) -> String {
    let modifiers = keyModifierMask(for: event.modifierFlags)
    return RustCoreBridge.normalizeKeyTokenPortable(
      keyCode: event.keyCode,
      modifiers: modifiers,
      characters: event.charactersIgnoringModifiers
    ) ?? ""
  }

  private func keyModifierMask(for flags: NSEvent.ModifierFlags) -> UInt32 {
    var raw: UInt32 = 0
    if flags.contains(.command) {
      raw |= 1 << 0
    }
    if flags.contains(.shift) {
      raw |= 1 << 1
    }
    if flags.contains(.option) {
      raw |= 1 << 2
    }
    if flags.contains(.control) {
      raw |= 1 << 3
    }
    return raw
  }
}

final class CaptureSessionRunner: @unchecked Sendable {
  private let session: AVCaptureSession
  private let queue: DispatchQueue

  init(session: AVCaptureSession, label: String) {
    self.session = session
    queue = DispatchQueue(label: label, qos: .userInitiated)
  }

  func start() async {
    await withCheckedContinuation { continuation in
      queue.async { [self] in
        if !session.isRunning {
          session.startRunning()
        }
        continuation.resume()
      }
    }
  }

  func startDetached() {
    queue.async { [self] in
      if !session.isRunning {
        session.startRunning()
      }
    }
  }

  func stop() async {
    await withCheckedContinuation { continuation in
      queue.async { [self] in
        if session.isRunning {
          session.stopRunning()
        }
        continuation.resume()
      }
    }
  }

  func stopDetached() {
    queue.async { [self] in
      if session.isRunning {
        session.stopRunning()
      }
    }
  }
}

@MainActor
final class WebcamRecorder: NSObject, AVCaptureFileOutputRecordingDelegate {
  private let outputURL: URL
  private let preferredDeviceID: String
  private let session = AVCaptureSession()
  private lazy var sessionRunner = CaptureSessionRunner(
    session: session,
    label: "com.vivyshot.webcam-recorder.session"
  )
  private let movieOutput = AVCaptureMovieFileOutput()
  private var stopContinuation: CheckedContinuation<URL, Error>?
  private var stopTimeoutTask: Task<Void, Never>?
  private var recordingDidStart = false
  private var lastRecordingError: Error?
  private(set) var recordingStartUptime: TimeInterval?

  init(outputURL: URL, preferredDeviceID: String) throws {
    self.outputURL = outputURL
    self.preferredDeviceID = preferredDeviceID
    super.init()
    try configureSession()
  }

  func start() async throws {
    lastRecordingError = nil
    recordingDidStart = false

    if FileManager.default.fileExists(atPath: outputURL.path) {
      try FileManager.default.removeItem(at: outputURL)
    }

    await sessionRunner.start()

    if !movieOutput.isRecording {
      movieOutput.startRecording(to: outputURL, recordingDelegate: self)
    }

    try await waitForRecordingToStart()
  }

  func stop() async throws -> URL {
    guard movieOutput.isRecording else {
      await sessionRunner.stop()
      if let lastRecordingError {
        throw lastRecordingError
      }
      try await waitForValidOutputFile(outputURL)
      return outputURL
    }

    return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
      stopContinuation = continuation
      scheduleStopTimeout()
      movieOutput.stopRecording()
    }
  }

  func makePreviewLayer() -> AVCaptureVideoPreviewLayer {
    let layer = AVCaptureVideoPreviewLayer(session: session)
    layer.videoGravity = .resizeAspectFill
    return layer
  }

  func cancel() {
    if movieOutput.isRecording {
      movieOutput.stopRecording()
    }
    finishStopContinuation(.failure(CancellationError()))
  }

  nonisolated func fileOutput(
    _ output: AVCaptureFileOutput,
    didStartRecordingTo fileURL: URL,
    from connections: [AVCaptureConnection]
  ) {
    Task { @MainActor [weak self] in
      self?.recordingDidStart = true
      self?.recordingStartUptime = ProcessInfo.processInfo.systemUptime
      self?.lastRecordingError = nil
    }
  }

  nonisolated func fileOutput(
    _ output: AVCaptureFileOutput,
    didFinishRecordingTo outputFileURL: URL,
    from connections: [AVCaptureConnection],
    error: Error?
  ) {
    Task { @MainActor [weak self] in
      guard let self else {
        return
      }

      self.sessionRunner.stopDetached()
      self.recordingDidStart = false
      self.stopTimeoutTask?.cancel()
      self.stopTimeoutTask = nil

      guard let continuation = self.stopContinuation else {
        if let error {
          self.lastRecordingError = error
        } else {
          self.lastRecordingError = nil
        }
        return
      }
      self.stopContinuation = nil

      if let error, !self.isSuccessfullyFinishedRecordingError(error) {
        self.lastRecordingError = error
        continuation.resume(throwing: error)
      } else {
        do {
          try await self.waitForValidOutputFile(outputFileURL)
          self.lastRecordingError = nil
          continuation.resume(returning: outputFileURL)
        } catch {
          self.lastRecordingError = error
          continuation.resume(throwing: error)
        }
      }
    }
  }

  private func scheduleStopTimeout(timeoutSeconds: Double = 4.0) {
    stopTimeoutTask?.cancel()
    stopTimeoutTask = Task { @MainActor [weak self] in
      let nanoseconds = UInt64(max(0.25, timeoutSeconds) * 1_000_000_000)
      try? await Task.sleep(nanoseconds: nanoseconds)
      guard !Task.isCancelled else {
        return
      }
      self?.finishStopContinuation(
        .failure(
          NSError(
            domain: "com.vivyshot.video",
            code: -78,
            userInfo: [NSLocalizedDescriptionKey: "Webcam recording did not finish in time."]
          )
        )
      )
    }
  }

  private func finishStopContinuation(_ result: Result<URL, Error>) {
    stopTimeoutTask?.cancel()
    stopTimeoutTask = nil
    sessionRunner.stopDetached()
    recordingDidStart = false
    guard let continuation = stopContinuation else {
      return
    }
    stopContinuation = nil
    switch result {
    case .success(let url):
      continuation.resume(returning: url)
    case .failure(let error):
      continuation.resume(throwing: error)
    }
  }

  private func waitForRecordingToStart(timeoutSeconds: Double = 5.0) async throws {
    let deadline = Date().addingTimeInterval(timeoutSeconds)

    while !recordingDidStart {
      if let lastRecordingError {
        throw lastRecordingError
      }
      if Date() >= deadline {
        throw NSError(
          domain: "com.vivyshot.video",
          code: -73,
          userInfo: [NSLocalizedDescriptionKey: "Webcam recording failed to start."]
        )
      }
      try await Task.sleep(nanoseconds: 50_000_000)
    }
  }

  private func validateOutputFile(_ url: URL) throws {
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw NSError(
        domain: "com.vivyshot.video",
        code: -74,
        userInfo: [NSLocalizedDescriptionKey: "Webcam recording file is missing."]
      )
    }

    let values = try url.resourceValues(forKeys: [.fileSizeKey])
    let fileSize = values.fileSize ?? 0
    if fileSize <= 0 {
      throw NSError(
        domain: "com.vivyshot.video",
        code: -75,
        userInfo: [NSLocalizedDescriptionKey: "Webcam recording is empty."]
      )
    }
  }

  private func waitForValidOutputFile(_ url: URL, timeoutSeconds: Double = 1.5) async throws {
    let deadline = Date().addingTimeInterval(timeoutSeconds)
    var latestError: Error?

    repeat {
      do {
        try validateOutputFile(url)
        return
      } catch {
        latestError = error
        try? await Task.sleep(nanoseconds: 50_000_000)
      }
    } while Date() < deadline

    throw latestError ?? NSError(
      domain: "com.vivyshot.video",
      code: -76,
      userInfo: [NSLocalizedDescriptionKey: "Webcam recording file is unavailable."]
    )
  }

  private func isSuccessfullyFinishedRecordingError(_ error: Error) -> Bool {
    let nsError = error as NSError
    return (nsError.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool) == true
  }

  private func configureSession() throws {
    session.beginConfiguration()
    session.sessionPreset = .high

    var deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
    if #available(macOS 14.0, *) {
      deviceTypes.append(.external)
    } else {
      deviceTypes.append(.externalUnknown)
    }
    if #available(macOS 15.0, *) {
      deviceTypes.append(.continuityCamera)
    }

    let allVideoDevices = AVCaptureDevice.DiscoverySession(
      deviceTypes: deviceTypes,
      mediaType: .video,
      position: .unspecified
    ).devices

    let selectedDevice = allVideoDevices.first(where: { $0.uniqueID == preferredDeviceID })
    guard let device = selectedDevice ?? AVCaptureDevice.default(for: .video) ?? allVideoDevices.first else {
      session.commitConfiguration()
      throw NSError(
        domain: "com.vivyshot.video",
        code: -70,
        userInfo: [NSLocalizedDescriptionKey: "No camera device is available."]
      )
    }

    let input = try AVCaptureDeviceInput(device: device)
    guard session.canAddInput(input) else {
      session.commitConfiguration()
      throw NSError(
        domain: "com.vivyshot.video",
        code: -71,
        userInfo: [NSLocalizedDescriptionKey: "Unable to add webcam input."]
      )
    }
    session.addInput(input)

    guard session.canAddOutput(movieOutput) else {
      session.commitConfiguration()
      throw NSError(
        domain: "com.vivyshot.video",
        code: -72,
        userInfo: [NSLocalizedDescriptionKey: "Unable to add webcam output."]
      )
    }
    session.addOutput(movieOutput)

    movieOutput.movieFragmentInterval = .invalid
    session.commitConfiguration()
  }
}

@MainActor
private final class RecordingOverlayController: NSWindowController {
  private let captureRectInScreen: CGRect
  private let webcamOverlayView: RecordingWebcamOverlayView?
  private let keystrokeOverlayView: RecordingKeystrokeOverlayView?

  init(
    captureRectInScreen: CGRect,
    webcamPreviewLayer: AVCaptureVideoPreviewLayer?,
    webcamFrame: CGRect,
    webcamShape: VideoWebcamOverlayShapeOption,
    webcamAspectRatio: VideoWebcamOverlayAspectRatioOption,
    showKeystrokeOverlay: Bool,
    keystrokeFrame: CGRect,
    keystrokeStyle: VideoKeystrokeOverlayStyleOption,
    keystrokeSize: VideoKeystrokeOverlaySizeOption,
    onWebcamFrameChanged: @escaping (CGRect) -> Void,
    onKeystrokeFrameChanged: @escaping (CGRect) -> Void
  ) {
    self.captureRectInScreen = captureRectInScreen.standardized

    let panel = NSPanel(
      contentRect: captureRectInScreen.standardized,
      styleMask: [.nonactivatingPanel, .borderless],
      backing: .buffered,
      defer: false
    )
    panel.isReleasedWhenClosed = false
    panel.level = .screenSaver
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    panel.hidesOnDeactivate = false
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.ignoresMouseEvents = false

    let container = RecordingOverlayContainerView(frame: CGRect(origin: .zero, size: captureRectInScreen.size))
    container.wantsLayer = true
    container.layer?.backgroundColor = NSColor.clear.cgColor
    panel.contentView = container

    if let webcamPreviewLayer {
      let view = RecordingWebcamOverlayView(
        normalizedFrame: VideoCaptureOverlayState.normalizedFrame(webcamFrame),
        previewLayer: webcamPreviewLayer,
        shape: webcamShape,
        aspectRatio: webcamAspectRatio
      )
      view.frame = Self.denormalizedWebcamFrame(
        view.normalizedFrame,
        aspectRatio: webcamAspectRatio,
        in: container.bounds
      )
      view.onNormalizedFrameChanged = onWebcamFrameChanged
      container.addSubview(view)
      webcamOverlayView = view
    } else {
      webcamOverlayView = nil
    }

    if showKeystrokeOverlay {
      let view = RecordingKeystrokeOverlayView(
        normalizedFrame: VideoCaptureOverlayState.normalizedFrame(keystrokeFrame),
        style: keystrokeStyle,
        size: keystrokeSize
      )
      view.frame = Self.denormalizedFrame(view.normalizedFrame, in: container.bounds)
      view.onNormalizedFrameChanged = onKeystrokeFrameChanged
      container.addSubview(view)
      keystrokeOverlayView = view
    } else {
      keystrokeOverlayView = nil
    }

    super.init(window: panel)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  func show() {
    guard let panel = window as? NSPanel else {
      return
    }
    panel.setFrame(captureRectInScreen, display: true)
    panel.orderFrontRegardless()
  }

  var capturedWindowID: CGWindowID? {
    guard let window else {
      return nil
    }
    return CGWindowID(window.windowNumber)
  }

  func showKeystroke(_ token: String) {
    keystrokeOverlayView?.showToken(token)
  }

  private static func denormalizedFrame(_ normalized: CGRect, in bounds: CGRect) -> CGRect {
    CGRect(
      x: bounds.minX + normalized.minX * bounds.width,
      y: bounds.minY + normalized.minY * bounds.height,
      width: normalized.width * bounds.width,
      height: normalized.height * bounds.height
    ).integral
  }

  private static func denormalizedWebcamFrame(
    _ normalized: CGRect,
    aspectRatio: VideoWebcamOverlayAspectRatioOption,
    in bounds: CGRect
  ) -> CGRect {
    aspectRatio.constrainedFrame(
      denormalizedFrame(normalized, in: bounds),
      in: bounds,
      minimumSize: CGSize(width: 84, height: 84)
    )
  }
}

@MainActor
private final class RecordingOverlayContainerView: NSView {
  override var isOpaque: Bool { false }
}

@MainActor
private class RecordingDraggableOverlayView: NSView {
  var normalizedFrame: CGRect
  var onNormalizedFrameChanged: ((CGRect) -> Void)?

  private var dragStartPoint: CGPoint?
  private var dragStartFrame: CGRect = .zero
  private var activeInteraction: OverlayFrameInteraction = .move

  var allowsResizing: Bool { false }
  var minimumFrameSize: CGSize { CGSize(width: 80, height: 80) }
  var fixedAspectRatio: VideoWebcamOverlayAspectRatioOption? { nil }

  private enum OverlayFrameInteraction {
    case move
    case resize(ResizeCorner)
  }

  init(normalizedFrame: CGRect) {
    self.normalizedFrame = VideoCaptureOverlayState.normalizedFrame(normalizedFrame)
    super.init(frame: .zero)
    wantsLayer = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  override func resetCursorRects() {
    addCursorRect(bounds, cursor: .openHand)
  }

  override func mouseDown(with event: NSEvent) {
    guard let superview else {
      return
    }
    dragStartPoint = superview.convert(event.locationInWindow, from: nil)
    dragStartFrame = frame
    let localPoint = convert(event.locationInWindow, from: nil)
    activeInteraction = resizeCorner(at: localPoint).map(OverlayFrameInteraction.resize) ?? .move
    NSCursor.closedHand.set()
  }

  override func mouseDragged(with event: NSEvent) {
    guard let superview, let dragStartPoint else {
      return
    }

    let point = superview.convert(event.locationInWindow, from: nil)
    let dx = point.x - dragStartPoint.x
    let dy = point.y - dragStartPoint.y
    let proposed: CGRect
    switch activeInteraction {
    case .move:
      proposed = dragStartFrame.offsetBy(dx: dx, dy: dy)
    case .resize(let corner):
      proposed = resizedFrame(from: dragStartFrame, corner: corner, delta: CGSize(width: dx, height: dy))
    }
    frame = clampedFrame(proposed, in: superview.bounds).integral
    normalizedFrame = Self.normalizedFrame(for: frame, in: superview.bounds)
    onNormalizedFrameChanged?(normalizedFrame)
    needsDisplay = true
  }

  override func mouseUp(with event: NSEvent) {
    dragStartPoint = nil
    activeInteraction = .move
    NSCursor.openHand.set()
    guard let superview else {
      return
    }
    normalizedFrame = Self.normalizedFrame(for: frame, in: superview.bounds)
    onNormalizedFrameChanged?(normalizedFrame)
  }

  private func resizeCorner(at point: CGPoint) -> ResizeCorner? {
    guard allowsResizing else {
      return nil
    }
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

  private func clampedFrame(_ proposed: CGRect, in superviewBounds: CGRect) -> CGRect {
    let bounds = superviewBounds.insetBy(dx: 8, dy: 8)
    let minWidth = min(minimumFrameSize.width, bounds.width)
    let minHeight = min(minimumFrameSize.height, bounds.height)
    if let fixedAspectRatio {
      return fixedAspectRatio.constrainedFrame(
        proposed,
        in: bounds,
        minimumSize: CGSize(width: minWidth, height: minHeight)
      )
    }

    let width = max(minWidth, min(proposed.width, bounds.width))
    let height = max(minHeight, min(proposed.height, bounds.height))
    let x = min(max(bounds.minX, proposed.minX), bounds.maxX - width)
    let y = min(max(bounds.minY, proposed.minY), bounds.maxY - height)
    return CGRect(x: x, y: y, width: width, height: height)
  }

  private static func normalizedFrame(for frame: CGRect, in bounds: CGRect) -> CGRect {
    guard bounds.width > 0, bounds.height > 0 else {
      return .zero
    }
    return VideoCaptureOverlayState.normalizedFrame(
      CGRect(
        x: (frame.minX - bounds.minX) / bounds.width,
        y: (frame.minY - bounds.minY) / bounds.height,
        width: frame.width / bounds.width,
        height: frame.height / bounds.height
      )
    )
  }
}

@MainActor
private final class RecordingWebcamOverlayView: RecordingDraggableOverlayView {
  private let previewLayer: AVCaptureVideoPreviewLayer
  private let shape: VideoWebcamOverlayShapeOption
  private let aspectRatio: VideoWebcamOverlayAspectRatioOption
  private let resizeGripLayer = CAShapeLayer()

  override var allowsResizing: Bool { true }
  override var minimumFrameSize: CGSize { CGSize(width: 84, height: 84) }
  override var fixedAspectRatio: VideoWebcamOverlayAspectRatioOption? { aspectRatio }

  init(
    normalizedFrame: CGRect,
    previewLayer: AVCaptureVideoPreviewLayer,
    shape: VideoWebcamOverlayShapeOption,
    aspectRatio: VideoWebcamOverlayAspectRatioOption
  ) {
    self.previewLayer = previewLayer
    self.shape = shape
    self.aspectRatio = shape == .circle ? .square : aspectRatio
    super.init(normalizedFrame: normalizedFrame)
    layer?.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
    layer?.borderColor = NSColor.white.withAlphaComponent(0.7).cgColor
    layer?.borderWidth = 1
    layer?.masksToBounds = true
    layer?.addSublayer(previewLayer)
    resizeGripLayer.fillColor = nil
    resizeGripLayer.strokeColor = NSColor.white.withAlphaComponent(0.50).cgColor
    resizeGripLayer.lineWidth = 1.2
    resizeGripLayer.lineCap = .round
    layer?.addSublayer(resizeGripLayer)
  }

  override func layout() {
    super.layout()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    previewLayer.frame = bounds
    layer?.cornerRadius = shape == .circle ? min(bounds.width, bounds.height) * 0.5 : 14
    resizeGripLayer.frame = bounds
    resizeGripLayer.path = Self.resizeGripPath(in: bounds)
    CATransaction.commit()
  }

  private static func resizeGripPath(in bounds: CGRect) -> CGPath {
    let grip = CGRect(x: bounds.maxX - 20, y: bounds.maxY - 18, width: 12, height: 12)
    let path = CGMutablePath()
    for offset in stride(from: CGFloat(4), through: CGFloat(12), by: CGFloat(4)) {
      path.move(to: CGPoint(x: grip.maxX - offset, y: grip.maxY))
      path.addLine(to: CGPoint(x: grip.maxX, y: grip.maxY - offset))
    }
    return path
  }
}

@MainActor
private final class RecordingKeystrokeOverlayView: RecordingDraggableOverlayView {
  private let style: VideoKeystrokeOverlayStyleOption
  private let size: VideoKeystrokeOverlaySizeOption
  private let hostingView: NSHostingView<KeystrokeOverlayGlassCapsule>
  private var currentToken = "⌘K"
  private var restoreTimer: Timer?

  override var allowsResizing: Bool { true }
  override var minimumFrameSize: CGSize { CGSize(width: 112, height: 42) }

  init(
    normalizedFrame: CGRect,
    style: VideoKeystrokeOverlayStyleOption,
    size: VideoKeystrokeOverlaySizeOption
  ) {
    self.style = style
    self.size = size
    hostingView = NSHostingView(
      rootView: KeystrokeOverlayGlassCapsule(
        text: "⌘K",
        style: style,
        size: size,
        showsResizeGrip: true
      )
    )
    super.init(normalizedFrame: normalizedFrame)
    layer?.masksToBounds = false
    hostingView.translatesAutoresizingMaskIntoConstraints = true
    hostingView.wantsLayer = true
    hostingView.layer?.backgroundColor = NSColor.clear.cgColor
    addSubview(hostingView)
  }

  func showToken(_ token: String) {
    currentToken = token.isEmpty ? "Key" : token
    refreshHostedView()
    restoreTimer?.invalidate()
    restoreTimer = Timer.scheduledTimer(withTimeInterval: 1.35, repeats: false) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.currentToken = "⌘K"
        self?.refreshHostedView()
      }
    }
  }

  override func layout() {
    super.layout()
    hostingView.frame = bounds
  }

  private func refreshHostedView() {
    hostingView.rootView = KeystrokeOverlayGlassCapsule(
      text: currentToken,
      style: style,
      size: size,
      showsResizeGrip: true
    )
  }
}

@MainActor
private enum PostRecordingProjectExporter {
  private static let maxGIFDurationSeconds: Double = 120

  static func exportCompositedVideo(
    project: PostRecordingProject,
    options: PostRecordingExportOptions,
    exportState: PostRecordingExportState,
    container: PostRecordingVideoSaveContainer?,
    outputURL: URL
  ) async throws {
    let visualURL = temporaryExportURL(extension: "mov")
    defer { try? FileManager.default.removeItem(at: visualURL) }

    try await renderCompositedVisualAsset(
      project: project,
      options: options,
      exportState: exportState,
      outputURL: visualURL
    )
    try await mergeRenderedVideoWithSourceAudio(
      renderedVideoURL: visualURL,
      sourceURL: project.inputURL,
      options: options,
      exportState: exportState,
      container: container,
      outputURL: outputURL
    )
  }

  static func exportGIF(
    project: PostRecordingProject,
    exportState: PostRecordingExportState,
    outputURL: URL
  ) async throws {
    let durationSeconds = exportState.trimmedDurationSeconds
    guard durationSeconds > 0 else {
      throw exportError("GIF export failed because the recording duration is unavailable.")
    }
    guard durationSeconds <= maxGIFDurationSeconds else {
      throw exportError("GIF export supports recordings up to 120 seconds.")
    }
    guard let plan = RustCoreBridge.shared.buildGIFExportPlan(
      startMS: exportState.trimStartMS,
      endMS: exportState.trimEndMS,
      preferredFPS: 12,
      maxDimension: 960
    ) else {
      throw exportError("Unable to build GIF export plan.")
    }

    try removeExistingFile(at: outputURL)

    let renderSize = gifRenderSize(videoSize: try await resolvedVideoSize(project: project), maxDimension: plan.maxDimension)
    let screenGenerator = makeImageGenerator(url: project.inputURL)
    let webcamGenerator = project.overlaysBurnedIn ? nil : project.webcamURL.map(makeImageGenerator(url:))
    let destinationProperties: [CFString: Any] = [
      kCGImagePropertyGIFDictionary: [
        kCGImagePropertyGIFLoopCount: 0
      ]
    ]
    let frameProperties: [CFString: Any] = [
      kCGImagePropertyGIFDictionary: [
        kCGImagePropertyGIFDelayTime: Double(plan.frameDelayMS) / 1000.0
      ]
    ]
    guard let destination = CGImageDestinationCreateWithURL(
      outputURL as CFURL,
      UTType.gif.identifier as CFString,
      plan.frameCount,
      nil
    ) else {
      throw exportError("Unable to create GIF writer.")
    }
    CGImageDestinationSetProperties(destination, destinationProperties as CFDictionary)

    for index in 0..<plan.frameCount {
      guard let timeMS = RustCoreBridge.shared.gifFrameTimeMS(plan: plan, index: index) else {
        throw exportError("Unable to resolve GIF frame timing.")
      }
      let seconds = Double(timeMS) / 1000.0
      let frame = try await makeCompositedFrameImage(
        time: CMTime(seconds: seconds, preferredTimescale: 600),
        seconds: seconds,
        renderSize: renderSize,
        screenGenerator: screenGenerator,
        webcamGenerator: webcamGenerator,
        project: project
      )
      CGImageDestinationAddImage(destination, frame, frameProperties as CFDictionary)
    }

    guard CGImageDestinationFinalize(destination) else {
      throw exportError("Unable to finalize GIF.")
    }
  }

  private static func renderCompositedVisualAsset(
    project: PostRecordingProject,
    options: PostRecordingExportOptions,
    exportState: PostRecordingExportState,
    outputURL: URL
  ) async throws {
    try removeExistingFile(at: outputURL)

    let renderSize = evenSize(try await resolvedVideoSize(project: project), scale: options.scale.factor)
    let frameRate = max(1, options.frameRate.rawValue)
    let frameCount = max(1, Int(ceil(exportState.trimmedDurationSeconds * Double(frameRate))))
    let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
    let bitrate = max(2_000_000, Int(renderSize.width * renderSize.height * CGFloat(frameRate) * bitrateMultiplier(options)))
    let input = AVAssetWriterInput(
      mediaType: .video,
      outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: Int(renderSize.width),
        AVVideoHeightKey: Int(renderSize.height),
        AVVideoCompressionPropertiesKey: [
          AVVideoAverageBitRateKey: bitrate,
          AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
        ]
      ]
    )
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: input,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: Int(renderSize.width),
        kCVPixelBufferHeightKey as String: Int(renderSize.height),
        kCVPixelBufferCGImageCompatibilityKey as String: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
      ]
    )
    guard writer.canAdd(input) else {
      throw exportError("Unable to configure video writer.")
    }
    writer.add(input)
    guard writer.startWriting() else {
      throw writer.error ?? exportError("Unable to start video writer.")
    }
    writer.startSession(atSourceTime: .zero)

    let screenGenerator = makeImageGenerator(url: project.inputURL)
    let webcamGenerator = project.overlaysBurnedIn ? nil : project.webcamURL.map(makeImageGenerator(url:))
    let frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate))
    screenGenerator.requestedTimeToleranceBefore = frameDuration
    screenGenerator.requestedTimeToleranceAfter = frameDuration
    webcamGenerator?.requestedTimeToleranceBefore = frameDuration
    webcamGenerator?.requestedTimeToleranceAfter = frameDuration

    guard let pixelBufferPool = adaptor.pixelBufferPool else {
      throw exportError("Unable to allocate video frame buffers.")
    }

    for frameIndex in 0..<frameCount {
      while !input.isReadyForMoreMediaData {
        try await Task.sleep(nanoseconds: 8_000_000)
      }

      var maybeBuffer: CVPixelBuffer?
      let status = CVPixelBufferPoolCreatePixelBuffer(nil, pixelBufferPool, &maybeBuffer)
      guard status == kCVReturnSuccess, let pixelBuffer = maybeBuffer else {
        throw exportError("Unable to allocate video frame.")
      }

      let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(frameIndex))
      let seconds = Double(exportState.trimStartMS) / 1000.0 + CMTimeGetSeconds(presentationTime)
      try await renderCompositedFrame(
        into: pixelBuffer,
        time: CMTime(seconds: seconds, preferredTimescale: 600),
        seconds: seconds,
        renderSize: renderSize,
        screenGenerator: screenGenerator,
        webcamGenerator: webcamGenerator,
        project: project
      )
      guard adaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
        throw writer.error ?? exportError("Unable to append video frame.")
      }
    }

    input.markAsFinished()
    nonisolated(unsafe) let unsafeWriter = writer
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      unsafeWriter.finishWriting {
        continuation.resume()
      }
    }
    switch unsafeWriter.status {
    case .completed:
      break
    case .failed:
      throw unsafeWriter.error ?? exportError("Video writer failed.")
    case .cancelled:
      throw exportError("Video writer was cancelled.")
    default:
      throw unsafeWriter.error ?? exportError("Video writer did not complete.")
    }
  }

  private static func mergeRenderedVideoWithSourceAudio(
    renderedVideoURL: URL,
    sourceURL: URL,
    options: PostRecordingExportOptions,
    exportState: PostRecordingExportState,
    container: PostRecordingVideoSaveContainer?,
    outputURL: URL
  ) async throws {
    try removeExistingFile(at: outputURL)

    let renderedAsset = AVURLAsset(url: renderedVideoURL)
    let sourceAsset = AVURLAsset(url: sourceURL)
    let composition = AVMutableComposition()
    let duration = try await renderedAsset.load(.duration)

    guard let renderedVideoTrack = try await renderedAsset.loadTracks(withMediaType: .video).first,
          let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
          )
    else {
      throw exportError("Rendered video track is missing.")
    }
    try compositionVideoTrack.insertTimeRange(
      CMTimeRange(start: .zero, duration: duration),
      of: renderedVideoTrack,
      at: .zero
    )

    if exportState.includesAudio {
      let sourceDuration = try? await sourceAsset.load(.duration)
      let sourceDurationSeconds = max(0, CMTimeGetSeconds(sourceDuration ?? duration))
      let sourceAudioRange = exportState.trimRange(durationSeconds: sourceDurationSeconds)
      for audioTrack in try await sourceAsset.loadTracks(withMediaType: .audio) {
        guard let compositionAudioTrack = composition.addMutableTrack(
          withMediaType: .audio,
          preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
          continue
        }
        try? compositionAudioTrack.insertTimeRange(
          sourceAudioRange,
          of: audioTrack,
          at: .zero
        )
      }
    }

    let presetName = RustCoreBridge.shared.bestVideoExportPreset(
      codec: options.codec,
      quality: options.quality,
      compatiblePresets: AVAssetExportSession.exportPresets(compatibleWith: composition)
    )
    guard let exportSession = AVAssetExportSession(asset: composition, presetName: presetName) else {
      throw exportError("Unable to create final export session.")
    }
    let outputFileType = RustCoreBridge.shared.bestVideoSaveFileType(
      codec: options.codec,
      supportedTypes: exportSession.supportedFileTypes,
      preferredContainer: container
    )
    exportSession.outputURL = outputURL
    exportSession.outputFileType = outputFileType
    exportSession.shouldOptimizeForNetworkUse = true
    exportSession.timeRange = CMTimeRange(start: .zero, duration: duration)
    if let fileLengthLimit = RustCoreBridge.shared.estimatedVideoFileLengthLimit(
      durationSeconds: CMTimeGetSeconds(duration),
      options: options
    ) {
      exportSession.fileLengthLimit = fileLengthLimit
    }
    try await exportSession.vs_export()
  }

  private static func makeCompositedFrameImage(
    time: CMTime,
    seconds: Double,
    renderSize: CGSize,
    screenGenerator: AVAssetImageGenerator,
    webcamGenerator: AVAssetImageGenerator?,
    project: PostRecordingProject
  ) async throws -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let width = max(2, Int(renderSize.width.rounded()))
    let height = max(2, Int(renderSize.height.rounded()))
    let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
    guard let context = CGContext(
      data: nil,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: width * 4,
      space: colorSpace,
      bitmapInfo: bitmapInfo
    ) else {
      throw exportError("Unable to create GIF frame context.")
    }
    try await drawCompositedFrame(
      context: context,
      time: time,
      seconds: seconds,
      renderSize: CGSize(width: width, height: height),
      screenGenerator: screenGenerator,
      webcamGenerator: webcamGenerator,
      project: project
    )
    guard let image = context.makeImage() else {
      throw exportError("Unable to create GIF frame image.")
    }
    return image
  }

  private static func renderCompositedFrame(
    into pixelBuffer: CVPixelBuffer,
    time: CMTime,
    seconds: Double,
    renderSize: CGSize,
    screenGenerator: AVAssetImageGenerator,
    webcamGenerator: AVAssetImageGenerator?,
    project: PostRecordingProject
  ) async throws {
    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
    guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
      throw exportError("Unable to access video frame buffer.")
    }
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
    guard let context = CGContext(
      data: baseAddress,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: bytesPerRow,
      space: colorSpace,
      bitmapInfo: bitmapInfo
    ) else {
      throw exportError("Unable to create video frame context.")
    }
    try await drawCompositedFrame(
      context: context,
      time: time,
      seconds: seconds,
      renderSize: renderSize,
      screenGenerator: screenGenerator,
      webcamGenerator: webcamGenerator,
      project: project
    )
  }

  private static func drawCompositedFrame(
    context: CGContext,
    time: CMTime,
    seconds: Double,
    renderSize: CGSize,
    screenGenerator: AVAssetImageGenerator,
    webcamGenerator: AVAssetImageGenerator?,
    project: PostRecordingProject
  ) async throws {
    let renderRect = CGRect(origin: .zero, size: renderSize)
    context.setFillColor(NSColor.black.cgColor)
    context.fill(renderRect)
    context.interpolationQuality = .high

    nonisolated(unsafe) let unsafeScreenGenerator = screenGenerator
    let (screenImage, _) = try await unsafeScreenGenerator.image(at: time)
    context.draw(screenImage, in: renderRect)

    guard !project.overlaysBurnedIn else {
      return
    }

    let renderPlan = project.rustProject.renderPlan(
      timeSeconds: seconds,
      renderSize: renderSize,
      target: .export
    )
    var cachedWebcamImage: CGImage?
    let webcamTime = CMTime(
      seconds: max(0, seconds + project.webcamTimeOffsetSeconds),
      preferredTimescale: 600
    )

    for item in renderPlan?.items ?? [] {
      switch item.kind {
      case .webcam:
        guard let webcamGenerator else {
          continue
        }
        if cachedWebcamImage == nil {
          do {
            nonisolated(unsafe) let unsafeWebcamGenerator = webcamGenerator
            let (webcamImage, _) = try await unsafeWebcamGenerator.image(at: webcamTime)
            cachedWebcamImage = webcamImage
          } catch {
            // If the webcam file ends before the screen recording, keep the screen frame instead of failing the whole export.
            continue
          }
        }
        if let cachedWebcamImage {
          drawWebcamOverlay(
            image: cachedWebcamImage,
            context: context,
            renderSize: renderSize,
            item: item
          )
        }
      case .keystroke:
        drawKeystrokeOverlay(
          context: context,
          renderSize: renderSize,
          item: item
        )
      }
    }
  }

  private static func drawWebcamOverlay(
    image: CGImage,
    context: CGContext,
    renderSize: CGSize,
    item: RustVideoRenderItem
  ) {
    let rect = coreGraphicsRect(fromBottomLeft: item.rect)
    guard rect.width > 0, rect.height > 0 else {
      return
    }
    let shape = VideoWebcamOverlayShapeOption(rawValue: Int(item.webcamShapeCode)) ?? .roundedRect
    context.saveGState()
    switch shape {
    case .circle:
      context.addEllipse(in: rect)
    case .roundedRect:
      context.addPath(CGPath(roundedRect: rect, cornerWidth: min(rect.height * 0.18, 18), cornerHeight: min(rect.height * 0.18, 18), transform: nil))
    }
    context.clip()
    context.draw(image, in: aspectFillRect(imageSize: CGSize(width: image.width, height: image.height), targetRect: rect))
    context.restoreGState()

    context.saveGState()
    context.setStrokeColor(NSColor.white.withAlphaComponent(0.55).cgColor)
    context.setLineWidth(max(1, min(renderSize.width, renderSize.height) * 0.0016))
    switch shape {
    case .circle:
      context.strokeEllipse(in: rect.insetBy(dx: 1, dy: 1))
    case .roundedRect:
      context.addPath(CGPath(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerWidth: min(rect.height * 0.18, 18), cornerHeight: min(rect.height * 0.18, 18), transform: nil))
      context.strokePath()
    }
    context.restoreGState()
  }

  private static func drawKeystrokeOverlay(
    context: CGContext,
    renderSize: CGSize,
    item: RustVideoRenderItem
  ) {
    let text = item.text.isEmpty ? "⌘K" : item.text
    var rect = coreGraphicsRect(fromBottomLeft: item.rect).integral
    guard rect.width > 0, rect.height > 0 else {
      return
    }
    let fallbackLayout = RustCoreBridge.keyOverlayLabelLayoutPortable(renderSize: renderSize, charCount: text.count)
    if rect.width <= 4 || rect.height <= 4, let fallbackLayout {
      rect = CGRect(
        x: (renderSize.width - fallbackLayout.width) * 0.5,
        y: fallbackLayout.y,
        width: fallbackLayout.width,
        height: fallbackLayout.height
      ).integral
    }

    let style = VideoKeystrokeOverlayStyleOption(rawValue: Int(item.keystrokeStyleCode)) ?? .compact
    let size = VideoKeystrokeOverlaySizeOption(rawValue: Int(item.keystrokeSizeCode)) ?? .medium
    context.saveGState()
    let radius = min(rect.height * 0.5, 22)
    let backgroundPath = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    if style == .glass {
      context.saveGState()
      context.addPath(backgroundPath)
      context.clip()
      let colors = [
        NSColor.white.withAlphaComponent(0.30).cgColor,
        NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor,
        NSColor.black.withAlphaComponent(0.34).cgColor
      ] as CFArray
      let locations: [CGFloat] = [0, 0.45, 1]
      if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations) {
        context.drawLinearGradient(
          gradient,
          start: CGPoint(x: rect.midX, y: rect.maxY),
          end: CGPoint(x: rect.midX, y: rect.minY),
          options: []
        )
      } else {
        context.setFillColor(NSColor.black.withAlphaComponent(0.42).cgColor)
        context.fill(rect)
      }
      context.restoreGState()
    } else {
      context.setFillColor(NSColor.black.withAlphaComponent(0.78).cgColor)
      context.addPath(backgroundPath)
      context.fillPath()
    }

    context.setStrokeColor(NSColor.white.withAlphaComponent(style == .glass ? 0.42 : 0.16).cgColor)
    context.setLineWidth(1)
    context.addPath(CGPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.strokePath()

    let fontScale: CGFloat
    switch size {
    case .small:
      fontScale = 0.30
    case .medium:
      fontScale = 0.36
    case .large:
      fontScale = 0.42
    }
    let fontSize = max(13, min(rect.height * fontScale, rect.width / CGFloat(max(4, text.count)) * 1.8))
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold),
      .foregroundColor: NSColor.white
    ]
    let attributed = NSAttributedString(string: text, attributes: attributes)
    let textSize = attributed.size()
    let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphicsContext
    attributed.draw(
      at: CGPoint(
        x: rect.midX - textSize.width * 0.5,
        y: rect.midY - textSize.height * 0.5
      )
    )
    NSGraphicsContext.restoreGraphicsState()
    context.restoreGState()
  }

  private static func coreGraphicsRect(fromBottomLeft rect: CGRect) -> CGRect {
    CGRect(
      x: rect.minX,
      y: rect.minY,
      width: rect.width,
      height: rect.height
    )
  }

  private static func aspectFillRect(imageSize: CGSize, targetRect: CGRect) -> CGRect {
    guard imageSize.width > 0, imageSize.height > 0, targetRect.width > 0, targetRect.height > 0 else {
      return targetRect
    }
    let scale = max(targetRect.width / imageSize.width, targetRect.height / imageSize.height)
    let width = imageSize.width * scale
    let height = imageSize.height * scale
    return CGRect(
      x: targetRect.midX - width * 0.5,
      y: targetRect.midY - height * 0.5,
      width: width,
      height: height
    )
  }

  private static func makeImageGenerator(url: URL) -> AVAssetImageGenerator {
    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 30)
    generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 30)
    return generator
  }

  private static func resolvedVideoSize(project: PostRecordingProject) async throws -> CGSize {
    if let videoSize = project.videoSize, videoSize.width > 0, videoSize.height > 0 {
      return videoSize
    }
    let asset = AVURLAsset(url: project.inputURL)
    guard let track = try await asset.loadTracks(withMediaType: .video).first else {
      throw exportError("Recording video track is missing.")
    }
    let naturalSize = try await track.load(.naturalSize)
    let preferredTransform = try await track.load(.preferredTransform)
    let transformed = naturalSize.applying(preferredTransform)
    return CGSize(width: abs(transformed.width), height: abs(transformed.height))
  }

  private static func evenSize(_ size: CGSize, scale: CGFloat) -> CGSize {
    let width = max(2, Int((size.width * scale).rounded()))
    let height = max(2, Int((size.height * scale).rounded()))
    return CGSize(width: width + width % 2, height: height + height % 2)
  }

  private static func gifRenderSize(videoSize: CGSize, maxDimension: Int) -> CGSize {
    guard videoSize.width > 0, videoSize.height > 0 else {
      return CGSize(width: maxDimension, height: maxDimension)
    }
    let scale = min(1, CGFloat(maxDimension) / max(videoSize.width, videoSize.height))
    return evenSize(videoSize, scale: scale)
  }

  private static func bitrateMultiplier(_ options: PostRecordingExportOptions) -> CGFloat {
    var multiplier: CGFloat = options.quality == .high ? 0.22 : 0.14
    switch options.bitrate {
    case .standard:
      break
    case .high:
      multiplier *= 1.45
    case .veryHigh:
      multiplier *= 2.1
    }
    return multiplier
  }

  private static func temporaryExportURL(extension pathExtension: String) -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("vivyshot-recordings", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("export-\(UUID().uuidString).\(pathExtension)")
  }

  private static func removeExistingFile(at url: URL) throws {
    if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
  }

  private static func exportError(_ message: String) -> NSError {
    NSError(domain: "VivyShot.Export", code: -200, userInfo: [NSLocalizedDescriptionKey: message])
  }
}

@MainActor
final class ScreenRegionRecorder: NSObject, SCStreamDelegate, SCRecordingOutputDelegate {
  private let selectionRectInScreen: CGRect
  private let config: VideoRecordingConfig
  private(set) var outputURL: URL

  private var stream: SCStream?
  private var recordingOutput: SCRecordingOutput?
  private let recordingErrorLock = NSLock()
  nonisolated(unsafe) private var latestRecordingError: Error?

  init(selectionRectInScreen: CGRect, config: VideoRecordingConfig, outputURL: URL) {
    self.selectionRectInScreen = selectionRectInScreen.standardized
    self.config = config
    self.outputURL = outputURL
    super.init()
  }

  func start() async throws {
    if FileManager.default.fileExists(atPath: outputURL.path) {
      try FileManager.default.removeItem(at: outputURL)
    }

    var content = try await SCShareableContent.current
    let overlayResolution = try await resolveCapturedOverlayWindows(initialContent: content)
    content = overlayResolution.content
    guard let screen = activeScreenForSelection(),
          let displayID = screen.displayID,
          let display = content.displays.first(where: { $0.displayID == displayID })
    else {
      throw NSError(
        domain: "com.vivyshot.recording",
        code: -20,
        userInfo: [NSLocalizedDescriptionKey: "No compatible display found for selected area."]
      )
    }

    let excludedApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
    let filter = SCContentFilter(
      display: display,
      excludingApplications: excludedApps,
      exceptingWindows: overlayResolution.windows
    )

    let streamConfig = SCStreamConfiguration()
    let displayRect = display.frame
    let selectionInCG = cocoaRectToCGDisplayRect(selectionRectInScreen)
    let sourceRect = selectionInCG
      .intersection(displayRect)
      .offsetBy(dx: -displayRect.minX, dy: -displayRect.minY)
      .integral
    guard !sourceRect.isNull, sourceRect.width >= 2, sourceRect.height >= 2 else {
      throw NSError(
        domain: "com.vivyshot.recording",
        code: -21,
        userInfo: [NSLocalizedDescriptionKey: "Selected region is too small to record."]
      )
    }

    let scale = max(1.0, screen.backingScaleFactor)
    streamConfig.sourceRect = sourceRect
    streamConfig.width = max(2, Int((sourceRect.width * scale).rounded()))
    streamConfig.height = max(2, Int((sourceRect.height * scale).rounded()))
    streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(1, config.frameRate)))
    streamConfig.pixelFormat = kCVPixelFormatType_32BGRA
    streamConfig.queueDepth = 5
    streamConfig.showsCursor = true
    streamConfig.showMouseClicks = config.highlightMouseClicks
    streamConfig.capturesAudio = config.captureSystemAudio
    streamConfig.captureMicrophone = config.captureMicrophone
    streamConfig.excludesCurrentProcessAudio = false
    streamConfig.captureDynamicRange = .SDR

    let stream = SCStream(filter: filter, configuration: streamConfig, delegate: self)
    let outputConfig = SCRecordingOutputConfiguration()
    outputConfig.outputURL = outputURL

    switch config.codec {
    case .h264:
      outputConfig.videoCodecType = .h264
    case .hevc:
      if outputConfig.availableVideoCodecTypes.contains(.hevc) {
        outputConfig.videoCodecType = .hevc
      } else {
        outputConfig.videoCodecType = .h264
      }
    }

    if outputConfig.availableOutputFileTypes.contains(.mp4) {
      outputConfig.outputFileType = .mp4
    } else if let first = outputConfig.availableOutputFileTypes.first {
      outputConfig.outputFileType = first
    }

    let recordingOutput = SCRecordingOutput(configuration: outputConfig, delegate: self)
    try stream.addRecordingOutput(recordingOutput)

    self.stream = stream
    self.recordingOutput = recordingOutput
    setRecordingError(nil)
    try await stream.vs_startCapture()
  }

  private func resolveCapturedOverlayWindows(
    initialContent: SCShareableContent
  ) async throws -> (content: SCShareableContent, windows: [SCWindow]) {
    let requestedIDs = Set(config.capturedOverlayWindowIDs)
    guard !requestedIDs.isEmpty else {
      return (initialContent, [])
    }

    var content = initialContent
    for attempt in 0..<5 {
      let windows = content.windows.filter { requestedIDs.contains($0.windowID) }
      if windows.count == requestedIDs.count {
        return (content, windows)
      }

      if attempt < 4 {
        try await Task.sleep(nanoseconds: 80_000_000)
        content = try await SCShareableContent.current
      }
    }

    throw NSError(
      domain: "com.vivyshot.recording",
      code: -22,
      userInfo: [NSLocalizedDescriptionKey: "Recording overlay window was not available to capture."]
    )
  }

  func stop() async throws -> URL {
    guard let stream else {
      return outputURL
    }

    try await stream.vs_stopCapture()
    self.stream = nil
    recordingOutput = nil

    if let recordingError = currentRecordingError() {
      throw recordingError
    }

    // Give recording writer a moment to flush trailer metadata.
    try? await Task.sleep(nanoseconds: 220_000_000)
    return outputURL
  }

  private func activeScreenForSelection() -> NSScreen? {
    let center = CGPoint(x: selectionRectInScreen.midX, y: selectionRectInScreen.midY)
    return NSScreen.screens.first(where: { $0.frame.contains(center) })
      ?? NSScreen.main
      ?? NSScreen.screens.first
  }

  nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
    setRecordingError(error)
  }

  nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
    setRecordingError(error)
  }

  nonisolated private func currentRecordingError() -> Error? {
    recordingErrorLock.lock()
    defer { recordingErrorLock.unlock() }
    return latestRecordingError
  }

  nonisolated private func setRecordingError(_ error: Error?) {
    recordingErrorLock.lock()
    latestRecordingError = error
    recordingErrorLock.unlock()
  }
}

private func cocoaRectToCGDisplayRect(_ rect: CGRect) -> CGRect {
  guard let primaryHeight = NSScreen.screens.first?.frame.height else { return rect }
  return CGRect(x: rect.origin.x, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
}

private extension NSScreen {
  var displayID: CGDirectDisplayID? {
    guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
      return nil
    }
    return CGDirectDisplayID(number.uint32Value)
  }
}

@MainActor
private extension SCStream {
  func vs_startCapture() async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      startCapture { error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume(returning: ())
        }
      }
    }
  }

  func vs_stopCapture() async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      stopCapture { error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume(returning: ())
        }
      }
    }
  }
}

private extension AVAssetExportSession {
  func vs_export() async throws {
    guard let url = outputURL, let fileType = outputFileType else {
      throw NSError(domain: "VivyShot.Export", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing output URL or file type."])
    }
    if #available(macOS 15.0, *) {
      try await export(to: url, as: fileType)
    } else {
      nonisolated(unsafe) let session = self
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        session.exportAsynchronously {
          switch session.status {
          case .completed:
            continuation.resume(returning: ())
          case .failed:
            continuation.resume(throwing: session.error ?? NSError(domain: "VivyShot.Export", code: -1))
          case .cancelled:
            continuation.resume(throwing: NSError(domain: "VivyShot.Export", code: -2))
          default:
            continuation.resume(throwing: session.error ?? NSError(domain: "VivyShot.Export", code: -3))
          }
        }
      }
    }
  }
}

private extension AVAssetWriter {
  func vs_finishWriting() async throws {
    nonisolated(unsafe) let writer = self
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      writer.finishWriting {
        continuation.resume()
      }
    }
    switch writer.status {
    case .completed:
      return
    case .failed:
      throw writer.error ?? NSError(domain: "VivyShot.Export", code: -211, userInfo: [NSLocalizedDescriptionKey: "Video writer failed."])
    case .cancelled:
      throw NSError(domain: "VivyShot.Export", code: -212, userInfo: [NSLocalizedDescriptionKey: "Video writer was cancelled."])
    default:
      throw writer.error ?? NSError(domain: "VivyShot.Export", code: -213, userInfo: [NSLocalizedDescriptionKey: "Video writer did not complete."])
    }
  }
}
