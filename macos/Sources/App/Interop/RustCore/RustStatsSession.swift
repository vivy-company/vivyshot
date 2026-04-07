import Foundation
import VivyShotKit

final class RustStatsSession {
  private static let maxSerializedBytes = 8_388_608
  private static let absentMetricValue: Int64 = -1

  private let handle: UnsafeMutableRawPointer

  init?() {
    guard let rawHandle = vs_stats_session_create() else {
      return nil
    }
    handle = rawHandle
  }

  private init(handle: UnsafeMutableRawPointer) {
    self.handle = handle
  }

  static func deserialize(json: Data) -> RustStatsSession? {
    guard !json.isEmpty else {
      return nil
    }
    let rawHandle: UnsafeMutableRawPointer? = json.withUnsafeBytes { raw in
      guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
        return nil
      }
      return vs_stats_session_deserialize_json(base, UInt32(raw.count))
    }
    guard let rawHandle else {
      return nil
    }
    return RustStatsSession(handle: rawHandle)
  }

  deinit {
    vs_stats_session_destroy(handle)
  }

  func ingestEvent(_ event: RustStatsEvent) -> Bool? {
    let eventKeyBytes = Array(event.eventKey.utf8)
    let captureIDBytes = Array(event.captureID.utf8)
    guard !eventKeyBytes.isEmpty, !captureIDBytes.isEmpty else {
      return nil
    }

    var applied = false
    let status = eventKeyBytes.withUnsafeBytes { eventKeyRaw in
      captureIDBytes.withUnsafeBytes { captureIDRaw in
        let raw = vs_stats_event(
          event_type: event.eventType.rawValue,
          reserved0: (0, 0, 0),
          timezone_offset_minutes: event.timezoneOffsetMinutes,
          occurred_at_ms: event.occurredAtMS,
          bytes_produced: event.bytesProduced,
          duration_ms: event.durationMS ?? Self.absentMetricValue,
          screenshot_completion_duration_ms: event.screenshotCompletionDurationMS ?? Self.absentMetricValue,
          event_key_ptr: eventKeyRaw.baseAddress?.assumingMemoryBound(to: UInt8.self),
          event_key_len: UInt(eventKeyRaw.count),
          capture_id_ptr: captureIDRaw.baseAddress?.assumingMemoryBound(to: UInt8.self),
          capture_id_len: UInt(captureIDRaw.count)
        )
        return vs_stats_session_ingest_event(handle, raw, &applied)
      }
    }

    guard RustFFIStatus.isSuccess(status) else {
      return nil
    }
    return applied
  }

  func summary() -> RustStatsSummary? {
    var raw = vs_stats_summary()
    let status = vs_stats_session_get_summary(handle, &raw)
    guard RustFFIStatus.isSuccess(status) else {
      return nil
    }
    return RustStatsSummary(
      totalScreenshotsCaptured: raw.total_screenshots_captured,
      totalRecordingsCompleted: raw.total_recordings_completed,
      totalRecordedDurationMS: raw.total_recorded_duration_ms,
      totalScreenshotCompletionDurationMS: raw.total_screenshot_completion_duration_ms,
      completedScreenshotSessionCount: raw.completed_screenshot_session_count,
      averageScreenshotEditorCompletionDurationMS: raw.average_screenshot_editor_completion_duration_ms,
      totalCaptureBytesProduced: raw.total_capture_bytes_produced,
      currentCaptureStreakDays: Int(raw.current_capture_streak_days),
      bestCaptureStreakDays: Int(raw.best_capture_streak_days),
      activeCaptureDays: Int(raw.active_capture_days),
      firstCaptureDay: raw.has_first_capture_day ? Self.makeDayKey(raw.first_capture_day) : nil,
      lastCaptureDay: raw.has_last_capture_day ? Self.makeDayKey(raw.last_capture_day) : nil,
      mostActiveDay: raw.has_most_active_day ? Self.makeDayKey(raw.most_active_day) : nil,
      mostActiveDayScore: raw.most_active_day_score
    )
  }

  func allDailyBuckets() -> [RustStatsDailyBucket] {
    loadDailyBuckets { outPtr, outCap, outWritten in
      vs_stats_session_get_all_daily_buckets(handle, outPtr, outCap, outWritten)
    }
  }

  func recentDailyBuckets(dayCount: Int) -> [RustStatsDailyBucket] {
    let clamped = UInt32(max(0, dayCount))
    return loadDailyBuckets { outPtr, outCap, outWritten in
      vs_stats_session_get_recent_daily_buckets(handle, clamped, outPtr, outCap, outWritten)
    }
  }

  func reset() -> Bool {
    RustFFIStatus.isSuccess(vs_stats_session_reset(handle))
  }

  func serializeJSON() -> Data? {
    var capacity = 1024
    while capacity <= Self.maxSerializedBytes {
      var buffer = [UInt8](repeating: 0, count: capacity)
      var written: UInt32 = 0
      let result = buffer.withUnsafeMutableBufferPointer { ptr in
        vs_stats_session_serialize_json(handle, ptr.baseAddress, UInt32(ptr.count), &written)
      }
      if result == VS_STATUS_BUFFER_TOO_SMALL {
        capacity = max(capacity * 2, Int(written))
        continue
      }
      guard RustFFIStatus.isSuccess(result) else {
        return nil
      }

      let required = Int(written)
      guard required <= buffer.count else {
        capacity = max(capacity * 2, required)
        continue
      }
      return Data(buffer.prefix(required))
    }
    return nil
  }

  private func loadDailyBuckets(
    _ loader: (_ outPtr: UnsafeMutablePointer<vs_stats_daily_bucket>?, _ outCap: UInt32, _ outWritten: UnsafeMutablePointer<UInt32>?) -> Int32
  ) -> [RustStatsDailyBucket] {
    var capacity = 64
    while capacity <= 16_384 {
      var buffer = [vs_stats_daily_bucket](repeating: vs_stats_daily_bucket(), count: capacity)
      var written: UInt32 = 0
      let result = buffer.withUnsafeMutableBufferPointer { ptr in
        loader(ptr.baseAddress, UInt32(ptr.count), &written)
      }
      guard RustFFIStatus.isSuccess(result) else {
        return []
      }

      let required = Int(written)
      if required <= buffer.count {
        return buffer.prefix(required).map(Self.makeDailyBucket)
      }
      capacity = max(capacity * 2, required)
    }
    return []
  }

  private static func makeDayKey(_ raw: vs_stats_day_key) -> RustStatsDayKey {
    RustStatsDayKey(year: Int(raw.year), month: Int(raw.month), day: Int(raw.day))
  }

  private static func makeDailyBucket(_ raw: vs_stats_daily_bucket) -> RustStatsDailyBucket {
    RustStatsDailyBucket(
      day: makeDayKey(raw.day),
      screenshotCount: Int(raw.screenshot_count),
      recordingCount: Int(raw.recording_count),
      recordedDurationMS: raw.recorded_duration_ms,
      captureBytesProduced: raw.capture_bytes_produced,
      firstCaptureAtMS: raw.has_first_capture_at_ms ? raw.first_capture_at_ms : nil,
      lastCaptureAtMS: raw.has_last_capture_at_ms ? raw.last_capture_at_ms : nil
    )
  }
}
