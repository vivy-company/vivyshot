import Foundation

struct StatisticsDashboardPresentation {
  let dashboardData: StatisticsDashboard
  var calendar: Calendar = .autoupdatingCurrent

  var hasAnyCaptureData: Bool {
    let s = dashboardData.summary
    return s.totalScreenshotsCaptured > 0 || s.totalRecordingsCompleted > 0 || !dashboardData.dailyBuckets.isEmpty
  }

  var totalCaptureCount: Int64 {
    Int64(dashboardData.summary.totalScreenshotsCaptured + dashboardData.summary.totalRecordingsCompleted)
  }

  var todayAggregate: StatisticsAggregate {
    let today = calendar.startOfDay(for: Date())
    return aggregateBuckets(in: StatisticsGraphBounds(startDate: today, endDate: today))
  }

  var currentWeekAggregate: StatisticsAggregate {
    let interval = calendar.dateInterval(of: .weekOfYear, for: Date())
    let start = calendar.startOfDay(for: interval?.start ?? Date())
    let end = calendar.startOfDay(for: interval.flatMap { calendar.date(byAdding: .day, value: -1, to: $0.end) } ?? Date())
    return aggregateBuckets(in: StatisticsGraphBounds(startDate: start, endDate: end))
  }

  var mostActiveDayLabel: String {
    guard let day = dashboardData.summary.mostActiveDay else { return "No activity yet" }
    return "\(StatisticsFormatting.formatDayKey(day)) \u{2022} score \(dashboardData.summary.mostActiveDayScore)"
  }

  func aggregate(for range: StatisticsGraphRange) -> StatisticsAggregate {
    aggregateBuckets(in: graphRangeBounds(for: range))
  }

  func hasActivity(in range: StatisticsGraphRange) -> Bool {
    aggregate(for: range).totalCaptureCount > 0
  }

  func activeDayCount(in range: StatisticsGraphRange) -> Int {
    let bounds = graphRangeBounds(for: range)
    return dashboardData.dailyBuckets.reduce(into: 0) { count, bucket in
      guard bucket.activityScore > 0, let bucketDate = bucket.day.asDate(calendar: calendar) else { return }
      let normalized = calendar.startOfDay(for: bucketDate)
      if normalized >= bounds.startDate && normalized <= bounds.endDate { count += 1 }
    }
  }

  func busiestDaySummary(in range: StatisticsGraphRange) -> String {
    let bounds = graphRangeBounds(for: range)
    guard let bucket = dashboardData.dailyBuckets
      .filter({ b in
        guard b.activityScore > 0, let d = b.day.asDate(calendar: calendar) else { return false }
        let n = calendar.startOfDay(for: d)
        return n >= bounds.startDate && n <= bounds.endDate
      })
      .max(by: { $0.activityScore < $1.activityScore })
    else { return "No activity yet" }

    let total = Int64(bucket.screenshotCount + bucket.recordingCount)
    return "\(StatisticsFormatting.formatDayKey(bucket.day)) \u{2022} \(total.formatted()) captures"
  }

  func dayRangeDescription(for range: StatisticsGraphRange) -> String {
    guard hasAnyCaptureData else {
      return "Capture activity appears here after your first screenshot or recording."
    }
    let bounds = graphRangeBounds(for: range)
    return "\(StatisticsFormatting.formatDate(bounds.startDate)) to \(StatisticsFormatting.formatDate(bounds.endDate))"
  }

  func recentMetricValues(dayCount: Int = 10, value: (StatsDailyBucket) -> Double) -> [Double] {
    let today = calendar.startOfDay(for: Date())
    let byKey = Dictionary(uniqueKeysWithValues: dashboardData.dailyBuckets.map { ($0.day.yyyyMMdd, $0) })
    return (0..<dayCount).map { i in
      let date = calendar.date(byAdding: .day, value: i - (dayCount - 1), to: today) ?? today
      guard let bucket = byKey[StatisticsFormatting.dayKey(for: date, calendar: calendar)] else { return 0 }
      return value(bucket)
    }
  }

  func recentActivityDays(dayCount: Int = 7) -> [StatisticsRecentActivityDay] {
    let today = calendar.startOfDay(for: Date())
    let byKey = Dictionary(uniqueKeysWithValues: dashboardData.dailyBuckets.map { ($0.day.yyyyMMdd, $0) })
    return (0..<dayCount).map { i in
      let date = calendar.date(byAdding: .day, value: i - (dayCount - 1), to: today) ?? today
      let bucket = byKey[StatisticsFormatting.dayKey(for: date, calendar: calendar)]
      return StatisticsRecentActivityDay(
        date: date,
        screenshotCount: Int64(bucket?.screenshotCount ?? 0),
        recordingCount: Int64(bucket?.recordingCount ?? 0),
        recordedDurationMS: bucket?.recordedDurationMS ?? 0,
        captureBytesProduced: bucket?.captureBytesProduced ?? 0
      )
    }
  }

