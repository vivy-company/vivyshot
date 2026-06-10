import CoreMedia
import Foundation

extension PostRecordingExportState {
  func trimRange(durationSeconds: Double) -> CMTimeRange {
    let durationMS = UInt32(max(1, Int((max(0, durationSeconds) * 1000).rounded())))
    let start = min(trimStartMS, durationMS - 1)
    let end = min(max(trimEndMS, start + 1), durationMS)
    return CMTimeRange(
      start: CMTime(value: CMTimeValue(start), timescale: 1000),
      duration: CMTime(value: CMTimeValue(end - start), timescale: 1000)
    )
  }
}
