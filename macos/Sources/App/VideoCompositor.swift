import AppKit
import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import QuartzCore
import UniformTypeIdentifiers

enum VideoCompositor {
  private struct WebcamOverlayLayout {
    let transform: CGAffineTransform
    let frame: CGRect
  }

  static func exportCompositeMP4(
    sourceURL: URL,
    trimRange: CMTimeRange,
    overlay: VideoExportOverlayConfiguration,
    includeAudio: Bool = true,
    outputURL: URL
  ) async throws {
    let sourceAsset = AVAsset(url: sourceURL)
    guard let sourceVideoTrack = sourceAsset.tracks(withMediaType: .video).first else {
      throw NSError(
        domain: "com.vivyshot.video",
        code: -80,
        userInfo: [NSLocalizedDescriptionKey: "Source recording has no video track."]
      )
    }

    let composition = AVMutableComposition()
    guard let baseTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
      throw NSError(
        domain: "com.vivyshot.video",
        code: -81,
        userInfo: [NSLocalizedDescriptionKey: "Unable to create composition video track."]
      )
    }
    try baseTrack.insertTimeRange(trimRange, of: sourceVideoTrack, at: .zero)
    baseTrack.preferredTransform = sourceVideoTrack.preferredTransform

    if includeAudio {
      for sourceAudioTrack in sourceAsset.tracks(withMediaType: .audio) {
        guard let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
          continue
        }
        try? audioTrack.insertTimeRange(trimRange, of: sourceAudioTrack, at: .zero)
      }
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
          // Keep webcam as the top-most layer in the composition.
          layerInstructions.append(webcamLayerInstruction)
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
        textOverlays: overlay.textOverlays,
        trimStartSeconds: trimRange.start.seconds,
        webcamLayout: webcamLayout,
        webcamShape: overlay.webcamOverlayShape
      )
    }

    guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
      throw NSError(
        domain: "com.vivyshot.video",
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
    textOverlays: [VideoTextOverlayClip],
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

    let textMaxWidth = renderSize.width * 0.78
    let textHeight = max(34, min(62, renderSize.height * 0.09))
    let textY = max(20, renderSize.height * 0.12)
    for clip in textOverlays {
      let start = clip.startSeconds - trimStartSeconds
      let end = clip.endSeconds - trimStartSeconds
      let displayStart = max(0, start)
      let displayEnd = max(displayStart, end)
      guard displayEnd - displayStart >= 0.05 else {
        continue
      }

      let text = clip.text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else {
        continue
      }

      let estimatedWidth = min(textMaxWidth, CGFloat(max(90, text.count * 14)))
      let layer = CATextLayer()
      layer.string = text
      layer.fontSize = max(15, textHeight * 0.42)
      layer.alignmentMode = .center
      layer.foregroundColor = NSColor.white.cgColor
      layer.backgroundColor = NSColor.black.withAlphaComponent(0.58).cgColor
      layer.cornerRadius = textHeight * 0.22
      layer.frame = CGRect(
        x: (renderSize.width - estimatedWidth) * 0.5,
        y: textY,
        width: estimatedWidth,
        height: textHeight
      )
      layer.contentsScale = 2
      layer.opacity = 0
      parentLayer.addSublayer(layer)

      let fade = CAKeyframeAnimation(keyPath: "opacity")
      fade.values = [0, 1, 1, 0]
      fade.keyTimes = [0, 0.08, 0.92, 1]
      fade.duration = max(0.1, displayEnd - displayStart)
      fade.beginTime = AVCoreAnimationBeginTimeAtZero + displayStart
      fade.fillMode = .forwards
      fade.isRemovedOnCompletion = false
      layer.add(fade, forKey: "text-fade-\(clip.id.uuidString)")
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

  static func renderGIF(
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
              domain: "com.vivyshot.video",
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
              domain: "com.vivyshot.video",
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

@MainActor
extension AVAssetExportSession {
  func vs_export() async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      exportAsynchronously {
        switch self.status {
        case .completed:
          continuation.resume(returning: ())
        case .failed:
          continuation.resume(throwing: self.error ?? NSError(
            domain: "com.vivyshot.video",
            code: -43,
            userInfo: [NSLocalizedDescriptionKey: "Video export failed."]
          ))
        case .cancelled:
          continuation.resume(throwing: NSError(
            domain: "com.vivyshot.video",
            code: -44,
            userInfo: [NSLocalizedDescriptionKey: "Video export cancelled."]
          ))
        default:
          continuation.resume(throwing: NSError(
            domain: "com.vivyshot.video",
            code: -45,
            userInfo: [NSLocalizedDescriptionKey: "Video export ended in unexpected state."]
          ))
        }
      }
    }
  }
}
