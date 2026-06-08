import CoreGraphics
import Foundation
import VivyShotKit

private final class CaptureRecordingStartContinuationBox {
  let continuation: CheckedContinuation<UInt, Error>

  init(_ continuation: CheckedContinuation<UInt, Error>) {
    self.continuation = continuation
  }
}

private final class CaptureRecordingStopContinuationBox {
  let continuation: CheckedContinuation<URL, Error>

  init(_ continuation: CheckedContinuation<URL, Error>) {
    self.continuation = continuation
  }
}

private let captureRecordingStartCallback:
  @convention(c) (UnsafeMutableRawPointer?, Int32, OpaquePointer?) -> Void = { userData, status, session in
    guard let userData else {
      return
    }
    let box = Unmanaged<CaptureRecordingStartContinuationBox>.fromOpaque(userData).takeRetainedValue()
    guard status == VS_CAPTURE_STATUS_OK, let session else {
      box.continuation.resume(throwing: CaptureRecordingError(status: Int(status)))
      return
    }
    box.continuation.resume(returning: UInt(bitPattern: session))
  }

private let captureRecordingStopCallback:
  @convention(c) (UnsafeMutableRawPointer?, Int32, vs_capture_recording_output) -> Void = { userData, status, output in
    guard let userData else {
      vs_capture_recording_output_free(output)
      return
    }
    let box = Unmanaged<CaptureRecordingStopContinuationBox>.fromOpaque(userData).takeRetainedValue()
    guard status == VS_CAPTURE_STATUS_OK else {
      vs_capture_recording_output_free(output)
      box.continuation.resume(throwing: CaptureRecordingError(status: Int(status)))
      return
    }

    guard let path = CaptureRecordingSession.pathString(from: output.output_path) else {
      vs_capture_recording_output_free(output)
      box.continuation.resume(throwing: CaptureRecordingError(status: VS_CAPTURE_STATUS_OUTPUT_FILE_UNAVAILABLE))
      return
    }
    vs_capture_recording_output_free(output)
    box.continuation.resume(returning: URL(fileURLWithPath: path))
  }

private struct CaptureRecordingError: LocalizedError {
  let status: Int

  var errorDescription: String? {
    switch status {
    case VS_CAPTURE_STATUS_NULL_POINTER, VS_CAPTURE_STATUS_INVALID_ARGUMENT:
      return "The capture backend received an invalid recording request."
    case VS_CAPTURE_STATUS_PERMISSION_DENIED:
      return "Screen recording permission was denied."
    case VS_CAPTURE_STATUS_PERMISSION_NOT_DETERMINED:
      return "Screen recording permission has not been granted yet."
    case VS_CAPTURE_STATUS_UNSUPPORTED_OS_VERSION:
      return "Screen recording requires macOS 15.2 or newer."
    case VS_CAPTURE_STATUS_NO_DISPLAY_FOR_SELECTION:
      return "No compatible display found for selected area."
    case VS_CAPTURE_STATUS_SELECTION_TOO_SMALL:
      return "Selected region is too small to record."
    case VS_CAPTURE_STATUS_UNSUPPORTED_CODEC:
      return "The selected recording encoder is not supported by this capture backend."
    case VS_CAPTURE_STATUS_UNSUPPORTED_CONTAINER:
      return "No supported recording file type is available."
    case VS_CAPTURE_STATUS_STREAM_START_FAILED:
      return "Screen recording failed to start."
    case VS_CAPTURE_STATUS_STREAM_STOPPED_WITH_ERROR:
      return "Screen recording stopped with an error."
    case VS_CAPTURE_STATUS_RECORDING_OUTPUT_FAILED:
      return "Recording output failed."
    case VS_CAPTURE_STATUS_NO_FRAMES_CAPTURED:
      return "No video frames were captured."
    case VS_CAPTURE_STATUS_OUTPUT_FILE_UNAVAILABLE:
      return "Recording output file was not available."
    case VS_CAPTURE_STATUS_CANCELLED:
      return "Recording was cancelled."
    case VS_CAPTURE_STATUS_UNSUPPORTED_PLATFORM:
      return "The capture backend is not available on this platform."
    default:
      return "The capture backend failed with status \(status)."
    }
  }
}

