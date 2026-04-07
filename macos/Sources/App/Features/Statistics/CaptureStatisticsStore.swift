import Foundation
import OSLog
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private final class SQLiteConnectionBox: @unchecked Sendable {
  var pointer: OpaquePointer?

  deinit {
    if let pointer {
      sqlite3_close(pointer)
    }
  }
}

actor CaptureStatisticsStore {
  static let shared = CaptureStatisticsStore()

  private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.vivyshot", category: "Statistics")
  private let databaseURLOverride: URL?
  private let connection = SQLiteConnectionBox()

  private var db: OpaquePointer? {
    get { connection.pointer }
    set { connection.pointer = newValue }
  }
  private var session: RustStatsSession?

  init(databaseURL: URL? = nil) {
    databaseURLOverride = databaseURL
  }

  func recordScreenshotCaptured(captureID: String, occurredAt: Date, bytesProduced: Int64) {
    let event = RustStatsEvent(
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
    let event = RustStatsEvent(
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
    let event = RustStatsEvent(
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

  func dashboardData() -> CaptureStatisticsDashboardData? {
    do {
      try ensureLoaded()
      guard let db, let session, let summary = session.summary() else {
        return nil
      }

      return CaptureStatisticsDashboardData(
        summary: summary,
        dailyBuckets: session.allDailyBuckets(),
        firstScreenshotAt: try firstOccurredAt(sourceType: "screenshot_capture", db: db),
        firstRecordingAt: try firstOccurredAt(sourceType: "recording_completed", db: db)
      )
    } catch {
      logger.error("Loading statistics dashboard failed: \(error.localizedDescription)")
      return nil
    }
  }

  func resetStatistics() {
    do {
      try ensureLoaded()
      guard let db, let session else {
        return
      }
      try beginTransaction(db)
      do {
        _ = session.reset()
        try execute("DELETE FROM stats_ingested_events;", db: db)
        try execute("DELETE FROM stats_daily_capture;", db: db)
        try execute("DELETE FROM stats_lifetime_totals;", db: db)
        try commitTransaction(db)
        postStatisticsDidChange()
      } catch {
        rollbackTransaction(db)
        throw error
      }
    } catch {
      logger.error("Reset statistics failed: \(error.localizedDescription)")
    }
  }

  private func ingest(_ event: RustStatsEvent, sourceType: String) {
    do {
      try ensureLoaded()
      guard let db, let session else {
        return
      }

      try beginTransaction(db)
      do {
        let inserted = try insertLedgerEventIfNeeded(event, sourceType: sourceType, db: db)
        if inserted {
          guard let applied = session.ingestEvent(event), applied else {
            throw StatisticsStoreError.rustIngestFailed
          }
          try rewriteProjections(using: session, db: db)
        }
        try commitTransaction(db)
        if inserted {
          postStatisticsDidChange()
        }
      } catch {
        rollbackTransaction(db)
        throw error
      }
    } catch {
      logger.error("Statistics ingest failed for \(sourceType, privacy: .public): \(error.localizedDescription)")
    }
  }

  private func ensureLoaded() throws {
    guard db == nil || session == nil else {
      return
    }

    let dbURL = try resolveDatabaseURL()
    let database = try openDatabase(at: dbURL)
    do {
      try configureDatabase(database)
      try installSchema(database)

      guard let session = RustStatsSession() else {
        throw StatisticsStoreError.unableToCreateRustSession
      }
      self.db = database
      self.session = session

      try replayLedger(into: session, db: database)
      try rewriteProjections(using: session, db: database)
    } catch {
      sqlite3_close(database)
      self.db = nil
      self.session = nil
      throw error
    }
  }

  private func resolveDatabaseURL() throws -> URL {
    if let databaseURLOverride {
      let directory = databaseURLOverride.deletingLastPathComponent()
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      return databaseURLOverride
    }

    guard let applicationSupport = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first else {
      throw StatisticsStoreError.applicationSupportUnavailable
    }

    let directory = applicationSupport
      .appendingPathComponent("VivyShot", isDirectory: true)
      .appendingPathComponent("history", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("history.sqlite", isDirectory: false)
  }

  private func openDatabase(at url: URL) throws -> OpaquePointer {
    var db: OpaquePointer?
    let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
    if sqlite3_open_v2(url.path, &db, flags, nil) != SQLITE_OK {
      let message = db.flatMap { sqliteErrorMessage(db: $0) } ?? "Unable to open database"
      if let db {
        sqlite3_close(db)
      }
      throw StatisticsStoreError.sqlite(message)
    }
    guard let db else {
      throw StatisticsStoreError.sqlite("Unable to open database")
    }
    return db
  }

  private func configureDatabase(_ db: OpaquePointer) throws {
    try execute("PRAGMA journal_mode=WAL;", db: db)
    try execute("PRAGMA foreign_keys=ON;", db: db)
    try execute("PRAGMA busy_timeout=3000;", db: db)
  }

  private func installSchema(_ db: OpaquePointer) throws {
    try execute(
      """
      CREATE TABLE IF NOT EXISTS stats_lifetime_totals (
        singleton_key INTEGER PRIMARY KEY CHECK (singleton_key = 1),
        total_screenshots_captured INTEGER NOT NULL DEFAULT 0,
        total_recordings_completed INTEGER NOT NULL DEFAULT 0,
        total_recorded_duration_ms INTEGER NOT NULL DEFAULT 0,
        total_screenshot_completion_duration_ms INTEGER NOT NULL DEFAULT 0,
        completed_screenshot_session_count INTEGER NOT NULL DEFAULT 0,
        total_capture_bytes_produced INTEGER NOT NULL DEFAULT 0,
        current_capture_streak_days INTEGER NOT NULL DEFAULT 0,
        best_capture_streak_days INTEGER NOT NULL DEFAULT 0,
        first_capture_day_key TEXT,
        last_capture_day_key TEXT,
        updated_at_ms INTEGER NOT NULL
      );
      """,
      db: db
    )

    try execute(
      """
      CREATE TABLE IF NOT EXISTS stats_daily_capture (
        day_key TEXT PRIMARY KEY,
        screenshot_count INTEGER NOT NULL DEFAULT 0,
        recording_count INTEGER NOT NULL DEFAULT 0,
        recorded_duration_ms INTEGER NOT NULL DEFAULT 0,
        capture_bytes_produced INTEGER NOT NULL DEFAULT 0,
        first_capture_at_ms INTEGER,
        last_capture_at_ms INTEGER
      );
      """,
      db: db
    )

    try execute(
      """
      CREATE TABLE IF NOT EXISTS stats_ingested_events (
        event_key TEXT PRIMARY KEY,
        source_type TEXT NOT NULL CHECK (
          source_type IN (
            'screenshot_capture',
            'screenshot_session_completed',
            'recording_completed'
          )
        ),
        occurred_at_ms INTEGER NOT NULL,
        timezone_offset_minutes INTEGER NOT NULL,
        capture_id TEXT NOT NULL,
        bytes_produced INTEGER NOT NULL,
        duration_ms INTEGER,
        screenshot_completion_duration_ms INTEGER,
        persisted_at_ms INTEGER NOT NULL
      );
      """,
      db: db
    )

    try execute(
      "CREATE INDEX IF NOT EXISTS idx_stats_ingested_events_occurred ON stats_ingested_events(occurred_at_ms ASC, event_key ASC);",
      db: db
    )
    try execute(
      "CREATE INDEX IF NOT EXISTS idx_stats_ingested_events_capture ON stats_ingested_events(capture_id, source_type);",
      db: db
    )
  }

  private func replayLedger(into session: RustStatsSession, db: OpaquePointer) throws {
    let statement = try prepare(
      """
      SELECT
        event_key,
        source_type,
        occurred_at_ms,
        timezone_offset_minutes,
        capture_id,
        bytes_produced,
        duration_ms,
        screenshot_completion_duration_ms
      FROM stats_ingested_events
      ORDER BY occurred_at_ms ASC, event_key ASC;
      """,
      db: db
    )
    defer { sqlite3_finalize(statement) }

    while sqlite3_step(statement) == SQLITE_ROW {
      let event = RustStatsEvent(
        eventKey: try columnText(statement, index: 0),
        eventType: try eventType(from: columnText(statement, index: 1)),
        occurredAtMS: sqlite3_column_int64(statement, 2),
        timezoneOffsetMinutes: Int32(sqlite3_column_int(statement, 3)),
        bytesProduced: sqlite3_column_int64(statement, 5),
        durationMS: sqlite3_column_type(statement, 6) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, 6),
        screenshotCompletionDurationMS: sqlite3_column_type(statement, 7) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, 7),
        captureID: try columnText(statement, index: 4)
      )
      guard let applied = session.ingestEvent(event), applied else {
        continue
      }
    }
  }

  private func insertLedgerEventIfNeeded(
    _ event: RustStatsEvent,
    sourceType: String,
    db: OpaquePointer
  ) throws -> Bool {
    let statement = try prepare(
      """
      INSERT OR IGNORE INTO stats_ingested_events (
        event_key,
        source_type,
        occurred_at_ms,
        timezone_offset_minutes,
        capture_id,
        bytes_produced,
        duration_ms,
        screenshot_completion_duration_ms,
        persisted_at_ms
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
      """,
      db: db
    )
    defer { sqlite3_finalize(statement) }

    try bind(statement, text: event.eventKey, index: 1)
    try bind(statement, text: sourceType, index: 2)
    sqlite3_bind_int64(statement, 3, event.occurredAtMS)
    sqlite3_bind_int(statement, 4, Int32(event.timezoneOffsetMinutes))
    try bind(statement, text: event.captureID, index: 5)
    sqlite3_bind_int64(statement, 6, event.bytesProduced)
    if let durationMS = event.durationMS {
      sqlite3_bind_int64(statement, 7, durationMS)
    } else {
      sqlite3_bind_null(statement, 7)
    }
    if let screenshotDuration = event.screenshotCompletionDurationMS {
      sqlite3_bind_int64(statement, 8, screenshotDuration)
    } else {
      sqlite3_bind_null(statement, 8)
    }
    sqlite3_bind_int64(statement, 9, Date().epochMilliseconds)

    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw StatisticsStoreError.sqlite(sqliteErrorMessage(db: db))
    }
    return sqlite3_changes(db) > 0
  }

  private func rewriteProjections(using session: RustStatsSession, db: OpaquePointer) throws {
    guard let summary = session.summary() else {
      throw StatisticsStoreError.rustSummaryUnavailable
    }
    let buckets = session.allDailyBuckets()

    try replaceLifetimeTotals(summary, db: db)
    try replaceDailyBuckets(buckets, db: db)
  }

  private func replaceLifetimeTotals(_ summary: RustStatsSummary, db: OpaquePointer) throws {
    let statement = try prepare(
      """
      INSERT INTO stats_lifetime_totals (
        singleton_key,
        total_screenshots_captured,
        total_recordings_completed,
        total_recorded_duration_ms,
        total_screenshot_completion_duration_ms,
        completed_screenshot_session_count,
        total_capture_bytes_produced,
        current_capture_streak_days,
        best_capture_streak_days,
        first_capture_day_key,
        last_capture_day_key,
        updated_at_ms
      ) VALUES (1, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(singleton_key) DO UPDATE SET
        total_screenshots_captured = excluded.total_screenshots_captured,
        total_recordings_completed = excluded.total_recordings_completed,
        total_recorded_duration_ms = excluded.total_recorded_duration_ms,
        total_screenshot_completion_duration_ms = excluded.total_screenshot_completion_duration_ms,
        completed_screenshot_session_count = excluded.completed_screenshot_session_count,
        total_capture_bytes_produced = excluded.total_capture_bytes_produced,
        current_capture_streak_days = excluded.current_capture_streak_days,
        best_capture_streak_days = excluded.best_capture_streak_days,
        first_capture_day_key = excluded.first_capture_day_key,
        last_capture_day_key = excluded.last_capture_day_key,
        updated_at_ms = excluded.updated_at_ms;
      """,
      db: db
    )
    defer { sqlite3_finalize(statement) }

    sqlite3_bind_int64(statement, 1, summary.totalScreenshotsCaptured)
    sqlite3_bind_int64(statement, 2, summary.totalRecordingsCompleted)
    sqlite3_bind_int64(statement, 3, summary.totalRecordedDurationMS)
    sqlite3_bind_int64(statement, 4, summary.totalScreenshotCompletionDurationMS)
    sqlite3_bind_int64(statement, 5, summary.completedScreenshotSessionCount)
    sqlite3_bind_int64(statement, 6, summary.totalCaptureBytesProduced)
    sqlite3_bind_int(statement, 7, Int32(summary.currentCaptureStreakDays))
    sqlite3_bind_int(statement, 8, Int32(summary.bestCaptureStreakDays))
    try bindNullable(statement, text: summary.firstCaptureDay?.yyyyMMdd, index: 9)
    try bindNullable(statement, text: summary.lastCaptureDay?.yyyyMMdd, index: 10)
    sqlite3_bind_int64(statement, 11, Date().epochMilliseconds)

    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw StatisticsStoreError.sqlite(sqliteErrorMessage(db: db))
    }
  }

  private func replaceDailyBuckets(_ buckets: [RustStatsDailyBucket], db: OpaquePointer) throws {
    try execute("DELETE FROM stats_daily_capture;", db: db)
    guard !buckets.isEmpty else {
      return
    }

    let statement = try prepare(
      """
      INSERT INTO stats_daily_capture (
        day_key,
        screenshot_count,
        recording_count,
        recorded_duration_ms,
        capture_bytes_produced,
        first_capture_at_ms,
        last_capture_at_ms
      ) VALUES (?, ?, ?, ?, ?, ?, ?);
      """,
      db: db
    )
    defer { sqlite3_finalize(statement) }

    for bucket in buckets {
      sqlite3_reset(statement)
      sqlite3_clear_bindings(statement)
      try bind(statement, text: bucket.day.yyyyMMdd, index: 1)
      sqlite3_bind_int(statement, 2, Int32(bucket.screenshotCount))
      sqlite3_bind_int(statement, 3, Int32(bucket.recordingCount))
      sqlite3_bind_int64(statement, 4, bucket.recordedDurationMS)
      sqlite3_bind_int64(statement, 5, bucket.captureBytesProduced)
      if let firstCaptureAtMS = bucket.firstCaptureAtMS {
        sqlite3_bind_int64(statement, 6, firstCaptureAtMS)
      } else {
        sqlite3_bind_null(statement, 6)
      }
      if let lastCaptureAtMS = bucket.lastCaptureAtMS {
        sqlite3_bind_int64(statement, 7, lastCaptureAtMS)
      } else {
        sqlite3_bind_null(statement, 7)
      }

      guard sqlite3_step(statement) == SQLITE_DONE else {
        throw StatisticsStoreError.sqlite(sqliteErrorMessage(db: db))
      }
    }
  }

  private func prepare(_ sql: String, db: OpaquePointer) throws -> OpaquePointer {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
      throw StatisticsStoreError.sqlite(sqliteErrorMessage(db: db))
    }
    return statement
  }

  private func execute(_ sql: String, db: OpaquePointer) throws {
    guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
      throw StatisticsStoreError.sqlite(sqliteErrorMessage(db: db))
    }
  }

  private func beginTransaction(_ db: OpaquePointer) throws {
    try execute("BEGIN IMMEDIATE TRANSACTION;", db: db)
  }

  private func commitTransaction(_ db: OpaquePointer) throws {
    try execute("COMMIT TRANSACTION;", db: db)
  }

  private func rollbackTransaction(_ db: OpaquePointer) {
    _ = sqlite3_exec(db, "ROLLBACK TRANSACTION;", nil, nil, nil)
  }

  private func bind(_ statement: OpaquePointer, text: String, index: Int32) throws {
    guard sqlite3_bind_text(statement, index, text, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
      throw StatisticsStoreError.sqlite("Unable to bind text")
    }
  }

  private func bindNullable(_ statement: OpaquePointer, text: String?, index: Int32) throws {
    if let text {
      try bind(statement, text: text, index: index)
    } else {
      sqlite3_bind_null(statement, index)
    }
  }

  private func columnText(_ statement: OpaquePointer, index: Int32) throws -> String {
    guard let cString = sqlite3_column_text(statement, index) else {
      throw StatisticsStoreError.sqlite("Missing text column")
    }
    return String(cString: cString)
  }

  private func firstOccurredAt(sourceType: String, db: OpaquePointer) throws -> Date? {
    let statement = try prepare(
      """
      SELECT MIN(occurred_at_ms)
      FROM stats_ingested_events
      WHERE source_type = ?;
      """,
      db: db
    )
    defer { sqlite3_finalize(statement) }

    try bind(statement, text: sourceType, index: 1)
    guard sqlite3_step(statement) == SQLITE_ROW else {
      throw StatisticsStoreError.sqlite(sqliteErrorMessage(db: db))
    }
    guard sqlite3_column_type(statement, 0) != SQLITE_NULL else {
      return nil
    }
    return Date(epochMilliseconds: sqlite3_column_int64(statement, 0))
  }

  private func postStatisticsDidChange() {
    Task { @MainActor in
      NotificationCenter.default.post(name: .vivyShotStatisticsDidChange, object: nil)
    }
  }

  private func eventType(from sourceType: String) throws -> RustStatsEventType {
    switch sourceType {
    case "screenshot_capture":
      return .screenshotCaptured
    case "screenshot_session_completed":
      return .screenshotSessionCompleted
    case "recording_completed":
      return .recordingCompleted
    default:
      throw StatisticsStoreError.sqlite("Unknown statistics source type: \(sourceType)")
    }
  }

  private func sqliteErrorMessage(db: OpaquePointer) -> String {
    if let message = sqlite3_errmsg(db) {
      return String(cString: message)
    }
    return "SQLite error"
  }
}

private enum StatisticsStoreError: LocalizedError {
  case applicationSupportUnavailable
  case unableToCreateRustSession
  case rustIngestFailed
  case rustSummaryUnavailable
  case sqlite(String)

  var errorDescription: String? {
    switch self {
    case .applicationSupportUnavailable:
      return "Application Support directory is unavailable"
    case .unableToCreateRustSession:
      return "Unable to create Rust statistics session"
    case .rustIngestFailed:
      return "Rust statistics ingest failed"
    case .rustSummaryUnavailable:
      return "Rust statistics summary unavailable"
    case .sqlite(let message):
      return message
    }
  }
}

private extension Date {
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
