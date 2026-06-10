import StoreKit
import SwiftUI

@MainActor
extension PaywallView {
  var successTitle: String {
    storeManager.lastPurchasedProductID == StoreProducts.supporter
      ? String(localized: "You are now a supporter", bundle: AppLocalizer.shared.bundle)
      : String(localized: "Lifetime unlocked", bundle: AppLocalizer.shared.bundle)
  }

  var successSubtitle: String {
    storeManager.lastPurchasedProductID == StoreProducts.supporter
      ? String(localized: "Supporter badge and Lifetime features are active.", bundle: AppLocalizer.shared.bundle)
      : String(localized: "Lifetime features are now active.", bundle: AppLocalizer.shared.bundle)
  }

  var availablePlans: [PlanKind] {
    if storeManager.hasSupporterBadge {
      return []
    }
    return PlanKind.displayOrder.filter { plan in
      product(for: plan) != nil && !isOwned(plan)
    }
  }

  var selectedProduct: Product? {
    guard availablePlans.contains(selectedPlan), !isOwned(selectedPlan) else {
      return nil
    }
    return product(for: selectedPlan)
  }

  var defaultPlan: PlanKind {
    if let firstAvailablePlan = availablePlans.first {
      return firstAvailablePlan
    }
    if storeManager.hasSupporterBadge { return .supporter }
    return .lifetime
  }

  func product(for plan: PlanKind) -> Product? {
    switch plan {
    case .lifetime:
      return storeManager.lifetimeProduct
    case .supporter:
      return storeManager.supporterProduct
    }
  }

  func isOwned(_ plan: PlanKind) -> Bool {
    switch plan {
    case .lifetime:
      return storeManager.hasLifetimeUnlock || storeManager.hasSupporterBadge
    case .supporter:
      return storeManager.hasSupporterBadge
    }
  }

  var isSelectedPlanAlreadyOwned: Bool {
    isOwned(selectedPlan)
  }

  var shouldShowPurchaseButton: Bool {
    !storeManager.hasSupporterBadge
  }

  var purchaseButtonTitle: String {
    guard let product = selectedProduct else {
      return String(localized: "Select a License", bundle: AppLocalizer.shared.bundle)
    }
    if isSelectedPlanAlreadyOwned {
      return String(localized: "Already Owned", bundle: AppLocalizer.shared.bundle)
    }
    if selectedPlan == .supporter && storeManager.hasLifetimeUnlock {
      return String(format: String(localized: "Add Supporter for %@", bundle: AppLocalizer.shared.bundle), product.displayPrice)
    }
    if selectedPlan == .supporter {
      return String(format: String(localized: "Become Supporter for %@", bundle: AppLocalizer.shared.bundle), product.displayPrice)
    }
    return String(format: String(localized: "Buy %@", bundle: AppLocalizer.shared.bundle), product.displayPrice)
  }

  var comparisonRows: [ComparisonFeature] {
    paywallComparisonRows()
  }

  func handlePurchaseStateChange(_ newState: PurchaseState) {
    switch newState {
    case .purchased:
      withAnimation(.easeInOut(duration: 0.3)) {
        showSuccess = true
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
        dismissPaywall()
      }
    case .failed(let message):
      alertInfo = AlertInfo(
        title: String(localized: "Purchase Failed", bundle: AppLocalizer.shared.bundle),
        message: message,
        isRestore: false
      )
    default:
      break
    }
  }

  func handleRestoreStateChange(_ newState: RestoreState) {
    switch newState {
    case .restored(let hasAccess):
      alertInfo = AlertInfo(
        title: String(localized: "Restore Purchases", bundle: AppLocalizer.shared.bundle),
        message: hasAccess
          ? String(localized: "Your purchases have been restored.", bundle: AppLocalizer.shared.bundle)
          : String(localized: "No purchases were found for this Apple ID.", bundle: AppLocalizer.shared.bundle),
        isRestore: true
      )
    case .failed(let message):
      alertInfo = AlertInfo(
        title: String(localized: "Restore Failed", bundle: AppLocalizer.shared.bundle),
        message: message,
        isRestore: true
      )
    default:
      break
    }
  }
}
