import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Crops and encodes still screenshots for copy, save, and statistics workflows.
enum ScreenshotImage {
  /// ImageIO expects JPEG quality as 0.0...1.0, while the app UI passes 1...100.
  private static let jpegQualityScale: CGFloat = 100
  private static let minimumJPEGQuality = 1
  private static let maximumJPEGQuality = 100

  /// Returns an integral crop inside the image bounds.
  static func crop(_ image: CGImage, imageRect: CGRect) -> CGImage? {
    guard let cropRect = normalizedCropRect(imageRect, maxWidth: image.width, maxHeight: image.height) else {
      return nil
    }
    return image.cropping(to: cropRect)
  }

  /// Encodes an image as PNG or JPEG.
  static func encode(_ image: CGImage, format: ImageEncodeFormat, jpegQuality: Int = 90) -> Data? {
    let data = NSMutableData()
    let type: CFString = format == .jpeg ? UTType.jpeg.identifier as CFString : UTType.png.identifier as CFString
    guard let destination = CGImageDestinationCreateWithData(data, type, 1, nil) else {
      return nil
    }
    let options: [CFString: Any] = format == .jpeg
      ? [kCGImageDestinationLossyCompressionQuality: CGFloat(max(minimumJPEGQuality, min(maximumJPEGQuality, jpegQuality))) / jpegQualityScale]
      : [:]
    CGImageDestinationAddImage(destination, image, options as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
      return nil
    }
    return data as Data
  }

  /// Crops and encodes in one pass for selection export.
  static func encode(_ image: CGImage, imageRect: CGRect, format: ImageEncodeFormat, jpegQuality: Int = 90) -> Data? {
    guard let cropped = crop(image, imageRect: imageRect) else {
      return nil
    }
    return encode(cropped, format: format, jpegQuality: jpegQuality)
  }

  static func cropScreenRect(
    from image: CGImage,
    captureRectInScreen: CGRect,
    screenFrame: CGRect
  ) -> CGImage? {
    guard let cropRect = imageCropRect(
      forScreenRect: captureRectInScreen,
      screenFrame: screenFrame,
      imageSize: CGSize(width: image.width, height: image.height)
    ) else {
      return nil
    }
    return crop(image, imageRect: cropRect)
  }

  static func imageCropRect(
    forScreenRect captureRectInScreen: CGRect,
    screenFrame: CGRect,
    imageSize: CGSize
  ) -> CGRect? {
    guard screenFrame.width > 0, screenFrame.height > 0, imageSize.width > 0, imageSize.height > 0 else {
      return nil
    }

    let clippedSelection = captureRectInScreen.standardized.intersection(screenFrame)
    guard !clippedSelection.isNull, clippedSelection.width >= 2, clippedSelection.height >= 2 else {
      return nil
    }

    let localRect = clippedSelection.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
    let scaleX = imageSize.width / screenFrame.width
    let scaleY = imageSize.height / screenFrame.height

    var cropRect = CGRect(
      x: floor(localRect.minX * scaleX),
      y: floor(imageSize.height - (localRect.maxY * scaleY)),
      width: ceil(localRect.width * scaleX),
      height: ceil(localRect.height * scaleY)
    )

    let imageBounds = CGRect(origin: .zero, size: imageSize)
    cropRect = cropRect.intersection(imageBounds)
    guard !cropRect.isNull, cropRect.width >= 2, cropRect.height >= 2 else {
      return nil
    }
    return cropRect.integral
  }

  private static func normalizedCropRect(_ imageRect: CGRect, maxWidth: Int, maxHeight: Int) -> CGRect? {
    guard maxWidth > 0, maxHeight > 0 else {
      return nil
    }
    let rect = imageRect.standardized.integral
    let clipped = rect.intersection(CGRect(x: 0, y: 0, width: maxWidth, height: maxHeight))
    guard clipped.width > 0, clipped.height > 0 else {
      return nil
    }
    return clipped
  }
}