  func graphRangeBounds(for range: StatisticsGraphRange) -> StatisticsGraphBounds {
    statisticsGraphBounds(for: range, dashboardData: dashboardData, calendar: calendar)
  }

  func makeGraphWeeks(range: StatisticsGraphRange) -> [StatisticsGraphWeek] {
    let bounds = graphRangeBounds(for: range)
    return makeGraphWeeks(startDate: bounds.startDate, endDate: bounds.endDate)
  }

  func aggregateBuckets(in bounds: StatisticsGraphBounds) -> StatisticsAggregate {
    dashboardData.dailyBuckets.reduce(into: StatisticsAggregate()) { agg, bucket in
      guard let d = bucket.day.asDate(calendar: calendar) else { return }
      let n = calendar.startOfDay(for: d)
      if n >= bounds.startDate && n <= bounds.endDate { agg.add(bucket) }
    }
  }

  func makeGraphWeeks(startDate: Date, endDate: Date) -> [StatisticsGraphWeek] {
    let normStart = calendar.startOfDay(for: startDate)
    let normEnd = calendar.startOfDay(for: endDate)
    let firstGrid = calendar.dateInterval(of: .weekOfYear, for: normStart)?.start ?? normStart
    let lastGrid = calendar.date(byAdding: .day, value: 6, to: calendar.dateInterval(of: .weekOfYear, for: normEnd)?.start ?? normEnd) ?? normEnd
    let byKey = Dictionary(uniqueKeysWithValues: dashboardData.dailyBuckets.map { ($0.day.yyyyMMdd, $0) })

    var days: [StatisticsGraphDay] = []
    var current = firstGrid
    while current <= lastGrid {
      let key = StatisticsFormatting.dayKey(for: current, calendar: calendar)
      days.append(StatisticsGraphDay(
        date: current,
        bucket: byKey[key],
        intensity: 0,
        isOutsidePrimaryRange: current < normStart || current > normEnd
      ))
      current = calendar.date(byAdding: .day, value: 1, to: current) ?? current.addingTimeInterval(86_400)
      if days.count > 2_500 { break }
    }

    let maxScore = max(days.compactMap { $0.bucket?.activityScore }.max() ?? 0, 1)
    let normalized = days.map { day in
      StatisticsGraphDay(
        date: day.date,
        bucket: day.bucket,
        intensity: Self.intensity(for: day.bucket?.activityScore ?? 0, maxScore: maxScore),
        isOutsidePrimaryRange: day.isOutsidePrimaryRange
      )
    }

    var weeks: [StatisticsGraphWeek] = []
    var i = 0
    while i < normalized.count {
      let slice = Array(normalized[i..<min(i + 7, normalized.count)])
      if let first = slice.first?.date {
        weeks.append(StatisticsGraphWeek(startDate: first, days: slice))
      }
      i += 7
    }
    return weeks
  }

  static func captureMixLabel(_ aggregate: StatisticsAggregate) -> String {
    let screenshots = aggregate.screenshotCount
    let recordings = aggregate.recordingCount
    if screenshots == 0 && recordings == 0 {
      return "No captures yet"
    }
    return "\(screenshots.formatted()) \(screenshots == 1 ? "screenshot" : "screenshots") \u{2022} \(recordings.formatted()) \(recordings == 1 ? "recording" : "recordings")"
  }

  static func dayCountLabel(_ count: Int) -> String {
    count == 1 ? "1 day" : "\(count) days"
  }

  static func orderedWeekdaySymbols(calendar: Calendar = .autoupdatingCurrent) -> [String] {
    let symbols = calendar.shortWeekdaySymbols
    let start = max(calendar.firstWeekday - 1, 0)
    return (Array(symbols[start...]) + Array(symbols[..<start])).map { String($0.prefix(1)) }
  }

  private static func intensity(for score: Int64, maxScore: Int64) -> Int {
    guard score > 0 else { return 0 }
    let n = Double(score) / Double(maxScore)
    switch n {
    case ..<0.25: return 1
    case ..<0.5: return 2
    case ..<0.75: return 3
    default: return 4
    }
  }
}
