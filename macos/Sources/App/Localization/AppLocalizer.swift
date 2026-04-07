import Foundation

final class AppLocalizer: ObservableObject {
  nonisolated(unsafe) static let shared = AppLocalizer()

  @Published private(set) var language: AppLanguage = .system

  private init() {}

  var locale: Locale {
    language.locale
  }

  var bundle: Bundle {
    localizationBundle ?? .main
  }

  func update(language: AppLanguage) {
    guard self.language != language else {
      return
    }
    self.language = language
  }

  func string(_ key: String, fallback: String? = nil) -> String {
    let fallback = fallback ?? key
    guard let bundle = localizationBundle else {
      return NSLocalizedString(key, comment: "")
    }

    let localized = bundle.localizedString(forKey: key, value: fallback, table: nil)
    return localized.isEmpty ? fallback : localized
  }

  private var localizationBundle: Bundle? {
    guard let code = language.localeIdentifier,
          let path = Bundle.main.path(forResource: code, ofType: "lproj"),
          let bundle = Bundle(path: path)
    else {
      return nil
    }
    return bundle
  }
}
