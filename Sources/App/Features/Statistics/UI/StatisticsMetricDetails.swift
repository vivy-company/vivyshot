import Charts
import SwiftUI

enum StatisticsOverviewMetric: String, CaseIterable, Identifiable, Hashable {
  case screenshots
  case recordings
  case recordingTime
  case storage

  var id: String { rawValue }

  var title: String {
    switch self {
    case .screenshots: return "Total Screenshots"
    case .recordings: return "Total Recordings"
    case .recordingTime: return "Total Recording Time"
    case .storage: return "Storage Produced"
    }
  }

  var menuTitle: String {
    switch self {
    case .screenshots: return "Screenshots"
    case .recordings: return "Recordings"
    case .recordingTime: return "Recording Time"
    case .storage: return "Storage"
    }
  }

  var sectionTitle: String {
    switch self {
    case .screenshots: return "Screenshots"
    case .recordings: return "Recordings"
    case .recordingTime: return "Recording Time"
    case .storage: return "Storage"
    }
  }

  var subtitle: String {
    switch self {
    case .screenshots: return "All screenshots captured on this Mac across the selected range."
    case .recordings: return "Completed video recordings across the selected range."
    case .recordingTime: return "Recorded duration from finished capture sessions."
    case .storage: return "Estimated disk output created by captures in the selected range."
    }
  }

  var systemImage: String {
    switch self {
    case .screenshots: return "camera"
    case .recordings: return "record.circle"
    case .recordingTime: return "timer"
    case .storage: return "internaldrive"
    }
  }

  var totalLabel: String {
    switch self {
    case .screenshots: return "Screenshots"
    case .recordings: return "Recordings"
    case .recordingTime: return "Recorded"
    case .storage: return "Produced"
    }
  }

  var peakLabel: String {
    switch self {
    case .screenshots: return "Most Screenshots"
    case .recordings: return "Most Recordings"
    case .recordingTime: return "Longest Day"
    case .storage: return "Largest Day"
    }
  }

  func value(for bucket: StatsDailyBucket) -> Double {
    switch self {
    case .screenshots: return Double(bucket.screenshotCount)
    case .recordings: return Double(bucket.recordingCount)
    case .recordingTime: return Double(bucket.recordedDurationMS)
    case .storage: return Double(bucket.captureBytesProduced)
    }
  }

  func formatValue(_ value: Double) -> String {
    switch self {
    case .screenshots, .recordings: return Int64(value.rounded()).formatted()
    case .recordingTime: return StatisticsFormatting.formatDuration(Int64(value.rounded()))
    case .storage: return StatisticsFormatting.formatBytes(Int64(value.rounded()))
    }
  }

  func formatYAxisValue(_ value: Double) -> String {
    switch self {
    case .screenshots, .recordings: return Int(value.rounded()).formatted()
    case .recordingTime: return StatisticsFormatting.formatDuration(Int64(value.rounded()))
    case .storage: return StatisticsFormatting.formatBytes(Int64(value.rounded()))
    }
  }

  func peakSummary(for point: StatisticsMetricDetailPoint) -> String {
    let date = StatisticsFormatting.formatDate(point.date)
    switch self {
    case .screenshots:
      let c = Int64(point.value.rounded())
      return "\(date) \u{2022} \(c.formatted())"
    case .recordings:
      let c = Int64(point.value.rounded())
      return "\(date) \u{2022} \(c.formatted()) \(c == 1 ? "recording" : "recordings")"
    case .recordingTime, .storage:
      return "\(date) \u{2022} \(formatValue(point.value))"
    }
  }
}

struct StatisticsMetricDetailPanel: View {
  let metric: StatisticsOverviewMetric
  let dashboardData: StatisticsDashboard
  let selectedRange: StatisticsGraphRange
  let accentColor: Color

  private var bounds: StatisticsGraphBounds {
    statisticsGraphBounds(for: selectedRange, dashboardData: dashboardData)
  }

  private var points: [StatisticsMetricDetailPoint] {
    let calendar = Calendar.autoupdatingCurrent
    let byKey = Dictionary(uniqueKeysWithValues: dashboardData.dailyBuckets.map { ($0.day.yyyyMMdd, $0) })
    var results: [StatisticsMetricDetailPoint] = []
    var current = bounds.startDate
    while current <= bounds.endDate {
      let key = StatisticsFormatting.dayKey(for: current, calendar: calendar)
      let value = byKey[key].map(metric.value(for:)) ?? 0
      results.append(StatisticsMetricDetailPoint(date: current, value: value))
      current = calendar.date(byAdding: .day, value: 1, to: current) ?? current.addingTimeInterval(86_400)
      if results.count > 5_000 { break }
    }
    return results
  }

  private var hasData: Bool { points.contains { $0.value > 0 } }
  private var totalValue: Double { points.reduce(0) { $0 + $1.value } }
  private var activeDays: Int { points.reduce(into: 0) { if $1.value > 0 { $0 += 1 } } }
  private var peakPoint: StatisticsMetricDetailPoint? {
    points.filter { $0.value > 0 }.max { $0.value < $1.value }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if hasData {
        StatisticsMetricDetailChart(metric: metric, points: points, accentColor: accentColor)

        StatisticsMetricDetailSummaryRow(
          totalTitle: metric.totalLabel,
          totalValue: metric.formatValue(totalValue),
          activeDays: activeDays.formatted(),
          peakTitle: metric.peakLabel,
          peakValue: peakPoint.map { metric.peakSummary(for: $0) } ?? "No activity yet"
        )
      } else {
        ContentUnavailableView {
          Label("No data in this range", systemImage: metric.systemImage)
        } description: {
          Text("Try a wider range or create a few more captures to build this chart.")
        }
        .frame(maxWidth: .infinity).padding(.vertical, 18)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct StatisticsMetricDetailPoint: Identifiable {
  let date: Date
  let value: Double
  var id: Date { date }
}

private struct StatisticsMetricDetailChart: View {
  let metric: StatisticsOverviewMetric
  let points: [StatisticsMetricDetailPoint]
  let accentColor: Color

  var body: some View {
    Chart(points) { point in
      BarMark(
        x: .value("Day", point.date, unit: .day),
        y: .value(metric.title, point.value)
      )
      .foregroundStyle(accentColor.gradient)
      .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    }
    .chartXAxis {
      AxisMarks(values: .stride(by: .month)) { _ in
        AxisGridLine().foregroundStyle(.quaternary)
        AxisValueLabel(format: .dateTime.month(.abbreviated))
      }
    }
    .chartYAxis {
      AxisMarks(position: .leading) { value in
        AxisGridLine().foregroundStyle(.quaternary)
        AxisTick()
        if let y = value.as(Double.self) {
          AxisValueLabel(metric.formatYAxisValue(y))
        }
      }
    }
    .chartPlotStyle { plot in
      plot
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
    .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 180)
  }
}

private struct StatisticsMetricDetailSummaryRow: View {
  let totalTitle: String
  let totalValue: String
  let activeDays: String
  let peakTitle: String
  let peakValue: String

  var body: some View {
    HStack(spacing: 12) {
      summaryPill(title: totalTitle, value: totalValue)
      summaryPill(title: "Active Days", value: activeDays)
      summaryPill(title: peakTitle, value: peakValue)
    }
  }

  private func summaryPill(title: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title).font(.caption.weight(.medium))
      Text(value).font(.caption).foregroundStyle(.primary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(Color.secondary.opacity(0.08))
    )
  }
}
