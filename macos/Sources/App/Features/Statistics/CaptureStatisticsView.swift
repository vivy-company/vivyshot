import AppKit
import Charts
import Combine
import SwiftUI

@MainActor
final class CaptureStatisticsViewModel: ObservableObject {
  @Published private(set) var dashboardData: CaptureStatisticsDashboardData = .empty
  @Published private(set) var isLoading = false
  @Published private(set) var hasLoaded = false
  @Published private(set) var loadError: String?
#if DEBUG
  @Published var debugPreviewEnabled = false
#endif

  func refresh() async {
    isLoading = true
    defer {
      isLoading = false
      hasLoaded = true
    }

    guard let dashboardData = await CaptureStatisticsStore.shared.dashboardData() else {
      loadError = "Statistics are temporarily unavailable."
      return
    }

    self.dashboardData = dashboardData
    loadError = nil
  }
}

@MainActor
struct VivyShotStatisticsView: View {
  enum Presentation {
    case settings
    case window
  }

  let presentation: Presentation

  @ObservedObject private var storeManager = StoreManager.shared
  @StateObject private var viewModel = CaptureStatisticsViewModel()
  @State private var selectedRange: StatisticsGraphRange = .sixMonths

  private var usesStandaloneWindowPresentation: Bool {
    switch presentation {
    case .settings:
      return false
    case .window:
      return true
    }
  }

  private var maxContentWidth: CGFloat {
    switch presentation {
    case .settings:
      return 520
    case .window:
      return .greatestFiniteMagnitude
    }
  }

  private var horizontalPadding: CGFloat {
    switch presentation {
    case .settings:
      return 12
    case .window:
      return 0
    }
  }

  private var verticalPadding: CGFloat {
    switch presentation {
    case .settings:
      return 10
    case .window:
      return 0
    }
  }

  private var hasStatisticsAccess: Bool {
#if DEBUG
    storeManager.hasPaidAccess || viewModel.debugPreviewEnabled
#else
    storeManager.hasPaidAccess
#endif
  }

  private var showDebugPreviewBanner: Bool {
#if DEBUG
    viewModel.debugPreviewEnabled && !storeManager.hasPaidAccess
#else
    false
#endif
  }

  private var statisticsAccentColor: Color {
    storeManager.hasSupporterBadge ? .orange : .accentColor
  }

  private var currentBadgeTitle: String? {
    if showDebugPreviewBanner {
      return "Debug Preview"
    }
    if let badgeTitle = storeManager.badgeTitle {
      return badgeTitle
    }
    return hasStatisticsAccess ? nil : "Preview"
  }

  private var currentBadgeProminence: StoreBadgeChip.Prominence {
    if showDebugPreviewBanner {
      return .free
    }
    if storeManager.hasSupporterBadge {
      return .supporter
    }
    if storeManager.hasLifetimeUnlock {
      return .lifetime
    }
    return .free
  }

  private var headerSubtitle: String {
    if hasStatisticsAccess {
      return "Local capture totals, streaks, history, and milestones for this Mac."
    }
    return "Free shows a small preview. Lifetime and Supporter unlock timing, storage, milestones, and longer history."
  }

  private var previewSummary: String {
    let totalCaptures = viewModel.dashboardData.summary.totalScreenshotsCaptured + viewModel.dashboardData.summary.totalRecordingsCompleted
    if totalCaptures == 0 {
      return "No captures tracked yet"
    }
    return "\(totalCaptures.formatted()) captures tracked locally"
  }

