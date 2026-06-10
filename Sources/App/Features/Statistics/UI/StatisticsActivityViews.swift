import SwiftUI

struct StatisticsMetricRow: View {
  let title: String
  let value: String
  let detail: String
  let systemImage: String
  var recentValues: [Double]? = nil

  var body: some View {
    HStack(alignment: .center, spacing: 14) {
      ZStack {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(Color.secondary.opacity(0.10))
          .frame(width: 34, height: 34)
        Image(systemName: systemImage)
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(.secondary)
      }

      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.body.weight(.medium))
        Text(detail).font(.caption).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 16)

      VStack(alignment: .trailing, spacing: 8) {
        Text(value)
          .font(.system(.body, design: .rounded).weight(.semibold))
          .monospacedDigit()
          .multilineTextAlignment(.trailing)
          .fixedSize(horizontal: true, vertical: false)

        if let recentValues {
          StatisticsInlineBarChart(values: recentValues)
        }
      }
    }
    .padding(.vertical, 2)
    .contentShape(Rectangle())
  }
}

struct StatisticsInsightPill: View {
  let title: String
  let value: String

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title)
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
      Text(value)
        .font(.system(.subheadline, design: .rounded).weight(.semibold))
        .foregroundStyle(.primary)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.8)
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

struct StatisticsRecentActivityDay: Identifiable {
  let date: Date
  let screenshotCount: Int64
  let recordingCount: Int64
  let recordedDurationMS: Int64
  let captureBytesProduced: Int64

  var id: Date { date }
  var totalCaptureCount: Int64 { screenshotCount + recordingCount }
}

struct StatisticsRecentActivityBarChart: View {
  let days: [StatisticsRecentActivityDay]
  let accentColor: Color

  private var maxCaptures: Double {
    max(Double(days.map(\.totalCaptureCount).max() ?? 0), 1)
  }

  var body: some View {
    GeometryReader { proxy in
      HStack(alignment: .bottom, spacing: 8) {
        ForEach(days) { day in
          VStack(spacing: 6) {
            Text(day.totalCaptureCount.formatted())
              .font(.caption2.weight(.semibold))
              .foregroundStyle(day.totalCaptureCount > 0 ? .primary : .secondary)
              .monospacedDigit()
              .lineLimit(1)
              .minimumScaleFactor(0.72)
              .frame(height: 14)

            RoundedRectangle(cornerRadius: 6, style: .continuous)
              .fill(day.totalCaptureCount > 0 ? accentColor.opacity(0.74) : Color.secondary.opacity(0.12))
              .frame(height: barHeight(for: day, availableHeight: proxy.size.height - 40))
              .help(tooltip(for: day))

            Text(weekdayLabel(for: day.date))
              .font(.caption2.weight(.medium))
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .frame(height: 14)
          }
          .frame(maxWidth: .infinity)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
    .frame(height: 150)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilitySummary)
  }

  private func barHeight(for day: StatisticsRecentActivityDay, availableHeight: CGFloat) -> CGFloat {
    let value = Double(day.totalCaptureCount)
    guard value > 0 else { return 5 }
    return max(12, availableHeight * CGFloat(value / maxCaptures))
  }

  private func weekdayLabel(for date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = .autoupdatingCurrent
    formatter.dateFormat = "EEE"
    return formatter.string(from: date)
  }

  private func tooltip(for day: StatisticsRecentActivityDay) -> String {
    let date = StatisticsFormatting.formatDate(day.date)
    return "\(date)\nScreenshots: \(day.screenshotCount)\nRecordings: \(day.recordingCount)\nRecorded: \(StatisticsFormatting.formatDuration(day.recordedDurationMS))\nStorage: \(StatisticsFormatting.formatBytes(day.captureBytesProduced))"
  }

  private var accessibilitySummary: String {
    let total = days.reduce(Int64(0)) { $0 + $1.totalCaptureCount }
    return "Last 7 days activity, \(total.formatted()) total captures"
  }
}

struct StatisticsActivitySummaryRow: View {
  let totalCaptures: String
  let activeDays: String
  let busiestDay: String

  var body: some View {
    HStack(spacing: 12) {
      summaryPill(title: "Captures", value: totalCaptures)
      summaryPill(title: "Active Days", value: activeDays)
      summaryPill(title: "Busiest Day", value: busiestDay)
    }
    .font(.caption)
    .foregroundStyle(.secondary)
  }

  private func summaryPill(title: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title).font(.caption.weight(.medium))
      Text(value).font(.caption).foregroundStyle(.primary).lineLimit(1)
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

private struct StatisticsInlineBarChart: View {
  let values: [Double]

  private var maxValue: Double { max(values.max() ?? 0, 1) }

  var body: some View {
    HStack(alignment: .bottom, spacing: 3) {
      ForEach(Array(values.enumerated()), id: \.offset) { _, value in
        RoundedRectangle(cornerRadius: 2, style: .continuous)
          .fill(value > 0 ? Color.accentColor.opacity(0.72) : Color.secondary.opacity(0.12))
          .frame(width: 5, height: max(3, CGFloat((value / maxValue) * 22)))
      }
    }
    .frame(height: 22)
    .accessibilityHidden(true)
  }
}
