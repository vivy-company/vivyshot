import AppKit
import CoreGraphics
import Foundation
import VivyShotKit

final class RustStitchSession {
  private let handle: UnsafeMutableRawPointer

  init?() {
    guard let rawHandle = vs_stitch_session_create() else {
      return nil
    }
    handle = rawHandle
  }

  deinit {
    vs_stitch_session_destroy(handle)
  }

  func reset(baseSegmentCount: Int = 1) -> Bool {
    vs_stitch_session_reset(handle, UInt32(max(1, baseSegmentCount))) == 0
  }

  func setBaseImage(_ image: CGImage, baseSegmentCount: Int = 1) -> Bool {
    guard let raster = RasterImage.from(cgImage: image) else {
      return false
    }
    return raster.pixels.withUnsafeBytes { raw in
      guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
        return false
      }
      let view = vs_bgra_image_view(
        width: UInt32(raster.width),
        height: UInt32(raster.height),
        stride: UInt32(raster.stride),
        ptr: base,
        len: UInt(raw.count)
      )
      return vs_stitch_session_set_base_bgra(handle, view, UInt32(max(1, baseSegmentCount))) == 0
    }
  }

  func pushFrame(_ frame: CGImage) -> RustStitchSessionResult? {
    guard let raster = RasterImage.from(cgImage: frame) else {
      return nil
    }
    var rawResult = vs_stitch_session_result()
    let status = raster.pixels.withUnsafeBytes { raw in
      guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
        return Int32(-1)
      }
      let view = vs_bgra_image_view(
        width: UInt32(raster.width),
        height: UInt32(raster.height),
        stride: UInt32(raster.stride),
        ptr: base,
        len: UInt(raw.count)
      )
      return vs_stitch_session_push_frame_bgra(handle, view, &rawResult)
    }
    guard status == 0 else {
      return nil
    }
    return Self.mapResult(rawResult)
  }

  func pushFrameAndMerge(_ frame: CGImage) -> (RustStitchSessionResult, CGImage?)? {
    guard let raster = RasterImage.from(cgImage: frame) else {
      return nil
    }
    var rawResult = vs_stitch_session_result()
    var rawImage = vs_bgra_owned_image(width: 0, height: 0, stride: 0, ptr: nil, len: 0)
    defer {
      vs_bgra_owned_image_destroy(&rawImage)
    }

    let status = raster.pixels.withUnsafeBytes { raw in
      guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
        return Int32(-1)
      }
      let view = vs_bgra_image_view(
        width: UInt32(raster.width),
        height: UInt32(raster.height),
        stride: UInt32(raster.stride),
        ptr: base,
        len: UInt(raw.count)
      )
      return vs_stitch_session_push_frame_and_merge_bgra(handle, view, &rawResult, &rawImage)
    }
    guard status == 0 else {
      return nil
    }

    let mergedImage = Self.makeImage(from: rawImage)
    return (Self.mapResult(rawResult), mergedImage)
  }

  func mergedImage() -> CGImage? {
    var rawImage = vs_bgra_owned_image(width: 0, height: 0, stride: 0, ptr: nil, len: 0)
    defer {
      vs_bgra_owned_image_destroy(&rawImage)
    }
    let status = vs_stitch_session_get_merged_image_bgra(handle, &rawImage)
    guard status == 0 else {
      return nil
    }
    return Self.makeImage(from: rawImage)
  }

  private static func mapResult(_ raw: vs_stitch_session_result) -> RustStitchSessionResult {
    RustStitchSessionResult(
      accepted: raw.accepted,
      rows: Int(raw.rows),
      side: raw.side,
      score: Double(raw.score),
      directionLocked: raw.direction_locked,
      expectedRows: Int(raw.expected_rows),
      segmentCount: Int(raw.segment_count),
      scrollDirectionSign: Int(raw.scroll_direction_sign)
    )
  }

  private static func makeImage(from raw: vs_bgra_owned_image) -> CGImage? {
    guard let ptr = raw.ptr, raw.len > 0 else {
      return nil
    }
    let pixels = Array(UnsafeBufferPointer(start: ptr, count: Int(raw.len)))
    let raster = RasterImage(
      width: Int(raw.width),
      height: Int(raw.height),
      stride: Int(raw.stride),
      pixels: pixels
    )
    return raster.toCGImage()
  }
}


