import AppKit
import Charts
import SwiftUI

// MARK: - View Model

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

// MARK: - Root View

@MainActor
struct VivyShotStatisticsView: View {
  enum Presentation {
    case settings
    case window
  }

  let presentation: Presentation

  @ObservedObject private var storeManager = StoreManager.shared
  @StateObject private var viewModel = CaptureStatisticsViewModel()
  private var hasStatisticsAccess: Bool {
  #if DEBUG
    storeManager.hasPaidAccess || viewModel.debugPreviewEnabled
  #else
    storeManager.hasPaidAccess
  #endif
  }

  private var statisticsAccentColor: Color {
    storeManager.hasSupporterBadge ? .orange : .accentColor
  }

  var body: some View {
    ZStack {
      NavigationStack {
        StatisticsRootView(
          viewModel: viewModel,
          storeManager: storeManager,
          accentColor: statisticsAccentColor,
          presentation: presentation
        )
      }
      .blur(radius: hasStatisticsAccess ? 0 : 8)
      .opacity(hasStatisticsAccess ? 1 : 0.52)
      .allowsHitTesting(hasStatisticsAccess)

      if !hasStatisticsAccess {
        StatisticsLockedOverlay(
          totalCapturesSummary: previewSummary,
          onUpgrade: { presentPaywallWindow() },
          debugPreviewEnabled: $viewModel.debugPreviewEnabled,
          hasPaidAccess: storeManager.hasPaidAccess
        )
      }
    }
    .task {
      await storeManager.refreshEntitlements()
      await viewModel.refresh()
    }
    .onReceive(NotificationCenter.default.publisher(for: .vivyShotStatisticsDidChange)) { _ in
      Task { await viewModel.refresh() }
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      Task {
        await storeManager.refreshEntitlements()
        await viewModel.refresh()
      }
    }
  }

  private var previewSummary: String {
    let total = viewModel.dashboardData.summary.totalScreenshotsCaptured + viewModel.dashboardData.summary.totalRecordingsCompleted
    if total == 0 { return "No captures tracked yet" }
    return "\(total.formatted()) captures tracked locally"
  }
}

// MARK: - Root List

private struct StatisticsRootView: View {
  @ObservedObject var viewModel: CaptureStatisticsViewModel
  @ObservedObject var storeManager: StoreManager
  let accentColor: Color
  let presentation: VivyShotStatisticsView.Presentation

  private var hasAnyCaptureData: Bool {
    let s = viewModel.dashboardData.summary
    return s.totalScreenshotsCaptured > 0 || s.totalRecordingsCompleted > 0 || !viewModel.dashboardData.dailyBuckets.isEmpty
  }

  var body: some View {
    Form {
      if presentation == .settings {
        headerSection
      }

    #if DEBUG
      if showDebugPreviewBanner {
        Section {
          debugPreviewBanner
        }
      }
    #endif

      overviewSection
      habitsSection
      activitySection
      breakdownSection
      milestonesSection
    }
    .formStyle(.grouped)
    .navigationTitle("Statistics")
    .navigationSubtitle("Local capture totals, streaks, history, and milestones for this Mac.")
    .onAppear {
      guard presentation == .window else { return }
      DispatchQueue.main.async {
        guard let window = NSApp.keyWindow else { return }
        window.title = "Statistics"
        window.subtitle = "Local capture totals, streaks, history, and milestones for this Mac."
        window.toolbarStyle = .unified
      }
    }
    .frame(maxWidth: presentation == .settings ? 560 : .infinity, maxHeight: .infinity, alignment: .top)
  }

  // MARK: Header (settings only)

