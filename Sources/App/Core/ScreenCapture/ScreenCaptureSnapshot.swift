import CoreGraphics
import Foundation
import ScreenCaptureKit

enum ScreenCaptureSnapshot {
  static func captureImage(inCocoaScreenRect rect: CGRect) async throws -> CGImage {
    guard #available(macOS 15.2, *) else {
      throw NSError(
        domain: "com.vivyshot.capture",
        code: -10,
        userInfo: [NSLocalizedDescriptionKey: "Screen capture requires macOS 15.2 or newer."]
      )
    }

    return try await withCheckedThrowingContinuation { continuation in
      let captureRect = DisplayCoordinateConversion.cocoaRectToCGDisplayRect(rect)
      SCScreenshotManager.captureImage(in: captureRect) { image, error in
        if let error {
          continuation.resume(throwing: error)
          return
        }

        guard let image else {
          continuation.resume(
            throwing: NSError(
              domain: "com.vivyshot.capture",
              code: -11,
              userInfo: [NSLocalizedDescriptionKey: "No image returned by ScreenCaptureKit."]
            )
          )
          return
        }

        continuation.resume(returning: image)
      }
    }
  }

  static func captureWindowImage(windowID: CGWindowID, includesShadow: Bool) async throws -> CGImage {
    guard #available(macOS 15.2, *) else {
      throw NSError(
        domain: "com.vivyshot.capture",
        code: -10,
        userInfo: [NSLocalizedDescriptionKey: "Screen capture requires macOS 15.2 or newer."]
      )
    }

    let content = try await SCShareableContent.current
    guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
      throw NSError(
        domain: "com.vivyshot.capture",
        code: -12,
        userInfo: [NSLocalizedDescriptionKey: "Selected window is no longer available."]
      )
    }

    let filter = SCContentFilter(desktopIndependentWindow: window)
    let configuration = SCStreamConfiguration()
    configuration.showsCursor = false
    configuration.ignoreShadowsSingleWindow = !includesShadow
    let scale = CGFloat(filter.pointPixelScale)
    configuration.width = max(2, Int((filter.contentRect.width * scale).rounded()))
    configuration.height = max(2, Int((filter.contentRect.height * scale).rounded()))

    return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
  }

  static func captureImageIfAvailable(
    inCocoaScreenRect rect: CGRect,
    requiresPermission: Bool = false
  ) async -> CGImage? {
    guard #available(macOS 15.2, *) else {
      return nil
    }
    if requiresPermission, !ScreenRecordingPermission.isGranted {
      return nil
    }
    return try? await captureImage(inCocoaScreenRect: rect)
  }
}
