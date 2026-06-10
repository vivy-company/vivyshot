import SwiftUI

struct StatisticsNavigationSubtitleModifier: ViewModifier {
  let subtitle: String?

  @ViewBuilder
  func body(content: Content) -> some View {
    if let subtitle {
      content.navigationSubtitle(subtitle)
    } else {
      content
    }
  }
}
