import AppKit
import ApplicationServices
import AVFoundation
import AVKit
import Carbon
import CoreGraphics
import CoreMedia
import ImageIO
import QuartzCore
import ScreenCaptureKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class CaptureCoordinator {
  private let settings: AppSettings
  private let selectionOverlay: RegionSelectionOverlayController
  private let videoCaptureCoordinator: VideoCaptureCoordinator

  var onRecordingStateChanged: ((Bool) -> Void)? {
    didSet {
      onRecordingStateChanged?(videoCaptureCoordinator.isRecordingActive)
    }
  }

  private var captureInProgress = false
  private var requestedScreenPermissionThisSession = false
  private var showingScreenPermissionAlert = false

  init(settings: AppSettings = .shared) {
    self.settings = settings
    selectionOverlay = RegionSelectionOverlayController(settings: settings)
    videoCaptureCoordinator = VideoCaptureCoordinator(settings: settings)
    videoCaptureCoordinator.onRecordingStateChanged = { [weak self] isRecording in
      self?.onRecordingStateChanged?(isRecording)
    }
  }

  func startRegionCapture() {
    guard !captureInProgress else {
      return
    }

    guard ensureScreenCapturePermission() else {
      return
    }

    guard let screen = activeScreenForCapture() else {
      showCaptureError("No active display found.")
      return
    }
    let screenFrame = screen.frame

    captureInProgress = true
    Task { [weak self] in
      guard let self else {
        return
      }

      do {
        let frozenImage = try await self.captureFrozenImage(in: screenFrame)
        self.selectionOverlay.beginSelection(onScreenFrame: screenFrame, frozenImage: frozenImage) { [weak self] result in
          guard let self else {
            return
          }

          guard let result else {
            self.captureInProgress = false
            return
          }

          guard let session = RustCoreBridge.shared.makeSession(image: frozenImage) else {
            self.captureInProgress = false
            self.selectionOverlay.closeFlow()
            self.showCaptureError("Failed to initialize Rust editor session.")
            return
          }

          self.selectionOverlay.enterEditing(
            session: session,
            selectionRectInScreen: result.selectionRectInScreen,
            initialCaptureType: result.captureType,
            onStartVideo: { [weak self] rect, completion in
              guard let self else {
                completion(false)
                return
              }
              var started = false
              self.videoCaptureCoordinator.startRecording(
                selectionRectInScreen: rect,
                showFloatingHUD: true,
                onStarted: { [weak self] in
                  started = true
                  // Close the frozen selection overlay once recording is live so
                  // the user can interact with the captured app region directly.
                  self?.selectionOverlay.closeFlow()
                  completion(true)
                },
                onDone: { [weak self] in
                  self?.captureInProgress = false
                },
                onError: { [weak self] message in
                  if !started {
                    completion(false)
                  } else {
                    self?.captureInProgress = false
                  }
                  self?.showCaptureError(message)
                }
              )
            },
            onStopVideo: { [weak self] in
              self?.videoCaptureCoordinator.stopRecordingFromInlineToolbar()
            },
            onDone: { [weak self] in
              self?.captureInProgress = false
            }
          )
        }
      } catch {
        self.captureInProgress = false
        self.showCaptureError("Failed to capture screen: \(error.localizedDescription)")
      }
    }
  }

  private func activeScreenForCapture() -> NSScreen? {
    let mouse = NSEvent.mouseLocation
    return NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main ?? NSScreen.screens.first
  }

  private func captureFrozenImage(in rect: CGRect) async throws -> CGImage {
    guard #available(macOS 15.2, *) else {
      throw NSError(
        domain: "com.vivyshot.capture",
        code: -10,
        userInfo: [NSLocalizedDescriptionKey: "Screen capture requires macOS 15.2 or newer."]
      )
    }

    return try await withCheckedThrowingContinuation { continuation in
      SCScreenshotManager.captureImage(in: rect) { image, error in
        if let error {
          continuation.resume(throwing: error)
          return
        }

        guard let image else {
          continuation.resume(
            throwing: NSError(
              domain: "com.vivyshot.capture",
              code: -11,
              userInfo: [NSLocalizedDescriptionKey: "No image returned by ScreenCaptureKit."]
            )
          )
          return
        }

        continuation.resume(returning: image)
      }
    }
  }

  private func ensureScreenCapturePermission() -> Bool {
    if CGPreflightScreenCaptureAccess() {
      return true
    }

    if !requestedScreenPermissionThisSession {
      requestedScreenPermissionThisSession = true
      _ = CGRequestScreenCaptureAccess()
    }

    if CGPreflightScreenCaptureAccess() {
      return true
    }

    if showingScreenPermissionAlert {
      return false
    }
    showingScreenPermissionAlert = true
    defer {
      showingScreenPermissionAlert = false
    }

    NSApp.activate(ignoringOtherApps: true)
    let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
      ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
      ?? "VivyShot"

    let alert = NSAlert()
    alert.messageText = "Screen Recording Permission Needed"
    alert.informativeText = "Enable Screen Recording for \(appName) in System Settings > Privacy & Security > Screen Recording."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Open Settings")
    alert.addButton(withTitle: "Cancel")

    if alert.runModal() == .alertFirstButtonReturn,
       let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
      NSWorkspace.shared.open(url)
    }

    return false
  }

  private func showCaptureError(_ message: String) {
    if captureInProgress {
      TransientToast.show(message, duration: 3.0)
    } else {
      let alert = NSAlert()
      alert.messageText = "Capture Failed"
      alert.informativeText = message
      alert.alertStyle = .critical
      alert.addButton(withTitle: "OK")
      alert.runModal()
    }
  }

  func stopActiveRecordingFromStatusItem() {
    videoCaptureCoordinator.stopRecordingFromStatusBar()
  }

  var isVideoRecordingActive: Bool {
    videoCaptureCoordinator.isRecordingActive
  }
}

