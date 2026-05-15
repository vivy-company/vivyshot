import Foundation
import StoreKit
import os.log

@MainActor
final class StoreManager: ObservableObject {
  static let shared = StoreManager()
  static let reviewModeCode = "VIVYSHOT-REVIEW-2026"

  @Published private(set) var entitlement: StoreEntitlement = .free
  @Published private(set) var products: [Product] = []
  @Published var purchaseState: PurchaseState = .idle
  @Published var restoreState: RestoreState = .idle
  @Published private(set) var lastPurchasedProductID: String?
  @Published private(set) var isReviewModeEnabled = false
  @Published private(set) var reviewModeExpiresAt: Date?

  private var updateListenerTask: Task<Void, Error>?
  private var reviewModeExpiryTask: Task<Void, Never>?
  private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.vivyshot", category: "Store")
  private let reviewModeDuration: TimeInterval = 60 * 60 * 2

  var hasLifetimeUnlock: Bool { entitlement.hasLifetimeUnlock }
  var hasSupporterBadge: Bool { entitlement.hasSupporterBadge }
  var hasPaidAccess: Bool { entitlement.hasPaidAccess }
  var badgeTitle: String? { entitlement.badgeTitle }
  var tierTitle: String { entitlement.tierTitle }

  func canUse(_ feature: VivyShotPaidFeature) -> Bool {
    entitlement.canUse(feature)
  }

  var lifetimeProduct: Product? {
    products.first { $0.id == VivyShotProducts.lifetime }
  }

  var supporterProduct: Product? {
    products.first { $0.id == VivyShotProducts.supporter }
  }

  private init() {
    updateListenerTask = listenForTransactions()
    Task {
      await loadProducts()
      await refreshEntitlements()
    }
  }

  deinit {
    updateListenerTask?.cancel()
    reviewModeExpiryTask?.cancel()
  }

  func loadProducts() async {
    do {
      let loadedProducts = try await Product.products(for: VivyShotProducts.allProductIDs)
      products = loadedProducts.sorted { lhs, rhs in
        VivyShotProducts.allProductIDs.firstIndex(of: lhs.id) ?? .max <
          VivyShotProducts.allProductIDs.firstIndex(of: rhs.id) ?? .max
      }
      logger.info("Loaded \(self.products.count) store products")
    } catch {
      logger.error("Failed to load products: \(error.localizedDescription)")
    }
  }

  func purchase(_ product: Product) async {
    guard !isProductAlreadyActive(product.id) else {
      purchaseState = .failed(String(localized: "Already Owned", bundle: AppLocalizer.shared.bundle))
      return
    }

    purchaseState = .purchasing
    lastPurchasedProductID = nil
    logger.info("Purchasing \(product.id)")

    do {
      let result = try await product.purchase()
      switch result {
      case .success(let verification):
        let transaction = try checkVerified(verification)
        await transaction.finish()
        await refreshEntitlements()
        lastPurchasedProductID = product.id
        purchaseState = .purchased
        logger.info("Purchase successful: \(product.id)")

      case .userCancelled:
        purchaseState = .idle
        logger.info("Purchase cancelled by user")

      case .pending:
        purchaseState = .idle
        logger.info("Purchase pending")

      @unknown default:
        purchaseState = .idle
      }
    } catch {
      let message = purchaseFailureMessage(for: error)
      purchaseState = .failed(message)
      logger.error("Purchase failed: \(message)")
    }
  }

  func purchaseProduct(withID productID: String) async {
    if products.isEmpty {
      await loadProducts()
    }
    guard let product = products.first(where: { $0.id == productID }) else {
      purchaseState = .failed(StoreError.productNotFound.localizedDescription)
      return
    }
    await purchase(product)
  }

  func restorePurchases() async {
    restoreState = .restoring
    logger.info("Restoring purchases")

    do {
      try await AppStore.sync()
      await refreshEntitlements()
      restoreState = .restored(hasAccess: hasPaidAccess)
      logger.info("Restore completed")
    } catch {
      let message = restoreFailureMessage(for: error)
      restoreState = .failed(message)
      logger.error("Restore failed: \(message)")
    }
  }

