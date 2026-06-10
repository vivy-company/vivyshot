import CoreGraphics
import CoreImage
import Foundation

enum ImageRegionEffect {
  private static let pixelateBlockSize = 12
  private static let blurRadius = 4
  private static let context = CIContext()

  static func pixelate(_ image: CGImage, rect: CGRect) -> CGImage? {
    apply(to: image, rect: rect) { input, region in
      input
        .cropped(to: region)
        .applyingFilter("CIPixellate", parameters: [
          kCIInputScaleKey: pixelateBlockSize,
          kCIInputCenterKey: CIVector(x: region.midX, y: region.midY)
        ])
        .cropped(to: region)
    }
  }

  static func blur(_ image: CGImage, rect: CGRect) -> CGImage? {
    apply(to: image, rect: rect) { input, region in
      let sample = region
        .insetBy(dx: -CGFloat(blurRadius), dy: -CGFloat(blurRadius))
        .intersection(input.extent)

      return input
        .cropped(to: sample)
        .clampedToExtent()
        .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: blurRadius])
        .cropped(to: region)
    }
  }

  private static func apply(
    to image: CGImage,
    rect: CGRect,
    effect: (CIImage, CGRect) -> CIImage?
  ) -> CGImage? {
    let input = CIImage(cgImage: image)
    let region = coreImageRect(fromTopLeftImageRect: rect, imageHeight: image.height).intersection(input.extent)
    guard !region.isNull, !region.isEmpty, let filteredRegion = effect(input, region) else {
      return nil
    }

    let output = filteredRegion.composited(over: input)
    return context.createCGImage(output, from: input.extent)
  }

  private static func coreImageRect(fromTopLeftImageRect rect: CGRect, imageHeight: Int) -> CGRect {
    let standardized = rect.standardized
    return CGRect(
      x: standardized.minX.rounded(.down),
      y: CGFloat(imageHeight) - standardized.maxY.rounded(.up),
      width: standardized.width.rounded(.up),
      height: standardized.height.rounded(.up)
    )
  }
}
