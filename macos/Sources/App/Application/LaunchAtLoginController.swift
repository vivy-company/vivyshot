import Foundation
import ServiceManagement

enum LaunchAtLoginServiceStatus: Equatable {
  case enabled
  case requiresApproval
  case notRegistered
  case unavailable
}

protocol LaunchAtLoginService {
  var status: LaunchAtLoginServiceStatus { get }
  func register() throws
  func unregister() throws
}

struct MainAppLaunchAtLoginService: LaunchAtLoginService {
  private let service: SMAppService

  init(service: SMAppService = .mainApp) {
    self.service = service
  }

  var status: LaunchAtLoginServiceStatus {
    switch service.status {
    case .enabled:
      return .enabled
    case .requiresApproval:
      return .requiresApproval
    case .notRegistered:
      return .notRegistered
    case .notFound:
      return .unavailable
    @unknown default:
      return .unavailable
    }
  }

  func register() throws {
    try service.register()
  }

  func unregister() throws {
    try service.unregister()
  }
}

@MainActor
final class LaunchAtLoginController: ObservableObject {
  static let shared = LaunchAtLoginController()

  @Published private(set) var isEnabled = false
  @Published private(set) var detailText: String?

  private let service: LaunchAtLoginService

  init(service: LaunchAtLoginService = MainAppLaunchAtLoginService()) {
    self.service = service
    refresh()
  }

  func refresh() {
    switch service.status {
    case .enabled:
      isEnabled = true
      detailText = nil
    case .requiresApproval:
      isEnabled = true
      detailText = String(
        localized: "Finish enabling startup in System Settings > General > Login Items.",
        bundle: AppLocalizer.shared.bundle
      )
    case .notRegistered:
      isEnabled = false
      detailText = nil
    case .unavailable:
      isEnabled = false
      detailText = String(
        localized: "Launch at login is unavailable for this app installation.",
        bundle: AppLocalizer.shared.bundle
      )
    }
  }

  func setEnabled(_ enabled: Bool) {
    do {
      if enabled {
        try service.register()
      } else {
        try service.unregister()
      }
      refresh()
    } catch {
      refresh()
      let errorDescription = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
      if errorDescription.isEmpty {
        detailText = String(
          localized: "Unable to update launch at login.",
          bundle: AppLocalizer.shared.bundle
        )
      } else {
        let messageTemplate = String(
          localized: "Unable to update launch at login. %@",
          bundle: AppLocalizer.shared.bundle
        )
        detailText = String(format: messageTemplate, locale: .current, errorDescription)
      }
    }
  }
}