@MainActor
private final class VideoCaptureCoordinator {
  private let settings: AppSettings
  private var recorder: ScreenRegionRecorder?
  private var webcamRecorder: WebcamRecorder?
  private var inputMonitor: RecordingInputMonitor?
  private var rustVideoSession: RustVideoSession?
  private var hudController: VideoRecordingHUDController?
  private var editorController: VideoEditorWindowController?
  private var postRecordingPanel: PostRecordingActionPanel?
  private var onDone: (() -> Void)?
  private var onError: ((String) -> Void)?
  private var recordingRect: CGRect = .zero
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
        let recordingConfig = VideoRecordingConfig(
          codec: settings.videoCodec,
          frameRate: settings.videoFrameRate.rawValue,
          highlightMouseClicks: settings.videoHighlightMouseClicks,
          captureSystemAudio: settings.videoRecordSystemAudio,
          captureMicrophone: settings.videoRecordMicrophone
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
            captureMicrophone: settings.videoRecordMicrophone,
            showWebcam: settings.videoShowWebcam,
            highlightMouseClicks: settings.videoHighlightMouseClicks,
            highlightKeystrokes: settings.videoHighlightKeystrokes
          )
        )

        let capturesKeystrokes = settings.videoHighlightKeystrokes && isAccessibilityTrusted(promptIfNeeded: false)
        if settings.videoHighlightKeystrokes && !capturesKeystrokes {
          TransientToast.show("Accessibility permission required for keystroke overlays.", duration: 1.8)
        }

        if settings.videoShowWebcam {
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
      recordMicrophone: settings.videoRecordMicrophone
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
      onDone?()
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

        let overlay = VideoExportOverlayConfiguration(
          webcamURL: webcamURL,
          keyEvents: monitorResult.keyEvents,
          webcamOverlayShape: settings.videoWebcamOverlayShape,
          webcamOverlaySize: settings.videoWebcamOverlaySize,
          textOverlays: []
        )
        presentPostRecordingDialog(
          inputURL: outputURL,
          overlay: overlay,
          rustSession: rustVideoSession
        )
      } catch {
        self.isRecordingActive = false
        cleanupRecordingSession()
        onError?("Failed to stop recording: \(error.localizedDescription)")
      }
    }
  }

  private func presentTrimEditor(
    inputURL: URL,
    overlay: VideoExportOverlayConfiguration,
    rustSession: RustVideoSession?
  ) {
    let editor = VideoEditorWindowController(
      inputURL: inputURL,
      overlay: overlay,
      rustSession: rustSession
    ) { [weak self] in
      self?.cleanupRecordingSession()
      self?.onDone?()
    }
    editorController = editor
    editor.present()
  }

  private func presentPostRecordingDialog(
    inputURL: URL,
    overlay: VideoExportOverlayConfiguration,
    rustSession: RustVideoSession?
  ) {
    let panel = PostRecordingActionPanel(inputURL: inputURL) { [weak self] action in
      guard let self else { return }
      self.postRecordingPanel = nil
      switch action {
      case .saveMP4:
        self.quickSaveMP4(inputURL: inputURL)
      case .saveGIF:
        self.quickSaveGIF(inputURL: inputURL)
      case .editVideo:
        self.presentTrimEditor(inputURL: inputURL, overlay: overlay, rustSession: rustSession)
      }
    }
    postRecordingPanel = panel
    panel.present()
  }

  private func quickSaveMP4(inputURL: URL) {
    let saveDirectory = settings.defaultSaveDirectoryURL
      ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
      .replacingOccurrences(of: ":", with: "-")
    let outputURL = saveDirectory.appendingPathComponent("VivyShot \(timestamp).mp4")

    Task { [weak self] in
      guard let self else { return }
      do {
        let asset = AVAsset(url: inputURL)
        let duration = CMTimeGetSeconds(asset.duration)
        let trimRange = CMTimeRange(start: .zero, duration: CMTime(seconds: duration, preferredTimescale: 600))

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
          TransientToast.show("Export failed: unable to create session.", duration: 2.5)
          self.cleanupRecordingSession()
          self.onDone?()
          return
        }
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.timeRange = trimRange
        try await exportSession.vs_export()
        TransientToast.show("Saved MP4 to \(outputURL.lastPathComponent)", duration: 2.5)
      } catch {
        TransientToast.show("MP4 save failed: \(error.localizedDescription)", duration: 2.5)
      }
      self.cleanupRecordingSession()
      self.onDone?()
    }
  }

  private func quickSaveGIF(inputURL: URL) {
    let saveDirectory = settings.defaultSaveDirectoryURL
      ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
      .replacingOccurrences(of: ":", with: "-")
    let outputURL = saveDirectory.appendingPathComponent("VivyShot \(timestamp).gif")

    Task { [weak self] in
      guard let self else { return }
      do {
        let asset = AVAsset(url: inputURL)
        let duration = CMTimeGetSeconds(asset.duration)
        try await VideoCompositor.renderGIF(
          sourceURL: inputURL,
          outputURL: outputURL,
          startSeconds: 0,
          endSeconds: duration.isFinite ? duration : 1
        )
        TransientToast.show("Saved GIF to \(outputURL.lastPathComponent)", duration: 2.5)
      } catch {
        TransientToast.show("GIF save failed: \(error.localizedDescription)", duration: 2.5)
      }
      self.cleanupRecordingSession()
      self.onDone?()
    }
  }

  private func cleanupRecordingSession() {
    isRecordingActive = false
    hudController?.close()
    hudController = nil
    recorder = nil
    webcamRecorder = nil
    inputMonitor = nil
    rustVideoSession = nil
    editorController = nil
    postRecordingPanel = nil
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
    if settings.videoRecordMicrophone {
      try await ensureMediaAccess(
        for: .audio,
        errorTitle: "Microphone permission is required when microphone recording is enabled."
      )
    }

    if settings.videoShowWebcam {
      try await ensureMediaAccess(
        for: .video,
        errorTitle: "Camera permission is required when webcam recording is enabled."
      )
    }

    if settings.videoHighlightKeystrokes, !isAccessibilityTrusted(promptIfNeeded: true) {
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
}

private struct VideoRecordingConfig {
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

private final class RecordingInputMonitor {
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
       last.timestampNS == timestampNS,
       last.token == token
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
    let normalizedX = max(0, min(1, nx))
    let normalizedY = max(0, min(1, ny))

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
       last.timestampNS == timestampNS,
       last.button == button,
       abs(last.x - normalizedX) < 0.0001,
       abs(last.y - normalizedY) < 0.0001
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
    var parts: [String] = []
    if event.modifierFlags.contains(.command) {
      parts.append("⌘")
    }
    if event.modifierFlags.contains(.shift) {
      parts.append("⇧")
    }
    if event.modifierFlags.contains(.option) {
      parts.append("⌥")
    }
    if event.modifierFlags.contains(.control) {
      parts.append("⌃")
    }

    let keyLabel: String
    if let chars = event.charactersIgnoringModifiers?.trimmingCharacters(in: .whitespacesAndNewlines),
       !chars.isEmpty,
       chars.count == 1 {
      keyLabel = chars.uppercased()
    } else {
      keyLabel = fallbackKeyLabel(for: event.keyCode)
    }
    parts.append(keyLabel)

    let token = parts.joined()
    if token.count > 24 {
      return String(token.prefix(24))
    }
    return token
  }

  private func fallbackKeyLabel(for keyCode: UInt16) -> String {
    switch Int(keyCode) {
    case kVK_Return: return "Return"
    case kVK_Tab: return "Tab"
    case kVK_Space: return "Space"
    case kVK_Delete: return "Delete"
    case kVK_Escape: return "Esc"
    case kVK_LeftArrow: return "←"
    case kVK_RightArrow: return "→"
    case kVK_UpArrow: return "↑"
    case kVK_DownArrow: return "↓"
    case kVK_F1: return "F1"
    case kVK_F2: return "F2"
    case kVK_F3: return "F3"
    case kVK_F4: return "F4"
    case kVK_F5: return "F5"
    case kVK_F6: return "F6"
    case kVK_F7: return "F7"
    case kVK_F8: return "F8"
    case kVK_F9: return "F9"
    case kVK_F10: return "F10"
    case kVK_F11: return "F11"
    case kVK_F12: return "F12"
    default:
      return "Key \(keyCode)"
    }
  }
}

@MainActor
private final class WebcamRecorder: NSObject, AVCaptureFileOutputRecordingDelegate {
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

    var deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .externalUnknown]
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

private final class ScreenRegionRecorder: NSObject, @preconcurrency SCStreamDelegate, @preconcurrency SCRecordingOutputDelegate {
  private let selectionRectInScreen: CGRect
  private let config: VideoRecordingConfig
  private(set) var outputURL: URL

  private var stream: SCStream?
  private var recordingOutput: SCRecordingOutput?
  private let recordingErrorLock = NSLock()
  private var latestRecordingError: Error?

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
    let sourceRect = selectionRectInScreen
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

  func stream(_ stream: SCStream, didStopWithError error: Error) {
    setRecordingError(error)
  }

  func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
    setRecordingError(error)
  }

  private func currentRecordingError() -> Error? {
    recordingErrorLock.lock()
    defer { recordingErrorLock.unlock() }
    return latestRecordingError
  }

  private func setRecordingError(_ error: Error?) {
    recordingErrorLock.lock()
    latestRecordingError = error
    recordingErrorLock.unlock()
  }
}

