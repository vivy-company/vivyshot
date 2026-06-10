import AVFoundation
import Foundation

final class CaptureSessionRunner: @unchecked Sendable {
  private let session: AVCaptureSession
  private let queue: DispatchQueue

  init(session: AVCaptureSession, label: String) {
    self.session = session
    queue = DispatchQueue(label: label, qos: .userInitiated)
  }

  func start() async {
    await withCheckedContinuation { continuation in
      queue.async { [self] in
        if !session.isRunning {
          session.startRunning()
        }
        continuation.resume()
      }
    }
  }

  func startDetached() {
    queue.async { [self] in
      if !session.isRunning {
        session.startRunning()
      }
    }
  }

  func stop() async {
    await withCheckedContinuation { continuation in
      queue.async { [self] in
        if session.isRunning {
          session.stopRunning()
        }
        continuation.resume()
      }
    }
  }

  func stopDetached() {
    queue.async { [self] in
      if session.isRunning {
        session.stopRunning()
      }
    }
  }
}
