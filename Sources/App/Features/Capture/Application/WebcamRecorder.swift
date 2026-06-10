import AppKit
import ApplicationServices
import AVFoundation
import AVKit
import CoreGraphics
import CoreMedia
import ImageIO
import QuartzCore
import ScreenCaptureKit
import UniformTypeIdentifiers
import VideoToolbox

@MainActor
final class WebcamRecorder: NSObject, AVCaptureFileOutputRecordingDelegate {
  private let outputURL: URL
  private var preferredDeviceID: String
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

  func setDeviceID(_ deviceID: String) async throws {
    let normalized = deviceID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard normalized != preferredDeviceID else {
      return
    }

    session.beginConfiguration()
    do {
      try replaceVideoInput(preferredDeviceID: normalized)
      session.commitConfiguration()
      preferredDeviceID = normalized
    } catch {
      session.commitConfiguration()
      throw error
    }
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

    do {
      try replaceVideoInput(preferredDeviceID: preferredDeviceID)
    } catch {
      session.commitConfiguration()
      throw error
    }

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

  private func replaceVideoInput(preferredDeviceID: String) throws {
    let device = try Self.videoDevice(preferredDeviceID: preferredDeviceID)
    let replacementInput = try AVCaptureDeviceInput(device: device)
    let existingVideoInputs = session.inputs.compactMap { input -> AVCaptureDeviceInput? in
      guard let deviceInput = input as? AVCaptureDeviceInput,
            deviceInput.device.hasMediaType(.video)
      else {
        return nil
      }
      return deviceInput
    }

    for input in existingVideoInputs {
      session.removeInput(input)
    }

    guard session.canAddInput(replacementInput) else {
      for input in existingVideoInputs where session.canAddInput(input) {
        session.addInput(input)
      }
      throw NSError(
        domain: "com.vivyshot.video",
        code: -71,
        userInfo: [NSLocalizedDescriptionKey: "Unable to add webcam input."]
      )
    }
    session.addInput(replacementInput)
  }

  private static func videoDevice(preferredDeviceID: String) throws -> AVCaptureDevice {
    let allVideoDevices = AVCaptureDevice.DiscoverySession(
      deviceTypes: RecordingSourceProvider.webcamDeviceTypes,
      mediaType: .video,
      position: .unspecified
    ).devices

    let selectedDevice = allVideoDevices.first(where: { $0.uniqueID == preferredDeviceID })
    guard let device = selectedDevice ?? AVCaptureDevice.default(for: .video) ?? allVideoDevices.first else {
      throw NSError(
        domain: "com.vivyshot.video",
        code: -70,
        userInfo: [NSLocalizedDescriptionKey: "No camera device is available."]
      )
    }
    return device
  }
}
