import AppKit
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import os
import ScreenCaptureKit

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.vivyshot", category: "Recording")

@MainActor
final class ScreenRegionAssetWriterRecorder: NSObject, RegionRecordingSession, SCStreamDelegate, SCStreamOutput {
  private static let stopCaptureTimeoutSeconds: Double = 5.0

  private let selectionRectInScreen: CGRect
  private let config: RecordingConfig
  private(set) var outputURL: URL
  var onStreamStopped: (() -> Void)?

  private var stream: SCStream?
  private var streamConfiguration: SCStreamConfiguration?
  private let sampleWriter: RecordingAssetWriter
  private var stopContinuation: CheckedContinuation<Void, Error>?
  private var stopTimeoutTask: Task<Void, Never>?
  private let recordingErrorLock = NSLock()
  nonisolated(unsafe) private var latestRecordingError: Error?

  var interruptionError: Error? {
    currentRecordingError()
  }

  init(selectionRectInScreen: CGRect, config: RecordingConfig, outputURL: URL) {
    self.selectionRectInScreen = selectionRectInScreen.standardized
    self.config = config
    self.outputURL = outputURL
    sampleWriter = RecordingAssetWriter(
      outputURL: outputURL,
      frameRate: config.frameRate,
      encoder: config.encoder,
      colorProfile: config.colorProfile,
      systemAudioEnabled: config.captureSystemAudio,
      microphoneAudioEnabled: config.captureMicrophone
    )
    super.init()
  }

