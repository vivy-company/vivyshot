import AppKit
import AVFoundation
import CoreGraphics
import CoreMedia

@MainActor
enum PostRecordingCompositor {
  static func makeFrameImage(
    time: CMTime,
    seconds: Double,
    renderSize: CGSize,
    screenGenerator: AVAssetImageGenerator,
    webcamGenerator: AVAssetImageGenerator?,
    project: PostRecordingProject
  ) async throws -> CGImage {
    let colorSpace = VideoRecordingColorPolicy.cgColorSpace(for: .h264)
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
    try await drawFrame(
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

  static func renderFrame(
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
    let colorSpace = VideoRecordingColorPolicy.cgColorSpace(for: .h264)
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
    try await drawFrame(
      context: context,
      time: time,
      seconds: seconds,
      renderSize: renderSize,
      screenGenerator: screenGenerator,
      webcamGenerator: webcamGenerator,
      project: project
    )
  }

  private static func drawFrame(
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

    let renderPlan = project.videoProject.renderPlan(
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
        guard !project.overlaysBurnedIn else {
          continue
        }
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
        guard !project.overlaysBurnedIn else {
          continue
        }
        drawKeystrokeOverlay(
          context: context,
          renderSize: renderSize,
          item: item
        )
      case .mouseClick:
        drawMouseClickOverlay(
          context: context,
          item: item
        )
      }
    }
  }

  private static func exportError(_ message: String) -> NSError {
    NSError(domain: "VivyShot.Export", code: -200, userInfo: [NSLocalizedDescriptionKey: message])
  }
}