  private var headerSection: some View {
    Section {
      HStack(alignment: .top, spacing: 14) {
        Image(systemName: "chart.bar.xaxis")
          .font(.system(size: 19, weight: .semibold))
          .foregroundStyle(accentColor)
          .frame(width: 32, height: 32)

        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 8) {
            Text("Statistics")
              .font(.title3.weight(.semibold))

            if let badgeTitle = currentBadgeTitle {
              StoreBadgeChip(title: badgeTitle, prominence: currentBadgeProminence)
            }
          }

          Text("Local capture totals, streaks, history, and milestones for this Mac.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        Spacer(minLength: 0)
      }

      HStack(alignment: .center, spacing: 12) {
        if viewModel.isLoading {
          ProgressView().controlSize(.small)
        } else if let error = viewModel.loadError, viewModel.dashboardData.dailyBuckets.isEmpty {
          Text(error).font(.caption).foregroundStyle(.secondary)
        } else {
          let total = viewModel.dashboardData.summary.totalScreenshotsCaptured + viewModel.dashboardData.summary.totalRecordingsCompleted
          Text(total == 0 ? "No captures tracked yet" : "\(total.formatted()) captures tracked locally")
            .font(.caption).foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
      }
    }
  }

  private var currentBadgeTitle: String? {
  #if DEBUG
    if showDebugPreviewBanner { return "Debug Preview" }
  #endif
    return storeManager.badgeTitle
  }

  private var currentBadgeProminence: StoreBadgeChip.Prominence {
  #if DEBUG
    if showDebugPreviewBanner { return .free }
  #endif
    if storeManager.hasSupporterBadge { return .supporter }
    if storeManager.hasLifetimeUnlock { return .lifetime }
    return .free
  }

  private var showDebugPreviewBanner: Bool {
  #if DEBUG
    viewModel.debugPreviewEnabled && !storeManager.hasPaidAccess
  #else
    false
  #endif
  }

  private var debugPreviewBanner: some View {
  #if DEBUG
    HStack(spacing: 10) {
      Label("Debug preview is forcing the paid statistics UI.", systemImage: "hammer")
        .font(.subheadline).foregroundStyle(.secondary)
      Spacer(minLength: 0)
      Button("Hide") { viewModel.debugPreviewEnabled = false }
        .buttonStyle(.bordered)
    }
  #else
    EmptyView()
  #endif
  }

  // MARK: Overview

  private var overviewSection: some View {
    Section {
      NavigationLink(value: StatisticsOverviewMetric.screenshots) {
        StatisticsMetricRow(
          title: "Total Screenshots",
          value: viewModel.dashboardData.summary.totalScreenshotsCaptured.formatted(),
          detail: "All-time captures",
          systemImage: "camera",
          recentValues: recentMetricValues { Double($0.screenshotCount) }
        )
      }

      NavigationLink(value: StatisticsOverviewMetric.recordings) {
        StatisticsMetricRow(
          title: "Total Recordings",
          value: viewModel.dashboardData.summary.totalRecordingsCompleted.formatted(),
          detail: "Completed recordings",
          systemImage: "record.circle",
          recentValues: recentMetricValues { Double($0.recordingCount) }
        )
      }

      NavigationLink(value: StatisticsOverviewMetric.recordingTime) {
        StatisticsMetricRow(
          title: "Total Recording Time",
          value: StatisticsFormatting.formatDuration(viewModel.dashboardData.summary.totalRecordedDurationMS),
          detail: "Finished sessions only",
          systemImage: "timer",
          recentValues: recentMetricValues { Double($0.recordedDurationMS) }
        )
      }

      NavigationLink(value: StatisticsOverviewMetric.storage) {
        StatisticsMetricRow(
          title: "Storage Produced",
          value: StatisticsFormatting.formatBytes(viewModel.dashboardData.summary.totalCaptureBytesProduced),
          detail: "Primary output artifacts",
          systemImage: "internaldrive",
          recentValues: recentMetricValues { Double($0.captureBytesProduced) }
        )
      }
    } header: {
      Text("Overview")
    } footer: {
      Text("All statistics are computed from local capture events and stored on this Mac.")
    }
    .navigationDestination(for: StatisticsOverviewMetric.self) { metric in
      StatisticsMetricDetailView(
        metric: metric,
        dashboardData: viewModel.dashboardData,
        accentColor: accentColor
      )
    }
  }

  // MARK: Habits

  private var habitsSection: some View {
    Section {
      StatisticsMetricRow(
        title: "Average Screenshot Time",
        value: StatisticsFormatting.formatDuration(viewModel.dashboardData.summary.averageScreenshotEditorCompletionDurationMS),
        detail: "Editor entry to copy/save",
        systemImage: "stopwatch"
      )
      StatisticsMetricRow(
        title: "Current Streak",
        value: dayCountLabel(viewModel.dashboardData.summary.currentCaptureStreakDays),
        detail: "Consecutive active days",
        systemImage: "flame"
      )
      StatisticsMetricRow(
        title: "Best Streak",
        value: dayCountLabel(viewModel.dashboardData.summary.bestCaptureStreakDays),
        detail: "Personal best",
        systemImage: "trophy"
      )
      StatisticsMetricRow(
        title: "Active Days",
        value: viewModel.dashboardData.summary.activeCaptureDays.formatted(),
        detail: "Days with captures",
        systemImage: "calendar"
      )
    } header: {
      Text("Habits")
    } footer: {
      Text("Usage rhythm and editing pace across your capture sessions.")
    }
  }

  // MARK: Activity

  @State private var selectedRange: StatisticsGraphRange = .sixMonths

  private var activitySection: some View {
    Section {
      activitySectionContent
    } header: {
      Text("Activity")
    } footer: {
      Text(dayRangeDescription)
    }
  }

  @ViewBuilder
  private var activitySectionContent: some View {
    if hasAnyCaptureData {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .center, spacing: 12) {
          Text("Range")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
          Spacer(minLength: 0)
          Picker("Range", selection: $selectedRange) {
            ForEach(StatisticsGraphRange.allCases) { range in
              Text(range.title).tag(range)
            }
          }
          .pickerStyle(.segmented)
          .frame(width: 220)
          .labelsHidden()
        }

        if hasActivityInSelectedRange {
          StatisticsContributionGraph(
            weeks: makeGraphWeeks(range: selectedRange),
            weekdaySymbols: orderedWeekdaySymbols(),
            accentColor: accentColor
          )
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.vertical, 4)

          StatisticsActivitySummaryRow(
            totalCaptures: selectedRangeAggregate.totalCaptureCount.formatted(),
            activeDays: selectedRangeActiveDayCount.formatted(),
            busiestDay: busiestDaySummary
          )
          .frame(maxWidth: .infinity, alignment: .leading)
        } else {
          ContentUnavailableView {
            Label("No activity in this range", systemImage: "calendar.badge.exclamationmark")
          } description: {
            Text("Try a wider range to see older capture sessions on this Mac.")
          }
          .frame(maxWidth: .infinity).padding(.vertical, 18)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    } else {
      ContentUnavailableView {
        Label("No capture activity yet", systemImage: "chart.xyaxis.line")
      } description: {
        Text("Take a screenshot or record a video, and your activity history will start building here.")
      }
      .frame(maxWidth: .infinity).padding(.vertical, 18)
    }
  }