  private var metricItems: [StatisticsMetricItem] {
    if hasStatisticsAccess {
      return [
        StatisticsMetricItem(
          title: "Total Screenshots",
          value: viewModel.dashboardData.summary.totalScreenshotsCaptured.formatted(),
          detail: "All-time captures",
          systemImage: "camera"
        ),
        StatisticsMetricItem(
          title: "Total Recordings",
          value: viewModel.dashboardData.summary.totalRecordingsCompleted.formatted(),
          detail: "Completed recordings",
          systemImage: "record.circle"
        ),
        StatisticsMetricItem(
          title: "Total Recording Time",
          value: formatDuration(viewModel.dashboardData.summary.totalRecordedDurationMS),
          detail: "Finished sessions only",
          systemImage: "timer"
        ),
        StatisticsMetricItem(
          title: "Average Screenshot Time",
          value: formatDuration(viewModel.dashboardData.summary.averageScreenshotEditorCompletionDurationMS),
          detail: "Editor entry to copy/save",
          systemImage: "stopwatch"
        ),
        StatisticsMetricItem(
          title: "Storage Produced",
          value: formatBytes(viewModel.dashboardData.summary.totalCaptureBytesProduced),
          detail: "Primary output artifacts",
          systemImage: "internaldrive"
        ),
        StatisticsMetricItem(
          title: "Current Streak",
          value: dayCountLabel(viewModel.dashboardData.summary.currentCaptureStreakDays),
          detail: "Consecutive active days",
          systemImage: "flame"
        ),
        StatisticsMetricItem(
          title: "Best Streak",
          value: dayCountLabel(viewModel.dashboardData.summary.bestCaptureStreakDays),
          detail: "Personal best",
          systemImage: "trophy"
        ),
        StatisticsMetricItem(
          title: "Active Days",
          value: viewModel.dashboardData.summary.activeCaptureDays.formatted(),
          detail: "Days with captures",
          systemImage: "calendar"
        )
      ]
    }

    return [
      StatisticsMetricItem(
        title: "Total Screenshots",
        value: viewModel.dashboardData.summary.totalScreenshotsCaptured.formatted(),
        detail: "All-time captures",
        systemImage: "camera"
      ),
      StatisticsMetricItem(
        title: "Total Recordings",
        value: viewModel.dashboardData.summary.totalRecordingsCompleted.formatted(),
        detail: "Completed recordings",
        systemImage: "record.circle"
      ),
      StatisticsMetricItem(
        title: "Current Streak",
        value: dayCountLabel(viewModel.dashboardData.summary.currentCaptureStreakDays),
        detail: "Consecutive active days",
        systemImage: "flame"
      ),
      StatisticsMetricItem(
        title: "Active Days",
        value: viewModel.dashboardData.summary.activeCaptureDays.formatted(),
        detail: "Days with captures",
        systemImage: "calendar"
      )
    ]
  }

  private var unlockFeatures: [StatisticsUnlockFeature] {
    [
      StatisticsUnlockFeature(
        title: "Longer History",
        detail: "Unlock month, half-year, year, and all-time activity ranges.",
        systemImage: "calendar.badge.clock"
      ),
      StatisticsUnlockFeature(
        title: "Timing",
        detail: "See average screenshot completion time and total recorded duration.",
        systemImage: "stopwatch"
      ),
      StatisticsUnlockFeature(
        title: "Storage",
        detail: "Track how much disk space your screenshots and recordings produce.",
        systemImage: "internaldrive"
      ),
      StatisticsUnlockFeature(
        title: "Milestones",
        detail: "Get first capture dates, most active day, and weekly or monthly breakdowns.",
        systemImage: "flag.2.crossed"
      )
    ]
  }

  var body: some View {
    Group {
      switch presentation {
      case .settings:
        settingsBody
      case .window:
        windowBody
      }
    }
    .background {
      if !usesStandaloneWindowPresentation {
        Color(nsColor: .windowBackgroundColor)
      }
    }
    .task {
      await storeManager.refreshEntitlements()
      await viewModel.refresh()
    }
    .onReceive(NotificationCenter.default.publisher(for: .vivyShotStatisticsDidChange)) { _ in
      Task { await viewModel.refresh() }
    }
  }

  private var settingsBody: some View {
    statisticsForm(hideScrollBackground: true)
      .frame(maxWidth: maxContentWidth, maxHeight: .infinity, alignment: .top)
      .padding(.horizontal, horizontalPadding)
      .padding(.vertical, verticalPadding)
  }

