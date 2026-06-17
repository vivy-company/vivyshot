import SwiftUI

struct StatisticsRootView: View {
  @ObservedObject var viewModel: StatisticsViewModel
  @ObservedObject var storeManager: StoreManager
  @ObservedObject private var localizer = AppLocalizer.shared
  let accentColor: Color
  let presentation: StatisticsView.Presentation
  let hasFullAccess: Bool
  let onUpgrade: () -> Void

  private var dashboardPresentation: StatisticsDashboardPresentation {
    StatisticsDashboardPresentation(dashboardData: viewModel.dashboardData)
  }

  private var hasAnyCaptureData: Bool {
    dashboardPresentation.hasAnyCaptureData
  }

  private var windowSubtitle: String {
    hasFullAccess
      ? localized("Local capture totals, streaks, history, and milestones for this Mac.")
      : localized("Local capture totals and recent activity for this Mac.")
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

      if hasFullAccess {
        statsLiteDashboardSection
        activitySection
        habitsSection
        metricDetailSections
        milestonesSection
      } else {
        statsLiteDashboardSection
        activitySection
        historyInsightsSection
      }
    }
    .formStyle(.grouped)
    .navigationTitle(localized("Statistics"))
    .modifier(StatisticsNavigationSubtitleModifier(subtitle: presentation == .window ? windowSubtitle : nil))
    .frame(maxWidth: presentation == .settings ? 560 : .infinity, maxHeight: .infinity, alignment: .top)
  }

  private var headerSection: some View {
    Section {
      HStack(alignment: .top, spacing: 14) {
        Image(systemName: "chart.bar.xaxis")
          .font(.system(size: 19, weight: .semibold))
          .foregroundStyle(accentColor)
          .frame(width: 32, height: 32)

        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 8) {
            Text(localized("Statistics"))
              .font(.title3.weight(.semibold))

            if let badgeTitle = currentBadgeTitle {
              StoreBadgeChip(title: badgeTitle, prominence: currentBadgeProminence)
            }
          }

          Text(hasFullAccess
               ? localized("Local capture totals, streaks, history, and milestones for this Mac.")
               : localized("Today, this week, and recent capture activity stored locally on this Mac."))
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
          Text(total == 0
               ? localized("No captures tracked yet")
               : String(format: localized("%@ captures tracked locally"), total.formatted()))
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
    viewModel.debugPreviewEnabled && !storeManager.canUse(.statistics)
  #else
    false
  #endif
  }

  private var debugPreviewBanner: some View {
  #if DEBUG
    HStack(spacing: 10) {
      Label(localized("Debug preview is forcing the paid statistics UI."), systemImage: "hammer")
        .font(.subheadline).foregroundStyle(.secondary)
      Spacer(minLength: 0)
      Button(localized("Hide")) { viewModel.debugPreviewEnabled = false }
        .buttonStyle(.bordered)
    }
  #else
    EmptyView()
  #endif
  }

  private var statsLiteDashboardSection: some View {
    Section {
      StatisticsMetricRow(
        title: localized("Today"),
        value: dashboardPresentation.todayAggregate.totalCaptureCount.formatted(),
        detail: StatisticsDashboardPresentation.captureMixLabel(dashboardPresentation.todayAggregate),
        systemImage: "sun.max",
        recentValues: dashboardPresentation.recentMetricValues(dayCount: 7) { Double($0.screenshotCount + $0.recordingCount) }
      )
      StatisticsMetricRow(
        title: localized("This Week"),
        value: dashboardPresentation.currentWeekAggregate.totalCaptureCount.formatted(),
        detail: StatisticsDashboardPresentation.captureMixLabel(dashboardPresentation.currentWeekAggregate),
        systemImage: "calendar",
        recentValues: dashboardPresentation.recentMetricValues(dayCount: 7) { Double($0.screenshotCount + $0.recordingCount) }
      )
      StatisticsMetricRow(
        title: localized("Current Streak"),
        value: StatisticsDashboardPresentation.dayCountLabel(viewModel.dashboardData.summary.currentCaptureStreakDays),
        detail: localized("Consecutive active days"),
        systemImage: "flame"
      )
      StatisticsMetricRow(
        title: localized("Active Days"),
        value: viewModel.dashboardData.summary.activeCaptureDays.formatted(),
        detail: localized("Days with captures on this Mac"),
        systemImage: "checkmark.circle"
      )
    } header: {
      Text(localized("Current Snapshot"))
    } footer: {
      Text(localized("Recent statistics are free. Everything is computed from local events stored on this Mac."))
    }
  }

  private var habitsSection: some View {
    Section {
      StatisticsMetricRow(
        title: localized("Average Screenshot Time"),
        value: StatisticsFormatting.formatDuration(viewModel.dashboardData.summary.averageScreenshotEditorCompletionDurationMS),
        detail: localized("Editor entry to copy/save"),
        systemImage: "stopwatch"
      )
      StatisticsMetricRow(
        title: localized("Current Streak"),
        value: StatisticsDashboardPresentation.dayCountLabel(viewModel.dashboardData.summary.currentCaptureStreakDays),
        detail: localized("Consecutive active days"),
        systemImage: "flame"
      )
      StatisticsMetricRow(
        title: localized("Best Streak"),
        value: StatisticsDashboardPresentation.dayCountLabel(viewModel.dashboardData.summary.bestCaptureStreakDays),
        detail: localized("Personal best"),
        systemImage: "trophy"
      )
      StatisticsMetricRow(
        title: localized("Active Days"),
        value: viewModel.dashboardData.summary.activeCaptureDays.formatted(),
        detail: localized("Days with captures"),
        systemImage: "calendar"
      )
    } header: {
      Text(localized("Habits"))
    } footer: {
      Text(localized("Usage rhythm and editing pace across your capture sessions."))
    }
  }

  @State private var selectedRange: StatisticsGraphRange = .sixMonths
  @State private var selectedDetailRange: StatisticsGraphRange = .sixMonths

  private var effectiveSelectedRange: StatisticsGraphRange {
    hasFullAccess ? selectedRange : .sevenDays
  }

  private var activitySection: some View {
    Section {
      activitySectionContent
    } header: {
      activitySectionHeader
    } footer: {
      let description = dashboardPresentation.dayRangeDescription(for: effectiveSelectedRange)
      Text(hasFullAccess ? description : String(format: localized("%@. Unlock full statistics for 3 months, 6 months, 1 year, and all-time history."), description))
    }
  }

  private var activitySectionHeader: some View {
    HStack {
      Text(localized("Activity"))
      Spacer(minLength: 12)
      if hasFullAccess {
        Picker(localized("Activity Range"), selection: $selectedRange) {
          ForEach(StatisticsGraphRange.allCases) { range in
            Text(range.title).tag(range)
          }
        }
        .pickerStyle(.menu)
        .labelsHidden()
      } else {
        Text(localized("Last 7 days"))
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
      }
    }
  }

  @ViewBuilder
  private var activitySectionContent: some View {
    if hasAnyCaptureData {
      VStack(alignment: .leading, spacing: 12) {
        if dashboardPresentation.hasActivity(in: effectiveSelectedRange) {
          if effectiveSelectedRange == .sevenDays {
            StatisticsRecentActivityBarChart(days: dashboardPresentation.recentActivityDays(dayCount: 7), accentColor: accentColor)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.vertical, 4)
          } else {
            StatisticsContributionGraph(
              weeks: dashboardPresentation.makeGraphWeeks(range: effectiveSelectedRange),
              weekdaySymbols: StatisticsDashboardPresentation.orderedWeekdaySymbols(),
              accentColor: accentColor
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
          }

          StatisticsActivitySummaryRow(
            totalCaptures: dashboardPresentation.aggregate(for: effectiveSelectedRange).totalCaptureCount.formatted(),
            activeDays: dashboardPresentation.activeDayCount(in: effectiveSelectedRange).formatted(),
            busiestDay: dashboardPresentation.busiestDaySummary(in: effectiveSelectedRange)
          )
          .frame(maxWidth: .infinity, alignment: .leading)
        } else {
          ContentUnavailableView {
            Label(localized("No activity in this range"), systemImage: "calendar.badge.exclamationmark")
          } description: {
            Text(hasFullAccess
                 ? localized("Try a wider range to see older capture sessions on this Mac.")
                 : localized("Older activity is still tracked locally. Unlock full statistics to browse longer history."))
          }
          .frame(maxWidth: .infinity).padding(.vertical, 18)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    } else {
      ContentUnavailableView {
        Label(localized("No capture activity yet"), systemImage: "chart.xyaxis.line")
      } description: {
        Text(localized("Take a screenshot or record a video, and your activity history will start building here."))
      }
      .frame(maxWidth: .infinity).padding(.vertical, 18)
    }
  }

  @ViewBuilder
  private var metricDetailSections: some View {
    metricDetailSection(.screenshots)
    metricDetailSection(.recordings)
    metricDetailSection(.recordingTime)
    metricDetailSection(.storage)
  }

  private func metricDetailSection(_ metric: StatisticsOverviewMetric) -> some View {
    Section {
      StatisticsMetricDetailPanel(
        metric: metric,
        dashboardData: viewModel.dashboardData,
        selectedRange: selectedDetailRange,
        accentColor: accentColor
      )
    } header: {
      metricDetailSectionHeader(metric)
    } footer: {
      let bounds = statisticsGraphBounds(for: selectedDetailRange, dashboardData: viewModel.dashboardData)
      Text("\(StatisticsFormatting.formatDate(bounds.startDate)) to \(StatisticsFormatting.formatDate(bounds.endDate))")
    }
  }

  private func metricDetailSectionHeader(_ metric: StatisticsOverviewMetric) -> some View {
    HStack {
      Text(metric.sectionTitle)
      Spacer(minLength: 12)
      Picker(String(format: localized("%@ Range"), metric.menuTitle), selection: $selectedDetailRange) {
        ForEach(StatisticsGraphRange.allCases) { range in
          Text(range.title).tag(range)
        }
      }
      .pickerStyle(.menu)
      .labelsHidden()
    }
  }

  private var historyInsightsSection: some View {
    Section {
      VStack(alignment: .leading, spacing: 14) {
        HStack(alignment: .top, spacing: 12) {
          Image(systemName: "chart.line.uptrend.xyaxis")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(accentColor)
            .frame(width: 28, height: 28)

          VStack(alignment: .leading, spacing: 4) {
            Text(localized("History & Insights"))
              .font(.body.weight(.semibold))
            Text(String(format: localized("%@ captures are already tracked locally. Unlock long-term trends, storage growth, timing, milestones, and metric drilldowns."), dashboardPresentation.totalCaptureCount.formatted()))
              .font(.caption)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }

          Spacer(minLength: 0)
        }

        HStack(spacing: 10) {
          StatisticsInsightPill(title: localized("Tracked"), value: dashboardPresentation.totalCaptureCount.formatted())
          StatisticsInsightPill(title: localized("Active Days"), value: viewModel.dashboardData.summary.activeCaptureDays.formatted())
          StatisticsInsightPill(title: localized("Storage"), value: StatisticsFormatting.formatBytes(viewModel.dashboardData.summary.totalCaptureBytesProduced))
        }

        HStack(spacing: 10) {
          Button(localized("Unlock Full Statistics"), action: onUpgrade)
            .buttonStyle(.borderedProminent)
        #if DEBUG
          Button(localized(viewModel.debugPreviewEnabled ? "Hide Debug Preview" : "Show Debug Preview")) {
            viewModel.debugPreviewEnabled.toggle()
          }
          .buttonStyle(.bordered)
        #endif
          Spacer(minLength: 0)
        }
      }
      .padding(.vertical, 4)
    } header: {
      Text(localized("History & Insights"))
    } footer: {
      Text(localized("Included with Lifetime and Supporter. No subscription."))
    }
  }

  private var milestonesSection: some View {
    Section {
      LabeledContent(localized("First Screenshot")) {
        Text(StatisticsFormatting.formatDateOptional(viewModel.dashboardData.firstScreenshotAt))
      }
      LabeledContent(localized("First Recording")) {
        Text(StatisticsFormatting.formatDateOptional(viewModel.dashboardData.firstRecordingAt))
      }
      LabeledContent(localized("Most Active Day")) {
        Text(dashboardPresentation.mostActiveDayLabel)
      }
    } header: {
      Text(localized("Milestones"))
    }
  }

  private func localized(_ value: String.LocalizationValue) -> String {
    String(localized: value, bundle: localizer.bundle)
  }

  private func localized(_ value: String) -> String {
    String(localized: String.LocalizationValue(value), bundle: localizer.bundle)
  }
}
