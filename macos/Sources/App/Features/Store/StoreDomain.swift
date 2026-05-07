import Foundation

enum PurchaseState: Equatable {
  case idle
  case purchasing
  case purchased
  case failed(String)
}

enum RestoreState: Equatable {
  case idle
  case restoring
  case restored(hasAccess: Bool)
  case failed(String)
}

enum VivyShotProducts {
  static let lifetime = "com.vivyshot.lifetime"
  static let supporter = "com.vivyshot.supporter"

  static let allProductIDs = [lifetime, supporter]
}

enum VivyShotPaidFeature: CaseIterable {
  case captureTransitions
  case microphone
  case webcamOverlay
  case keystrokeOverlay
  case gifExport
  case advancedExport
  case statistics

  var title: String {
    switch self {
    case .captureTransitions:
      return String(localized: "Capture transitions", bundle: AppLocalizer.shared.bundle)
    case .microphone:
      return String(localized: "Microphone recording", bundle: AppLocalizer.shared.bundle)
    case .webcamOverlay:
      return String(localized: "Webcam overlay", bundle: AppLocalizer.shared.bundle)
    case .keystrokeOverlay:
      return String(localized: "Keystroke overlay", bundle: AppLocalizer.shared.bundle)
    case .gifExport:
      return String(localized: "GIF export", bundle: AppLocalizer.shared.bundle)
    case .advancedExport:
      return String(localized: "Advanced export", bundle: AppLocalizer.shared.bundle)
    case .statistics:
      return String(localized: "Statistics", bundle: AppLocalizer.shared.bundle)
    }
  }
}

struct StoreEntitlement: Equatable {
  let hasLifetimeUnlock: Bool
  let hasSupporterBadge: Bool

  var hasPaidAccess: Bool {
    hasLifetimeUnlock || hasSupporterBadge
  }

  var badgeTitle: String? {
    if hasSupporterBadge {
      return String(localized: "Supporter", bundle: AppLocalizer.shared.bundle)
    }
    if hasLifetimeUnlock {
      return String(localized: "Lifetime", bundle: AppLocalizer.shared.bundle)
    }
    return nil
  }

  var tierTitle: String {
    badgeTitle ?? String(localized: "Free", bundle: AppLocalizer.shared.bundle)
  }

  func canUse(_ feature: VivyShotPaidFeature) -> Bool {
    switch feature {
    case .captureTransitions,
         .microphone,
         .webcamOverlay,
         .keystrokeOverlay,
         .gifExport,
         .advancedExport,
         .statistics:
      return hasPaidAccess
    }
  }

  static let free = StoreEntitlement(hasLifetimeUnlock: false, hasSupporterBadge: false)

  static func resolve(productIDs: Set<String>) -> StoreEntitlement {
    StoreEntitlement(
      hasLifetimeUnlock: productIDs.contains(VivyShotProducts.lifetime),
      hasSupporterBadge: productIDs.contains(VivyShotProducts.supporter)
    )
  }
}

enum StoreError: LocalizedError {
  case verificationFailed
  case productNotFound

  var errorDescription: String? {
    switch self {
    case .verificationFailed:
      return String(localized: "Purchase verification failed", bundle: AppLocalizer.shared.bundle)
    case .productNotFound:
      return String(localized: "Product not found", bundle: AppLocalizer.shared.bundle)
    }
  }
}