private extension NSScreen {
  var displayID: CGDirectDisplayID? {
    guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
      return nil
    }
    return CGDirectDisplayID(number.uint32Value)
  }
}

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

@MainActor
private final class VideoRecordingHUDController: NSWindowController {
  private let recordSystemAudio: Bool
  private let recordMicrophone: Bool
  private let onStop: () -> Void
  private let timerLabel = NSTextField(labelWithString: "● 00:00")
  private var timer: Timer?
  private var startedAt = Date()

  init(
    recordSystemAudio: Bool,
    recordMicrophone: Bool,
    onStop: @escaping () -> Void
  ) {
    self.recordSystemAudio = recordSystemAudio
    self.recordMicrophone = recordMicrophone
    self.onStop = onStop

    let panel = NSPanel(
      contentRect: CGRect(x: 0, y: 0, width: 230, height: 92),
      styleMask: [.nonactivatingPanel, .hudWindow],
      backing: .buffered,
      defer: false
    )
    panel.isReleasedWhenClosed = false
    panel.level = .statusBar
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    panel.hidesOnDeactivate = false
    panel.titleVisibility = .hidden
    panel.titlebarAppearsTransparent = true

    super.init(window: panel)
    configureUI()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  func show(near rect: CGRect) {
    guard let panel = window else {
      return
    }

    let size = panel.frame.size
    let x = rect.midX - size.width * 0.5
    let y = rect.maxY + 12
    panel.setFrame(CGRect(x: x, y: y, width: size.width, height: size.height).integral, display: false)
    panel.orderFrontRegardless()
    startedAt = Date()
    updateTimerLabel()

    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      guard let self else {
        return
      }
      MainActor.assumeIsolated {
        self.updateTimerLabel()
      }
    }
  }