  @ViewBuilder
  private var statisticsSections: some View {
    Section {
      statisticsHeader
    }

#if DEBUG
    if showDebugPreviewBanner {
      Section {
        debugPreviewBanner
      }
    }
#endif

    Section {
      ForEach(metricItems) { item in
        StatisticsMetricRow(item: item)
      }
    } header: {
      Text(overviewSectionTitle)
    } footer: {
      Text(overviewSectionFooter)
    }

    if hasStatisticsAccess {
      Section {
        activitySectionContent
      } header: {
        Text("Activity")
      } footer: {
        Text(dayRangeDescription)
      }

      Section {
        breakdownSectionContent
      } header: {
        Text("Breakdown")
      } footer: {
        Text("This week, this month, and lifetime totals.")
      }

      Section {
        milestonesSectionContent
      } header: {
        Text("Milestones")
      }
    } else {
      Section {
        previewActivitySectionContent
      } header: {
        Text("Recent Activity")
      } footer: {
        Text(recentActivityFooter)
      }

      Section {
        unlockSectionContent
      } header: {
        Text("Unlock Full Statistics")
      }
    }
  }

  private func statisticsForm(hideScrollBackground: Bool) -> some View {
    Form {
      statisticsSections
    }
    .formStyle(.grouped)
    .modifier(StatisticsScrollBackgroundModifier(isHidden: hideScrollBackground))
  }

