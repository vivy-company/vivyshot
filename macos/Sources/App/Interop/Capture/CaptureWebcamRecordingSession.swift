import AVFoundation
import Foundation
import VivyShotKit

struct CaptureWebcamRecordingOutput {
  let outputURL: URL
  let recordingStartUptime: TimeInterval
}

private final class CaptureWebcamStartContinuationBox {
  let continuation: CheckedContinuation<Void, Error>

  init(_ continuation: CheckedContinuation<Void, Error>) {
    self.continuation = continuation
  }
}

private final class CaptureWebcamStopContinuationBox {
  let continuation: CheckedContinuation<CaptureWebcamRecordingOutput, Error>

  init(_ continuation: CheckedContinuation<CaptureWebcamRecordingOutput, Error>) {
    self.continuation = continuation
  }
}

private let captureWebcamStartCallback:
  @convention(c) (UnsafeMutableRawPointer?, Int32) -> Void = { userData, status in
    guard let userData else {
      return
    }
    let box = Unmanaged<CaptureWebcamStartContinuationBox>.fromOpaque(userData).takeRetainedValue()
    guard status == VS_CAPTURE_STATUS_OK else {
      box.continuation.resume(throwing: CaptureWebcamRecordingError(status: Int(status)))
      return
    }
    box.continuation.resume()
  }

private let captureWebcamStopCallback:
  @convention(c) (UnsafeMutableRawPointer?, Int32, vs_capture_webcam_recording_output) -> Void = { userData, status, output in
    guard let userData else {
      vs_capture_webcam_recording_output_free(output)
      return
    }
    let box = Unmanaged<CaptureWebcamStopContinuationBox>.fromOpaque(userData).takeRetainedValue()
    guard status == VS_CAPTURE_STATUS_OK else {
      vs_capture_webcam_recording_output_free(output)
      box.continuation.resume(throwing: CaptureWebcamRecordingError(status: Int(status)))
      return
    }
    guard let path = CaptureRecordingSession.pathString(from: output.output_path) else {
      vs_capture_webcam_recording_output_free(output)
      box.continuation.resume(throwing: CaptureWebcamRecordingError(status: VS_CAPTURE_STATUS_OUTPUT_FILE_UNAVAILABLE))
      return
    }
    let result = CaptureWebcamRecordingOutput(
      outputURL: URL(fileURLWithPath: path),
      recordingStartUptime: output.recording_start_uptime_seconds
    )
    vs_capture_webcam_recording_output_free(output)
    box.continuation.resume(returning: result)
  }

private struct CaptureWebcamRecordingError: LocalizedError {
  let status: Int

  var errorDescription: String? {
    switch status {
    case VS_CAPTURE_STATUS_NULL_POINTER, VS_CAPTURE_STATUS_INVALID_ARGUMENT:
      return "The capture backend received an invalid webcam recording request."
    case VS_CAPTURE_STATUS_PERMISSION_DENIED:
      return "Camera permission was denied."
    case VS_CAPTURE_STATUS_STREAM_START_FAILED:
      return "Webcam recording failed to start."
    case VS_CAPTURE_STATUS_RECORDING_OUTPUT_FAILED:
      return "Webcam recording output failed."
    case VS_CAPTURE_STATUS_OUTPUT_FILE_UNAVAILABLE:
      return "Webcam recording file is unavailable."
    case VS_CAPTURE_STATUS_CANCELLED:
      return "Webcam recording was cancelled."
    case VS_CAPTURE_STATUS_UNSUPPORTED_PLATFORM:
      return "The webcam backend is not available on this platform."
    default:
      return "The webcam backend failed with status \(status)."
    }
  }
}

@MainActor
final class CaptureWebcamRecordingSession {
  private let outputURL: URL
  nonisolated(unsafe) private var session: OpaquePointer?

  init(outputURL: URL, preferredDeviceID: String) throws {
    self.outputURL = outputURL
    let outputPathBytes = Array(outputURL.path.utf8)
    let deviceIDBytes = Array(preferredDeviceID.utf8)
    var rawSession: OpaquePointer?
    let status = outputPathBytes.withUnsafeBufferPointer { outputPathBuffer in
      deviceIDBytes.withUnsafeBufferPointer { deviceIDBuffer in
        var config = vs_capture_webcam_recording_config(
          output_path: vs_capture_path(
            path_utf8: outputPathBuffer.baseAddress,
            path_len: UInt32(outputPathBuffer.count)
          ),
          preferred_device_id_utf8: deviceIDBuffer.baseAddress,
          preferred_device_id_len: UInt32(deviceIDBuffer.count)
        )
        return vs_capture_webcam_recording_create(&config, &rawSession)
      }
    }
    guard status == VS_CAPTURE_STATUS_OK, let rawSession else {
      throw CaptureWebcamRecordingError(status: Int(status))
    }
    session = rawSession
  }

  deinit {
    if let session {
      vs_capture_webcam_recording_cancel(session)
    }
  }

  func makePreviewLayer() -> AVCaptureVideoPreviewLayer? {
    guard let session,
          let rawPreviewSession = vs_capture_webcam_recording_preview_session(session)
    else {
      return nil
    }
    let captureSession = Unmanaged<AVCaptureSession>.fromOpaque(rawPreviewSession).takeUnretainedValue()
    let layer = AVCaptureVideoPreviewLayer(session: captureSession)
    layer.videoGravity = .resizeAspectFill
    return layer
  }

  func start() async throws {
    guard let session else {
      throw CaptureWebcamRecordingError(status: VS_CAPTURE_STATUS_INVALID_ARGUMENT)
    }
    try await withCheckedThrowingContinuation { continuation in
      let box = Unmanaged.passRetained(CaptureWebcamStartContinuationBox(continuation))
      vs_capture_webcam_recording_start(session, box.toOpaque(), captureWebcamStartCallback)
    }
  }

  func stop() async throws -> CaptureWebcamRecordingOutput {
    guard let session else {
      return CaptureWebcamRecordingOutput(outputURL: outputURL, recordingStartUptime: 0)
    }
    self.session = nil
    return try await withCheckedThrowingContinuation { continuation in
      let box = Unmanaged.passRetained(CaptureWebcamStopContinuationBox(continuation))
      vs_capture_webcam_recording_stop(session, box.toOpaque(), captureWebcamStopCallback)
    }
  }

  func cancel() {
    guard let session else {
      return
    }
    self.session = nil
    vs_capture_webcam_recording_cancel(session)
  }
}
