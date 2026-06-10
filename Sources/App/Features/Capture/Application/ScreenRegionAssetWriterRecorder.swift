import AppKit
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit

@MainActor
final class ScreenRegionAssetWriterRecorder: NSObject, RegionRecordingSession, SCStreamDelegate, SCStreamOutput {
  private let selectionRectInScreen: CGRect
  private let config: RecordingConfig
  private(set) var outputURL: URL

  private var stream: SCStream?
  private var streamConfiguration: SCStreamConfiguration?
  private let sampleWriter: RecordingAssetWriter
  private let recordingErrorLock = NSLock()
  nonisolated(unsafe) private var latestRecordingError: Error?

  init(selectionRectInScreen: CGRect, config: RecordingConfig, outputURL: URL) {
    self.selectionRectInScreen = selectionRectInScreen.standardized
    self.config = config
    self.outputURL = outputURL
    sampleWriter = RecordingAssetWriter(
      outputURL: outputURL,
      frameRate: config.frameRate,
      encoder: config.encoder,
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

    let scale = max(1.0, screen.backingScaleFactor)
    let outputWidth = max(2, Int((sourceRect.width * scale).rounded()))
    let outputHeight = max(2, Int((sourceRect.height * scale).rounded()))
    streamConfig.sourceRect = sourceRect
    streamConfig.width = outputWidth
    streamConfig.height = outputHeight
    streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(1, config.frameRate)))
    streamConfig.pixelFormat = kCVPixelFormatType_32BGRA
    streamConfig.queueDepth = 5
    streamConfig.showsCursor = true
    streamConfig.showMouseClicks = false
    streamConfig.capturesAudio = config.captureSystemAudio
    streamConfig.captureMicrophone = config.captureMicrophone
    streamConfig.microphoneCaptureDeviceID = config.microphoneDeviceID.nilIfEmpty
    streamConfig.excludesCurrentProcessAudio = false
    streamConfig.captureDynamicRange = .SDR
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
    } catch {
      sampleWriter.cancel()
      throw error
    }
  }

  func stop() async throws -> URL {
    guard let stream else {
      return outputURL
    }

    try await stream.stopCaptureChecked()
    self.stream = nil
    streamConfiguration = nil

    if let recordingError = currentRecordingError() {
      sampleWriter.cancel()
      throw recordingError
    }

    try await sampleWriter.finish()
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

  func stopCaptureChecked() async throws {
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

private extension String {
  var nilIfEmpty: String? {
    isEmpty ? nil : self
  }
}