  override func close() {
    timer?.invalidate()
    timer = nil
    super.close()
  }

  private func configureUI() {
    guard let content = window?.contentView else {
      return
    }

    timerLabel.font = .monospacedDigitSystemFont(ofSize: 16, weight: .semibold)
    timerLabel.textColor = .systemRed
    timerLabel.alignment = .left

    let sourceLabel = NSTextField(labelWithString: sourceSummaryText())
    sourceLabel.font = .systemFont(ofSize: 11, weight: .medium)
    sourceLabel.textColor = .secondaryLabelColor

    let stopButton = NSButton(title: "Stop", target: self, action: #selector(stopPressed))
    stopButton.bezelStyle = .rounded
    stopButton.keyEquivalent = "\r"

    let topRow = NSStackView(views: [timerLabel, NSView(), stopButton])
    topRow.orientation = .horizontal
    topRow.alignment = .centerY
    topRow.spacing = 8
    topRow.translatesAutoresizingMaskIntoConstraints = false

    sourceLabel.translatesAutoresizingMaskIntoConstraints = false
    content.addSubview(topRow)
    content.addSubview(sourceLabel)

    NSLayoutConstraint.activate([
      topRow.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
      topRow.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
      topRow.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
      sourceLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
      sourceLabel.topAnchor.constraint(equalTo: topRow.bottomAnchor, constant: 8),
      sourceLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
    ])
  }

  private func sourceSummaryText() -> String {
    var parts: [String] = ["Screen"]
    if recordSystemAudio {
      parts.append("System Audio")
    }
    if recordMicrophone {
      parts.append("Microphone")
    }
    return parts.joined(separator: " + ")
  }

  private func updateTimerLabel() {
    let elapsed = max(0, Int(Date().timeIntervalSince(startedAt)))
    let minutes = elapsed / 60
    let seconds = elapsed % 60
    timerLabel.stringValue = String(format: "● %02d:%02d", minutes, seconds)
  }

  @objc
  private func stopPressed() {
    onStop()
  }
}

// MARK: - Post-Recording Action Dialog

private enum PostRecordingAction {
  case saveMP4
  case saveGIF
  case editVideo
}

@MainActor
private final class PostRecordingActionPanel: NSWindowController, NSWindowDelegate {
  private let inputURL: URL
  private let onAction: (PostRecordingAction) -> Void
  private var didPickAction = false