  private var windowBody: some View {
    statisticsForm(hideScrollBackground: false)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  private var statisticsHeader: some View {
    StatisticsHeaderBlock(
      title: "Statistics",
      subtitle: headerSubtitle,
      badgeTitle: currentBadgeTitle,
      badgeProminence: currentBadgeProminence,
      systemImage: "chart.bar.xaxis",
      accentColor: statisticsAccentColor,
      isLoading: viewModel.isLoading,
      loadError: viewModel.dashboardData.dailyBuckets.isEmpty ? viewModel.loadError : nil,
      secondaryNote: hasStatisticsAccess ? "Stored locally on this Mac" : previewSummary,
      onRefresh: { Task { await viewModel.refresh() } },
      onUpgrade: hasStatisticsAccess ? nil : { presentPaywallWindow() }
    )
  }

  private var debugPreviewBanner: some View {
#if DEBUG
    StatisticsDebugPreviewRow {
      viewModel.debugPreviewEnabled = false
    }
#else
    EmptyView()
#endif
  }

  private var overviewSectionTitle: String {
    hasStatisticsAccess ? "Overview" : "Preview"
  }

  private var overviewSectionFooter: String {
    if hasStatisticsAccess {
      return "All statistics are computed from local capture events and stored on this Mac."
    }
    return "Free includes top-line counts only. Upgrade to unlock timing, storage, milestones, and longer history."
  }

  private var recentActivityFooter: String {
    "Free includes the most recent 7 days only. Longer history is part of the paid tier."
  }

  private var activitySectionContent: some View {
    VStack(alignment: .leading, spacing: 12) {
      LabeledContent("Range") {
        Picker("Range", selection: $selectedRange) {
          ForEach(StatisticsGraphRange.allCases) { range in
            Text(range.title).tag(range)
          }
        }
        .pickerStyle(.segmented)
        .frame(width: 220)
        .labelsHidden()
      }

      StatisticsContributionGraph(
        weeks: makeGraphWeeks(range: selectedRange),
        weekdaySymbols: orderedWeekdaySymbols(),
        monthTitles: monthTitles(for: makeGraphWeeks(range: selectedRange)),
        accentColor: statisticsAccentColor
      )
      .padding(.vertical, 4)
    }
  }

  private var breakdownSectionContent: some View {
    StatisticsBreakdownGrid(
      screenshotWeek: metricBreakdown(\.screenshotCount).week.formatted(),
      screenshotMonth: metricBreakdown(\.screenshotCount).month.formatted(),
      screenshotAllTime: viewModel.dashboardData.summary.totalScreenshotsCaptured.formatted(),
      recordingWeek: metricBreakdown(\.recordingCount).week.formatted(),
      recordingMonth: metricBreakdown(\.recordingCount).month.formatted(),
      recordingAllTime: viewModel.dashboardData.summary.totalRecordingsCompleted.formatted(),
      durationWeek: formatDuration(metricBreakdown(\.recordedDurationMS).week),
      durationMonth: formatDuration(metricBreakdown(\.recordedDurationMS).month),
      durationAllTime: formatDuration(viewModel.dashboardData.summary.totalRecordedDurationMS),
      storageWeek: formatBytes(metricBreakdown(\.captureBytesProduced).week),
      storageMonth: formatBytes(metricBreakdown(\.captureBytesProduced).month),
      storageAllTime: formatBytes(viewModel.dashboardData.summary.totalCaptureBytesProduced)
    )
  }

  @ViewBuilder
  private var milestonesSectionContent: some View {
    LabeledContent("First Screenshot") {
      Text(formatDate(viewModel.dashboardData.firstScreenshotAt))
    }

    LabeledContent("First Recording") {
      Text(formatDate(viewModel.dashboardData.firstRecordingAt))
    }

    LabeledContent("Most Active Day") {
      Text(mostActiveDayLabel)
    }
  }

  private var previewActivitySectionContent: some View {
    StatisticsPreviewChart(days: previewDays, accentColor: statisticsAccentColor)
  }

  @ViewBuilder
  private var unlockSectionContent: some View {
    Text("Lifetime and Supporter both unlock the full statistics panel.")
      .foregroundStyle(.secondary)

    ForEach(unlockFeatures) { feature in
      StatisticsUnlockFeatureRow(feature: feature)
    }

    HStack(spacing: 10) {
      Button("Upgrade") {
        presentPaywallWindow()
      }
      .buttonStyle(.borderedProminent)

#if DEBUG
      Button(viewModel.debugPreviewEnabled ? "Hide Debug Preview" : "Show Debug Preview") {
        viewModel.debugPreviewEnabled.toggle()
      }
      .buttonStyle(.bordered)
#endif
    }
    .padding(.vertical, 2)
  }

  private var mostActiveDayLabel: String {
    guard let day = viewModel.dashboardData.summary.mostActiveDay else {
      return "No activity yet"
    }
    return "\(formatDayKey(day)) • score \(viewModel.dashboardData.summary.mostActiveDayScore)"
  }

  private var dayRangeDescription: String {
    let weeks = makeGraphWeeks(range: selectedRange)
    guard let first = weeks.first?.days.first?.date, let last = weeks.last?.days.last?.date else {
      return "No capture activity yet"
    }
    return "\(formatDate(first)) to \(formatDate(last))"
  }

  private var previewDays: [StatisticsPreviewDay] {
    let calendar = Calendar.autoupdatingCurrent
    let today = calendar.startOfDay(for: Date())
    let bucketsByDayKey = Dictionary(uniqueKeysWithValues: viewModel.dashboardData.dailyBuckets.map { ($0.day.yyyyMMdd, $0) })
    let formatter = DateFormatter()
    formatter.locale = Locale.autoupdatingCurrent
    formatter.setLocalizedDateFormatFromTemplate("EEE")

    return (0..<7).compactMap { offset in
      guard let date = calendar.date(byAdding: .day, value: offset - 6, to: today) else {
        return nil
      }

      let components = calendar.dateComponents([.year, .month, .day], from: date)
      let dayKey = String(
        format: "%04d-%02d-%02d",
        components.year ?? 0,
        components.month ?? 1,
        components.day ?? 1
      )

      return StatisticsPreviewDay(
        date: date,
        label: formatter.string(from: date),
        bucket: bucketsByDayKey[dayKey]
      )
    }
  }

  private func metricBreakdown(_ keyPath: KeyPath<StatisticsAggregate, Int64>) -> StatisticsRangeBreakdown {
    let weekStart = Calendar.autoupdatingCurrent.dateInterval(of: .weekOfYear, for: Date())?.start
    let monthStart = Calendar.autoupdatingCurrent.date(from: Calendar.autoupdatingCurrent.dateComponents([.year, .month], from: Date()))

    let weekAggregate = aggregateBuckets(startingAt: weekStart)
    let monthAggregate = aggregateBuckets(startingAt: monthStart)

    return StatisticsRangeBreakdown(
      week: weekAggregate[keyPath: keyPath],
      month: monthAggregate[keyPath: keyPath]
    )
  }

  private func aggregateBuckets(startingAt startDate: Date?) -> StatisticsAggregate {
    let calendar = Calendar.autoupdatingCurrent

    return viewModel.dashboardData.dailyBuckets.reduce(into: StatisticsAggregate()) { aggregate, bucket in
      guard let bucketDate = bucket.day.asDate(calendar: calendar) else {
        return
      }
      guard let startDate else {
        aggregate.add(bucket)
        return
      }
      if bucketDate >= calendar.startOfDay(for: startDate) {
        aggregate.add(bucket)
      }
    }
  }

  private func makeGraphWeeks(range: StatisticsGraphRange) -> [StatisticsGraphWeek] {
    makeGraphWeeks(rollingDayCount: range.rollingDayCount)
  }

  private func makeGraphWeeks(rollingDayCount: Int?) -> [StatisticsGraphWeek] {
    let calendar = Calendar.autoupdatingCurrent
    let today = calendar.startOfDay(for: Date())
    let firstActiveDate: Date = {
      if let rollingDayCount {
        return calendar.date(byAdding: .day, value: -(rollingDayCount - 1), to: today) ?? today
      }
      let firstBucketDate = viewModel.dashboardData.dailyBuckets
        .compactMap { $0.day.asDate(calendar: calendar) }
        .min()
      return firstBucketDate ?? today
    }()

    let firstGridDate = calendar.dateInterval(of: .weekOfYear, for: firstActiveDate)?.start ?? firstActiveDate
    let lastGridDate = calendar.date(byAdding: .day, value: 6, to: calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today) ?? today
    let bucketsByDayKey = Dictionary(uniqueKeysWithValues: viewModel.dashboardData.dailyBuckets.map { ($0.day.yyyyMMdd, $0) })

    var days: [StatisticsGraphDay] = []
    var current = firstGridDate
    while current <= lastGridDate {
      let components = calendar.dateComponents([.year, .month, .day], from: current)
      let dayKey = String(
        format: "%04d-%02d-%02d",
        components.year ?? 0,
        components.month ?? 1,
        components.day ?? 1
      )

      days.append(
        StatisticsGraphDay(
          date: current,
          bucket: bucketsByDayKey[dayKey],
          intensity: 0,
          isOutsidePrimaryRange: current < firstActiveDate
        )
      )

      current = calendar.date(byAdding: .day, value: 1, to: current) ?? current.addingTimeInterval(86_400)
      if days.count > 2_500 {
        break
      }
    }

    let maxScore = max(days.compactMap { $0.bucket?.activityScore }.max() ?? 0, 1)
    let normalizedDays = days.map { day in
      StatisticsGraphDay(
        date: day.date,
        bucket: day.bucket,
        intensity: intensity(for: day.bucket?.activityScore ?? 0, maxScore: maxScore),
        isOutsidePrimaryRange: day.isOutsidePrimaryRange
      )
    }

    var weeks: [StatisticsGraphWeek] = []
    var weekStartIndex = 0
    while weekStartIndex < normalizedDays.count {
      let slice = Array(normalizedDays[weekStartIndex ..< min(weekStartIndex + 7, normalizedDays.count)])
      if let firstDate = slice.first?.date {
        weeks.append(StatisticsGraphWeek(startDate: firstDate, days: slice))
      }
      weekStartIndex += 7
    }
    return weeks
  }

  private func intensity(for score: Int64, maxScore: Int64) -> Int {
    guard score > 0 else {
      return 0
    }
    let normalized = Double(score) / Double(maxScore)
    switch normalized {
    case ..<0.25:
      return 1
    case ..<0.5:
      return 2
    case ..<0.75:
      return 3
    default:
      return 4
    }
  }

  private func monthTitles(for weeks: [StatisticsGraphWeek]) -> [String?] {
    let formatter = DateFormatter()
    formatter.locale = Locale.autoupdatingCurrent
    formatter.dateFormat = "MMM"

    var previousMonth: Int?
    return weeks.map { week in
      let month = Calendar.autoupdatingCurrent.component(.month, from: week.startDate)
      defer { previousMonth = month }
      guard month != previousMonth else {
        return nil
      }
      return formatter.string(from: week.startDate)
    }
  }

  private func orderedWeekdaySymbols() -> [String] {
    let calendar = Calendar.autoupdatingCurrent
    let symbols = calendar.shortWeekdaySymbols
    let startIndex = max(calendar.firstWeekday - 1, 0)
    let ordered = Array(symbols[startIndex...] + symbols[..<startIndex])
    return ordered.map { String($0.prefix(1)) }
  }

  private func formatDuration(_ durationMS: Int64) -> String {
    guard durationMS > 0 else {
      return "0s"
    }
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = durationMS >= 3_600_000 ? [.hour, .minute] : [.minute, .second]
    formatter.unitsStyle = .abbreviated
    formatter.zeroFormattingBehavior = [.dropLeading, .dropAll]
    return formatter.string(from: TimeInterval(durationMS) / 1000) ?? "0s"
  }

  private func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }

