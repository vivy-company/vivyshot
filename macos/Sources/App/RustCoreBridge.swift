import AppKit
import CoreGraphics
import Foundation

struct TextAnnotationStyle {
  let fontSize: CGFloat
  let color: NSColor

  static let `default` = TextAnnotationStyle(
    fontSize: 16,
    color: .white
  )
}

struct RustAnnotationInfo {
  let index: Int
  let kind: Int
  let bounds: CGRect

  func contains(_ point: CGPoint) -> Bool {
    let x = point.x
    let y = point.y
    return x >= bounds.minX && x <= bounds.maxX && y >= bounds.minY && y <= bounds.maxY
  }
}

struct RustVideoSessionConfig {
  let frameRate: Int
  let captureSystemAudio: Bool
  let captureMicrophone: Bool
  let showWebcam: Bool
  let highlightMouseClicks: Bool
  let highlightKeystrokes: Bool
}

struct RustVideoExportPlan {
  let trimStartMS: Int
  let trimEndMS: Int
  let keyEventCount: Int
  let clickEventCount: Int
}

@MainActor
final class RustCoreBridge {
  static let shared = RustCoreBridge()

  private init() {}

  func makeSession(image: CGImage) -> RustDocumentSession? {
    RustDocumentSession(image: image)
  }

  func makeVideoSession(config: RustVideoSessionConfig) -> RustVideoSession? {
    RustVideoSession(config: config)
  }
}

final class RustVideoSession {
  private let handle: UnsafeMutableRawPointer

  init?(config: RustVideoSessionConfig) {
    let rawConfig = vs_video_session_config(
      frame_rate: UInt32(max(1, config.frameRate)),
      capture_system_audio: config.captureSystemAudio,
      capture_microphone: config.captureMicrophone,
      show_webcam: config.showWebcam,
      highlight_mouse_clicks: config.highlightMouseClicks,
      highlight_keystrokes: config.highlightKeystrokes
    )
    guard let rawHandle = vs_video_session_create(rawConfig) else {
      return nil
    }
    handle = rawHandle
  }

  deinit {
    vs_video_session_destroy(handle)
  }

  func addKeyEvent(timestampNS: UInt64, token: String) -> Bool {
    let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return false
    }

    let utf8 = Array(trimmed.utf8)
    return utf8.withUnsafeBytes { raw in
      guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
        return false
      }
      let event = vs_video_key_event(
        timestamp_ns: timestampNS,
        token_ptr: base,
        token_len: UInt(raw.count)
      )
      return vs_video_session_add_key_event(handle, event) == 0
    }
  }

  func addClickEvent(timestampNS: UInt64, normalizedX: CGFloat, normalizedY: CGFloat, button: UInt32) -> Bool {
    let event = vs_video_click_event(
      timestamp_ns: timestampNS,
      normalized_x: Float(normalizedX),
      normalized_y: Float(normalizedY),
      button: button
    )
    return vs_video_session_add_click_event(handle, event) == 0
  }

  func setTrim(startMS: Int, endMS: Int) -> Bool {
    guard startMS >= 0, endMS >= 0 else {
      return false
    }
    return vs_video_session_set_trim(handle, UInt32(startMS), UInt32(endMS)) == 0
  }

  func exportPlan() -> RustVideoExportPlan? {
    var raw = vs_video_export_plan(trim_start_ms: 0, trim_end_ms: 0, key_event_count: 0, click_event_count: 0)
    guard vs_video_session_get_export_plan(handle, &raw) == 0 else {
      return nil
    }
    return RustVideoExportPlan(
      trimStartMS: Int(raw.trim_start_ms),
      trimEndMS: Int(raw.trim_end_ms),
      keyEventCount: Int(raw.key_event_count),
      clickEventCount: Int(raw.click_event_count)
    )
  }
}

final class RustDocumentSession {
  private let handle: UnsafeMutableRawPointer
  private let width: Int
  private let height: Int
  private let stride: Int
  private var outputPixels: [UInt8]

