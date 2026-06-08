import Foundation

/// In-memory statistics reducer used by persistence and tests.
final class StatsSession {
  private var eventKeys = Set<String>()
  private var buckets: [StatsDayKey: StatsDailyBucketAccumulator] = [:]

  init?() {}

  func ingestEvent(_ event: StatsEvent) -> Bool? {
    let key = event.eventKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty, !event.captureID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return nil
    }
    guard eventKeys.insert(key).inserted else {
      return false
    }

    let day = Self.dayKey(occurredAtMS: event.occurredAtMS, timezoneOffsetMinutes: event.timezoneOffsetMinutes)
    var bucket = buckets[day] ?? StatsDailyBucketAccumulator(day: day)
    bucket.ingest(event)
    buckets[day] = bucket
    return true
  }

  func summary() -> StatsSummary? {
    let ordered = sortedBuckets()
    let totalScreenshots = ordered.reduce(Int64(0)) { $0 + Int64($1.screenshotCount) }
    let totalRecordings = ordered.reduce(Int64(0)) { $0 + Int64($1.recordingCount) }
    let totalRecordedDuration = ordered.reduce(Int64(0)) { $0 + $1.recordedDurationMS }
    let totalBytes = ordered.reduce(Int64(0)) { $0 + $1.captureBytesProduced }
    let completedScreenshotSessions = ordered.reduce(Int64(0)) { $0 + $1.completedScreenshotSessionCount }
    let screenshotCompletionDuration = ordered.reduce(Int64(0)) { $0 + $1.screenshotCompletionDurationMS }
    let mostActive = ordered.max { lhs, rhs in
      lhs.activityScore == rhs.activityScore ? lhs.day < rhs.day : lhs.activityScore < rhs.activityScore
    }
    return StatsSummary(
      totalScreenshotsCaptured: totalScreenshots,
      totalRecordingsCompleted: totalRecordings,
      totalRecordedDurationMS: totalRecordedDuration,
      totalScreenshotCompletionDurationMS: screenshotCompletionDuration,
      completedScreenshotSessionCount: completedScreenshotSessions,
      averageScreenshotEditorCompletionDurationMS: completedScreenshotSessions > 0 ? screenshotCompletionDuration / completedScreenshotSessions : 0,
      totalCaptureBytesProduced: totalBytes,
      currentCaptureStreakDays: currentStreakDays(ordered),
      bestCaptureStreakDays: bestStreakDays(ordered),
      activeCaptureDays: ordered.count,
      firstCaptureDay: ordered.first?.day,
      lastCaptureDay: ordered.last?.day,
      mostActiveDay: mostActive?.day,
      mostActiveDayScore: mostActive?.activityScore ?? 0
    )
  }

  func allDailyBuckets() -> [StatsDailyBucket] {
    sortedBuckets().map(\.dailyBucket)
  }

  func reset() -> Bool {
    eventKeys.removeAll()
    buckets.removeAll()
    return true
  }

  private func sortedBuckets() -> [StatsDailyBucketAccumulator] {
    buckets.values.sorted { $0.day < $1.day }
  }

  private func bestStreakDays(_ ordered: [StatsDailyBucketAccumulator]) -> Int {
    guard !ordered.isEmpty else {
      return 0
    }
    var best = 1
    var current = 1
    for index in 1..<ordered.count {
      current = ordered[index - 1].day.days(to: ordered[index].day) == 1 ? current + 1 : 1
      best = max(best, current)
    }
    return best
  }

  private func currentStreakDays(_ ordered: [StatsDailyBucketAccumulator]) -> Int {
    guard var day = ordered.last?.day else {
      return 0
    }
    let activeDays = Set(ordered.map(\.day))
    var streak = 0
    while activeDays.contains(day) {
      streak += 1
      guard let previous = day.addingDays(-1) else {
        break
      }
      day = previous
    }
    return streak
  }

  private static func dayKey(occurredAtMS: Int64, timezoneOffsetMinutes: Int32) -> StatsDayKey {
    let seconds = TimeInterval(occurredAtMS) / 1000 + TimeInterval(timezoneOffsetMinutes) * 60
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    let components = calendar.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: seconds))
    return StatsDayKey(year: components.year ?? 1970, month: components.month ?? 1, day: components.day ?? 1)
  }
}

private struct StatsDailyBucketAccumulator {
  let day: StatsDayKey
  var screenshotCount = 0
  var recordingCount = 0
  var recordedDurationMS: Int64 = 0
  var captureBytesProduced: Int64 = 0
  var firstCaptureAtMS: Int64?
  var lastCaptureAtMS: Int64?
  var completedScreenshotSessionCount: Int64 = 0
  var screenshotCompletionDurationMS: Int64 = 0

  init(day: StatsDayKey) {
    self.day = day
  }

  var activityScore: Int64 {
    Int64(screenshotCount) + Int64(recordingCount * 3) + recordedDurationMS / 300_000
  }

  var dailyBucket: StatsDailyBucket {
    StatsDailyBucket(
      day: day,
      screenshotCount: screenshotCount,
      recordingCount: recordingCount,
      recordedDurationMS: recordedDurationMS,
      captureBytesProduced: captureBytesProduced,
      firstCaptureAtMS: firstCaptureAtMS,
      lastCaptureAtMS: lastCaptureAtMS
    )
  }

  mutating func ingest(_ event: StatsEvent) {
    switch event.eventType {
    case .screenshotCaptured:
      screenshotCount += 1
    case .screenshotSessionCompleted:
      completedScreenshotSessionCount += 1
      screenshotCompletionDurationMS += max(0, event.screenshotCompletionDurationMS ?? 0)
    case .recordingCompleted:
      recordingCount += 1
      recordedDurationMS += max(0, event.durationMS ?? 0)
    }
    captureBytesProduced += max(0, event.bytesProduced)
    firstCaptureAtMS = min(firstCaptureAtMS ?? event.occurredAtMS, event.occurredAtMS)
    lastCaptureAtMS = max(lastCaptureAtMS ?? event.occurredAtMS, event.occurredAtMS)
  }
}

private func < (lhs: StatsDayKey, rhs: StatsDayKey) -> Bool {
  if lhs.year != rhs.year { return lhs.year < rhs.year }
  if lhs.month != rhs.month { return lhs.month < rhs.month }
  return lhs.day < rhs.day
}

private extension StatsDayKey {
  func addingDays(_ days: Int) -> StatsDayKey? {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    guard
      let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
      let adjusted = calendar.date(byAdding: .day, value: days, to: date)
    else {
      return nil
    }
    let components = calendar.dateComponents([.year, .month, .day], from: adjusted)
    return StatsDayKey(year: components.year ?? year, month: components.month ?? month, day: components.day ?? day)
  }

  func days(to other: StatsDayKey) -> Int? {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    guard
      let start = calendar.date(from: DateComponents(year: year, month: month, day: day)),
      let end = calendar.date(from: DateComponents(year: other.year, month: other.month, day: other.day))
    else {
      return nil
    }
    return calendar.dateComponents([.day], from: start, to: end).day
  }
}
