import StoreKit
import SwiftUI

@MainActor
extension PaywallView {
  var successTitle: String {
    storeManager.lastPurchasedProductID == StoreProducts.supporter
      ? localized("You are now a supporter")
      : localized("Lifetime unlocked")
  }

  var successSubtitle: String {
    storeManager.lastPurchasedProductID == StoreProducts.supporter
      ? localized("Supporter badge and Lifetime features are active.")
      : localized("Lifetime features are now active.")
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
      return localized("Select a License")
    }
    if isSelectedPlanAlreadyOwned {
      return localized("Already Owned")
    }
    if selectedPlan == .supporter && storeManager.hasLifetimeUnlock {
      return String(format: localized("Add Supporter for %@"), product.displayPrice)
    }
    if selectedPlan == .supporter {
      return String(format: localized("Become Supporter for %@"), product.displayPrice)
    }
    return String(format: localized("Buy %@"), product.displayPrice)
  }

  var comparisonRows: [ComparisonFeature] {
    paywallComparisonRows(localizer: localizer)
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
        title: localized("Purchase Failed"),
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
        title: localized("Restore Purchases"),
        message: hasAccess
          ? localized("Your purchases have been restored.")
          : localized("No purchases were found for this Apple ID."),
        isRestore: true
      )
    case .failed(let message):
      alertInfo = AlertInfo(
        title: localized("Restore Failed"),
        message: message,
        isRestore: true
      )
    default:
      break
    }
  }
}
