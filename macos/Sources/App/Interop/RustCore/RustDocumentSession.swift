import AppKit
import CoreGraphics
import Foundation
import VivyShotKit

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
    let rect = quantizedImageRect(imageRect)

    let status = vs_resize_annotation(
      handle,
      UInt32(index),
      rect.x,
      rect.y,
      rect.width,
      rect.height
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
    let rect = quantizedImageRect(imageRect)
    let rgba = quantizedColor(color)

    return vs_rect_command(
      x: rect.x,
      y: rect.y,
      width: rect.width,
      height: rect.height,
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
    let (sx, sy) = quantizedImagePoint(start)
    let (ex, ey) = quantizedImagePoint(end)
    let rgba = quantizedColor(color)

    return vs_line_command(
      x0: sx,
      y0: sy,
      x1: ex,
      y1: ey,
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
    let rect = quantizedImageRect(imageRect)
    let rgba = quantizedColor(color)

    return vs_ellipse_command(
      x: rect.x,
      y: rect.y,
      width: rect.width,
      height: rect.height,
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
    let (sx, sy) = quantizedImagePoint(start)
    let (ex, ey) = quantizedImagePoint(end)
    let rgba = quantizedColor(color)

    return vs_arrow_command(
      x0: sx,
      y0: sy,
      x1: ex,
      y1: ey,
      stroke_width: strokeWidth,
      r: rgba.r,
      g: rgba.g,
      b: rgba.b,
      a: rgba.a
    )
  }

  private func makePathStyle(color: NSColor, strokeWidth: UInt32) -> vs_path_style {
    let rgba = quantizedColor(color)
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
      let (x, y) = quantizedImagePoint(point)
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
    let (x, y) = quantizedImagePoint(point)
    let color = quantizedColor(style.color)
    let fontPx = UInt32(clampToRange(Int(style.fontSize.rounded()), min: 8, max: 96))

    return vs_text_command(
      x: x,
      y: y,
      font_px: fontPx,
      r: color.r,
      g: color.g,
      b: color.b,
      a: color.a
    )
  }

  private func makePixelateCommand(from imageRect: CGRect) -> vs_pixelate_rect_command {
    let rect = quantizedImageRect(imageRect)

    return vs_pixelate_rect_command(
      x: rect.x,
      y: rect.y,
      width: rect.width,
      height: rect.height,
      block_size: 12
    )
  }

  private func makeBlurCommand(from imageRect: CGRect) -> vs_blur_rect_command {
    let rect = quantizedImageRect(imageRect)

    return vs_blur_rect_command(
      x: rect.x,
      y: rect.y,
      width: rect.width,
      height: rect.height,
      radius: 4
    )
  }

  private func clampToRange(_ value: Int, min lower: Int, max upper: Int) -> Int {
    Swift.max(lower, Swift.min(value, upper))
  }

  private func quantizedImageRect(_ imageRect: CGRect) -> vs_i32_rect {
    var raw = vs_i32_rect()
    let status = vs_quantize_image_rect(
      UInt32(max(1, width)),
      UInt32(max(1, height)),
      vs_f32_rect(
        x: Float(imageRect.origin.x),
        y: Float(imageRect.origin.y),
        width: Float(imageRect.size.width),
        height: Float(imageRect.size.height)
      ),
      &raw
    )
    if status == 0 {
      return raw
    }
    return vs_i32_rect(x: 0, y: 0, width: Int32(max(1, width)), height: Int32(max(1, height)))
  }

  private func quantizedImagePoint(_ point: CGPoint) -> (Int32, Int32) {
    var outX: Int32 = 0
    var outY: Int32 = 0
    let status = vs_quantize_image_point(
      UInt32(max(1, width)),
      UInt32(max(1, height)),
      Float(point.x),
      Float(point.y),
      &outX,
      &outY
    )
    if status == 0 {
      return (outX, outY)
    }
    return (0, 0)
  }

  private func quantizedColor(_ color: NSColor) -> vs_rgba8 {
    guard let rgb = color.usingColorSpace(.deviceRGB) else {
      return vs_rgba8(r: 255, g: 255, b: 255, a: 245)
    }

    var r: CGFloat = 1
    var g: CGFloat = 1
    var b: CGFloat = 1
    var a: CGFloat = 1
    rgb.getRed(&r, green: &g, blue: &b, alpha: &a)

    var raw = vs_rgba8()
    let status = vs_quantize_rgba(Float(r), Float(g), Float(b), Float(a), &raw)
    if status == 0 {
      return raw
    }
    return vs_rgba8(r: 255, g: 255, b: 255, a: 245)
  }
}


struct RasterImage {
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


