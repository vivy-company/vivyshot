import AVFoundation
import Foundation

enum RecordingSourceProvider {
  static var webcamDeviceTypes: [AVCaptureDevice.DeviceType] {
    var deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
    if #available(macOS 14.0, *) {
      deviceTypes.append(.external)
    } else {
      deviceTypes.append(.externalUnknown)
    }
    if #available(macOS 15.0, *) {
      deviceTypes.append(.continuityCamera)
    }
    return deviceTypes
  }

  static func webcamSources() -> [RecordingSourceOption] {
    return sourceOptions(
      deviceTypes: webcamDeviceTypes,
      mediaType: .video
    )
  }

  static func microphoneSources() -> [RecordingSourceOption] {
    sourceOptions(
      deviceTypes: [.microphone],
      mediaType: .audio
    )
  }

  private static func sourceOptions(
    deviceTypes: [AVCaptureDevice.DeviceType],
    mediaType: AVMediaType
  ) -> [RecordingSourceOption] {
    let discovery = AVCaptureDevice.DiscoverySession(
      deviceTypes: deviceTypes,
      mediaType: mediaType,
      position: .unspecified
    )
    return discovery.devices
      .map { RecordingSourceOption(id: $0.uniqueID, name: $0.localizedName) }
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }
}
