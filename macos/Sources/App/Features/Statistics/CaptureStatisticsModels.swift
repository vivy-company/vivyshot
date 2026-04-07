import Foundation

extension Notification.Name {
  static let vivyShotStatisticsDidChange = Notification.Name("com.vivyshot.statisticsDidChange")
}

struct CaptureStatisticsDashboardData: Sendable {
  let summary: RustStatsSummary
  let dailyBuckets: [RustStatsDailyBucket]
  let firstScreenshotAt: Date?
  let firstRecordingAt: Date?
}

extension CaptureStatisticsDashboardData {
  static let empty = CaptureStatisticsDashboardData(
    summary: RustStatsSummary(
      totalScreenshotsCaptured: 0,
      totalRecordingsCompleted: 0,
      totalRecordedDurationMS: 0,
      totalScreenshotCompletionDurationMS: 0,
      completedScreenshotSessionCount: 0,
      averageScreenshotEditorCompletionDurationMS: 0,
      totalCaptureBytesProduced: 0,
      currentCaptureStreakDays: 0,
      bestCaptureStreakDays: 0,
      activeCaptureDays: 0,
      firstCaptureDay: nil,
      lastCaptureDay: nil,
      mostActiveDay: nil,
      mostActiveDayScore: 0
    ),
    dailyBuckets: [],
    firstScreenshotAt: nil,
    firstRecordingAt: nil
  )
}

enum StatisticsGraphRange: String, CaseIterable, Identifiable {
  case threeMonths
  case sixMonths
  case oneYear
  case all

  var id: String { rawValue }

  var title: String {
    switch self {
    case .threeMonths:
      return "3M"
    case .sixMonths:
      return "6M"
    case .oneYear:
      return "1Y"
    case .all:
      return "All"
    }
  }

  var rollingDayCount: Int? {
    switch self {
    case .threeMonths:
      return 90
    case .sixMonths:
      return 182
    case .oneYear:
      return 365
    case .all:
      return nil
    }
  }
}

extension RustStatsDayKey {
  func asDate(calendar: Calendar = .autoupdatingCurrent) -> Date? {
    calendar.date(from: DateComponents(year: year, month: month, day: day))
  }
}

extension RustStatsDailyBucket {
  var activityScore: Int64 {
    Int64(screenshotCount) + Int64(recordingCount * 3) + (recordedDurationMS / 300_000)
  }
}
