import Foundation

struct RecordingStatisticsRecorder {
  let statisticsStore: StatisticsStore

  func recordCompletedRecordingIfNeeded(inputURL: URL, durationSeconds: Double) {
    let recordingID = inputURL.deletingPathExtension().lastPathComponent
    guard !recordingID.isEmpty else {
      return
    }

    let fileSize = (try? inputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
    let durationMS = Int64(max(0, durationSeconds) * 1000.0)
    Task {
      await statisticsStore.recordRecordingCompleted(
        recordingID: recordingID,
        occurredAt: Date(),
        bytesProduced: fileSize,
        durationMS: durationMS
      )
    }
  }
}