  private func formatDate(_ date: Date?) -> String {
    guard let date else {
      return "No data yet"
    }
    return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none)
  }

  private func formatDayKey(_ dayKey: RustStatsDayKey) -> String {
    formatDate(dayKey.asDate())
  }

  private func dayCountLabel(_ dayCount: Int) -> String {
    dayCount == 1 ? "1 day" : "\(dayCount) days"
  }
}

private struct StatisticsMetricItem: Identifiable {
  let title: String
  let value: String
  let detail: String
  let systemImage: String

  var id: String { title }
}

private struct StatisticsUnlockFeature: Identifiable {
  let title: String
  let detail: String
  let systemImage: String

  var id: String { title }
}

private struct StatisticsPreviewDay: Identifiable {
  let date: Date
  let label: String
  let bucket: RustStatsDailyBucket?

  var id: Date { date }

  var captureCount: Int {
    (bucket?.screenshotCount ?? 0) + (bucket?.recordingCount ?? 0)
  }

  var activityScore: Int64 {
    bucket?.activityScore ?? 0
  }

  var isToday: Bool {
    Calendar.autoupdatingCurrent.isDateInToday(date)
  }
}

private struct StatisticsAggregate {
  var screenshotCount: Int64 = 0
  var recordingCount: Int64 = 0
  var recordedDurationMS: Int64 = 0
  var captureBytesProduced: Int64 = 0