  // MARK: Breakdown

  @ViewBuilder
  private var breakdownSection: some View {
    Section {
      if hasAnyCaptureData {
        StatisticsBreakdownGrid(
          screenshotWeek: metricBreakdown(\.screenshotCount).week.formatted(),
          screenshotMonth: metricBreakdown(\.screenshotCount).month.formatted(),
          screenshotAllTime: viewModel.dashboardData.summary.totalScreenshotsCaptured.formatted(),
          recordingWeek: metricBreakdown(\.recordingCount).week.formatted(),
          recordingMonth: metricBreakdown(\.recordingCount).month.formatted(),
          recordingAllTime: viewModel.dashboardData.summary.totalRecordingsCompleted.formatted(),
          durationWeek: StatisticsFormatting.formatDuration(metricBreakdown(\.recordedDurationMS).week),
          durationMonth: StatisticsFormatting.formatDuration(metricBreakdown(\.recordedDurationMS).month),
          durationAllTime: StatisticsFormatting.formatDuration(viewModel.dashboardData.summary.totalRecordedDurationMS),
          storageWeek: StatisticsFormatting.formatBytes(metricBreakdown(\.captureBytesProduced).week),
          storageMonth: StatisticsFormatting.formatBytes(metricBreakdown(\.captureBytesProduced).month),
          storageAllTime: StatisticsFormatting.formatBytes(viewModel.dashboardData.summary.totalCaptureBytesProduced)
        )
      } else {
        ContentUnavailableView {
          Label("No totals yet", systemImage: "sum")
        } description: {
          Text("Weekly, monthly, and all-time totals appear after your first capture.")
        }
        .frame(maxWidth: .infinity).padding(.vertical, 18)
      }
    } header: {
      Text("Breakdown")
    } footer: {
      Text("This week, this month, and lifetime totals.")
    }
  }

