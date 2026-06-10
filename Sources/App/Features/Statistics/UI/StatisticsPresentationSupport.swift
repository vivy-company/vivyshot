import Foundation

struct StatisticsAggregate {
  var screenshotCount: Int64 = 0
  var recordingCount: Int64 = 0
  var recordedDurationMS: Int64 = 0
  var captureBytesProduced: Int64 = 0

  var totalCaptureCount: Int64 { screenshotCount + recordingCount }

  mutating func add(_ bucket: StatsDailyBucket) {
    screenshotCount += Int64(bucket.screenshotCount)
    recordingCount += Int64(bucket.recordingCount)
    recordedDurationMS += bucket.recordedDurationMS
    captureBytesProduced += bucket.captureBytesProduced
  }
}

func statisticsGraphBounds(
  for range: StatisticsGraphRange,
  dashboardData: StatisticsDashboard,
  calendar: Calendar = .autoupdatingCurrent
) -> StatisticsGraphBounds {
  let today = calendar.startOfDay(for: Date())
  let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
  let monthEnd = calendar.dateInterval(of: .month, for: today)
    .flatMap { calendar.date(byAdding: .day, value: -1, to: $0.end) } ?? today

  switch range {
  case .sevenDays:
    let start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
    return StatisticsGraphBounds(startDate: start, endDate: today)
  case .threeMonths:
    let start = calendar.date(byAdding: .month, value: -2, to: monthStart) ?? monthStart
    return StatisticsGraphBounds(startDate: start, endDate: monthEnd)
  case .sixMonths:
    let start = calendar.date(byAdding: .month, value: -5, to: monthStart) ?? monthStart
    return StatisticsGraphBounds(startDate: start, endDate: monthEnd)
  case .oneYear:
    let start = calendar.date(byAdding: .month, value: -11, to: monthStart) ?? monthStart
    return StatisticsGraphBounds(startDate: start, endDate: monthEnd)
  case .all:
    let firstCapture = dashboardData.summary.firstCaptureDay?.asDate(calendar: calendar)
      ?? dashboardData.dailyBuckets.compactMap { $0.day.asDate(calendar: calendar) }.min()
      ?? today
    let start = calendar.date(from: calendar.dateComponents([.year], from: firstCapture)) ?? firstCapture
    let end = calendar.dateInterval(of: .year, for: today)
      .flatMap { calendar.date(byAdding: .day, value: -1, to: $0.end) } ?? monthEnd
    return StatisticsGraphBounds(startDate: start, endDate: end)
  }
}

enum StatisticsFormatting {
  static func formatDuration(_ durationMS: Int64) -> String {
    guard durationMS > 0 else { return "0s" }
    let f = DateComponentsFormatter()
    f.allowedUnits = durationMS >= 3_600_000 ? [.hour, .minute] : [.minute, .second]
    f.unitsStyle = .abbreviated
    f.zeroFormattingBehavior = [.dropLeading, .dropAll]
    return f.string(from: TimeInterval(durationMS) / 1000) ?? "0s"
  }

  static func formatBytes(_ bytes: Int64) -> String {
    guard bytes > 0 else { return "0 KB" }
    return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }

  static func formatDate(_ date: Date) -> String {
    DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none)
  }

  static func formatDateOptional(_ date: Date?) -> String {
    guard let date else { return "No data yet" }
    return formatDate(date)
  }

  static func formatDayKey(_ dayKey: StatsDayKey) -> String {
    formatDateOptional(dayKey.asDate())
  }

  static func dayKey(for date: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
    let c = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
  }
}
