import Foundation
import OSLog

/// SQLite-backed persistence and aggregation service for capture statistics.
actor StatisticsStore {
  private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.vivyshot", category: "Statistics")
  private let ledger: StatisticsSQLiteLedger
  private var session: StatsSession?
  private var changeContinuations: [UUID: AsyncStream<Void>.Continuation] = [:]

  init(databaseURL: URL? = nil) {
    ledger = StatisticsSQLiteLedger(databaseURL: databaseURL)
  }

  func recordScreenshotCaptured(captureID: String, occurredAt: Date, bytesProduced: Int64) {
    let event = StatsEvent(
      eventKey: "screenshot_capture:\(captureID)",
      eventType: .screenshotCaptured,
      occurredAtMS: occurredAt.epochMilliseconds,
      timezoneOffsetMinutes: occurredAt.timezoneOffsetMinutes,
      bytesProduced: max(0, bytesProduced),
      durationMS: nil,
      screenshotCompletionDurationMS: nil,
      captureID: captureID
    )
    ingest(event, sourceType: "screenshot_capture")
  }

  func recordScreenshotSessionCompleted(captureID: String, startedAt: Date, finishedAt: Date) {
    let durationMS = max(0, finishedAt.epochMilliseconds - startedAt.epochMilliseconds)
    let event = StatsEvent(
      eventKey: "screenshot_session_completed:\(captureID)",
      eventType: .screenshotSessionCompleted,
      occurredAtMS: finishedAt.epochMilliseconds,
      timezoneOffsetMinutes: finishedAt.timezoneOffsetMinutes,
      bytesProduced: 0,
      durationMS: nil,
      screenshotCompletionDurationMS: durationMS,
      captureID: captureID
    )
    ingest(event, sourceType: "screenshot_session_completed")
  }

  func recordRecordingCompleted(
    recordingID: String,
    occurredAt: Date,
    bytesProduced: Int64,
    durationMS: Int64
  ) {
    let event = StatsEvent(
      eventKey: "recording_completed:\(recordingID)",
      eventType: .recordingCompleted,
      occurredAtMS: occurredAt.epochMilliseconds,
      timezoneOffsetMinutes: occurredAt.timezoneOffsetMinutes,
      bytesProduced: max(0, bytesProduced),
      durationMS: max(0, durationMS),
      screenshotCompletionDurationMS: nil,
      captureID: recordingID
    )
    ingest(event, sourceType: "recording_completed")
  }

  func dashboardData() -> StatisticsDashboard? {
    do {
      try ensureLoaded()
      guard let session, let summary = session.summary() else {
        return nil
      }

      return StatisticsDashboard(
        summary: summary,
        dailyBuckets: session.allDailyBuckets(),
        firstScreenshotAt: try ledger.firstOccurredAt(sourceType: "screenshot_capture"),
        firstRecordingAt: try ledger.firstOccurredAt(sourceType: "recording_completed")
      )
    } catch {
      logger.error("Loading statistics dashboard failed: \(error.localizedDescription)")
      return nil
    }
  }

  func changeStream() -> AsyncStream<Void> {
    let id = UUID()
    return AsyncStream { continuation in
      changeContinuations[id] = continuation
      continuation.onTermination = { [weak self] _ in
        Task {
          await self?.removeChangeContinuation(id)
        }
      }
    }
  }

  func resetStatistics() {
    do {
      try ensureLoaded()
      guard let session else {
        return
      }
      try ledger.performTransaction {
        _ = session.reset()
        try ledger.deleteAllEvents()
      }
      postStatisticsDidChange()
    } catch {
      logger.error("Reset statistics failed: \(error.localizedDescription)")
    }
  }

  private func ingest(_ event: StatsEvent, sourceType: String) {
    do {
      try ensureLoaded()
      guard let session else {
        return
      }

      let inserted = try ledger.performTransaction {
        let inserted = try ledger.insertEventIfNeeded(event, sourceType: sourceType)
        if inserted {
          guard let applied = session.ingestEvent(event), applied else {
            throw StatisticsStoreError.statsIngestFailed
          }
        }
        return inserted
      }
      if inserted {
        postStatisticsDidChange()
      }
    } catch {
      logger.error("Statistics ingest failed for \(sourceType, privacy: .public): \(error.localizedDescription)")
    }
  }

  private func ensureLoaded() throws {
    guard !ledger.isOpen || session == nil else {
      return
    }

    guard let session = StatsSession() else {
      throw StatisticsStoreError.unableToCreateStatsSession
    }
    do {
      try ledger.open(replayingInto: session)
      self.session = session
    } catch {
      self.session = nil
      throw error
    }
  }

  private func postStatisticsDidChange() {
    for continuation in changeContinuations.values {
      continuation.yield()
    }
  }

  private func removeChangeContinuation(_ id: UUID) {
    changeContinuations[id] = nil
  }

}

enum StatisticsStoreError: LocalizedError {
  case applicationSupportUnavailable
  case unableToCreateStatsSession
  case statsIngestFailed
  case sqlite(String)

  var errorDescription: String? {
    switch self {
    case .applicationSupportUnavailable:
      return "Application Support directory is unavailable"
    case .unableToCreateStatsSession:
      return "Unable to create statistics session"
    case .statsIngestFailed:
      return "Statistics ingest failed"
    case .sqlite(let message):
      return message
    }
  }
}

extension Date {
  init(epochMilliseconds: Int64) {
    self = Date(timeIntervalSince1970: TimeInterval(epochMilliseconds) / 1000)
  }

  var epochMilliseconds: Int64 {
    Int64((timeIntervalSince1970 * 1000).rounded())
  }

  var timezoneOffsetMinutes: Int32 {
    Int32(TimeZone.current.secondsFromGMT(for: self) / 60)
  }
}