  // MARK: Milestones

  private var milestonesSection: some View {
    Section {
      LabeledContent("First Screenshot") {
        Text(StatisticsFormatting.formatDateOptional(viewModel.dashboardData.firstScreenshotAt))
      }
      LabeledContent("First Recording") {
        Text(StatisticsFormatting.formatDateOptional(viewModel.dashboardData.firstRecordingAt))
      }
      LabeledContent("Most Active Day") {
        Text(mostActiveDayLabel)
      }
    } header: {
      Text("Milestones")
    }
  }

  // MARK: Computed Helpers

  private var mostActiveDayLabel: String {
    guard let day = viewModel.dashboardData.summary.mostActiveDay else { return "No activity yet" }
    return "\(StatisticsFormatting.formatDayKey(day)) \u{2022} score \(viewModel.dashboardData.summary.mostActiveDayScore)"
  }

  private var selectedRangeAggregate: StatisticsAggregate {
    aggregateBuckets(in: graphRangeBounds(for: selectedRange))
  }

  private var hasActivityInSelectedRange: Bool {
    selectedRangeAggregate.totalCaptureCount > 0
  }

  private var selectedRangeActiveDayCount: Int {
    let calendar = Calendar.autoupdatingCurrent
    let bounds = graphRangeBounds(for: selectedRange)
    return viewModel.dashboardData.dailyBuckets.reduce(into: 0) { count, bucket in
      guard bucket.activityScore > 0, let bucketDate = bucket.day.asDate(calendar: calendar) else { return }
      let normalized = calendar.startOfDay(for: bucketDate)
      if normalized >= bounds.startDate && normalized <= bounds.endDate { count += 1 }
    }
  }

