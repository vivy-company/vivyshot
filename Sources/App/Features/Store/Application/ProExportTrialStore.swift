import Foundation

@MainActor
final class ProExportTrialStore: ObservableObject {
  private enum Keys {
    static let consumedAt = "settings.proExportTrial.consumedAt"
  }

  @Published private(set) var consumedAt: Date?
  private let defaults: UserDefaults

  var isAvailable: Bool {
    consumedAt == nil
  }

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    consumedAt = defaults.object(forKey: Keys.consumedAt) as? Date
  }

  func markConsumed(at date: Date = Date()) {
    guard consumedAt == nil else {
      return
    }
    consumedAt = date
    defaults.set(date, forKey: Keys.consumedAt)
  }

  func reset() {
    guard consumedAt != nil else {
      return
    }
    consumedAt = nil
    defaults.removeObject(forKey: Keys.consumedAt)
  }
}
