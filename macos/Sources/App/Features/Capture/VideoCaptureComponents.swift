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
  // TODO(vivyshot): Re-enable microphone capture once video recording support is production-ready.
  private let videoMicrophoneFeatureEnabled = false
  // TODO(vivyshot): Re-enable webcam overlay once video recording support is production-ready.
  private let videoWebcamFeatureEnabled = false
  // TODO(vivyshot): Re-enable keystroke highlighting once video recording support is production-ready.
  private let videoKeystrokesFeatureEnabled = false
  private let settings: AppSettings
  private var recorder: ScreenRegionRecorder?
  private var webcamRecorder: WebcamRecorder?
  private var inputMonitor: RecordingInputMonitor?
  private var rustVideoSession: RustVideoSession?
  private var hudController: VideoRecordingHUDController?
  private var postRecordingPanels: [PostRecordingActionPanel] = []
  private var onDone: (() -> Void)?
  private var onError: ((String) -> Void)?
  private var recordingRect: CGRect = .zero
  private var capturedKeystrokesInSession = false
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
    showFloatingHUD: Bool = true,
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
        if settings.videoHideNotificationsBestEffort {
          TransientToast.show("Tip: Enable Focus for cleaner recordings.", duration: 1.8)
        }
        try await runCountdownIfNeeded()
        try await ensureRuntimePermissions()

        let outputURL = makeTemporaryRecordingURL()
        let microphoneEnabled = effectiveCaptureMicrophoneEnabled
        let webcamEnabled = effectiveShowWebcamEnabled
        let keystrokesEnabled = effectiveHighlightKeystrokesEnabled
        let recordingConfig = VideoRecordingConfig(
          codec: settings.videoCodec,
          frameRate: settings.videoFrameRate.rawValue,
          highlightMouseClicks: settings.videoHighlightMouseClicks,
          captureSystemAudio: settings.videoRecordSystemAudio,
          captureMicrophone: microphoneEnabled
        )
        let recorder = ScreenRegionRecorder(
          selectionRectInScreen: recordingRect,
          config: recordingConfig,
          outputURL: outputURL
        )
        let rustSession = RustCoreBridge.shared.makeVideoSession(
          config: RustVideoSessionConfig(
            frameRate: settings.videoFrameRate.rawValue,
            captureSystemAudio: settings.videoRecordSystemAudio,
            captureMicrophone: microphoneEnabled,
            showWebcam: webcamEnabled,
            highlightMouseClicks: settings.videoHighlightMouseClicks,
            highlightKeystrokes: keystrokesEnabled
          )
        )

        let capturesKeystrokes = keystrokesEnabled && isAccessibilityTrusted(promptIfNeeded: false)
        if keystrokesEnabled && !capturesKeystrokes {
          TransientToast.show("Accessibility permission required for keystroke overlays.", duration: 1.8)
        }

        if webcamEnabled {
          let webcamOutputURL = makeTemporaryWebcamURL()
          let webcamRecorder = try WebcamRecorder(
            outputURL: webcamOutputURL,
            preferredDeviceID: settings.videoWebcamDeviceID
          )
          try await webcamRecorder.start()
          self.webcamRecorder = webcamRecorder
        }

        try await recorder.start()
        self.recorder = recorder
        self.rustVideoSession = rustSession

        let monitor = RecordingInputMonitor(
          captureRectInScreen: recordingRect,
          captureKeystrokes: capturesKeystrokes,
          captureMouseClicks: settings.videoHighlightMouseClicks
        )
        monitor.start()
        inputMonitor = monitor
        capturedKeystrokesInSession = capturesKeystrokes

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
    isRecordingActive = false
    hudController?.close()
    hudController = nil

    guard let activeRecorder = recorder else {
      markCaptureFlowFinished()
      cleanupRecordingSession()
      return
    }
    recorder = nil

    Task { [weak self] in
      guard let self else {
        return
      }

      do {
        let monitorResult = inputMonitor?.stop() ?? RecordingInputResult(keyEvents: [], clickEvents: [])
        inputMonitor = nil

        let outputURL = try await activeRecorder.stop()
        let activeWebcamRecorder = webcamRecorder
        webcamRecorder = nil
        let webcamURL = try await activeWebcamRecorder?.stop()

        for keyEvent in monitorResult.keyEvents {
          _ = rustVideoSession?.addKeyEvent(timestampNS: keyEvent.timestampNS, token: keyEvent.displayToken)
        }

        for clickEvent in monitorResult.clickEvents {
          _ = rustVideoSession?.addClickEvent(
            timestampNS: clickEvent.timestampNS,
            normalizedX: clickEvent.normalizedX,
            normalizedY: clickEvent.normalizedY,
            button: clickEvent.button
          )
        }

        let recordingDetails = PostRecordingDetails(
          frameRate: settings.videoFrameRate.rawValue,
          systemAudioEnabled: settings.videoRecordSystemAudio,
          microphoneEnabled: effectiveCaptureMicrophoneEnabled,
          webcamEnabled: effectiveShowWebcamEnabled && webcamURL != nil,
          mouseClicksEnabled: settings.videoHighlightMouseClicks,
          keystrokesEnabled: capturedKeystrokesInSession,
          keyEventCount: monitorResult.keyEvents.count,
          clickEventCount: monitorResult.clickEvents.count
        )

        // Recording is fully stopped: allow a new capture flow immediately.
        markCaptureFlowFinished()
        rustVideoSession = nil

        await self.presentPostRecordingDialog(
          inputURL: outputURL,
          details: recordingDetails
        )
      } catch {
        self.isRecordingActive = false
        cleanupRecordingSession()
        onError?("Failed to stop recording: \(error.localizedDescription)")
      }
    }
  }

  private func presentPostRecordingDialog(
    inputURL: URL,
    details: PostRecordingDetails
  ) async {
    let assetInfo = await PostRecordingActionPanel.loadAssetInfo(url: inputURL)
    recordRecordingStatisticsIfNeeded(inputURL: inputURL, durationSeconds: assetInfo.durationSeconds)
    var panelRef: PostRecordingActionPanel?
    let panel = PostRecordingActionPanel(
      inputURL: inputURL,
      details: details,
      durationSeconds: assetInfo.durationSeconds,
      thumbnail: assetInfo.thumbnail,
      videoSize: assetInfo.videoSize
    ) { [self] action in
      if let panelRef {
        postRecordingPanels.removeAll(where: { $0 === panelRef })
      }
      switch action {
      case .saveVideo(let options):
        quickSaveVideo(inputURL: inputURL, options: options)
      case .saveGIF:
        quickSaveGIF(inputURL: inputURL)
      case .discard:
        discardTemporaryRecording(inputURL: inputURL)
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

  private func quickSaveVideo(inputURL: URL, options: PostRecordingExportOptions) {
    let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
      .replacingOccurrences(of: ":", with: "-")
    let contentType = RustCoreBridge.shared.preferredVideoSaveContentType(codec: options.codec)
    let defaultName = "VivyShot \(timestamp).\(contentType.preferredFilenameExtension ?? "mp4")"

    let panel = NSSavePanel()
    panel.allowedContentTypes = RustCoreBridge.shared.allowedVideoSaveContentTypes(codec: options.codec)
    panel.nameFieldStringValue = defaultName
    panel.canCreateDirectories = true
    panel.isExtensionHidden = false

    guard panel.runModal() == .OK, let outputURL = panel.url else { return }

    Task {
      do {
        let asset = AVURLAsset(url: inputURL)
        let durationTime = try await asset.load(.duration)
        let durationSeconds = max(0, CMTimeGetSeconds(durationTime))
        let trimRange = CMTimeRange(start: .zero, duration: durationTime)
        let presetName = RustCoreBridge.shared.bestVideoExportPreset(
          codec: options.codec,
          quality: options.quality,
          compatiblePresets: AVAssetExportSession.exportPresets(compatibleWith: asset)
        )

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: presetName) else {
          TransientToast.show("Export failed: unable to create session.", duration: 2.5)
          return
        }

        let outputFileType = RustCoreBridge.shared.bestVideoSaveFileType(
          codec: options.codec,
          supportedTypes: exportSession.supportedFileTypes
        )
        exportSession.outputURL = outputURL
        exportSession.outputFileType = outputFileType
        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.timeRange = trimRange
        if let videoComposition = try await makePostRecordingVideoComposition(asset: asset, options: options) {
          exportSession.videoComposition = videoComposition
        }
        if let fileLengthLimit = RustCoreBridge.shared.estimatedVideoFileLengthLimit(
          durationSeconds: durationSeconds,
          options: options
        ) {
          exportSession.fileLengthLimit = fileLengthLimit
        }
        try await exportSession.vs_export()
        TransientToast.show("Saved video to \(outputURL.lastPathComponent)", duration: 2.5)
      } catch {
        TransientToast.show("Video save failed: \(error.localizedDescription)", duration: 2.5)
      }
    }
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

  private func quickSaveGIF(inputURL: URL) {
    _ = inputURL
    Task {
      TransientToast.show("GIF export is temporarily unavailable during editor redesign.", duration: 2.8)
    }
  }

  private func discardTemporaryRecording(inputURL: URL) {
    Task {
      do {
        if FileManager.default.fileExists(atPath: inputURL.path) {
          try FileManager.default.removeItem(at: inputURL)
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
    webcamRecorder = nil
    inputMonitor = nil
    rustVideoSession = nil
    capturedKeystrokesInSession = false
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
      throw NSError(
        domain: "com.vivyshot.video",
        code: -56,
        userInfo: [NSLocalizedDescriptionKey: "Accessibility permission is required for keystroke overlays."]
      )
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

struct VideoExportOverlayConfiguration {
  let webcamURL: URL?
  let keyEvents: [RecordedKeystrokeEvent]
  let clickEvents: [RecordedMouseClickEvent]
  let webcamOverlayShape: VideoWebcamOverlayShapeOption
  let webcamOverlaySize: VideoWebcamOverlaySizeOption
  let textOverlays: [VideoTextOverlayClip]
}

struct VideoTextOverlayClip: Identifiable, Equatable {
  let id: UUID
  var text: String
  var startSeconds: Double
  var endSeconds: Double
}

final class RecordingInputMonitor {
  private let captureRectInScreen: CGRect
  private let captureKeystrokes: Bool
  private let captureMouseClicks: Bool
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
    captureMouseClicks: Bool
  ) {
    self.captureRectInScreen = captureRectInScreen.standardized
    self.captureKeystrokes = captureKeystrokes
    self.captureMouseClicks = captureMouseClicks
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

    keyEvents.append(
      RecordedKeystrokeEvent(
        timestampNS: timestampNS,
        displayToken: token
      )
    )
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

@MainActor
final class WebcamRecorder: NSObject, AVCaptureFileOutputRecordingDelegate {
  private let outputURL: URL
  private let preferredDeviceID: String
  private let session = AVCaptureSession()
  private let movieOutput = AVCaptureMovieFileOutput()
  private var stopContinuation: CheckedContinuation<URL, Error>?
  private var recordingDidStart = false
  private var lastRecordingError: Error?

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

    if !session.isRunning {
      session.startRunning()
    }

    if !movieOutput.isRecording {
      movieOutput.startRecording(to: outputURL, recordingDelegate: self)
    }

    try await waitForRecordingToStart()
  }

  func stop() async throws -> URL {
    guard movieOutput.isRecording else {
      if session.isRunning {
        session.stopRunning()
      }
      if let lastRecordingError {
        throw lastRecordingError
      }
      try validateOutputFile(outputURL)
      return outputURL
    }

    return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
      stopContinuation = continuation
      movieOutput.stopRecording()
    }
  }

  nonisolated func fileOutput(
    _ output: AVCaptureFileOutput,
    didStartRecordingTo fileURL: URL,
    from connections: [AVCaptureConnection]
  ) {
    Task { @MainActor [weak self] in
      self?.recordingDidStart = true
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

      if self.session.isRunning {
        self.session.stopRunning()
      }
      self.recordingDidStart = false

      guard let continuation = self.stopContinuation else {
        if let error {
          self.lastRecordingError = error
        } else {
          self.lastRecordingError = nil
        }
        return
      }
      self.stopContinuation = nil

      if let error {
        self.lastRecordingError = error
        continuation.resume(throwing: error)
      } else {
        do {
          try self.validateOutputFile(outputFileURL)
          self.lastRecordingError = nil
          continuation.resume(returning: outputFileURL)
        } catch {
          self.lastRecordingError = error
          continuation.resume(throwing: error)
        }
      }
    }
  }

  private func waitForRecordingToStart(timeoutSeconds: Double = 2.0) async throws {
    let deadline = Date().addingTimeInterval(timeoutSeconds)

    while !recordingDidStart && !movieOutput.isRecording {
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

    let content = try await SCShareableContent.current
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
    let filter = SCContentFilter(display: display, excludingApplications: excludedApps, exceptingWindows: [])

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