  mutating func add(_ bucket: RustStatsDailyBucket) {
    screenshotCount += Int64(bucket.screenshotCount)
    recordingCount += Int64(bucket.recordingCount)
    recordedDurationMS += bucket.recordedDurationMS
    captureBytesProduced += bucket.captureBytesProduced
  }
}

private struct StatisticsRangeBreakdown {
  let week: Int64
  let month: Int64
}

private struct StatisticsGraphWeek: Identifiable {
  let startDate: Date
  let days: [StatisticsGraphDay]

  var id: Date { startDate }
}

private struct StatisticsGraphDay: Identifiable {
  let date: Date
  let bucket: RustStatsDailyBucket?
  let intensity: Int
  let isOutsidePrimaryRange: Bool

  var id: Date { date }

  var isToday: Bool {
    Calendar.autoupdatingCurrent.isDateInToday(date)
  }
}

private struct StatisticsScrollBackgroundModifier: ViewModifier {
  let isHidden: Bool

  func body(content: Content) -> some View {
    if isHidden {
      content.scrollContentBackground(.hidden)
    } else {
      content
    }
  }
}

private struct StatisticsHeaderBlock: View {
  let title: String
  let subtitle: String
  let badgeTitle: String?
  let badgeProminence: StoreBadgeChip.Prominence
  let systemImage: String
  let accentColor: Color
  let isLoading: Bool
  let loadError: String?
  let secondaryNote: String
  let onRefresh: () -> Void
  let onUpgrade: (() -> Void)?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top, spacing: 14) {
        Image(systemName: systemImage)
          .font(.system(size: 19, weight: .semibold))
          .foregroundStyle(accentColor)
          .frame(width: 32, height: 32)

        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 8) {
            Text(title)
              .font(.title3.weight(.semibold))

            if let badgeTitle {
              StoreBadgeChip(title: badgeTitle, prominence: badgeProminence)
            }
          }

          Text(subtitle)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        Spacer(minLength: 0)
      }

      HStack(alignment: .center, spacing: 12) {
        if isLoading {
          ProgressView()
            .controlSize(.small)
        } else if let loadError {
          Text(loadError)
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
          Text(secondaryNote)
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer(minLength: 0)

        if let onUpgrade {
          Button("Upgrade", action: onUpgrade)
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }

        Button("Refresh", action: onRefresh)
          .buttonStyle(.bordered)
          .controlSize(.regular)
      }
    }
    .padding(.vertical, 2)
  }
}

