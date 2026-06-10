import CoreGraphics

/// Aspect-ratio lock for webcam overlay resizing.
enum WebcamAspectRatio: Int, CaseIterable, Identifiable {
  case square = 0
  case fourThree = 1
  case sixteenNine = 2

  var id: Int { rawValue }

  var widthToHeight: CGFloat {
    switch self {
    case .square:
      return Self.squareRatio
    case .fourThree:
      return Self.fourThreeRatio
    case .sixteenNine:
      return Self.sixteenNineRatio
    }
  }

  func constrainedFrame(_ frame: CGRect, in container: CGRect, minimumSize: CGSize) -> CGRect {
    guard !container.isNull, !container.isEmpty, widthToHeight > 0 else {
      return frame.standardized
    }

    let source = frame.standardized
    let minWidth = min(max(1, minimumSize.width), container.width)
    let minHeight = min(max(1, minimumSize.height), container.height)
    var width = max(minWidth, min(source.width, container.width))
    var height = width / widthToHeight

    if height < minHeight {
      height = minHeight
      width = height * widthToHeight
    }

    if height > container.height {
      height = container.height
      width = height * widthToHeight
    }

    if width > container.width {
      width = container.width
      height = width / widthToHeight
    }

    let x = min(max(container.minX, source.midX - width * 0.5), container.maxX - width)
    let y = min(max(container.minY, source.midY - height * 0.5), container.maxY - height)
    return CGRect(x: x, y: y, width: width, height: height).integral
  }

  /// Square camera crop used by circle overlays.
  private static let squareRatio: CGFloat = 1
  /// Classic webcam aspect ratio.
  private static let fourThreeRatio: CGFloat = 4.0 / 3.0
  /// Widescreen webcam aspect ratio.
  private static let sixteenNineRatio: CGFloat = 16.0 / 9.0
}

/// Visual mask used by the webcam overlay.
enum WebcamShape: Int, CaseIterable, Identifiable {
  case roundedRect = 0
  case circle = 1

  var id: Int { rawValue }
}

enum RecordingOverlayFrameGeometry {
  static let defaultNormalizedFallbackFrame = CGRect(x: 0, y: 0, width: 0.2, height: 0.2)
  static let defaultMinimumNormalizedDimension: CGFloat = 0.04

  static func normalizedUnitFrame(
    _ frame: CGRect,
    fallback: CGRect = defaultNormalizedFallbackFrame,
    minimumDimension: CGFloat = defaultMinimumNormalizedDimension
  ) -> CGRect {
    let source = frame.isNull || frame.isEmpty ? fallback : frame.standardized
    let width = max(minimumDimension, min(1, source.width))
    let height = max(minimumDimension, min(1, source.height))
    let x = max(0, min(1 - width, source.minX))
    let y = max(0, min(1 - height, source.minY))
    return CGRect(x: x, y: y, width: width, height: height)
  }

  static func resizedNormalizedUnitFrame(
    _ frame: CGRect,
    width: CGFloat,
    height: CGFloat,
    minimumDimension: CGFloat = defaultMinimumNormalizedDimension
  ) -> CGRect {
    let normalizedWidth = max(minimumDimension, min(1, width))
    let normalizedHeight = max(minimumDimension, min(1, height))
    let source = normalizedUnitFrame(
      frame,
      fallback: CGRect(x: 0, y: 0, width: normalizedWidth, height: normalizedHeight),
      minimumDimension: minimumDimension
    )
    let x = max(0, min(1 - normalizedWidth, source.midX - normalizedWidth * 0.5))
    let y = max(0, min(1 - normalizedHeight, source.midY - normalizedHeight * 0.5))
    return CGRect(x: x, y: y, width: normalizedWidth, height: normalizedHeight)
  }

  static func resolvedOverlayFrame(_ normalized: CGRect, in container: CGRect) -> CGRect {
    guard container.width > 0, container.height > 0 else {
      return .zero
    }

    let source = normalized.standardized
    let width = min(max(container.width * source.width, 36), container.width)
    let height = min(max(container.height * source.height, 28), container.height)
    let x = min(max(container.minX, container.minX + container.width * source.minX), container.maxX - width)
    let y = min(max(container.minY, container.minY + container.height * source.minY), container.maxY - height)
    return CGRect(x: x, y: y, width: width, height: height).integral
  }

  static func resolvedWebcamOverlayFrame(
    _ normalized: CGRect,
    in container: CGRect,
    shape: WebcamShape,
    aspectRatio: WebcamAspectRatio
  ) -> CGRect {
    let frame = resolvedOverlayFrame(normalized, in: container)
    let resolvedAspectRatio = shape == .circle ? WebcamAspectRatio.square : aspectRatio
    return resolvedAspectRatio.constrainedFrame(frame, in: container, minimumSize: CGSize(width: 84, height: 84))
  }