  func start() async throws {
    var content = try await SCShareableContent.current
    let overlayResolution = try await resolveCapturedOverlayWindows(initialContent: content)
    content = overlayResolution.content
    guard let screen = activeScreenForSelection(),
          let displayID = screen.displayID,
          let display = content.displays.first(where: { $0.displayID == displayID })
    else {
      throw NSError(
        domain: "com.vivyshot.recording",
        code: -30,
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
    let selectionInCG = DisplayCoordinateConversion.cocoaRectToCGDisplayRect(selectionRectInScreen)
    let sourceRect = selectionInCG
      .intersection(displayRect)
      .offsetBy(dx: -displayRect.minX, dy: -displayRect.minY)
      .integral
    guard !sourceRect.isNull, sourceRect.width >= 2, sourceRect.height >= 2 else {
      throw NSError(
        domain: "com.vivyshot.recording",
        code: -31,
        userInfo: [NSLocalizedDescriptionKey: "Selected region is too small to record."]
      )
    }

    let scale = max(1.0, screen.backingScaleFactor) * config.captureResolution.scale
    let outputWidth = max(2, Int((sourceRect.width * scale).rounded()))
    let outputHeight = max(2, Int((sourceRect.height * scale).rounded()))
    streamConfig.sourceRect = sourceRect
    streamConfig.width = outputWidth
    streamConfig.height = outputHeight
    streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(1, config.frameRate)))
    streamConfig.pixelFormat = VideoRecordingColorPolicy.capturePixelFormat(
      for: config.encoder,
      colorProfile: config.colorProfile
    )
    streamConfig.colorSpaceName = VideoRecordingColorPolicy.captureColorSpaceName(
      for: config.encoder,
      colorProfile: config.colorProfile
    )
    streamConfig.queueDepth = config.captureBuffering.rawValue
    streamConfig.showsCursor = config.showsPointer
    streamConfig.showMouseClicks = config.showsSystemClickRings
    streamConfig.capturesAudio = config.captureSystemAudio
    streamConfig.captureMicrophone = config.captureMicrophone
    streamConfig.microphoneCaptureDeviceID = config.microphoneDeviceID.nilIfEmpty
    streamConfig.excludesCurrentProcessAudio = !config.includesAppAudio
    streamConfig.captureDynamicRange = VideoRecordingColorPolicy.captureDynamicRange(
      for: config.encoder,
      colorProfile: config.colorProfile
    )
    streamConfiguration = streamConfig

    sampleWriter.configureVideoSize(width: outputWidth, height: outputHeight)
    try sampleWriter.prepare()

    let stream = SCStream(filter: filter, configuration: streamConfig, delegate: self)
    try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleWriter.queue)
    try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleWriter.queue)
    try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: sampleWriter.queue)

    self.stream = stream
    setRecordingError(nil)
    do {
      try await stream.startCaptureChecked()
      logger.info("Screen capture started: \(outputWidth)x\(outputHeight) @\(self.config.frameRate)fps")
    } catch {
      logger.error("Screen capture failed to start: \(error.localizedDescription, privacy: .public)")
      sampleWriter.cancel()
      throw error
    }
  }

  func stop() async throws -> URL {
    onStreamStopped = nil
    guard let stream else {
      return outputURL
    }

    // stopCapture's callback can never arrive when the capture service dies
    // mid-session; a hung stop must not leave the app unable to record again,
    // so the wait is bounded and the writer is finalized either way to keep
    // the frames captured so far.
    do {
      try await stopCapture(stream)
    } catch {
      logger.error("stopCapture did not complete cleanly: \(error.localizedDescription, privacy: .public)")
    }
    self.stream = nil
    streamConfiguration = nil

    if let recordingError = currentRecordingError() {
      logger.error("Stream reported mid-session error: \(recordingError.localizedDescription, privacy: .public)")
    }

    try await sampleWriter.finish()
    logger.info("Recording finalized at \(self.outputURL.lastPathComponent, privacy: .public)")
    return outputURL
  }

  func setSystemAudioEnabled(_ enabled: Bool) async throws {
    guard let stream, let streamConfiguration else {
      sampleWriter.setSystemAudioEnabled(enabled)
      return
    }
    let previous = streamConfiguration.capturesAudio
    if enabled {
      sampleWriter.setSystemAudioEnabled(true)
    }
    streamConfiguration.capturesAudio = enabled
    do {
      try await stream.updateConfiguration(streamConfiguration)
      if !enabled {
        sampleWriter.setSystemAudioEnabled(false)
      }
    } catch {
      streamConfiguration.capturesAudio = previous
      sampleWriter.setSystemAudioEnabled(previous)
      throw error
    }
  }

  func setMicrophoneEnabled(_ enabled: Bool) async throws {
    guard let stream, let streamConfiguration else {
      sampleWriter.setMicrophoneAudioEnabled(enabled)
      return
    }
    let previous = streamConfiguration.captureMicrophone
    if enabled {
      sampleWriter.setMicrophoneAudioEnabled(true)
    }
    streamConfiguration.captureMicrophone = enabled
    do {
      try await stream.updateConfiguration(streamConfiguration)
      if !enabled {
        sampleWriter.setMicrophoneAudioEnabled(false)
      }
    } catch {
      streamConfiguration.captureMicrophone = previous
      sampleWriter.setMicrophoneAudioEnabled(previous)
      throw error
    }
  }

  func setMicrophoneDeviceID(_ deviceID: String) async throws {
    guard let stream, let streamConfiguration else {
      return
    }
    let previous = streamConfiguration.microphoneCaptureDeviceID
    streamConfiguration.microphoneCaptureDeviceID = deviceID.nilIfEmpty
    do {
      try await stream.updateConfiguration(streamConfiguration)
    } catch {
      streamConfiguration.microphoneCaptureDeviceID = previous
      throw error
    }
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
      code: -32,
      userInfo: [NSLocalizedDescriptionKey: "Recording overlay window was not available to capture."]
    )
  }

  private func activeScreenForSelection() -> NSScreen? {
    let center = CGPoint(x: selectionRectInScreen.midX, y: selectionRectInScreen.midY)
    return DisplayCoordinateConversion.activeScreen(containing: center)
  }

  nonisolated func stream(
    _ stream: SCStream,
    didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
    of type: SCStreamOutputType
  ) {
    sampleWriter.append(sampleBuffer: sampleBuffer, type: type)
  }

  nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
    logger.error("Stream stopped externally: \(error.localizedDescription, privacy: .public)")
    setRecordingError(error)
    Task { @MainActor [weak self] in
      guard let self, let callback = self.onStreamStopped else {
        return
      }
      self.onStreamStopped = nil
      callback()
    }
  }

  private func stopCapture(_ stream: SCStream) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      stopContinuation = continuation
      scheduleStopTimeout()
      stream.stopCapture { [weak self] error in
        Task { @MainActor in
          self?.finishStopCapture(error.map(Result.failure) ?? .success(()))
        }
      }
    }
  }

  private func scheduleStopTimeout() {
    stopTimeoutTask?.cancel()
    stopTimeoutTask = Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(Self.stopCaptureTimeoutSeconds * 1_000_000_000))
      guard !Task.isCancelled else {
        return
      }
      self?.finishStopCapture(.failure(NSError(
        domain: "com.vivyshot.recording",
        code: -33,
        userInfo: [NSLocalizedDescriptionKey: "Screen capture did not stop in time."]
      )))
    }
  }

  private func finishStopCapture(_ result: Result<Void, Error>) {
    stopTimeoutTask?.cancel()
    stopTimeoutTask = nil
    guard let continuation = stopContinuation else {
      return
    }
    stopContinuation = nil
    continuation.resume(with: result)
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
  func startCaptureChecked() async throws {
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

}

private extension String {
  var nilIfEmpty: String? {
    isEmpty ? nil : self
  }
}
