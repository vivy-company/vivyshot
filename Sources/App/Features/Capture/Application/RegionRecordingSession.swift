import Foundation

@MainActor
protocol RegionRecordingSession: AnyObject {
  /// Invoked once when the capture stream stops without a stop() call (system
  /// "Stop Sharing", display sleep, capture service failure).
  var onStreamStopped: (() -> Void)? { get set }
  /// Error reported by the stream mid-session, if any. Populated before stop() returns.
  var interruptionError: Error? { get }
  func start() async throws
  func stop() async throws -> URL
  func setSystemAudioEnabled(_ enabled: Bool) async throws
  func setMicrophoneEnabled(_ enabled: Bool) async throws
  func setMicrophoneDeviceID(_ deviceID: String) async throws
}
