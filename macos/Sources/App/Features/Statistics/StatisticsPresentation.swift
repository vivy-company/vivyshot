import SwiftUI

enum StatisticsWindowScene {
  static let id = "statistics-window"
}

struct StatisticsWindowSceneRootView: View {
  var body: some View {
    if #available(macOS 26.0, *) {
      VivyShotStatisticsView(presentation: .window)
        .frame(minWidth: 660, minHeight: 560)
        .scrollEdgeEffectStyle(.soft, for: .top)
    } else {
      VivyShotStatisticsView(presentation: .window)
        .frame(minWidth: 660, minHeight: 560)
    }
  }
}