  static func normalizedOverlayFrame(_ frame: CGRect, in container: CGRect) -> CGRect {
    guard container.width > 0, container.height > 0 else {
      return .zero
    }

    let standardized = frame.standardized
    return CGRect(
      x: (standardized.minX - container.minX) / container.width,
      y: (standardized.minY - container.minY) / container.height,
      width: standardized.width / container.width,
      height: standardized.height / container.height
    )
  }

  static func denormalizedOverlayFrame(_ normalized: CGRect, in container: CGRect) -> CGRect {
    CGRect(
      x: container.minX + normalized.minX * container.width,
      y: container.minY + normalized.minY * container.height,
      width: normalized.width * container.width,
      height: normalized.height * container.height
    ).integral
  }

  static func clampedOverlayFrame(
    _ proposed: CGRect,
    in container: CGRect,
    minimumSize: CGSize,
    aspectRatio: WebcamAspectRatio? = nil
  ) -> CGRect {
    guard !container.isNull, !container.isEmpty else {
      return proposed.standardized
    }

    let minWidth = min(max(1, minimumSize.width), container.width)
    let minHeight = min(max(1, minimumSize.height), container.height)
    if let aspectRatio {
      return aspectRatio.constrainedFrame(
        proposed,
        in: container,
        minimumSize: CGSize(width: minWidth, height: minHeight)
      )
    }

    let width = max(minWidth, min(proposed.width, container.width))
    let height = max(minHeight, min(proposed.height, container.height))
    let x = min(max(container.minX, proposed.minX), container.maxX - width)
    let y = min(max(container.minY, proposed.minY), container.maxY - height)
    return CGRect(x: x, y: y, width: width, height: height).integral
  }

  static func resizeCorner(at point: CGPoint, in bounds: CGRect, hitSlop: CGFloat = 14) -> ResizeCorner? {
    let nearLeft = point.x <= bounds.minX + hitSlop
    let nearRight = point.x >= bounds.maxX - hitSlop
    let nearBottom = point.y <= bounds.minY + hitSlop
    let nearTop = point.y >= bounds.maxY - hitSlop

    switch (nearLeft, nearRight, nearBottom, nearTop) {
    case (true, false, false, true): return .topLeft
    case (false, true, false, true): return .topRight
    case (true, false, true, false): return .bottomLeft
    case (false, true, true, false): return .bottomRight
    case (true, false, false, false): return .left
    case (false, true, false, false): return .right
    case (false, false, true, false): return .bottom
    case (false, false, false, true): return .top
    default: return nil
    }
  }

  static func resizedOverlayFrame(
    from start: CGRect,
    corner: ResizeCorner,
    delta: CGSize,
    minimumSize: CGSize
  ) -> CGRect {
    var rect = start.standardized

    switch corner {
    case .topLeft, .left, .bottomLeft:
      let maxX = rect.maxX
      rect.origin.x = min(maxX - minimumSize.width, rect.minX + delta.width)
      rect.size.width = maxX - rect.minX
    case .topRight, .right, .bottomRight:
      rect.size.width = max(minimumSize.width, rect.width + delta.width)
    case .top, .bottom:
      break
    }

    switch corner {
    case .bottomLeft, .bottom, .bottomRight:
      let maxY = rect.maxY
      rect.origin.y = min(maxY - minimumSize.height, rect.minY + delta.height)
      rect.size.height = maxY - rect.minY
    case .topLeft, .top, .topRight:
      rect.size.height = max(minimumSize.height, rect.height + delta.height)
    case .left, .right:
      break
    }

    return rect
  }
}

/// Visual treatment for rendered keystroke overlays.
enum KeystrokeStyle: Int, CaseIterable, Identifiable {
  case compact = 0
  case glass = 1

  var id: Int { rawValue }
}

/// Relative size for keystroke overlay placement.
enum KeystrokeSize: Int, CaseIterable, Identifiable {
  case small = 0
  case medium = 1
  case large = 2

  var id: Int { rawValue }

  var normalizedSize: CGSize {
    switch self {
    case .small:
      return Self.smallNormalizedSize
    case .medium:
      return Self.mediumNormalizedSize
    case .large:
      return Self.largeNormalizedSize
    }
  }

  /// Compact normalized frame for short hotkey labels.
  private static let smallNormalizedSize = CGSize(width: 0.32, height: 0.10)
  /// Default normalized frame for readable keystroke labels.
  private static let mediumNormalizedSize = CGSize(width: 0.40, height: 0.12)
  /// Large normalized frame for presentation-style recordings.
  private static let largeNormalizedSize = CGSize(width: 0.48, height: 0.14)
}