  init?(image: CGImage) {
    guard let raster = RasterImage.from(cgImage: image) else {
      return nil
    }

    let createdHandle: UnsafeMutableRawPointer? = raster.pixels.withUnsafeBytes { raw in
      guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
        return nil
      }

      return vs_create_document_from_bgra(
        UInt32(raster.width),
        UInt32(raster.height),
        UInt32(raster.stride),
        base,
        UInt(raw.count)
      )
    }

    guard let createdHandle else {
      return nil
    }

    self.handle = createdHandle
    self.width = raster.width
    self.height = raster.height
    self.stride = raster.stride
    self.outputPixels = raster.pixels

    let renderStatus = outputPixels.withUnsafeMutableBytes { raw in
      guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
        return Int32(-1)
      }
      return vs_render_full(handle, base, UInt(raw.count))
    }

    guard renderStatus == 0 else {
      vs_destroy_document(createdHandle)
      return nil
    }
  }

  deinit {
    vs_destroy_document(handle)
  }

  func currentImage() -> CGImage? {
    RasterImage(width: width, height: height, stride: stride, pixels: outputPixels).toCGImage()
  }

  func addRect(
    imageRect: CGRect,
    color: NSColor = .systemOrange,
    strokeWidth: UInt32 = 4
  ) -> CGImage? {
    let cmd = makeRectCommand(from: imageRect, color: color, strokeWidth: strokeWidth)
    guard vs_add_rect(handle, cmd) == 0 else {
      return nil
    }

    guard renderDirty() else {
      return nil
    }

    return currentImage()
  }

  func addFilledRect(
    imageRect: CGRect,
    color: NSColor = .systemOrange
  ) -> CGImage? {
    let cmd = makeRectCommand(from: imageRect, color: color, strokeWidth: 1)
    guard vs_add_filled_rect(handle, cmd) == 0 else {
      return nil
    }

    guard renderDirty() else {
      return nil
    }

    return currentImage()
  }

  func addCircle(
    imageRect: CGRect,
    color: NSColor = .systemOrange,
    strokeWidth: UInt32 = 4
  ) -> CGImage? {
    let cmd = makeEllipseCommand(from: imageRect, color: color, strokeWidth: strokeWidth)
    guard vs_add_ellipse(handle, cmd) == 0 else {
      return nil
    }

    guard renderDirty() else {
      return nil
    }

    return currentImage()
  }

  func addFilledCircle(
    imageRect: CGRect,
    color: NSColor = .systemOrange
  ) -> CGImage? {
    let cmd = makeEllipseCommand(from: imageRect, color: color, strokeWidth: 1)
    guard vs_add_filled_ellipse(handle, cmd) == 0 else {
      return nil
    }

    guard renderDirty() else {
      return nil
    }

    return currentImage()
  }

  func addLine(
    from start: CGPoint,
    to end: CGPoint,
    color: NSColor = .systemOrange,
    strokeWidth: UInt32 = 4
  ) -> CGImage? {
    let cmd = makeLineCommand(from: start, to: end, color: color, strokeWidth: strokeWidth)
    guard vs_add_line(handle, cmd) == 0 else {
      return nil
    }

    guard renderDirty() else {
      return nil
    }

    return currentImage()
  }

  func addPath(
    _ points: [CGPoint],
    color: NSColor = .systemOrange,
    strokeWidth: UInt32 = 6
  ) -> CGImage? {
    let commandPoints = makePathPoints(points)
    guard !commandPoints.isEmpty else {
      return currentImage()
    }

    let style = makePathStyle(color: color, strokeWidth: strokeWidth)
    let status = commandPoints.withUnsafeBufferPointer { buffer in
      guard let base = buffer.baseAddress else {
        return Int32(-1)
      }
      return vs_add_path(handle, base, UInt(buffer.count), style)
    }

    guard status == 0 else {
      return nil
    }

    guard renderDirty() else {
      return nil
    }

    return currentImage()
  }

  func addArrow(
    from start: CGPoint,
    to end: CGPoint,
    color: NSColor = .systemOrange,
    strokeWidth: UInt32 = 5
  ) -> CGImage? {
    let cmd = makeArrowCommand(from: start, to: end, color: color, strokeWidth: strokeWidth)
    guard vs_add_arrow(handle, cmd) == 0 else {
      return nil
    }

    guard renderDirty() else {
      return nil
    }

    return currentImage()
  }

  func addText(_ text: String, at point: CGPoint, style: TextAnnotationStyle) -> CGImage? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return currentImage()
    }

    let cmd = makeTextCommand(at: point, style: style)
    let utf8 = Array(trimmed.utf8)

    let status = utf8.withUnsafeBytes { raw in
      guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
        return Int32(-1)
      }
      return vs_add_text(handle, base, UInt(raw.count), cmd)
    }

    guard status == 0 else {
      return nil
    }

    guard renderDirty() else {
      return nil
    }

    return currentImage()
  }

  func addPixelate(imageRect: CGRect) -> CGImage? {
    let cmd = makePixelateCommand(from: imageRect)
    guard vs_add_pixelate_rect(handle, cmd) == 0 else {
      return nil
    }

    guard renderDirty() else {
      return nil
    }

    return currentImage()
  }

  func addBlur(imageRect: CGRect) -> CGImage? {
    let cmd = makeBlurCommand(from: imageRect)
    guard vs_add_blur_rect(handle, cmd) == 0 else {
      return nil
    }

    guard renderDirty() else {
      return nil
    }

    return currentImage()
  }

  func undo() -> CGImage? {
    let status = vs_undo(handle)
    if status == 1 {
      return currentImage()
    }
    guard status == 0 else {
      return nil
    }

    guard renderDirty() else {
      return nil
    }

    return currentImage()
  }

  func redo() -> CGImage? {
    let status = vs_redo(handle)
    if status == 1 {
      return currentImage()
    }
    guard status == 0 else {
      return nil
    }

    guard renderDirty() else {
      return nil
    }

    return currentImage()
  }

  func listAnnotations() -> [RustAnnotationInfo] {
    var needed: UInt = 0
    let countStatus = vs_list_annotations(handle, nil, 0, &needed)
    guard countStatus == 0, needed > 0 else {
      return []
    }

    var rawInfos = Array(
      repeating: vs_annotation_info(index: 0, kind: 0, x: 0, y: 0, width: 0, height: 0),
      count: Int(needed)
    )
    var totalWritten: UInt = 0
    let listStatus = rawInfos.withUnsafeMutableBufferPointer { buffer in
      guard let base = buffer.baseAddress else {
        return Int32(-1)
      }
      return vs_list_annotations(handle, base, UInt(buffer.count), &totalWritten)
    }

    guard listStatus == 0 else {
      return []
    }

    let outputCount = min(rawInfos.count, Int(totalWritten))
    return rawInfos.prefix(outputCount).map { raw in
      RustAnnotationInfo(
        index: Int(raw.index),
        kind: Int(raw.kind),
        bounds: CGRect(
          x: CGFloat(raw.x),
          y: CGFloat(raw.y),
          width: CGFloat(max(0, raw.width)),
          height: CGFloat(max(0, raw.height))
        )
      )
    }
  }

  func hitTestAnnotation(at point: CGPoint) -> RustAnnotationInfo? {
    let infos = listAnnotations()
    for info in infos.reversed() where info.contains(point) {
      return info
    }
    return nil
  }

  func annotationInfo(index: Int) -> RustAnnotationInfo? {
    guard index >= 0 else {
      return nil
    }
    return listAnnotations().first { $0.index == index }
  }

  func moveAnnotation(index: Int, delta: CGPoint) -> CGImage? {
    let dx = Int32(delta.x.rounded())
    let dy = Int32(delta.y.rounded())
    if dx == 0 && dy == 0 {
      return currentImage()
    }

    guard index >= 0 else {
      return nil
    }

    let status = vs_move_annotation(handle, UInt32(index), dx, dy)
    if status == 1 {
      return currentImage()
    }
    guard status == 0 else {
      return nil
    }

    guard renderDirty() else {
      return nil
    }

    return currentImage()
  }

  func removeAnnotation(index: Int) -> CGImage? {
    guard index >= 0 else {
      return nil
    }

    let status = vs_remove_annotation(handle, UInt32(index))
    if status == 1 {
      return currentImage()
    }
    guard status == 0 else {
      return nil
    }

    guard renderDirty() else {
      return nil
    }

    return currentImage()
  }

  func resizeAnnotation(index: Int, imageRect: CGRect) -> CGImage? {
    guard index >= 0 else {
      return nil
    }

    let normalized = imageRect.standardized

    let x = clampToImageCoordinate(Int(normalized.minX.rounded(.down)), limit: width)
    let y = clampToImageCoordinate(Int(normalized.minY.rounded(.down)), limit: height)
    let maxWidth = max(1, width - x)
    let maxHeight = max(1, height - y)
    let commandWidth = min(maxWidth, max(1, Int(normalized.width.rounded(.up))))
    let commandHeight = min(maxHeight, max(1, Int(normalized.height.rounded(.up))))

    let status = vs_resize_annotation(
      handle,
      UInt32(index),
      Int32(x),
      Int32(y),
      Int32(commandWidth),
      Int32(commandHeight)
    )
    if status == 1 {
      return currentImage()
    }
    guard status == 0 else {
      return nil
    }

    guard renderDirty() else {
      return nil
    }

    return currentImage()
  }

  func copyAnnotations(
    from source: RustDocumentSession,
    oldSelectionInView: CGRect,
    newSelectionInView: CGRect
  ) -> CGImage? {
    let oldSelection = oldSelectionInView.standardized
    let newSelection = newSelectionInView.standardized
    guard oldSelection.width >= 1, oldSelection.height >= 1,
          newSelection.width >= 1, newSelection.height >= 1 else {
      return nil
    }

    let sourceAnnotations = source.listAnnotations()
    guard !sourceAnnotations.isEmpty else {
      return currentImage()
    }

    let oldScaleX = CGFloat(source.width) / oldSelection.width
    let oldScaleY = CGFloat(source.height) / oldSelection.height
    let newScaleX = CGFloat(width) / newSelection.width
    let newScaleY = CGFloat(height) / newSelection.height
    guard oldScaleX > 0, oldScaleY > 0, newScaleX > 0, newScaleY > 0 else {
      return nil
    }

    let scaleX = Float(newScaleX / oldScaleX)
    let scaleY = Float(newScaleY / oldScaleY)
    let translateX = Float((oldSelection.minX - newSelection.minX) * newScaleX)
    let translateY = Float((newSelection.maxY - oldSelection.maxY) * newScaleY)

    let status = vs_copy_annotations_affine(
      handle,
      source.handle,
      scaleX,
      scaleY,
      translateX,
      translateY
    )
    guard status == 0 else {
      return nil
    }

    guard renderDirty() else {
      return nil
    }

    return currentImage()
  }

  private func renderDirty() -> Bool {
    var dirty = vs_dirty_rect(x: 0, y: 0, width: 0, height: 0)
    var written: UInt = 0

    let status = outputPixels.withUnsafeMutableBytes { raw in
      guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
        return Int32(-1)
      }

      return vs_render_dirty(
        handle,
        base,
        UInt(raw.count),
        &dirty,
        1,
        &written
      )
    }

    return status == 0
  }

  private func makeRectCommand(
    from imageRect: CGRect,
    color: NSColor,
    strokeWidth: UInt32
  ) -> vs_rect_command {
    let normalized = imageRect.standardized

    let x = clampToImageCoordinate(Int(normalized.minX.rounded(.down)), limit: width)
    let y = clampToImageCoordinate(Int(normalized.minY.rounded(.down)), limit: height)

    let maxWidth = max(1, width - x)
    let maxHeight = max(1, height - y)
    let commandWidth = min(maxWidth, max(1, Int(normalized.width.rounded(.up))))
    let commandHeight = min(maxHeight, max(1, Int(normalized.height.rounded(.up))))

    let rgba = colorComponents(color)

    return vs_rect_command(
      x: Int32(x),
      y: Int32(y),
      width: Int32(commandWidth),
      height: Int32(commandHeight),
      stroke_width: strokeWidth,
      r: rgba.r,
      g: rgba.g,
      b: rgba.b,
      a: rgba.a
    )
  }

  private func makeLineCommand(
    from start: CGPoint,
    to end: CGPoint,
    color: NSColor,
    strokeWidth: UInt32
  ) -> vs_line_command {
    let sx = clampToImageCoordinate(Int(start.x.rounded()), limit: width)
    let sy = clampToImageCoordinate(Int(start.y.rounded()), limit: height)
    let ex = clampToImageCoordinate(Int(end.x.rounded()), limit: width)
    let ey = clampToImageCoordinate(Int(end.y.rounded()), limit: height)
    let rgba = colorComponents(color)

    return vs_line_command(
      x0: Int32(sx),
      y0: Int32(sy),
      x1: Int32(ex),
      y1: Int32(ey),
      stroke_width: strokeWidth,
      r: rgba.r,
      g: rgba.g,
      b: rgba.b,
      a: rgba.a
    )
  }

  private func makeEllipseCommand(
    from imageRect: CGRect,
    color: NSColor,
    strokeWidth: UInt32
  ) -> vs_ellipse_command {
    let normalized = imageRect.standardized

    let x = clampToImageCoordinate(Int(normalized.minX.rounded(.down)), limit: width)
    let y = clampToImageCoordinate(Int(normalized.minY.rounded(.down)), limit: height)

    let maxWidth = max(1, width - x)
    let maxHeight = max(1, height - y)
    let commandWidth = min(maxWidth, max(1, Int(normalized.width.rounded(.up))))
    let commandHeight = min(maxHeight, max(1, Int(normalized.height.rounded(.up))))

    let rgba = colorComponents(color)

    return vs_ellipse_command(
      x: Int32(x),
      y: Int32(y),
      width: Int32(commandWidth),
      height: Int32(commandHeight),
      stroke_width: strokeWidth,
      r: rgba.r,
      g: rgba.g,
      b: rgba.b,
      a: rgba.a
    )
  }

  private func makeArrowCommand(
    from start: CGPoint,
    to end: CGPoint,
    color: NSColor,
    strokeWidth: UInt32
  ) -> vs_arrow_command {
    let sx = clampToImageCoordinate(Int(start.x.rounded()), limit: width)
    let sy = clampToImageCoordinate(Int(start.y.rounded()), limit: height)
    let ex = clampToImageCoordinate(Int(end.x.rounded()), limit: width)
    let ey = clampToImageCoordinate(Int(end.y.rounded()), limit: height)
    let rgba = colorComponents(color)

    return vs_arrow_command(
      x0: Int32(sx),
      y0: Int32(sy),
      x1: Int32(ex),
      y1: Int32(ey),
      stroke_width: strokeWidth,
      r: rgba.r,
      g: rgba.g,
      b: rgba.b,
      a: rgba.a
    )
  }

  private func makePathStyle(color: NSColor, strokeWidth: UInt32) -> vs_path_style {
    let rgba = colorComponents(color)
    return vs_path_style(
      stroke_width: max(1, strokeWidth),
      r: rgba.r,
      g: rgba.g,
      b: rgba.b,
      a: rgba.a
    )
  }

  private func makePathPoints(_ points: [CGPoint]) -> [vs_point_i32] {
    var output: [vs_point_i32] = []
    output.reserveCapacity(points.count)

    var lastX = Int32.min
    var lastY = Int32.min
    for point in points {
      let x = Int32(clampToImageCoordinate(Int(point.x.rounded()), limit: width))
      let y = Int32(clampToImageCoordinate(Int(point.y.rounded()), limit: height))
      if x == lastX, y == lastY {
        continue
      }
      output.append(vs_point_i32(x: x, y: y))
      lastX = x
      lastY = y
    }

    return output
  }

  private func makeTextCommand(at point: CGPoint, style: TextAnnotationStyle) -> vs_text_command {
    let x = clampToImageCoordinate(Int(point.x.rounded()), limit: width)
    let y = clampToImageCoordinate(Int(point.y.rounded()), limit: height)
    let color = colorComponents(style.color)
    let fontPx = UInt32(clampToRange(Int(style.fontSize.rounded()), min: 8, max: 96))

    return vs_text_command(
      x: Int32(x),
      y: Int32(y),
      font_px: fontPx,
      r: color.r,
      g: color.g,
      b: color.b,
      a: color.a
    )
  }

  private func makePixelateCommand(from imageRect: CGRect) -> vs_pixelate_rect_command {
    let normalized = imageRect.standardized

    let x = clampToImageCoordinate(Int(normalized.minX.rounded(.down)), limit: width)
    let y = clampToImageCoordinate(Int(normalized.minY.rounded(.down)), limit: height)

    let maxWidth = max(1, width - x)
    let maxHeight = max(1, height - y)
    let commandWidth = min(maxWidth, max(1, Int(normalized.width.rounded(.up))))
    let commandHeight = min(maxHeight, max(1, Int(normalized.height.rounded(.up))))

    return vs_pixelate_rect_command(
      x: Int32(x),
      y: Int32(y),
      width: Int32(commandWidth),
      height: Int32(commandHeight),
      block_size: 12
    )
  }

  private func makeBlurCommand(from imageRect: CGRect) -> vs_blur_rect_command {
    let normalized = imageRect.standardized

    let x = clampToImageCoordinate(Int(normalized.minX.rounded(.down)), limit: width)
    let y = clampToImageCoordinate(Int(normalized.minY.rounded(.down)), limit: height)

    let maxWidth = max(1, width - x)
    let maxHeight = max(1, height - y)
    let commandWidth = min(maxWidth, max(1, Int(normalized.width.rounded(.up))))
    let commandHeight = min(maxHeight, max(1, Int(normalized.height.rounded(.up))))

    return vs_blur_rect_command(
      x: Int32(x),
      y: Int32(y),
      width: Int32(commandWidth),
      height: Int32(commandHeight),
      radius: 4
    )
  }

  private func clampToImageCoordinate(_ value: Int, limit: Int) -> Int {
    guard limit > 0 else {
      return 0
    }
    return min(max(0, value), limit - 1)
  }

  private func clampToRange(_ value: Int, min lower: Int, max upper: Int) -> Int {
    Swift.max(lower, Swift.min(value, upper))
  }

  private func colorComponents(_ color: NSColor) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
    guard let rgb = color.usingColorSpace(.deviceRGB) else {
      return (255, 255, 255, 245)
    }

    var r: CGFloat = 1
    var g: CGFloat = 1
    var b: CGFloat = 1
    var a: CGFloat = 1
    rgb.getRed(&r, green: &g, blue: &b, alpha: &a)

    return (
      uint8FromUnit(r),
      uint8FromUnit(g),
      uint8FromUnit(b),
      uint8FromUnit(a)
    )
  }

  private func uint8FromUnit(_ value: CGFloat) -> UInt8 {
    let scaled = (value * 255).rounded()
    let clamped = Swift.max(0, Swift.min(255, scaled))
    return UInt8(clamped)
  }
}

private struct RasterImage {
  let width: Int
  let height: Int
  let stride: Int
  let pixels: [UInt8]

  static func from(cgImage: CGImage) -> RasterImage? {
    let width = cgImage.width
    let height = cgImage.height
    let stride = width * 4
    var pixels = [UInt8](repeating: 0, count: stride * height)

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue

    let drawStatus = pixels.withUnsafeMutableBytes { raw -> Bool in
      guard let baseAddress = raw.baseAddress else {
        return false
      }

      guard let context = CGContext(
        data: baseAddress,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: stride,
        space: colorSpace,
        bitmapInfo: bitmapInfo
      ) else {
        return false
      }

      context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }

    guard drawStatus else {
      return nil
    }

    return RasterImage(width: width, height: height, stride: stride, pixels: pixels)
  }

  func toCGImage() -> CGImage? {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue

    let data = Data(pixels)
    guard let provider = CGDataProvider(data: data as CFData) else {
      return nil
    }

    return CGImage(
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
    )
  }
}
