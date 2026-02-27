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
import UniformTypeIdentifiers

@MainActor
final class CaptureCoordinator {
  private let settings: AppSettings
  private let selectionOverlay: RegionSelectionOverlayController
  private let videoCaptureCoordinator: VideoCaptureCoordinator

  private var captureInProgress = false
  private var requestedScreenPermissionThisSession = false
  private var showedPermissionHintThisSession = false

  init(settings: AppSettings = .shared) {
    self.settings = settings
    selectionOverlay = RegionSelectionOverlayController(settings: settings)
    videoCaptureCoordinator = VideoCaptureCoordinator(settings: settings)
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
        domain: "com.vivy.vivyshot.capture",
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
              domain: "com.vivy.vivyshot.capture",
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

  private func cropFrozenImage(
    _ image: CGImage,
    selectionRectInScreen: CGRect,
    screenFrame: CGRect
  ) -> CGImage? {
    let normalizedSelection = selectionRectInScreen.standardized
    let clippedSelection = normalizedSelection.intersection(screenFrame)
    guard !clippedSelection.isNull, clippedSelection.width >= 2, clippedSelection.height >= 2 else {
      return nil
    }

    let localRect = clippedSelection.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
    let scaleX = CGFloat(image.width) / screenFrame.width
    let scaleY = CGFloat(image.height) / screenFrame.height

    let x = localRect.minX * scaleX
    let yTop = CGFloat(image.height) - (localRect.maxY * scaleY)
    let width = localRect.width * scaleX
    let height = localRect.height * scaleY

    var cropRect = CGRect(
      x: floor(x),
      y: floor(yTop),
      width: ceil(width),
      height: ceil(height)
    )

    let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    cropRect = cropRect.intersection(imageBounds)

    guard !cropRect.isNull, cropRect.width >= 2, cropRect.height >= 2 else {
      return nil
    }

    return image.cropping(to: cropRect.integral)
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

    if showedPermissionHintThisSession {
      return false
    }
    showedPermissionHintThisSession = true

    let alert = NSAlert()
    alert.messageText = "Screen Recording Permission Needed"
    alert.informativeText = "Enable Screen Recording for VivyShotDev in System Settings > Privacy & Security > Screen Recording."
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
    let alert = NSAlert()
    alert.messageText = "Capture Failed"
    alert.informativeText = message
    alert.alertStyle = .critical
    alert.addButton(withTitle: "OK")
    alert.runModal()
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
  private var editorController: VideoTrimWindowController?
  private var onDone: (() -> Void)?
  private var onError: ((String) -> Void)?
  private var recordingRect: CGRect = .zero

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
          try webcamRecorder.start()
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
        if showFloatingHUD {
          showHUD()
        }
      } catch {
        cleanupRecordingSession()
        onError("Failed to start video recording: \(error.localizedDescription)")
      }
    }
  }

  func stopRecordingFromInlineToolbar() {
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
          webcamOverlaySize: settings.videoWebcamOverlaySize
        )
        presentTrimEditor(
          inputURL: outputURL,
          overlay: overlay,
          rustSession: rustVideoSession
        )
      } catch {
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
    let editor = VideoTrimWindowController(
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

  private func cleanupRecordingSession() {
    hudController?.close()
    hudController = nil
    recorder = nil
    webcamRecorder = nil
    inputMonitor = nil
    rustVideoSession = nil
    editorController = nil
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
        domain: "com.vivy.vivyshot.video",
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
        domain: "com.vivy.vivyshot.video",
        code: -57,
        userInfo: [NSLocalizedDescriptionKey: errorTitle]
      )
    case .denied, .restricted:
      throw NSError(
        domain: "com.vivy.vivyshot.video",
        code: -58,
        userInfo: [NSLocalizedDescriptionKey: errorTitle]
      )
    @unknown default:
      throw NSError(
        domain: "com.vivy.vivyshot.video",
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

private struct RecordedKeystrokeEvent {
  let timestampNS: UInt64
  let displayToken: String
}

private struct RecordedMouseClickEvent {
  let timestampNS: UInt64
  let normalizedX: CGFloat
  let normalizedY: CGFloat
  let button: UInt32
}

private struct RecordingInputResult {
  let keyEvents: [RecordedKeystrokeEvent]
  let clickEvents: [RecordedMouseClickEvent]
}

private struct VideoExportOverlayConfiguration {
  let webcamURL: URL?
  let keyEvents: [RecordedKeystrokeEvent]
  let webcamOverlayShape: VideoWebcamOverlayShapeOption
  let webcamOverlaySize: VideoWebcamOverlaySizeOption
}

private final class RecordingInputMonitor {
  private let captureRectInScreen: CGRect
  private let captureKeystrokes: Bool
  private let captureMouseClicks: Bool

  private var startUptime: TimeInterval = 0
  private var keyMonitorToken: Any?
  private var clickMonitorToken: Any?
  private var keyEvents: [RecordedKeystrokeEvent] = []
  private var clickEvents: [RecordedMouseClickEvent] = []

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
      keyMonitorToken = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
        self?.handleKeyDown(event)
      }
    }

    if captureMouseClicks {
      clickMonitorToken = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
        self?.handleMouseDown(event)
      }
    }
  }

  func stop() -> RecordingInputResult {
    stopObservers()
    return RecordingInputResult(
      keyEvents: keyEvents,
      clickEvents: clickEvents
    )
  }

  private func stopObservers() {
    if let keyMonitorToken {
      NSEvent.removeMonitor(keyMonitorToken)
      self.keyMonitorToken = nil
    }

    if let clickMonitorToken {
      NSEvent.removeMonitor(clickMonitorToken)
      self.clickMonitorToken = nil
    }
  }

  private func handleKeyDown(_ event: NSEvent) {
    let token = displayToken(for: event)
    guard !token.isEmpty else {
      return
    }

    keyEvents.append(
      RecordedKeystrokeEvent(
        timestampNS: elapsedTimestampNS(),
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

    clickEvents.append(
      RecordedMouseClickEvent(
        timestampNS: elapsedTimestampNS(),
        normalizedX: normalizedX,
        normalizedY: normalizedY,
        button: button
      )
    )
  }

  private func elapsedTimestampNS() -> UInt64 {
    let elapsed = max(0, ProcessInfo.processInfo.systemUptime - startUptime)
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

  init(outputURL: URL, preferredDeviceID: String) throws {
    self.outputURL = outputURL
    self.preferredDeviceID = preferredDeviceID
    super.init()
    try configureSession()
  }

  func start() throws {
    if FileManager.default.fileExists(atPath: outputURL.path) {
      try FileManager.default.removeItem(at: outputURL)
    }

    if !session.isRunning {
      session.startRunning()
    }

    if !movieOutput.isRecording {
      movieOutput.startRecording(to: outputURL, recordingDelegate: self)
    }
  }

  func stop() async throws -> URL {
    guard movieOutput.isRecording else {
      if session.isRunning {
        session.stopRunning()
      }
      return outputURL
    }

    return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
      stopContinuation = continuation
      movieOutput.stopRecording()
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

      guard let continuation = self.stopContinuation else {
        return
      }
      self.stopContinuation = nil

      if let error {
        continuation.resume(throwing: error)
      } else {
        continuation.resume(returning: outputFileURL)
      }
    }
  }

  private func configureSession() throws {
    session.beginConfiguration()
    session.sessionPreset = .medium

    let allVideoDevices = AVCaptureDevice.DiscoverySession(
      deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
      mediaType: .video,
      position: .unspecified
    ).devices

    let selectedDevice = allVideoDevices.first(where: { $0.uniqueID == preferredDeviceID })
    guard let device = selectedDevice ?? AVCaptureDevice.default(for: .video) ?? allVideoDevices.first else {
      session.commitConfiguration()
      throw NSError(
        domain: "com.vivy.vivyshot.video",
        code: -70,
        userInfo: [NSLocalizedDescriptionKey: "No camera device is available."]
      )
    }

    let input = try AVCaptureDeviceInput(device: device)
    guard session.canAddInput(input) else {
      session.commitConfiguration()
      throw NSError(
        domain: "com.vivy.vivyshot.video",
        code: -71,
        userInfo: [NSLocalizedDescriptionKey: "Unable to add webcam input."]
      )
    }
    session.addInput(input)

    guard session.canAddOutput(movieOutput) else {
      session.commitConfiguration()
      throw NSError(
        domain: "com.vivy.vivyshot.video",
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
  private var recordingError: Error?

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
        domain: "com.vivy.vivyshot.recording",
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
        domain: "com.vivy.vivyshot.recording",
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
    recordingError = nil
    try await stream.vs_startCapture()
  }

  func stop() async throws -> URL {
    guard let stream else {
      return outputURL
    }

    try await stream.vs_stopCapture()
    self.stream = nil
    recordingOutput = nil

    if let recordingError {
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
    recordingError = error
  }

  func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
    recordingError = error
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

@MainActor
private final class VideoTrimWindowController: NSWindowController, NSWindowDelegate {
  private let inputURL: URL
  private let overlay: VideoExportOverlayConfiguration
  private let rustSession: RustVideoSession?
  private let onDone: () -> Void

  private let playerView = AVPlayerView()
  private let startSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
  private let endSlider = NSSlider(value: 1, minValue: 0, maxValue: 1, target: nil, action: nil)
  private let startValueLabel = NSTextField(labelWithString: "0.00s")
  private let endValueLabel = NSTextField(labelWithString: "0.00s")
  private let durationLabel = NSTextField(labelWithString: "Duration 0.00s")
  private let statusLabel = NSTextField(labelWithString: "")
  private let asset: AVAsset
  private var durationSeconds: Double = 0

  init(
    inputURL: URL,
    overlay: VideoExportOverlayConfiguration,
    rustSession: RustVideoSession?,
    onDone: @escaping () -> Void
  ) {
    self.inputURL = inputURL
    self.overlay = overlay
    self.rustSession = rustSession
    self.onDone = onDone
    asset = AVAsset(url: inputURL)

    let window = NSWindow(
      contentRect: CGRect(x: 140, y: 120, width: 860, height: 640),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = "Trim Recording"
    window.isReleasedWhenClosed = false

    super.init(window: window)
    window.delegate = self
    configureUI()
    loadAsset()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  func present() {
    showWindow(nil)
    window?.center()
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func windowWillClose(_ notification: Notification) {
    onDone()
  }

  private func configureUI() {
    guard let content = window?.contentView else {
      return
    }

    playerView.translatesAutoresizingMaskIntoConstraints = false
    playerView.controlsStyle = .floating
    playerView.showsFullScreenToggleButton = true
    playerView.player = AVPlayer(url: inputURL)

    startSlider.target = self
    startSlider.action = #selector(trimSliderChanged)
    endSlider.target = self
    endSlider.action = #selector(trimSliderChanged)

    startSlider.translatesAutoresizingMaskIntoConstraints = false
    endSlider.translatesAutoresizingMaskIntoConstraints = false

    startValueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
    endValueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
    durationLabel.font = .systemFont(ofSize: 12, weight: .semibold)
    statusLabel.font = .systemFont(ofSize: 11, weight: .medium)
    statusLabel.textColor = .secondaryLabelColor

    let startRow = labeledSliderRow(title: "Start", slider: startSlider, valueLabel: startValueLabel)
    let endRow = labeledSliderRow(title: "End", slider: endSlider, valueLabel: endValueLabel)

    let exportMP4Button = NSButton(title: "Export MP4", target: self, action: #selector(exportMP4Pressed))
    exportMP4Button.bezelStyle = .rounded
    let exportGIFButton = NSButton(title: "Export GIF", target: self, action: #selector(exportGIFPressed))
    exportGIFButton.bezelStyle = .rounded
    let doneButton = NSButton(title: "Done", target: self, action: #selector(donePressed))
    doneButton.bezelStyle = .rounded
    doneButton.keyEquivalent = "\r"

    let buttonRow = NSStackView(views: [durationLabel, NSView(), exportMP4Button, exportGIFButton, doneButton])
    buttonRow.orientation = .horizontal
    buttonRow.alignment = .centerY
    buttonRow.spacing = 8
    buttonRow.translatesAutoresizingMaskIntoConstraints = false

    statusLabel.translatesAutoresizingMaskIntoConstraints = false
    statusLabel.lineBreakMode = .byTruncatingTail

    content.addSubview(playerView)
    content.addSubview(startRow)
    content.addSubview(endRow)
    content.addSubview(buttonRow)
    content.addSubview(statusLabel)

    NSLayoutConstraint.activate([
      playerView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
      playerView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
      playerView.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
      playerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 320),

      startRow.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
      startRow.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
      startRow.topAnchor.constraint(equalTo: playerView.bottomAnchor, constant: 12),

      endRow.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
      endRow.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
      endRow.topAnchor.constraint(equalTo: startRow.bottomAnchor, constant: 8),

      buttonRow.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
      buttonRow.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
      buttonRow.topAnchor.constraint(equalTo: endRow.bottomAnchor, constant: 14),

      statusLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
      statusLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
      statusLabel.topAnchor.constraint(equalTo: buttonRow.bottomAnchor, constant: 10),
      statusLabel.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -12),
    ])
  }

  private func labeledSliderRow(title: String, slider: NSSlider, valueLabel: NSTextField) -> NSView {
    let titleLabel = NSTextField(labelWithString: title)
    titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
    valueLabel.alignment = .right
    valueLabel.frame.size.width = 58

    let row = NSStackView(views: [titleLabel, slider, valueLabel])
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 8
    row.translatesAutoresizingMaskIntoConstraints = false
    valueLabel.widthAnchor.constraint(equalToConstant: 62).isActive = true
    return row
  }

  private func loadAsset() {
    durationSeconds = max(0, CMTimeGetSeconds(asset.duration))
    if !durationSeconds.isFinite || durationSeconds <= 0 {
      durationSeconds = 1
    }

    startSlider.minValue = 0
    startSlider.maxValue = durationSeconds
    endSlider.minValue = 0
    endSlider.maxValue = durationSeconds
    startSlider.doubleValue = 0
    endSlider.doubleValue = durationSeconds
    updateTrimLabels()
  }

  @objc
  private func trimSliderChanged() {
    let minGap = min(0.1, max(0.01, durationSeconds / 1000))
    if startSlider.doubleValue >= endSlider.doubleValue - minGap {
      if startSlider.currentEditor() != nil {
        endSlider.doubleValue = min(durationSeconds, startSlider.doubleValue + minGap)
      } else {
        startSlider.doubleValue = max(0, endSlider.doubleValue - minGap)
      }
    }

    let startTime = CMTime(seconds: startSlider.doubleValue, preferredTimescale: 600)
    playerView.player?.seek(to: startTime, toleranceBefore: .zero, toleranceAfter: .zero)
    updateTrimLabels()
  }

  @objc
  private func exportMP4Pressed() {
    Task { [weak self] in
      guard let self else {
        return
      }
      await exportMP4()
    }
  }

  @objc
  private func exportGIFPressed() {
    Task { [weak self] in
      guard let self else {
        return
      }
      await exportGIF()
    }
  }

  @objc
  private func donePressed() {
    close()
  }

  private func updateTrimLabels() {
    startValueLabel.stringValue = String(format: "%.2fs", startSlider.doubleValue)
    endValueLabel.stringValue = String(format: "%.2fs", endSlider.doubleValue)
    let trimmed = max(0, endSlider.doubleValue - startSlider.doubleValue)
    durationLabel.stringValue = String(format: "Duration %.2fs", trimmed)
  }

  private var currentTimeRange: CMTimeRange {
    let start = max(0, min(durationSeconds, startSlider.doubleValue))
    let end = max(start, min(durationSeconds, endSlider.doubleValue))
    let startTime = CMTime(seconds: start, preferredTimescale: 600)
    let duration = CMTime(seconds: max(0.01, end - start), preferredTimescale: 600)
    return CMTimeRange(start: startTime, duration: duration)
  }

  private var hasOverlayEnhancements: Bool {
    overlay.webcamURL != nil || !overlay.keyEvents.isEmpty
  }

  private func persistTrimIntoRustModel(_ range: CMTimeRange) {
    let startMS = max(0, Int((range.start.seconds * 1000).rounded()))
    let endMS = max(startMS, Int(((range.start.seconds + range.duration.seconds) * 1000).rounded()))
    _ = rustSession?.setTrim(startMS: startMS, endMS: endMS)
  }

  private func exportSummarySuffix() -> String {
    guard let plan = rustSession?.exportPlan() else {
      return ""
    }
    return " (\(plan.keyEventCount) keys, \(plan.clickEventCount) clicks)"
  }

  private func exportMP4() async {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [UTType.mpeg4Movie]
    panel.nameFieldStringValue = "recording-trimmed.mp4"

    guard panel.runModal() == .OK, let outputURL = panel.url else {
      return
    }

    statusLabel.stringValue = "Exporting MP4…"
    do {
      if FileManager.default.fileExists(atPath: outputURL.path) {
        try FileManager.default.removeItem(at: outputURL)
      }

      let trimRange = currentTimeRange
      persistTrimIntoRustModel(trimRange)

      if hasOverlayEnhancements {
        try await VideoCompositor.exportCompositeMP4(
          sourceURL: inputURL,
          trimRange: trimRange,
          overlay: overlay,
          outputURL: outputURL
        )
      } else {
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
          throw NSError(
            domain: "com.vivy.vivyshot.video",
            code: -40,
            userInfo: [NSLocalizedDescriptionKey: "Unable to create MP4 export session."]
          )
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.timeRange = trimRange
        exportSession.shouldOptimizeForNetworkUse = true
        try await exportSession.vs_export()
      }

      statusLabel.stringValue = "Saved MP4 to \(outputURL.lastPathComponent)\(exportSummarySuffix())"
    } catch {
      statusLabel.stringValue = "MP4 export failed: \(error.localizedDescription)"
    }
  }

  private func exportGIF() async {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [UTType.gif]
    panel.nameFieldStringValue = "recording-trimmed.gif"

    guard panel.runModal() == .OK, let outputURL = panel.url else {
      return
    }

    statusLabel.stringValue = "Exporting GIF…"
    do {
      if FileManager.default.fileExists(atPath: outputURL.path) {
        try FileManager.default.removeItem(at: outputURL)
      }

      let trimRange = currentTimeRange
      persistTrimIntoRustModel(trimRange)

      var gifSourceURL = inputURL
      var gifStart = trimRange.start.seconds
      var gifEnd = trimRange.start.seconds + trimRange.duration.seconds

      if hasOverlayEnhancements {
        let temporaryURL = makeTemporaryExportURL(extension: "mp4")
        try await VideoCompositor.exportCompositeMP4(
          sourceURL: inputURL,
          trimRange: trimRange,
          overlay: overlay,
          outputURL: temporaryURL
        )
        gifSourceURL = temporaryURL
        gifStart = 0
        gifEnd = trimRange.duration.seconds
      }

      try await renderGIF(
        sourceURL: gifSourceURL,
        outputURL: outputURL,
        startSeconds: gifStart,
        endSeconds: gifEnd
      )
      statusLabel.stringValue = "Saved GIF to \(outputURL.lastPathComponent)\(exportSummarySuffix())"
    } catch {
      statusLabel.stringValue = "GIF export failed: \(error.localizedDescription)"
    }
  }

  private func makeTemporaryExportURL(`extension`: String) -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("vivyshot-recordings", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("export-\(UUID().uuidString).\(`extension`)")
  }

  private func renderGIF(
    sourceURL: URL,
    outputURL: URL,
    startSeconds: Double,
    endSeconds: Double
  ) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let frameRate: Double = 12
          let generator = AVAssetImageGenerator(asset: AVAsset(url: sourceURL))
          generator.appliesPreferredTrackTransform = true
          generator.maximumSize = CGSize(width: 960, height: 960)
          generator.requestedTimeToleranceAfter = .zero
          generator.requestedTimeToleranceBefore = .zero

          let frameCount = max(1, Int(ceil((endSeconds - startSeconds) * frameRate)))
          guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.gif.identifier as CFString,
            frameCount,
            nil
          ) else {
            throw NSError(
              domain: "com.vivy.vivyshot.video",
              code: -41,
              userInfo: [NSLocalizedDescriptionKey: "Unable to create GIF destination."]
            )
          }

          let gifProps: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
              kCGImagePropertyGIFLoopCount: 0,
            ],
          ]
          CGImageDestinationSetProperties(destination, gifProps as CFDictionary)

          let frameDelay = 1.0 / frameRate
          for index in 0 ..< frameCount {
            let progress = Double(index) / Double(max(1, frameCount - 1))
            let second = startSeconds + (endSeconds - startSeconds) * progress
            let time = CMTime(seconds: second, preferredTimescale: 600)
            let image = try generator.copyCGImage(at: time, actualTime: nil)
            let frameProps: [CFString: Any] = [
              kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: frameDelay,
              ],
            ]
            CGImageDestinationAddImage(destination, image, frameProps as CFDictionary)
          }

          guard CGImageDestinationFinalize(destination) else {
            throw NSError(
              domain: "com.vivy.vivyshot.video",
              code: -42,
              userInfo: [NSLocalizedDescriptionKey: "Failed to finalize GIF export."]
            )
          }
          continuation.resume(returning: ())
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }
}

private enum VideoCompositor {
  private struct WebcamOverlayLayout {
    let transform: CGAffineTransform
    let frame: CGRect
  }

  static func exportCompositeMP4(
    sourceURL: URL,
    trimRange: CMTimeRange,
    overlay: VideoExportOverlayConfiguration,
    outputURL: URL
  ) async throws {
    let sourceAsset = AVAsset(url: sourceURL)
    guard let sourceVideoTrack = sourceAsset.tracks(withMediaType: .video).first else {
      throw NSError(
        domain: "com.vivy.vivyshot.video",
        code: -80,
        userInfo: [NSLocalizedDescriptionKey: "Source recording has no video track."]
      )
    }

    let composition = AVMutableComposition()
    guard let baseTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
      throw NSError(
        domain: "com.vivy.vivyshot.video",
        code: -81,
        userInfo: [NSLocalizedDescriptionKey: "Unable to create composition video track."]
      )
    }
    try baseTrack.insertTimeRange(trimRange, of: sourceVideoTrack, at: .zero)
    baseTrack.preferredTransform = sourceVideoTrack.preferredTransform

    for sourceAudioTrack in sourceAsset.tracks(withMediaType: .audio) {
      guard let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
        continue
      }
      try? audioTrack.insertTimeRange(trimRange, of: sourceAudioTrack, at: .zero)
    }

    let renderSize = normalizedRenderSize(of: sourceVideoTrack)
    let instruction = AVMutableVideoCompositionInstruction()
    instruction.timeRange = CMTimeRange(start: .zero, duration: trimRange.duration)

    let baseLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: baseTrack)
    baseLayerInstruction.setTransform(sourceVideoTrack.preferredTransform, at: .zero)

    var layerInstructions: [AVVideoCompositionLayerInstruction] = [baseLayerInstruction]
    var webcamLayout: WebcamOverlayLayout?

    if let webcamURL = overlay.webcamURL,
       FileManager.default.fileExists(atPath: webcamURL.path)
    {
      let webcamAsset = AVAsset(url: webcamURL)
      if let webcamVideoTrack = webcamAsset.tracks(withMediaType: .video).first,
         let webcamCompositionTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
      {
        let webcamDuration = minCMTime(trimRange.duration, webcamAsset.duration)
        if CMTimeCompare(webcamDuration, .zero) > 0 {
          try webcamCompositionTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: webcamDuration),
            of: webcamVideoTrack,
            at: .zero
          )
          let webcamLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: webcamCompositionTrack)
          let layout = webcamOverlayLayout(
            webcamTrack: webcamVideoTrack,
            renderSize: renderSize,
            sizeOption: overlay.webcamOverlaySize,
            shapeOption: overlay.webcamOverlayShape
          )
          webcamLayerInstruction.setTransform(
            layout.transform,
            at: .zero
          )
          layerInstructions.insert(webcamLayerInstruction, at: 0)
          webcamLayout = layout
        }
      }
    }

    instruction.layerInstructions = layerInstructions

    let videoComposition = AVMutableVideoComposition()
    videoComposition.instructions = [instruction]
    videoComposition.renderSize = renderSize
    videoComposition.frameDuration = frameDuration(for: sourceVideoTrack)
    if !overlay.keyEvents.isEmpty || webcamLayout != nil {
      videoComposition.animationTool = makeAnimationTool(
        renderSize: renderSize,
        keyEvents: overlay.keyEvents,
        trimStartSeconds: trimRange.start.seconds,
        webcamLayout: webcamLayout,
        webcamShape: overlay.webcamOverlayShape
      )
    }

    guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
      throw NSError(
        domain: "com.vivy.vivyshot.video",
        code: -82,
        userInfo: [NSLocalizedDescriptionKey: "Unable to create compositor export session."]
      )
    }

    exportSession.outputURL = outputURL
    exportSession.outputFileType = .mp4
    exportSession.shouldOptimizeForNetworkUse = true
    exportSession.videoComposition = videoComposition
    try await exportSession.vs_export()
  }

  private static func normalizedRenderSize(of track: AVAssetTrack) -> CGSize {
    let transformed = track.naturalSize.applying(track.preferredTransform)
    let width = max(2, abs(transformed.width).rounded())
    let height = max(2, abs(transformed.height).rounded())
    return CGSize(width: width, height: height)
  }

  private static func frameDuration(for track: AVAssetTrack) -> CMTime {
    let fps = Int(round(Double(track.nominalFrameRate)))
    if fps > 0 {
      return CMTime(value: 1, timescale: CMTimeScale(fps))
    }
    return CMTime(value: 1, timescale: 30)
  }

  private static func webcamOverlayLayout(
    webcamTrack: AVAssetTrack,
    renderSize: CGSize,
    sizeOption: VideoWebcamOverlaySizeOption,
    shapeOption: VideoWebcamOverlayShapeOption
  ) -> WebcamOverlayLayout {
    let webcamSize = normalizedRenderSize(of: webcamTrack)
    let targetWidth = max(108, min(renderSize.width * sizeOption.widthFraction, 420))
    let scale = targetWidth / max(1, webcamSize.width)
    var targetHeight = webcamSize.height * scale
    if shapeOption == .circle {
      targetHeight = targetWidth
    }
    let margin = max(14, renderSize.width * 0.018)
    let targetX = renderSize.width - targetWidth - margin
    let targetY = margin

    var transform = webcamTrack.preferredTransform
    if shapeOption == .circle {
      let scaleY = targetHeight / max(1, webcamSize.height)
      transform = transform.scaledBy(x: scale, y: scaleY)
      transform = transform.translatedBy(
        x: targetX / max(0.01, scale),
        y: targetY / max(0.01, scaleY)
      )
    } else {
      transform = transform.scaledBy(x: scale, y: scale)
      transform = transform.translatedBy(x: targetX / max(0.01, scale), y: targetY / max(0.01, scale))
    }

    return WebcamOverlayLayout(
      transform: transform,
      frame: CGRect(x: targetX, y: targetY, width: targetWidth, height: targetHeight)
    )
  }

  private static func makeAnimationTool(
    renderSize: CGSize,
    keyEvents: [RecordedKeystrokeEvent],
    trimStartSeconds: Double,
    webcamLayout: WebcamOverlayLayout?,
    webcamShape: VideoWebcamOverlayShapeOption
  ) -> AVVideoCompositionCoreAnimationTool {
    let parentLayer = CALayer()
    parentLayer.frame = CGRect(origin: .zero, size: renderSize)
    parentLayer.masksToBounds = true

    let videoLayer = CALayer()
    videoLayer.frame = parentLayer.frame
    parentLayer.addSublayer(videoLayer)

    if let webcamLayout {
      let webcamFrame = webcamLayout.frame.insetBy(dx: 1.5, dy: 1.5)
      let borderLayer = CAShapeLayer()
      borderLayer.frame = parentLayer.frame
      borderLayer.fillColor = NSColor.clear.cgColor
      borderLayer.strokeColor = NSColor(calibratedWhite: 1.0, alpha: 0.9).cgColor
      borderLayer.lineWidth = max(2, webcamFrame.width * 0.012)
      borderLayer.shadowColor = NSColor.black.cgColor
      borderLayer.shadowOpacity = 0.35
      borderLayer.shadowRadius = 4
      borderLayer.shadowOffset = CGSize(width: 0, height: 1.5)
      if webcamShape == .circle {
        borderLayer.path = CGPath(ellipseIn: webcamFrame, transform: nil)
      } else {
        let radius = max(10, webcamFrame.height * 0.16)
        borderLayer.path = CGPath(
          roundedRect: webcamFrame,
          cornerWidth: radius,
          cornerHeight: radius,
          transform: nil
        )
      }
      parentLayer.addSublayer(borderLayer)
    }

    let tokenHeight = max(34, min(58, renderSize.height * 0.085))
    let maxTokenWidth = renderSize.width * 0.72
    let tokenY = max(18, renderSize.height * 0.07)

    for event in keyEvents {
      let eventSeconds = Double(event.timestampNS) / 1_000_000_000 - trimStartSeconds
      if eventSeconds < 0 {
        continue
      }

      let text = event.displayToken
      if text.isEmpty {
        continue
      }

      let estimatedWidth = min(maxTokenWidth, CGFloat(max(84, text.count * 18)))
      let layer = CATextLayer()
      layer.string = text
      layer.fontSize = max(16, tokenHeight * 0.46)
      layer.alignmentMode = .center
      layer.foregroundColor = NSColor.white.cgColor
      layer.backgroundColor = NSColor(calibratedWhite: 0.06, alpha: 0.82).cgColor
      layer.cornerRadius = tokenHeight * 0.26
      layer.frame = CGRect(
        x: (renderSize.width - estimatedWidth) * 0.5,
        y: tokenY,
        width: estimatedWidth,
        height: tokenHeight
      )
      layer.opacity = 0
      layer.contentsScale = 2
      parentLayer.addSublayer(layer)

      let fade = CAKeyframeAnimation(keyPath: "opacity")
      fade.values = [0, 1, 1, 0]
      fade.keyTimes = [0, 0.1, 0.78, 1]
      fade.duration = 0.95
      fade.beginTime = AVCoreAnimationBeginTimeAtZero + eventSeconds
      fade.fillMode = .forwards
      fade.isRemovedOnCompletion = false
      layer.add(fade, forKey: "fade")
    }

    return AVVideoCompositionCoreAnimationTool(
      postProcessingAsVideoLayer: videoLayer,
      in: parentLayer
    )
  }

  private static func minCMTime(_ lhs: CMTime, _ rhs: CMTime) -> CMTime {
    if !lhs.isValid {
      return rhs
    }
    if !rhs.isValid {
      return lhs
    }
    return CMTimeCompare(lhs, rhs) <= 0 ? lhs : rhs
  }
}

@MainActor
private extension AVAssetExportSession {
  func vs_export() async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      exportAsynchronously {
        switch self.status {
        case .completed:
          continuation.resume(returning: ())
        case .failed:
          continuation.resume(throwing: self.error ?? NSError(
            domain: "com.vivy.vivyshot.video",
            code: -43,
            userInfo: [NSLocalizedDescriptionKey: "Video export failed."]
          ))
        case .cancelled:
          continuation.resume(throwing: NSError(
            domain: "com.vivy.vivyshot.video",
            code: -44,
            userInfo: [NSLocalizedDescriptionKey: "Video export cancelled."]
          ))
        default:
          continuation.resume(throwing: NSError(
            domain: "com.vivy.vivyshot.video",
            code: -45,
            userInfo: [NSLocalizedDescriptionKey: "Video export ended in unexpected state."]
          ))
        }
      }
    }
  }
}
