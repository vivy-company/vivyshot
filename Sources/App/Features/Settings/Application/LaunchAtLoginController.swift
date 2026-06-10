import Foundation
import ServiceManagement

/// Launch-at-login states normalized from `SMAppService`.
enum LaunchAtLoginServiceStatus: Equatable {
  case enabled
  case requiresApproval
  case notRegistered
  case unavailable
}

/// Testable abstraction over macOS launch-at-login registration.
protocol LaunchAtLoginService {
  var status: LaunchAtLoginServiceStatus { get }
  func register() throws
  func unregister() throws
}

/// `SMAppService.mainApp` adapter used by production settings.
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

/// Observable settings controller for enabling or disabling launch at login.
@MainActor
final class LaunchAtLoginController: ObservableObject {
  @Published private(set) var isEnabled = false
  @Published private(set) var detailText: String?

  private let service: LaunchAtLoginService
  private let localizer: AppLocalizer

  init(
    service: LaunchAtLoginService = MainAppLaunchAtLoginService(),
    localizer: AppLocalizer
  ) {
    self.service = service
    self.localizer = localizer
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
        bundle: localizer.bundle
      )
    case .notRegistered:
      isEnabled = false
      detailText = nil
    case .unavailable:
      isEnabled = false
      detailText = String(
        localized: "Launch at login is unavailable for this app installation.",
        bundle: localizer.bundle
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
          bundle: localizer.bundle
        )
      } else {
        let messageTemplate = String(
          localized: "Unable to update launch at login. %@",
          bundle: localizer.bundle
        )
        detailText = String(format: messageTemplate, locale: .current, errorDescription)
      }
    }
  }
}
