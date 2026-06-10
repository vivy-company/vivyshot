import Foundation

/// Current state of a purchase request.
enum PurchaseState: Equatable {
  case idle
  case purchasing
  case purchased
  case failed(String)
}

/// Current state of a restore request.
enum RestoreState: Equatable {
  case idle
  case restoring
  case restored(hasAccess: Bool)
  case failed(String)
}

/// App Store product identifiers used by the StoreKit feature.
enum StoreProducts {
  static let lifetime = "com.vivyshot.lifetime"
  static let supporter = "com.vivyshot.supporter"

  static let allProductIDs = [lifetime, supporter]
}

/// Resolved local entitlement state from StoreKit product ownership.
struct StoreEntitlement: Equatable {
  let hasLifetimeUnlock: Bool
  let hasSupporterBadge: Bool

  var hasPaidAccess: Bool {
    hasLifetimeUnlock || hasSupporterBadge
  }

  func canUse(_ feature: PaidFeature) -> Bool {
    switch feature {
    case .captureTransitions,
         .microphoneAudioExport,
         .webcamOverlay,
         .keystrokeOverlay,
         .gifExport,
         .hevcExport,
         .sixtyFPSExport,
         .highQualityExport,
         .highBitrateExport,
         .statistics:
      return hasPaidAccess
    }
  }

  static let free = StoreEntitlement(hasLifetimeUnlock: false, hasSupporterBadge: false)
  static let reviewer = StoreEntitlement(hasLifetimeUnlock: true, hasSupporterBadge: true)

  static func resolve(productIDs: Set<String>) -> StoreEntitlement {
    StoreEntitlement(
      hasLifetimeUnlock: productIDs.contains(StoreProducts.lifetime),
      hasSupporterBadge: productIDs.contains(StoreProducts.supporter)
    )
  }
}

/// User-facing store error categories.
enum StoreError: Error {
  case verificationFailed
  case productNotFound
}