  init(inputURL: URL, onAction: @escaping (PostRecordingAction) -> Void) {
    self.inputURL = inputURL
    self.onAction = onAction

    let panel = NSPanel(
      contentRect: CGRect(x: 0, y: 0, width: 360, height: 280),
      styleMask: [.titled, .closable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    panel.level = .floating
    panel.titlebarAppearsTransparent = true
    panel.titleVisibility = .hidden
    panel.isMovableByWindowBackground = true
    panel.isReleasedWhenClosed = false

    super.init(window: panel)
    panel.delegate = self

    let asset = AVAsset(url: inputURL)
    let durationSeconds = max(0, CMTimeGetSeconds(asset.duration))
    let thumbnail = generateThumbnail(asset: asset)

    let actionView = PostRecordingActionView(
      thumbnail: thumbnail,
      durationSeconds: durationSeconds.isFinite ? durationSeconds : 0
    ) { [weak self] action in
      guard let self, !self.didPickAction else { return }
      self.didPickAction = true
      self.window?.close()
      self.onAction(action)
    }
    panel.contentView = NSHostingView(rootView: actionView)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  func present() {
    window?.center()
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func windowWillClose(_ notification: Notification) {
    if !didPickAction {
      didPickAction = true
      onAction(.editVideo)
    }
  }

  private func generateThumbnail(asset: AVAsset) -> NSImage? {
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: 320, height: 320)
    generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)
    generator.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
    guard let cgImage = try? generator.copyCGImage(at: CMTime(seconds: 0.5, preferredTimescale: 600), actualTime: nil) else {
      return nil
    }
    return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
  }
}

private struct PostRecordingActionView: View {
  let thumbnail: NSImage?
  let durationSeconds: Double
  let onAction: (PostRecordingAction) -> Void

  private var formattedDuration: String {
    let minutes = Int(durationSeconds) / 60
    let seconds = Int(durationSeconds) % 60
    let centiseconds = Int((durationSeconds.truncatingRemainder(dividingBy: 1)) * 100)
    return String(format: "%02d:%02d.%02d", minutes, seconds, centiseconds)
  }

  var body: some View {
    VStack(spacing: 16) {
      if let thumbnail {
        Image(nsImage: thumbnail)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(maxWidth: 280, maxHeight: 160)
          .background(Color.black)
          .cornerRadius(8)
      } else {
        RoundedRectangle(cornerRadius: 8)
          .fill(Color.black)
          .frame(width: 280, height: 160)
          .overlay(
            Image(systemName: "film")
              .font(.system(size: 32))
              .foregroundColor(.secondary)
          )
      }

      Text(formattedDuration)
        .font(.system(.body, design: .monospaced))
        .foregroundColor(.secondary)

      VStack(spacing: 8) {
        Button(action: { onAction(.saveMP4) }) {
          Text("Save as MP4")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .keyboardShortcut(.return, modifiers: [])

        HStack(spacing: 8) {
          Button(action: { onAction(.saveGIF) }) {
            Text("Save as GIF")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered)
          .controlSize(.large)

          Button(action: { onAction(.editVideo) }) {
            Text("Edit Video")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered)
          .controlSize(.large)
        }
      }
    }
    .padding(24)
    .background(
      RoundedRectangle(cornerRadius: 16)
        .fill(.ultraThinMaterial)
        .overlay(
          RoundedRectangle(cornerRadius: 16)
            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
    )
  }
}

