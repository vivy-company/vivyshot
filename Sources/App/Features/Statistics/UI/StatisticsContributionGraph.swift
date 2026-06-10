import SwiftUI

struct StatisticsGraphBounds {
  let startDate: Date
  let endDate: Date
}

struct StatisticsGraphWeek: Identifiable {
  let startDate: Date
  let days: [StatisticsGraphDay]
  var id: Date { startDate }
}

struct StatisticsGraphDay: Identifiable {
  let date: Date
  let bucket: StatsDailyBucket?
  let intensity: Int
  let isOutsidePrimaryRange: Bool
  var id: Date { date }
  var isToday: Bool { Calendar.autoupdatingCurrent.isDateInToday(date) }
}

struct StatisticsContributionGraph: View {
  let weeks: [StatisticsGraphWeek]
  let weekdaySymbols: [String]
  let accentColor: Color

  private let verticalSpacing: CGFloat = 4
  private let weekdayColumnWidth: CGFloat = 24
  private let graphSpacing: CGFloat = 10

  var body: some View {
    GeometryReader { proxy in
      let layout = graphLayout(for: max(proxy.size.width - weekdayColumnWidth - graphSpacing, 0))

      HStack(alignment: .top, spacing: graphSpacing) {
        VStack(alignment: .trailing, spacing: layout.verticalSpacing) {
          Color.clear.frame(height: 22)
          ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { index, symbol in
            Text(index.isMultiple(of: 2) ? symbol : " ")
              .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
              .frame(height: layout.cellSize)
          }
        }

        graphContent(layout: layout)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
    .frame(maxWidth: .infinity, minHeight: graphHeight, maxHeight: graphHeight, alignment: .leading)
    .padding(.vertical, 2)
  }

  private func graphContent(layout: ContributionGraphLayout) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      monthLabels(layout: layout).frame(maxWidth: .infinity, alignment: .leading)

      HStack(alignment: .top, spacing: layout.horizontalSpacing) {
        ForEach(weeks) { week in
          VStack(spacing: layout.verticalSpacing) {
            ForEach(week.days) { day in
              RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(cellColor(for: day))
                .frame(width: layout.cellSize, height: layout.cellSize)
                .overlay(
                  RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(day.isToday ? accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
                )
                .help(tooltip(for: day))
            }
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(width: layout.contentWidth, alignment: .leading)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.bottom, 2)
  }

  private func monthLabels(layout: ContributionGraphLayout) -> some View {
    HStack(spacing: layout.horizontalSpacing) {
      ForEach(monthSegments) { segment in
        let w = segmentWidth(for: segment, layout: layout)
        Text(w < 28 ? "" : segment.title)
          .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
          .lineLimit(1).frame(width: w, alignment: .leading)
      }
    }
  }

  private var monthSegments: [StatisticsGraphMonthSegment] {
    guard let first = weeks.first else { return [] }
    let formatter = DateFormatter()
    formatter.locale = Locale.autoupdatingCurrent
    formatter.dateFormat = "MMM"

    var segments: [StatisticsGraphMonthSegment] = []
    var currentMonth = Calendar.autoupdatingCurrent.component(.month, from: first.startDate)
    var currentStart = first.startDate
    var count = 0

    for week in weeks {
      let month = Calendar.autoupdatingCurrent.component(.month, from: week.startDate)
      if month != currentMonth {
        segments.append(StatisticsGraphMonthSegment(title: formatter.string(from: currentStart), weekCount: count, startDate: currentStart))
        currentMonth = month
        currentStart = week.startDate
        count = 0
      }
      count += 1
    }
    segments.append(StatisticsGraphMonthSegment(title: formatter.string(from: currentStart), weekCount: count, startDate: currentStart))
    return segments
  }

  private func segmentWidth(for segment: StatisticsGraphMonthSegment, layout: ContributionGraphLayout) -> CGFloat {
    let wc = CGFloat(max(segment.weekCount, 1))
    return wc * layout.cellSize + max(wc - 1, 0) * layout.horizontalSpacing
  }

  private var graphHeight: CGFloat {
    switch weeks.count {
    case ...16: return 168
    case 17...32: return 168
    case 33...56: return 156
    default: return 144
    }
  }

  private struct ContributionGraphLayout {
    let cellSize: CGFloat
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat
    let contentWidth: CGFloat
  }

  private func graphLayout(for width: CGFloat) -> ContributionGraphLayout {
    let wc = max(weeks.count, 1)
    let gaps = CGFloat(max(wc - 1, 0))
    let minSpacing = minimumHorizontalSpacing(for: wc)
    let fitted = floor((width - gaps * minSpacing) / CGFloat(wc))
    let cell = min(maximumCellSize(for: wc), max(minimumCellSize(for: wc), fitted))
    let contentWidth = CGFloat(wc) * cell + gaps * minSpacing
    if contentWidth > width {
      let compressedCell = min(cell, max(4, floor((width - gaps) / CGFloat(wc))))
      let spacing = gaps > 0 ? max(1, (width - CGFloat(wc) * compressedCell) / gaps) : 0
      return ContributionGraphLayout(cellSize: compressedCell, horizontalSpacing: spacing, verticalSpacing: verticalSpacing, contentWidth: width)
    }
    return ContributionGraphLayout(cellSize: cell, horizontalSpacing: minSpacing, verticalSpacing: verticalSpacing, contentWidth: contentWidth)
  }

  private func minimumCellSize(for wc: Int) -> CGFloat {
    switch wc {
    case ...16: return 18
    case 17...32: return 12
    case 33...56: return 8
    default: return 6
    }
  }

  private func maximumCellSize(for wc: Int) -> CGFloat {
    switch wc {
    case ...16: return 18
    case ...32: return 14
    case ...56: return 10
    default: return 8
    }
  }

  private func minimumHorizontalSpacing(for wc: Int) -> CGFloat {
    switch wc {
    case ...16: return 6
    case ...32: return 4
    default: return 3
    }
  }

  private func cellColor(for day: StatisticsGraphDay) -> Color {
    if day.isOutsidePrimaryRange { return Color.secondary.opacity(0.04) }
    switch day.intensity {
    case 0: return Color.secondary.opacity(0.08)
    case 1: return accentColor.opacity(0.18)
    case 2: return accentColor.opacity(0.34)
    case 3: return accentColor.opacity(0.52)
    default: return accentColor.opacity(0.78)
    }
  }

  private func tooltip(for day: StatisticsGraphDay) -> String {
    let date = DateFormatter.localizedString(from: day.date, dateStyle: .medium, timeStyle: .none)
    guard let b = day.bucket else { return "\(date)\nNo capture activity" }
    let df = DateComponentsFormatter()
    df.allowedUnits = b.recordedDurationMS >= 3_600_000 ? [.hour, .minute] : [.minute, .second]
    df.unitsStyle = .abbreviated
    let dur = df.string(from: TimeInterval(b.recordedDurationMS) / 1000) ?? "0s"
    let bytes = ByteCountFormatter.string(fromByteCount: b.captureBytesProduced, countStyle: .file)
    return "\(date)\nScreenshots: \(b.screenshotCount)\nRecordings: \(b.recordingCount)\nRecorded: \(dur)\nStorage: \(bytes)"
  }
}

private struct StatisticsGraphMonthSegment: Identifiable {
  let title: String
  let weekCount: Int
  let startDate: Date
  var id: Date { startDate }
}
