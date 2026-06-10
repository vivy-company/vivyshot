import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit
import VideoToolbox

final class RecordingAssetWriter: @unchecked Sendable {
  let queue = DispatchQueue(label: "com.vivyshot.recording.asset-writer", qos: .userInitiated)

  private let outputURL: URL
  private let frameRate: Int
  private let encoder: RecordingEncoder
  private let stateLock = NSLock()
  private var systemAudioEnabled: Bool
  private var microphoneAudioEnabled: Bool
  private var configuredVideoSize: CGSize?
  private var writer: AVAssetWriter?
  private var videoInput: AVAssetWriterInput?
  private var systemAudioInput: AVAssetWriterInput?
  private var microphoneAudioInput: AVAssetWriterInput?
  private var sessionStartTime: CMTime?
  private var didFinish = false

  init(
    outputURL: URL,
    frameRate: Int,
    encoder: RecordingEncoder,
    systemAudioEnabled: Bool,
    microphoneAudioEnabled: Bool
  ) {
    self.outputURL = outputURL
    self.frameRate = max(1, frameRate)
    self.encoder = encoder
    self.systemAudioEnabled = systemAudioEnabled
    self.microphoneAudioEnabled = microphoneAudioEnabled
  }

  func configureVideoSize(width: Int, height: Int) {
    configuredVideoSize = CGSize(width: max(2, width), height: max(2, height))
  }

  func prepare() throws {
    if FileManager.default.fileExists(atPath: outputURL.path) {
      try FileManager.default.removeItem(at: outputURL)
    }

    guard let videoSize = configuredVideoSize else {
      throw NSError(
        domain: "com.vivyshot.recording",
        code: -40,
        userInfo: [NSLocalizedDescriptionKey: "Recording writer video size was not configured."]
      )
    }

    let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
    writer.shouldOptimizeForNetworkUse = true

    let bitrateMultiplier: CGFloat = encoder == .smallerFileHEVC ? 0.08 : 0.12
    let bitrate = max(6_000_000, Int(videoSize.width * videoSize.height * CGFloat(frameRate) * bitrateMultiplier))
    let videoInput = AVAssetWriterInput(
      mediaType: .video,
      outputSettings: videoOutputSettings(videoSize: videoSize, bitrate: bitrate)
    )
    videoInput.expectsMediaDataInRealTime = true
    guard writer.canAdd(videoInput) else {
      throw NSError(
        domain: "com.vivyshot.recording",
        code: -41,
        userInfo: [NSLocalizedDescriptionKey: "Unable to configure recording video writer."]
      )
    }
    writer.add(videoInput)

    let systemInput = makeAudioInput()
    guard writer.canAdd(systemInput) else {
      throw NSError(
        domain: "com.vivyshot.recording",
        code: -42,
        userInfo: [NSLocalizedDescriptionKey: "Unable to configure system audio writer."]
      )
    }
    writer.add(systemInput)
    systemAudioInput = systemInput

    let microphoneInput = makeAudioInput()
    guard writer.canAdd(microphoneInput) else {
      throw NSError(
        domain: "com.vivyshot.recording",
        code: -43,
        userInfo: [NSLocalizedDescriptionKey: "Unable to configure microphone audio writer."]
      )
    }
    writer.add(microphoneInput)
    microphoneAudioInput = microphoneInput

    guard writer.startWriting() else {
      throw writer.error ?? NSError(
        domain: "com.vivyshot.recording",
        code: -44,
        userInfo: [NSLocalizedDescriptionKey: "Unable to start recording writer."]
      )
    }

    self.writer = writer
    self.videoInput = videoInput
  }

  func append(sampleBuffer: CMSampleBuffer, type: SCStreamOutputType) {
    guard CMSampleBufferDataIsReady(sampleBuffer), !didFinish else {
      return
    }

    switch type {
    case .screen:
      appendVideo(sampleBuffer)
    case .audio:
      guard isAudioEnabled(for: type) else { return }
      appendAudio(sampleBuffer, input: systemAudioInput)
    case .microphone:
      guard isAudioEnabled(for: type) else { return }
      appendAudio(sampleBuffer, input: microphoneAudioInput)
    @unknown default:
      return
    }
  }

  func setSystemAudioEnabled(_ enabled: Bool) {
    stateLock.lock()
    systemAudioEnabled = enabled
    stateLock.unlock()
  }

  func setMicrophoneAudioEnabled(_ enabled: Bool) {
    stateLock.lock()
    microphoneAudioEnabled = enabled
    stateLock.unlock()
  }

