import AppKit
import SwiftUI

// MARK: - Root View

/// Statistics screen reused inside settings and in the standalone statistics window.
@MainActor
struct StatisticsView: View {
  enum Presentation {
    case settings
    case window
  }

  let presentation: Presentation
  @ObservedObject var storeManager: StoreManager
  let statisticsStore: StatisticsStore
  let onUpgrade: () -> Void

  @StateObject private var viewModel = StatisticsViewModel()
  private var hasFullStatisticsAccess: Bool {
  #if DEBUG
    storeManager.canUse(.statistics) || viewModel.debugPreviewEnabled
  #else
    storeManager.canUse(.statistics)
  #endif
  }

  var body: some View {
    ZStack {
      NavigationStack {
        StatisticsRootView(
          viewModel: viewModel,
          storeManager: storeManager,
          accentColor: .accentColor,
          presentation: presentation,
          hasFullAccess: hasFullStatisticsAccess,
          onUpgrade: onUpgrade
        )
      }
    }
    .task {
      await storeManager.refreshEntitlements()
      await viewModel.refresh(statisticsStore: statisticsStore)
      let changes = await statisticsStore.changeStream()
      for await _ in changes {
        await viewModel.refresh(statisticsStore: statisticsStore)
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      Task {
        await storeManager.refreshEntitlements()
        await viewModel.refresh(statisticsStore: statisticsStore)
      }
    }
  }
}
