import Foundation

@MainActor
protocol RegionRecordingSession: AnyObject {
  func start() async throws
  func stop() async throws -> URL
  func setSystemAudioEnabled(_ enabled: Bool) async throws
  func setMicrophoneEnabled(_ enabled: Bool) async throws
  func setMicrophoneDeviceID(_ deviceID: String) async throws
}
