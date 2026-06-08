import Foundation
import VivyShotKit

struct CaptureWebcamDevice: Identifiable, Hashable {
  let id: String
  let name: String
}

enum CaptureWebcamDevices {
  static func load() -> [CaptureWebcamDevice] {
    var count: UInt32 = 0
    let countStatus = vs_capture_copy_webcam_devices(nil, 0, &count)
    guard countStatus == VS_CAPTURE_STATUS_OK, count > 0 else {
      return []
    }

    let capacity = Int(count)
    let buffer = UnsafeMutablePointer<vs_capture_webcam_device>.allocate(capacity: capacity)
    defer {
      vs_capture_webcam_devices_free(buffer, count)
      buffer.deallocate()
    }

    let status = vs_capture_copy_webcam_devices(buffer, count, &count)
    guard status == VS_CAPTURE_STATUS_OK else {
      return []
    }

    return (0..<Int(count)).map { index in
      let device = buffer.advanced(by: index).pointee
      return CaptureWebcamDevice(
        id: string(from: device.stable_id_utf8, length: device.stable_id_len),
        name: string(from: device.display_name_utf8, length: device.display_name_len)
      )
    }
  }

  private static func string(from ptr: UnsafePointer<UInt8>?, length: UInt32) -> String {
    guard let ptr, length > 0 else {
      return ""
    }
    return String(decoding: UnsafeBufferPointer(start: ptr, count: Int(length)), as: UTF8.self)
  }
}