  private var busiestDaySummary: String {
    let calendar = Calendar.autoupdatingCurrent
    let bounds = graphRangeBounds(for: selectedRange)
    guard let bucket = viewModel.dashboardData.dailyBuckets
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

  private var dayRangeDescription: String {
    guard hasAnyCaptureData else {
      return "Capture activity appears here after your first screenshot or recording."
    }
    let bounds = graphRangeBounds(for: selectedRange)
    return "\(StatisticsFormatting.formatDate(bounds.startDate)) to \(StatisticsFormatting.formatDate(bounds.endDate))"
  }

  private func dayCountLabel(_ count: Int) -> String {
    count == 1 ? "1 day" : "\(count) days"
  }

  private func recentMetricValues(dayCount: Int = 10, value: (RustStatsDailyBucket) -> Double) -> [Double] {
    let calendar = Calendar.autoupdatingCurrent
    let today = calendar.startOfDay(for: Date())
    let byKey = Dictionary(uniqueKeysWithValues: viewModel.dashboardData.dailyBuckets.map { ($0.day.yyyyMMdd, $0) })
    return (0..<dayCount).map { i in
      let date = calendar.date(byAdding: .day, value: i - (dayCount - 1), to: today) ?? today
      guard let bucket = byKey[StatisticsFormatting.dayKey(for: date, calendar: calendar)] else { return 0 }
      return value(bucket)
    }
  }

  private func metricBreakdown(_ keyPath: KeyPath<StatisticsAggregate, Int64>) -> (week: Int64, month: Int64) {
    let calendar = Calendar.autoupdatingCurrent
    let weekInterval = calendar.dateInterval(of: .weekOfYear, for: Date())
    let monthInterval = calendar.dateInterval(of: .month, for: Date())
    let weekStart = weekInterval?.start ?? Date()
    let weekEnd = weekInterval.flatMap { calendar.date(byAdding: .day, value: -1, to: $0.end) } ?? Date()
    let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
    let monthEnd = monthInterval.flatMap { calendar.date(byAdding: .day, value: -1, to: $0.end) } ?? Date()
    let w = aggregateBuckets(in: StatisticsGraphBounds(startDate: calendar.startOfDay(for: weekStart), endDate: calendar.startOfDay(for: weekEnd)))
    let m = aggregateBuckets(in: StatisticsGraphBounds(startDate: calendar.startOfDay(for: monthStart), endDate: calendar.startOfDay(for: monthEnd)))
    return (w[keyPath: keyPath], m[keyPath: keyPath])
  }

  private func graphRangeBounds(for range: StatisticsGraphRange) -> StatisticsGraphBounds {
    statisticsGraphBounds(for: range, dashboardData: viewModel.dashboardData)
  }

  private func aggregateBuckets(in bounds: StatisticsGraphBounds) -> StatisticsAggregate {
    let calendar = Calendar.autoupdatingCurrent
    return viewModel.dashboardData.dailyBuckets.reduce(into: StatisticsAggregate()) { agg, bucket in
      guard let d = bucket.day.asDate(calendar: calendar) else { return }
      let n = calendar.startOfDay(for: d)
      if n >= bounds.startDate && n <= bounds.endDate { agg.add(bucket) }
    }
  }

  private func makeGraphWeeks(range: StatisticsGraphRange) -> [StatisticsGraphWeek] {
    let bounds = graphRangeBounds(for: range)
    return makeGraphWeeks(startDate: bounds.startDate, endDate: bounds.endDate)
  }

  private func makeGraphWeeks(startDate: Date, endDate: Date) -> [StatisticsGraphWeek] {
    let calendar = Calendar.autoupdatingCurrent
    let normStart = calendar.startOfDay(for: startDate)
    let normEnd = calendar.startOfDay(for: endDate)
    let firstGrid = calendar.dateInterval(of: .weekOfYear, for: normStart)?.start ?? normStart
    let lastGrid = calendar.date(byAdding: .day, value: 6, to: calendar.dateInterval(of: .weekOfYear, for: normEnd)?.start ?? normEnd) ?? normEnd
    let byKey = Dictionary(uniqueKeysWithValues: viewModel.dashboardData.dailyBuckets.map { ($0.day.yyyyMMdd, $0) })

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
        date: day.date, bucket: day.bucket,
        intensity: intensity(for: day.bucket?.activityScore ?? 0, maxScore: maxScore),
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

  private func intensity(for score: Int64, maxScore: Int64) -> Int {
    guard score > 0 else { return 0 }
    let n = Double(score) / Double(maxScore)
    switch n {
    case ..<0.25: return 1
    case ..<0.5: return 2
    case ..<0.75: return 3
    default: return 4
    }
  }

  private func orderedWeekdaySymbols() -> [String] {
    let calendar = Calendar.autoupdatingCurrent
    let symbols = calendar.shortWeekdaySymbols
    let start = max(calendar.firstWeekday - 1, 0)
    return (Array(symbols[start...]) + Array(symbols[..<start])).map { String($0.prefix(1)) }
  }
}

// MARK: - Metric Detail View (NavigationStack destination)

enum StatisticsOverviewMetric: String, Identifiable, Hashable {
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

  func value(for bucket: RustStatsDailyBucket) -> Double {
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
      return "\(date) \u{2022} \(c.formatted()) \(c == 1 ? "screenshot" : "screenshots")"
    case .recordings:
      let c = Int64(point.value.rounded())
      return "\(date) \u{2022} \(c.formatted()) \(c == 1 ? "recording" : "recordings")"
    case .recordingTime, .storage:
      return "\(date) \u{2022} \(formatValue(point.value))"
    }
  }
}

private struct StatisticsMetricDetailView: View {
  let metric: StatisticsOverviewMetric
  let dashboardData: CaptureStatisticsDashboardData
  let accentColor: Color

