import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
  case system
  case english = "en"
  case simplifiedChinese = "zh-Hans"
  case japanese = "ja"
  case korean = "ko"
  case german = "de"
  case french = "fr"
  case spanish = "es"

  var id: String { rawValue }

  var localeIdentifier: String? {
    switch self {
    case .system:
      return nil
    case .english:
      return "en"
    case .simplifiedChinese:
      return "zh-Hans"
    case .japanese:
      return "ja"
    case .korean:
      return "ko"
    case .german:
      return "de"
    case .french:
      return "fr"
    case .spanish:
      return "es"
    }
  }

  var locale: Locale {
    if let localeIdentifier {
      return Locale(identifier: localeIdentifier)
    }
    return .autoupdatingCurrent
  }

  var nativeDisplayName: String {
    switch self {
    case .system:
      return "System Default"
    case .english:
      return "English"
    case .simplifiedChinese:
      return "简体中文"
    case .japanese:
      return "日本語"
    case .korean:
      return "한국어"
    case .german:
      return "Deutsch"
    case .french:
      return "Français"
    case .spanish:
      return "Español"
    }
  }
}