@MainActor
final class CaptureRecordingSession: RegionRecordingSession {
  private let selectionRectInScreen: CGRect
  private let config: VideoRecordingConfig
  private(set) var outputURL: URL
  nonisolated(unsafe) private var session: OpaquePointer?

  init(selectionRectInScreen: CGRect, config: VideoRecordingConfig, outputURL: URL) {
    self.selectionRectInScreen = selectionRectInScreen.standardized
    self.config = config
    self.outputURL = outputURL
  }

  deinit {
    if let session {
      vs_capture_recording_cancel(session)
    }
  }

  func start() async throws {
    let rawSession = try await withCheckedThrowingContinuation { continuation in
      let box = Unmanaged.passRetained(CaptureRecordingStartContinuationBox(continuation))
      let outputPathBytes = Array(outputURL.path.utf8)
      let overlayWindowIDs = config.capturedOverlayWindowIDs.map { UInt32($0) }
      let selectionInCG = cocoaRectToCGDisplayRect(selectionRectInScreen)

      outputPathBytes.withUnsafeBufferPointer { outputPathBuffer in
        overlayWindowIDs.withUnsafeBufferPointer { overlayWindowBuffer in
          var rawConfig = vs_capture_recording_config(
            selection_rect_screen: vs_capture_rect(
              x: selectionInCG.origin.x,
              y: selectionInCG.origin.y,
              width: selectionInCG.width,
              height: selectionInCG.height
            ),
            output_path: vs_capture_path(
              path_utf8: outputPathBuffer.baseAddress,
              path_len: UInt32(outputPathBuffer.count)
            ),
            frame_rate: UInt32(max(1, config.frameRate)),
            encoder: Self.encoderCode(config.encoder),
            capture_system_audio: config.captureSystemAudio,
            capture_microphone: config.captureMicrophone,
            show_cursor: config.showCursor,
            highlight_mouse_clicks: config.highlightMouseClicks,
            include_window_ids: overlayWindowBuffer.baseAddress,
            include_window_id_count: UInt32(overlayWindowBuffer.count),
            exclude_current_process: true
          )
          vs_capture_recording_start(&rawConfig, box.toOpaque(), captureRecordingStartCallback)
        }
      }
    }
    guard let session = OpaquePointer(bitPattern: rawSession) else {
      throw CaptureRecordingError(status: VS_CAPTURE_STATUS_INVALID_ARGUMENT)
    }
    self.session = session
  }

  func stop() async throws -> URL {
    guard let session else {
      return outputURL
    }
    self.session = nil
    return try await withCheckedThrowingContinuation { continuation in
      let box = Unmanaged.passRetained(CaptureRecordingStopContinuationBox(continuation))
      vs_capture_recording_stop(session, box.toOpaque(), captureRecordingStopCallback)
    }
  }

  nonisolated fileprivate static func pathString(from path: vs_capture_path) -> String? {
    guard let pathBytes = path.path_utf8, path.path_len > 0 else {
      return nil
    }
    let buffer = UnsafeBufferPointer(start: pathBytes, count: Int(path.path_len))
    return String(decoding: buffer, as: UTF8.self)
  }

  private static func encoderCode(_ encoder: VideoRecordingEncoderOption) -> UInt8 {
    switch encoder {
    case .standardH264:
      return UInt8(VS_CAPTURE_ENCODER_STANDARD_H264)
    case .smallerFileHEVC:
      return UInt8(VS_CAPTURE_ENCODER_SMALLER_FILE_HEVC)
    case .cpuH264:
      return UInt8(VS_CAPTURE_ENCODER_SOFTWARE_H264)
    }
  }
}
