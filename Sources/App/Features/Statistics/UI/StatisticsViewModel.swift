import Combine
import Foundation

/// Loads dashboard data and owns transient statistics UI state.
@MainActor
final class StatisticsViewModel: ObservableObject {
  @Published private(set) var dashboardData: StatisticsDashboard = .empty
  @Published private(set) var isLoading = false
  @Published private(set) var hasLoaded = false
  @Published private(set) var loadError: String?
#if DEBUG
  @Published var debugPreviewEnabled = false
#endif

  func refresh(statisticsStore: StatisticsStore) async {
    isLoading = true
    defer {
      isLoading = false
      hasLoaded = true
    }

    guard let dashboardData = await statisticsStore.dashboardData() else {
      loadError = "Statistics are temporarily unavailable."
      return
    }

    self.dashboardData = dashboardData
    loadError = nil
  }
}
