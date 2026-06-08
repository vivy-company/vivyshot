import CoreGraphics
import Foundation
import VivyShotKit

private final class CaptureScreenshotContinuationBox {
  let continuation: CheckedContinuation<CGImage, Error>

  init(_ continuation: CheckedContinuation<CGImage, Error>) {
    self.continuation = continuation
  }
}

private let captureScreenshotCallback:
  @convention(c) (UnsafeMutableRawPointer?, Int32, vs_capture_captured_image) -> Void = { userData, status, image in
    guard let userData else {
      vs_capture_captured_image_free(image)
      return
    }
    let box = Unmanaged<CaptureScreenshotContinuationBox>.fromOpaque(userData).takeRetainedValue()
    defer {
      vs_capture_captured_image_free(image)
    }
    guard status == VS_CAPTURE_STATUS_OK else {
      box.continuation.resume(throwing: CaptureScreenshotError(status: Int(status)))
      return
    }
    do {
      box.continuation.resume(returning: try CaptureScreenshotClient.makeImage(from: image))
    } catch {
      box.continuation.resume(throwing: error)
    }
  }

struct CaptureScreenshotClient {
  static func captureImage(in rect: CGRect) async throws -> CGImage {
    guard #available(macOS 15.2, *) else {
      throw CaptureScreenshotError(status: VS_CAPTURE_STATUS_UNSUPPORTED_OS_VERSION)
    }

    return try await withCheckedThrowingContinuation { continuation in
      let box = Unmanaged.passRetained(CaptureScreenshotContinuationBox(continuation))
      let captureRect = vs_capture_rect(
        x: rect.origin.x,
        y: rect.origin.y,
        width: rect.width,
        height: rect.height
      )
      vs_capture_screenshot(captureRect, box.toOpaque(), captureScreenshotCallback)
    }
  }

  fileprivate static func makeImage(from image: vs_capture_captured_image) throws -> CGImage {
    let width = Int(image.width)
    let height = Int(image.height)
    let stride = Int(image.bytes_per_row)
    let byteCount = Int(image.data_len)

    guard image.pixel_format == VS_CAPTURE_PIXEL_FORMAT_BGRA8_PREMULTIPLIED_FIRST,
          width > 0,
          height > 0,
          stride >= width * 4,
          byteCount >= stride * height,
          let dataPointer = image.data
    else {
      throw CaptureScreenshotError(status: VS_CAPTURE_STATUS_INVALID_ARGUMENT)
    }

    let data = Data(bytes: dataPointer, count: byteCount)
    guard let provider = CGDataProvider(data: data as CFData) else {
      throw CaptureScreenshotError(status: VS_CAPTURE_STATUS_INTERNAL_PLATFORM_ERROR)
    }
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue

    guard let cgImage = CGImage(
      width: width,
      height: height,
      bitsPerComponent: 8,
      bitsPerPixel: 32,
      bytesPerRow: stride,
      space: colorSpace,
      bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
      provider: provider,
      decode: nil,
      shouldInterpolate: false,
      intent: .defaultIntent
    ) else {
      throw CaptureScreenshotError(status: VS_CAPTURE_STATUS_INTERNAL_PLATFORM_ERROR)
    }
    return cgImage
  }
}

private struct CaptureScreenshotError: LocalizedError {
  let status: Int

  var errorDescription: String? {
    switch status {
    case VS_CAPTURE_STATUS_NULL_POINTER, VS_CAPTURE_STATUS_INVALID_ARGUMENT:
      return "The capture backend received an invalid screenshot request."
    case VS_CAPTURE_STATUS_PERMISSION_DENIED:
      return "Screen recording permission was denied."
    case VS_CAPTURE_STATUS_PERMISSION_NOT_DETERMINED:
      return "Screen recording permission has not been granted yet."
    case VS_CAPTURE_STATUS_UNSUPPORTED_OS_VERSION:
      return "Screenshot capture requires macOS 15.2 or newer."
    case VS_CAPTURE_STATUS_SELECTION_TOO_SMALL:
      return "Selected region is too small to capture."
    case VS_CAPTURE_STATUS_UNSUPPORTED_PLATFORM:
      return "The capture backend is not available on this platform."
    default:
      return "The capture backend failed with status \(status)."
    }
  }
}