  func refreshEntitlements() async {
    refreshReviewModeState()
    if isReviewModeEnabled {
      entitlement = .reviewer
      logger.info("Entitlements refreshed: reviewMode=true")
      return
    }

    var activeProductIDs = Set<String>()
    for await result in Transaction.currentEntitlements {
      guard case .verified(let transaction) = result else {
        continue
      }
      if VivyShotProducts.allProductIDs.contains(transaction.productID) {
        activeProductIDs.insert(transaction.productID)
      }
    }

    let resolvedEntitlement = StoreEntitlement.resolve(productIDs: activeProductIDs)
    entitlement = resolvedEntitlement
    logger.info(
      "Entitlements refreshed: paid=\(resolvedEntitlement.hasPaidAccess), lifetime=\(resolvedEntitlement.hasLifetimeUnlock), supporter=\(resolvedEntitlement.hasSupporterBadge)"
    )
  }

  func resetTransientState() {
    purchaseState = .idle
    restoreState = .idle
  }

  @discardableResult
  func enableReviewMode(code: String) -> Bool {
    let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmedCode.caseInsensitiveCompare(Self.reviewModeCode) == .orderedSame else {
      logger.warning("Review mode activation failed")
      return false
    }

    setReviewModeEnabled(true)
    return true
  }

  func setReviewModeEnabled(_ enabled: Bool) {
    if enabled {
      isReviewModeEnabled = true
      reviewModeExpiresAt = Date().addingTimeInterval(reviewModeDuration)
      entitlement = .reviewer
      scheduleReviewModeExpiry()
      logger.info("Review mode enabled")
      return
    }

    guard isReviewModeEnabled || reviewModeExpiresAt != nil else { return }
    isReviewModeEnabled = false
    reviewModeExpiresAt = nil
    reviewModeExpiryTask?.cancel()
    reviewModeExpiryTask = nil
    logger.info("Review mode disabled")

    Task { await refreshEntitlements() }
  }

  private func listenForTransactions() -> Task<Void, Error> {
    Task.detached { [weak self] in
      for await result in Transaction.updates {
        guard case .verified(let transaction) = result else {
          continue
        }
        await self?.refreshEntitlements()
        await transaction.finish()
      }
    }
  }

  private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
    switch result {
    case .verified(let safe):
      return safe
    case .unverified:
      throw StoreError.verificationFailed
    }
  }

  private func isProductAlreadyActive(_ productID: String) -> Bool {
    switch productID {
    case VivyShotProducts.lifetime:
      return hasLifetimeUnlock || hasSupporterBadge
    case VivyShotProducts.supporter:
      return hasSupporterBadge
    default:
      return false
    }
  }

  private func scheduleReviewModeExpiry() {
    reviewModeExpiryTask?.cancel()
    guard let reviewModeExpiresAt else { return }

    let delay = max(0, reviewModeExpiresAt.timeIntervalSinceNow)
    reviewModeExpiryTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
      await MainActor.run {
        self?.refreshReviewModeState()
      }
    }
  }

  private func refreshReviewModeState() {
    guard isReviewModeEnabled else { return }
    if let reviewModeExpiresAt, Date() >= reviewModeExpiresAt {
      setReviewModeEnabled(false)
    }
  }

  private func purchaseFailureMessage(for error: Error) -> String {
    let message = error.localizedDescription
    let normalized = message.lowercased()

    if normalized.contains("sandbox"),
       normalized.contains("permission"),
       normalized.contains("in-app purchase")
    {
      return "This Sandbox Apple Account cannot make purchases right now. Sign in with a Sandbox tester that is allowed to make in-app purchases in App Store Connect."
    }

    return message
  }

  private func restoreFailureMessage(for error: Error) -> String {
    let message = error.localizedDescription
    let normalized = message.lowercased()

    if normalized.contains("sandbox"),
       normalized.contains("permission"),
       normalized.contains("in-app purchase")
    {
      return "This Sandbox Apple Account cannot restore purchases right now. Sign in with a Sandbox tester that is allowed to make in-app purchases in App Store Connect."
    }

    return message
  }
}
