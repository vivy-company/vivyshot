import Combine

enum AppSettingsChange: Hashable, Sendable {
  case captureShortcut
  case regionSelection
  case video
  case appLanguage
}

extension AppSettings {
  var settingsChanges: AnyPublisher<AppSettingsChange, Never> {
    settingsChangeSubject.eraseToAnyPublisher()
  }

  var captureShortcutChanges: AnyPublisher<Void, Never> {
    settingsChanges(for: .captureShortcut)
  }

  var regionSelectionSettingsChanges: AnyPublisher<Void, Never> {
    settingsChanges(for: .regionSelection)
  }

  var videoSettingsChanges: AnyPublisher<Void, Never> {
    settingsChanges(for: .video)
  }

  var appLanguageChanges: AnyPublisher<Void, Never> {
    settingsChanges(for: .appLanguage)
  }

  func notifySettingsChanged(_ changes: AppSettingsChange...) {
    for change in changes {
      settingsChangeSubject.send(change)
    }
  }

  private func settingsChanges(for target: AppSettingsChange) -> AnyPublisher<Void, Never> {
    settingsChangeSubject
      .filter { $0 == target }
      .map { _ in () }
      .eraseToAnyPublisher()
  }
}
