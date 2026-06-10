import AVFoundation
import CoreMedia
import Foundation

extension AVAssetExportSession {
  static func recordingExport(
    asset: AVAsset,
    options: PostRecordingExportOptions,
    container: PostRecordingVideoSaveContainer?,
    outputURL: URL,
    timeRange: CMTimeRange,
    estimatedDurationSeconds: Double,
    creationError: Error
  ) throws -> AVAssetExportSession {
    let presetName = ExportPlanner.bestAvailableExportPreset(
      codec: options.codec,
      quality: options.quality,
      asset: asset
    )
    guard let exportSession = AVAssetExportSession(asset: asset, presetName: presetName) else {
      throw creationError
    }
    exportSession.outputURL = outputURL
    exportSession.outputFileType = ExportPlanner.bestSaveFileType(
      codec: options.codec,
      supportedTypes: exportSession.supportedFileTypes,
      preferredContainer: container?.exportContainer
    )
    if let fileLengthLimit = ExportPlanner.estimatedFileLengthLimit(
      durationSeconds: estimatedDurationSeconds,
      options: options
    ) {
      exportSession.fileLengthLimit = fileLengthLimit
    }
    exportSession.shouldOptimizeForNetworkUse = true
    exportSession.timeRange = timeRange
    return exportSession
  }

  func exportChecked() async throws {
    guard let url = outputURL, let fileType = outputFileType else {
      throw NSError(
        domain: "VivyShot.Export",
        code: -1,
        userInfo: [NSLocalizedDescriptionKey: "Missing output URL or file type."]
      )
    }
    if #available(macOS 15.0, *) {
      try await export(to: url, as: fileType)
    } else {
      nonisolated(unsafe) let session = self
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        session.exportAsynchronously {
          switch session.status {
          case .completed:
            continuation.resume(returning: ())
          case .failed:
            continuation.resume(throwing: session.error ?? NSError(domain: "VivyShot.Export", code: -1))
          case .cancelled:
            continuation.resume(throwing: NSError(domain: "VivyShot.Export", code: -2))
          default:
            continuation.resume(throwing: session.error ?? NSError(domain: "VivyShot.Export", code: -3))
          }
        }
      }
    }
  }
}