private struct StatisticsDebugPreviewRow: View {
  let onHide: () -> Void

  var body: some View {
    HStack(spacing: 10) {
      Label("Debug preview is forcing the paid statistics UI.", systemImage: "hammer")
        .font(.subheadline)
        .foregroundStyle(.secondary)

      Spacer(minLength: 0)

      Button("Hide", action: onHide)
        .buttonStyle(.bordered)
    }
  }
}

private struct StatisticsMetricRow: View {
  let item: StatisticsMetricItem

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: item.systemImage)
        .foregroundStyle(.secondary)
        .frame(width: 18, height: 18)
        .padding(.top, 2)

      VStack(alignment: .leading, spacing: 2) {
        Text(item.title)
          .font(.body.weight(.medium))

        Text(item.detail)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 16)

      Text(item.value)
        .font(.system(.body, design: .rounded).weight(.semibold))
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
        .fixedSize(horizontal: true, vertical: false)
    }
    .padding(.vertical, 2)
  }
}

private struct StatisticsPreviewChart: View {
  let days: [StatisticsPreviewDay]
  let accentColor: Color

  private var weekTotal: Int {
    days.reduce(0) { $0 + $1.captureCount }
  }

  private var busiestDayText: String {
    guard let busiest = days.max(by: { $0.captureCount < $1.captureCount }), busiest.captureCount > 0 else {
      return "No captures yet"
    }
    return "\(busiest.label): \(busiest.captureCount.formatted())"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Chart(days) { day in
        BarMark(
          x: .value("Day", day.label),
          y: .value("Captures", day.captureCount)
        )
        .foregroundStyle(day.isToday ? accentColor : accentColor.opacity(0.7))
        .cornerRadius(4)
      }
      .chartLegend(.hidden)
      .chartYAxis {
        AxisMarks(position: .leading)
      }
      .frame(height: 120)

      HStack {
        LabeledContent("This Week") {
          Text(weekTotal.formatted())
            .monospacedDigit()
        }

        Spacer(minLength: 24)

        LabeledContent("Busiest Day") {
          Text(busiestDayText)
        }
      }
      .font(.subheadline)
    }
    .padding(.vertical, 4)
  }
}

private struct StatisticsUnlockFeatureRow: View {
  let feature: StatisticsUnlockFeature

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: feature.systemImage)
        .foregroundStyle(.secondary)
        .frame(width: 18)

      VStack(alignment: .leading, spacing: 2) {
        Text(feature.title)
          .font(.body.weight(.medium))

        Text(feature.detail)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(.vertical, 2)
  }
}

private struct StatisticsBreakdownGrid: View {
  let screenshotWeek: String
  let screenshotMonth: String
  let screenshotAllTime: String
  let recordingWeek: String
  let recordingMonth: String
  let recordingAllTime: String
  let durationWeek: String
  let durationMonth: String
  let durationAllTime: String
  let storageWeek: String
  let storageMonth: String
  let storageAllTime: String

