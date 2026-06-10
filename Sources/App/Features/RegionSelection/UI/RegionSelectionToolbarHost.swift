import SwiftUI

@MainActor
final class RegionSelectionToolbarRefresh: ObservableObject {
  @Published private(set) var revision = 0
  private(set) var lastRefreshAnimated = false

  func refresh(animated: Bool) {
    lastRefreshAnimated = animated
    if animated {
      withAnimation(.smooth(duration: 0.28)) {
        revision += 1
      }
    } else {
      revision += 1
    }
  }
}

@MainActor
struct RegionSelectionToolbarHost: View {
  @ObservedObject var refresh: RegionSelectionToolbarRefresh
  let content: (Namespace.ID) -> AnyView

  @Namespace private var glassNamespace

  var body: some View {
    let revision = refresh.revision
    let animated = refresh.lastRefreshAnimated
    ZStack {
      content(glassNamespace)
        .id(revision)
        .transition(toolbarTransition(animated: animated))
    }
    .animation(animated ? .smooth(duration: 0.26) : nil, value: revision)
  }

  private func toolbarTransition(animated: Bool) -> AnyTransition {
    guard animated else {
      return .identity
    }

    return .asymmetric(
      insertion: .opacity
        .combined(with: .scale(scale: 0.985, anchor: .center))
        .combined(with: .offset(y: 3)),
      removal: .opacity
        .combined(with: .scale(scale: 1.015, anchor: .center))
        .combined(with: .offset(y: -3))
    )
  }
}
