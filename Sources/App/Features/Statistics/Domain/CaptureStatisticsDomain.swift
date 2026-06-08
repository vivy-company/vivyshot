import Foundation

/// Capture event category stored by the statistics feature.
enum StatsEventType: UInt8, Sendable {
  case screenshotCaptured = 0
  case screenshotSessionCompleted = 1
  case recordingCompleted = 2
}

/// Calendar day key normalized to the user's timezone at event time.
struct StatsDayKey: Equatable, Hashable, Sendable {
  let year: Int
  let month: Int
  let day: Int

  var yyyyMMdd: String {
    String(format: "%04d-%02d-%02d", year, month, day)
  }
}

/// One deduplicated capture event from screenshot or recording workflows.
struct StatsEvent: Sendable {
  let eventKey: String
  let eventType: StatsEventType
  let occurredAtMS: Int64
  let timezoneOffsetMinutes: Int32
  let bytesProduced: Int64
  let durationMS: Int64?
  let screenshotCompletionDurationMS: Int64?
  let captureID: String
}

/// Aggregate statistics shown in the dashboard and menu surfaces.
struct StatsSummary: Sendable {
  let totalScreenshotsCaptured: Int64
  let totalRecordingsCompleted: Int64
  let totalRecordedDurationMS: Int64
  let totalScreenshotCompletionDurationMS: Int64
  let completedScreenshotSessionCount: Int64
  let averageScreenshotEditorCompletionDurationMS: Int64
  let totalCaptureBytesProduced: Int64
  let currentCaptureStreakDays: Int
  let bestCaptureStreakDays: Int
  let activeCaptureDays: Int
  let firstCaptureDay: StatsDayKey?
  let lastCaptureDay: StatsDayKey?
  let mostActiveDay: StatsDayKey?
  let mostActiveDayScore: Int64
}

/// Per-day statistics bucket used by charts and streak calculations.
struct StatsDailyBucket: Sendable {
  let day: StatsDayKey
  let screenshotCount: Int
  let recordingCount: Int
  let recordedDurationMS: Int64
  let captureBytesProduced: Int64
  let firstCaptureAtMS: Int64?
  let lastCaptureAtMS: Int64?
}