  @State private var selectedRange: StatisticsGraphRange = .sixMonths

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
    Form {
      Section {
        HStack(alignment: .center, spacing: 12) {
          Text("Range")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
          Spacer(minLength: 0)
          Picker("Range", selection: $selectedRange) {
            ForEach(StatisticsGraphRange.allCases) { range in
              Text(range.title).tag(range)
            }
          }
          .pickerStyle(.segmented)
          .frame(width: 220)
          .labelsHidden()
        }

        if hasData {
          StatisticsMetricDetailChart(metric: metric, points: points, accentColor: accentColor)
            .padding(.top, 8)

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
      } footer: {
        Text("\(StatisticsFormatting.formatDate(bounds.startDate)) to \(StatisticsFormatting.formatDate(bounds.endDate))")
      }
    }
    .formStyle(.grouped)
    .navigationTitle(metric.title)
    .navigationSubtitle(metric.subtitle)
  }
}

// MARK: - Reusable Row Components

private struct StatisticsMetricRow: View {
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

// MARK: - Detail Chart

struct StatisticsMetricDetailPoint: Identifiable {
  let date: Date
  let value: Double
  var id: Date { date }
}

private struct StatisticsMetricDetailChart: View {
  let metric: StatisticsOverviewMetric
  let points: [StatisticsMetricDetailPoint]
  let accentColor: Color

  private var chartWidth: CGFloat {
    max(640, CGFloat(points.count) * pointWidth)
  }

  private var pointWidth: CGFloat {
    switch points.count {
    case ...31: return 16
    case ...92: return 10
    case ...185: return 8
    default: return 6
    }
  }

  var body: some View {
    GeometryReader { proxy in
      ScrollView(.horizontal, showsIndicators: false) {
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
        .frame(width: max(proxy.size.width, chartWidth), height: 240)
      }
    }
    .frame(height: 240)
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

// MARK: - Activity Components

private struct StatisticsActivitySummaryRow: View {
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

// MARK: - Breakdown Grid

private struct StatisticsBreakdownGrid: View {
  let screenshotWeek, screenshotMonth, screenshotAllTime: String
  let recordingWeek, recordingMonth, recordingAllTime: String
  let durationWeek, durationMonth, durationAllTime: String
  let storageWeek, storageMonth, storageAllTime: String

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      breakdownHeader
      breakdownRow("Screenshots", screenshotWeek, screenshotMonth, screenshotAllTime)
      breakdownRow("Recordings", recordingWeek, recordingMonth, recordingAllTime)
      breakdownRow("Recording Time", durationWeek, durationMonth, durationAllTime)
      breakdownRow("Storage Produced", storageWeek, storageMonth, storageAllTime)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 4)
  }

  private var breakdownHeader: some View {
    HStack(spacing: 18) {
      Text("Metric").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
      Text("Week").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .trailing)
      Text("Month").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .trailing)
      Text("All Time").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
  }

  private func breakdownRow(_ title: String, _ week: String, _ month: String, _ allTime: String) -> some View {
    HStack(spacing: 18) {
      Text(title).font(.subheadline.weight(.medium))
        .frame(maxWidth: .infinity, alignment: .leading)
      Text(week).font(.system(.subheadline, design: .monospaced))
        .frame(maxWidth: .infinity, alignment: .trailing)
      Text(month).font(.system(.subheadline, design: .monospaced))
        .frame(maxWidth: .infinity, alignment: .trailing)
      Text(allTime).font(.system(.subheadline, design: .monospaced))
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
  }
}

// MARK: - Locked Overlay

private struct StatisticsLockedOverlay: View {
  let totalCapturesSummary: String
  let onUpgrade: () -> Void
  @Binding var debugPreviewEnabled: Bool
  let hasPaidAccess: Bool

  private let features: [(String, String, String)] = [
    ("Longer History", "Browse your capture activity across weeks, months, and years.", "calendar.badge.clock"),
    ("Timing", "See how long screenshots and recordings usually take.", "stopwatch"),
    ("Storage", "Keep an eye on how much space your captures create.", "internaldrive"),
    ("Milestones", "Spot first captures, busiest days, and progress over time.", "flag.2.crossed"),
  ]

