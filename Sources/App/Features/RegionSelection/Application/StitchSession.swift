import CoreGraphics
import Foundation

/// Incremental image-stitching session for long screenshot capture.
final class StitchSession {
  private var merged: CGImage?
  private var segmentCount = 1

  init?() {}

  func reset(baseSegmentCount: Int = 1) -> Bool {
    merged = nil
    segmentCount = max(1, baseSegmentCount)
    return true
  }

  func setBaseImage(_ image: CGImage, baseSegmentCount: Int = 1) -> Bool {
    merged = image
    segmentCount = max(1, baseSegmentCount)
    return true
  }

  func pushFrame(_ frame: CGImage) -> StitchSessionResult? {
    if merged == nil {
      merged = frame
    }
    return result(rows: frame.height)
  }

  func pushFrameAndMerge(_ frame: CGImage) -> (StitchSessionResult, CGImage?)? {
    if let current = merged, let stacked = Self.stack(top: current, bottom: frame) {
      merged = stacked
    } else {
      merged = frame
    }
    segmentCount += 1
    return (result(rows: frame.height), merged)
  }

  func mergedImage() -> CGImage? {
    merged
  }

  private func result(rows: Int) -> StitchSessionResult {
    StitchSessionResult(
      accepted: true,
      rows: max(0, rows),
      side: 1,
      score: 1,
      directionLocked: true,
      expectedRows: max(0, rows),
      segmentCount: segmentCount,
      scrollDirectionSign: 1
    )
  }

  private static func stack(top: CGImage, bottom: CGImage) -> CGImage? {
    let width = max(top.width, bottom.width)
    let height = top.height + bottom.height
    guard
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else {
      return nil
    }
    context.interpolationQuality = .high
    context.draw(top, in: CGRect(x: 0, y: CGFloat(bottom.height), width: CGFloat(top.width), height: CGFloat(top.height)))
    context.draw(bottom, in: CGRect(x: 0, y: 0, width: CGFloat(bottom.width), height: CGFloat(bottom.height)))
    return context.makeImage()
  }
}