  var body: some View {
    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
      GridRow {
        Text("Metric").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        Text("Week").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        Text("Month").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        Text("All Time").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
      }

      StatisticsBreakdownRow(title: "Screenshots", weekValue: screenshotWeek, monthValue: screenshotMonth, allTimeValue: screenshotAllTime)
      StatisticsBreakdownRow(title: "Recordings", weekValue: recordingWeek, monthValue: recordingMonth, allTimeValue: recordingAllTime)
      StatisticsBreakdownRow(title: "Recording Time", weekValue: durationWeek, monthValue: durationMonth, allTimeValue: durationAllTime)
      StatisticsBreakdownRow(title: "Storage Produced", weekValue: storageWeek, monthValue: storageMonth, allTimeValue: storageAllTime)
    }
    .padding(.vertical, 4)
  }
}

private struct StatisticsBreakdownRow: View {
  let title: String
  let weekValue: String
  let monthValue: String
  let allTimeValue: String

  var body: some View {
    GridRow {
      Text(title)
        .font(.subheadline.weight(.medium))
        .gridColumnAlignment(.leading)

      Text(weekValue)
        .font(.system(.subheadline, design: .monospaced))
        .gridColumnAlignment(.trailing)

      Text(monthValue)
        .font(.system(.subheadline, design: .monospaced))
        .gridColumnAlignment(.trailing)

      Text(allTimeValue)
        .font(.system(.subheadline, design: .monospaced))
        .gridColumnAlignment(.trailing)
    }
  }
}

private struct StatisticsContributionGraph: View {
  let weeks: [StatisticsGraphWeek]
  let weekdaySymbols: [String]
  let monthTitles: [String?]
  let accentColor: Color

  private let cellSize: CGFloat = 11
  private let cellSpacing: CGFloat = 4

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      VStack(alignment: .trailing, spacing: cellSpacing) {
        Color.clear.frame(height: 18)
        ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { index, symbol in
          Text(index.isMultiple(of: 2) ? symbol : " ")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(height: cellSize)
        }
      }

      ScrollView(.horizontal, showsIndicators: false) {
        VStack(alignment: .leading, spacing: 6) {
          HStack(spacing: cellSpacing) {
            ForEach(Array(monthTitles.enumerated()), id: \.offset) { _, monthTitle in
              Text(monthTitle ?? "")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: cellSize, alignment: .leading)
            }
          }

          HStack(alignment: .top, spacing: cellSpacing) {
            ForEach(weeks) { week in
              VStack(spacing: cellSpacing) {
                ForEach(week.days) { day in
                  RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(cellColor(for: day))
                    .frame(width: cellSize, height: cellSize)
                    .overlay(
                      RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(day.isToday ? accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
                    )
                    .help(tooltip(for: day))
                }
              }
            }
          }
        }
        .padding(.bottom, 2)
      }
    }
    .padding(.vertical, 2)
  }

  private func cellColor(for day: StatisticsGraphDay) -> Color {
    if day.isOutsidePrimaryRange {
      return Color.secondary.opacity(0.04)
    }

    switch day.intensity {
    case 0:
      return Color.secondary.opacity(0.08)
    case 1:
      return accentColor.opacity(0.18)
    case 2:
      return accentColor.opacity(0.34)
    case 3:
      return accentColor.opacity(0.52)
    default:
      return accentColor.opacity(0.78)
    }
  }

  private func tooltip(for day: StatisticsGraphDay) -> String {
    let date = DateFormatter.localizedString(from: day.date, dateStyle: .medium, timeStyle: .none)
    guard let bucket = day.bucket else {
      return "\(date)\nNo capture activity"
    }

    let durationFormatter = DateComponentsFormatter()
    durationFormatter.allowedUnits = bucket.recordedDurationMS >= 3_600_000 ? [.hour, .minute] : [.minute, .second]
    durationFormatter.unitsStyle = .abbreviated
    let duration = durationFormatter.string(from: TimeInterval(bucket.recordedDurationMS) / 1000) ?? "0s"
    let bytes = ByteCountFormatter.string(fromByteCount: bucket.captureBytesProduced, countStyle: .file)

    return "\(date)\nScreenshots: \(bucket.screenshotCount)\nRecordings: \(bucket.recordingCount)\nRecorded: \(duration)\nStorage: \(bytes)"
  }
}