  func finish() async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      queue.async { [self] in
        didFinish = true

        guard let writer else {
          continuation.resume(returning: ())
          return
        }

        guard sessionStartTime != nil else {
          writer.cancelWriting()
          continuation.resume(throwing: NSError(
            domain: "com.vivyshot.recording",
            code: -45,
            userInfo: [NSLocalizedDescriptionKey: "No video frames were captured for recording."]
          ))
          return
        }

        videoInput?.markAsFinished()
        systemAudioInput?.markAsFinished()
        microphoneAudioInput?.markAsFinished()

        nonisolated(unsafe) let unsafeWriter = writer
        unsafeWriter.finishWriting {
          switch unsafeWriter.status {
          case .completed:
            continuation.resume(returning: ())
          case .failed:
            continuation.resume(throwing: unsafeWriter.error ?? NSError(
              domain: "com.vivyshot.recording",
              code: -46,
              userInfo: [NSLocalizedDescriptionKey: "Software H.264 writer failed."]
            ))
          case .cancelled:
            continuation.resume(throwing: NSError(
              domain: "com.vivyshot.recording",
              code: -47,
              userInfo: [NSLocalizedDescriptionKey: "Software H.264 writer was cancelled."]
            ))
          default:
            continuation.resume(throwing: unsafeWriter.error ?? NSError(
              domain: "com.vivyshot.recording",
              code: -48,
              userInfo: [NSLocalizedDescriptionKey: "Software H.264 writer did not complete."]
            ))
          }
        }
      }
    }
  }

  func cancel() {
    queue.async { [self] in
      didFinish = true
      writer?.cancelWriting()
    }
  }

  private func appendVideo(_ sampleBuffer: CMSampleBuffer) {
    guard let writer, writer.status == .writing, let videoInput else {
      return
    }
    guard CMSampleBufferGetImageBuffer(sampleBuffer) != nil else {
      return
    }
    guard isCompleteScreenFrame(sampleBuffer) else {
      return
    }

    let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
    guard presentationTime.isValid else {
      return
    }

    if sessionStartTime == nil {
      sessionStartTime = presentationTime
      writer.startSession(atSourceTime: presentationTime)
    }

    guard videoInput.isReadyForMoreMediaData else {
      return
    }
    _ = videoInput.append(sampleBuffer)
  }

  private func appendAudio(_ sampleBuffer: CMSampleBuffer, input: AVAssetWriterInput?) {
    guard let input, input.isReadyForMoreMediaData, sessionStartTime != nil else {
      return
    }
    _ = input.append(sampleBuffer)
  }

  private func isAudioEnabled(for type: SCStreamOutputType) -> Bool {
    stateLock.lock()
    defer { stateLock.unlock() }
    switch type {
    case .audio:
      return systemAudioEnabled
    case .microphone:
      return microphoneAudioEnabled
    default:
      return true
    }
  }

  private func videoOutputSettings(videoSize: CGSize, bitrate: Int) -> [String: Any] {
    var compression: [String: Any] = [
      AVVideoAverageBitRateKey: bitrate,
      AVVideoExpectedSourceFrameRateKey: frameRate,
      AVVideoMaxKeyFrameIntervalKey: frameRate * 2
    ]
    if encoder != .smallerFileHEVC {
      compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
    }
    let codec: AVVideoCodecType = encoder == .smallerFileHEVC ? .hevc : .h264
    var settings: [String: Any] = [
      AVVideoCodecKey: codec,
      AVVideoWidthKey: Int(videoSize.width),
      AVVideoHeightKey: Int(videoSize.height),
      AVVideoCompressionPropertiesKey: compression
    ]
    if encoder == .cpuH264 {
      settings[AVVideoEncoderSpecificationKey] = [
        kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder as String: false
      ]
    }
    return settings
  }

  private func makeAudioInput() -> AVAssetWriterInput {
    let input = AVAssetWriterInput(
      mediaType: .audio,
      outputSettings: [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 48_000,
        AVNumberOfChannelsKey: 2,
        AVEncoderBitRateKey: 128_000
      ]
    )
    input.expectsMediaDataInRealTime = true
    return input
  }

  private func isCompleteScreenFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
    guard let attachments = CMSampleBufferGetSampleAttachmentsArray(
      sampleBuffer,
      createIfNecessary: false
    ) as? [[SCStreamFrameInfo: Any]],
      let statusValue = attachments.first?[SCStreamFrameInfo.status] as? Int,
      let status = SCFrameStatus(rawValue: statusValue)
    else {
      return true
    }
    return status == .complete || status == .started
  }
}
