import Foundation

/// Complete data set required by the statistics dashboard.
struct StatisticsDashboard: Sendable {
  let summary: StatsSummary
  let dailyBuckets: [StatsDailyBucket]
  let firstScreenshotAt: Date?
  let firstRecordingAt: Date?
}

extension StatisticsDashboard {
  static let empty = StatisticsDashboard(
    summary: StatsSummary(
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

/// Date range selected for statistics charts.
enum StatisticsGraphRange: String, CaseIterable, Identifiable {
  case sevenDays
  case threeMonths
  case sixMonths
  case oneYear
  case all

  var id: String { rawValue }

  var title: String {
    switch self {
    case .sevenDays:
      return "7D"
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
    case .sevenDays:
      return 7
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

extension StatsDayKey {
  func asDate(calendar: Calendar = .autoupdatingCurrent) -> Date? {
    calendar.date(from: DateComponents(year: year, month: month, day: day))
  }
}

extension StatsDailyBucket {
  var activityScore: Int64 {
    Int64(screenshotCount) + Int64(recordingCount * 3) + (recordedDurationMS / 300_000)
  }
}
