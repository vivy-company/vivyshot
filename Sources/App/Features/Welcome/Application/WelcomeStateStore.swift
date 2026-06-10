import Foundation

@MainActor
final class WelcomeStateStore: ObservableObject {
  private enum Keys {
    static let hasSeenWelcome = "settings.welcome.hasSeenWelcome"
  }

  @Published private(set) var hasSeenWelcome: Bool

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    hasSeenWelcome = defaults.bool(forKey: Keys.hasSeenWelcome)
  }

  func markSeen() {
    guard !hasSeenWelcome else {
      return
    }
    hasSeenWelcome = true
    defaults.set(true, forKey: Keys.hasSeenWelcome)
  }
}
