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
enum PostRecordingProjectExporter {
  private static let maxGIFDurationSeconds: Double = 120

  static func exportCompositedVideo(
    project: PostRecordingProject,
    options: PostRecordingExportOptions,
    exportState: PostRecordingExportState,
    container: PostRecordingVideoSaveContainer?,
    outputURL: URL,
    progress: PostRecordingExportProgressHandler? = nil
  ) async throws {
    let visualURL = temporaryExportURL(extension: "mov")
    defer { try? FileManager.default.removeItem(at: visualURL) }

    try await renderCompositedVisualAsset(
      project: project,
      options: options,
      exportState: exportState,
      outputURL: visualURL,
      progress: progress
    )
    try await mergeRenderedVideoWithSourceAudio(
      renderedVideoURL: visualURL,
      sourceURL: project.inputURL,
      options: options,
      exportState: exportState,
      container: container,
      outputURL: outputURL,
      progress: progress
    )
  }

  static func exportGIF(
    project: PostRecordingProject,
    exportState: PostRecordingExportState,
    outputURL: URL,
    progress: PostRecordingExportProgressHandler? = nil
  ) async throws {
    let durationSeconds = exportState.trimmedDurationSeconds
    guard durationSeconds > 0 else {
      throw exportError("GIF export failed because the recording duration is unavailable.")
    }
    guard durationSeconds <= maxGIFDurationSeconds else {
      throw exportError("GIF export supports recordings up to 120 seconds.")
    }
    guard let plan = ExportPlanner.gifPlan(
      startMS: exportState.trimStartMS,
      endMS: exportState.trimEndMS,
      preferredFPS: 12,
      maxDimension: 960
    ) else {
      throw exportError("Unable to build GIF export plan.")
    }

    try removeExistingFile(at: outputURL)
    let renderingGIFPhase = String(localized: "Rendering GIF...", bundle: AppLocalizer.shared.bundle)
    let finalizingGIFPhase = String(localized: "Finalizing GIF...", bundle: AppLocalizer.shared.bundle)
    PostRecordingExportProgress.update(
      progress,
      phase: renderingGIFPhase,
      fraction: 0
    )

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
      guard let timeMS = ExportPlanner.gifFrameTimeMS(plan: plan, index: index) else {
        throw exportError("Unable to resolve GIF frame timing.")
      }
      let seconds = Double(timeMS) / 1000.0
      let frame = try await PostRecordingCompositor.makeFrameImage(
        time: CMTime(seconds: seconds, preferredTimescale: 600),
        seconds: seconds,
        renderSize: renderSize,
        screenGenerator: screenGenerator,
        webcamGenerator: webcamGenerator,
        project: project
      )
      CGImageDestinationAddImage(destination, frame, frameProperties as CFDictionary)
      PostRecordingExportProgress.update(
        progress,
        phase: renderingGIFPhase,
        fraction: Double(index + 1) / Double(plan.frameCount)
      )
    }

    PostRecordingExportProgress.update(
      progress,
      phase: finalizingGIFPhase,
      fraction: nil
    )
    guard CGImageDestinationFinalize(destination) else {
      throw exportError("Unable to finalize GIF.")
    }
    PostRecordingExportProgress.update(
      progress,
      phase: finalizingGIFPhase,
      fraction: 1
    )
  }

  private static func renderCompositedVisualAsset(
    project: PostRecordingProject,
    options: PostRecordingExportOptions,
    exportState: PostRecordingExportState,
    outputURL: URL,
    progress: PostRecordingExportProgressHandler?
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
        AVVideoColorPropertiesKey: VideoRecordingColorPolicy.videoColorProperties(for: .h264),
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
        kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        kCVImageBufferCGColorSpaceKey as String: VideoRecordingColorPolicy.cgColorSpace(for: .h264)
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

    let renderingVideoPhase = String(localized: "Rendering video...", bundle: AppLocalizer.shared.bundle)
    let finalizingVideoPhase = String(localized: "Finalizing rendered video...", bundle: AppLocalizer.shared.bundle)
    PostRecordingExportProgress.update(
      progress,
      phase: renderingVideoPhase,
      fraction: 0
    )
    for frameIndex in 0..<frameCount {
      while !input.isReadyForMoreMediaData {
        try await Task.sleep(nanoseconds: 8_000_000)
      }

      var maybeBuffer: CVPixelBuffer?
      let status = CVPixelBufferPoolCreatePixelBuffer(nil, pixelBufferPool, &maybeBuffer)
      guard status == kCVReturnSuccess, let pixelBuffer = maybeBuffer else {
        throw exportError("Unable to allocate video frame.")
      }
      VideoRecordingColorPolicy.tag(pixelBuffer, for: .h264)

      let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(frameIndex))
      let seconds = Double(exportState.trimStartMS) / 1000.0 + CMTimeGetSeconds(presentationTime)
      try await PostRecordingCompositor.renderFrame(
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
      PostRecordingExportProgress.update(
        progress,
        phase: renderingVideoPhase,
        fraction: 0.75 * Double(frameIndex + 1) / Double(frameCount)
      )
    }

    PostRecordingExportProgress.update(
      progress,
      phase: finalizingVideoPhase,
      fraction: nil
    )
    input.markAsFinished()
    nonisolated(unsafe) let unsafeWriter = writer
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      unsafeWriter.finishWriting {
        continuation.resume()
      }
    }
    switch unsafeWriter.status {
    case .completed:
      PostRecordingExportProgress.update(
        progress,
        phase: finalizingVideoPhase,
        fraction: 0.75
      )
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
    outputURL: URL,
    progress: PostRecordingExportProgressHandler?
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

    let exportSession = try AVAssetExportSession.recordingExport(
      asset: composition,
      options: options,
      container: container,
      outputURL: outputURL,
      timeRange: CMTimeRange(start: .zero, duration: duration),
      estimatedDurationSeconds: CMTimeGetSeconds(duration),
      creationError: exportError("Unable to create final export session.")
    )
    try await exportChecked(
      exportSession,
      phase: String(localized: "Saving video...", bundle: AppLocalizer.shared.bundle),
      progressBase: 0.75,
      progressScale: 0.25,
      progress: progress
    )
  }

  private static func exportChecked(
    _ exportSession: AVAssetExportSession,
    phase: String,
    progressBase: Double,
    progressScale: Double,
    progress: PostRecordingExportProgressHandler?
  ) async throws {
    PostRecordingExportProgress.update(progress, phase: phase, fraction: progressBase)
    let progressTask = PostRecordingExportProgress.pollExportSession(
      exportSession,
      phase: phase,
      progressBase: progressBase,
      progressScale: progressScale,
      progress: progress
    )
    defer {
      progressTask?.cancel()
    }
    nonisolated(unsafe) let unsafeExportSession = exportSession
    try await unsafeExportSession.exportChecked()
    PostRecordingExportProgress.update(progress, phase: phase, fraction: progressBase + progressScale)
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
    CaptureTemporaryFiles.exportURL(pathExtension: pathExtension)
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
