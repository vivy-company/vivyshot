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