  var body: some View {
    ZStack {
      Rectangle().fill(Color.black.opacity(0.16)).ignoresSafeArea()

      VStack(alignment: .leading, spacing: 18) {
        HStack(spacing: 12) {
          ZStack {
            Circle().fill(.thinMaterial).frame(width: 34, height: 34)
            Image(systemName: "lock.fill")
              .font(.system(size: 15, weight: .semibold)).foregroundStyle(.secondary)
          }
          Text("Unlock Statistics").font(.title3.weight(.semibold))
        }

        VStack(alignment: .leading, spacing: 8) {
          Text("See your streaks, recording time, storage, and long-term capture habits in one place.")
            .font(.subheadline).foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
          Text("Included with Lifetime and Supporter. Your captures are already being counted on this Mac.")
            .font(.subheadline).foregroundStyle(Color.primary.opacity(0.72))
            .fixedSize(horizontal: false, vertical: true)
          Text(totalCapturesSummary)
            .font(.caption).foregroundStyle(Color.primary.opacity(0.58))
        }

        VStack(alignment: .leading, spacing: 0) {
          ForEach(features.indices, id: \.self) { i in
            let (title, detail, icon) = features[i]
            HStack(alignment: .top, spacing: 12) {
              Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(.secondary)
                .frame(width: 20, height: 20).padding(.top, 2)
              VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
                  .fixedSize(horizontal: false, vertical: true)
              }
            }
            .padding(.vertical, 6)
            if i < features.count - 1 { Divider() }
          }
        }
        .padding(.vertical, 4)

        HStack(spacing: 10) {
          Button("Unlock Statistics", action: onUpgrade)
            .buttonStyle(.borderedProminent)
        #if DEBUG
          Button(debugPreviewEnabled ? "Hide Debug Preview" : "Show Debug Preview") {
            debugPreviewEnabled.toggle()
          }
          .buttonStyle(.bordered)
        #endif
        }

        Text("One-time purchase. No subscription.")
          .font(.caption).foregroundStyle(Color.primary.opacity(0.58))
      }
      .padding(26)
      .frame(maxWidth: 620, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 22, style: .continuous)
          .fill(Color(nsColor: .windowBackgroundColor).opacity(0.96))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 22, style: .continuous)
          .strokeBorder(Color.white.opacity(0.05))
      )
      .shadow(color: .black.opacity(0.16), radius: 22, y: 12)
      .padding(8)
    }
  }
}

// MARK: - Contribution Graph

private struct StatisticsGraphBounds {
  let startDate: Date
  let endDate: Date
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
  var isToday: Bool { Calendar.autoupdatingCurrent.isDateInToday(date) }
}

private struct StatisticsGraphMonthSegment: Identifiable {
  let title: String
  let weekCount: Int
  let startDate: Date
  var id: Date { startDate }
}

private struct StatisticsContributionGraph: View {
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
    case ...16: return 380
    case 17...32: return 220
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
    let cell = max(minimumCellSize(for: wc), fitted)
    let remaining = max(width - CGFloat(wc) * cell, 0)
    let spacing = gaps > 0 ? remaining / gaps : 0
    return ContributionGraphLayout(cellSize: cell, horizontalSpacing: spacing, verticalSpacing: verticalSpacing, contentWidth: width)
  }

  private func minimumCellSize(for wc: Int) -> CGFloat {
    switch wc {
    case ...16: return 18
    case 17...32: return 12
    case 33...56: return 8
    default: return 6
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

// MARK: - Aggregate

private struct StatisticsAggregate {
  var screenshotCount: Int64 = 0
  var recordingCount: Int64 = 0
  var recordedDurationMS: Int64 = 0
  var captureBytesProduced: Int64 = 0

  var totalCaptureCount: Int64 { screenshotCount + recordingCount }

  mutating func add(_ bucket: RustStatsDailyBucket) {
    screenshotCount += Int64(bucket.screenshotCount)
    recordingCount += Int64(bucket.recordingCount)
    recordedDurationMS += bucket.recordedDurationMS
    captureBytesProduced += bucket.captureBytesProduced
  }
}

// MARK: - Graph Bounds

private func statisticsGraphBounds(
  for range: StatisticsGraphRange,
  dashboardData: CaptureStatisticsDashboardData,
  calendar: Calendar = .autoupdatingCurrent
) -> StatisticsGraphBounds {
  let today = calendar.startOfDay(for: Date())
  let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
  let monthEnd = calendar.dateInterval(of: .month, for: today)
    .flatMap { calendar.date(byAdding: .day, value: -1, to: $0.end) } ?? today

  switch range {
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

// MARK: - Formatting

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

  static func formatDayKey(_ dayKey: RustStatsDayKey) -> String {
    formatDateOptional(dayKey.asDate())
  }

  static func dayKey(for date: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
    let c = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
  }
}
