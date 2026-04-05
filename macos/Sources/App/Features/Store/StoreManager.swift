import Foundation
import StoreKit
import os.log

@MainActor
final class StoreManager: ObservableObject {
  static let shared = StoreManager()

  @Published private(set) var entitlement: StoreEntitlement = .free
  @Published private(set) var products: [Product] = []
  @Published var purchaseState: PurchaseState = .idle
  @Published var restoreState: RestoreState = .idle
  @Published private(set) var lastPurchasedProductID: String?

  private var updateListenerTask: Task<Void, Error>?
  private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.vivyshot", category: "Store")

  var hasLifetimeUnlock: Bool { entitlement.hasLifetimeUnlock }
  var hasSupporterBadge: Bool { entitlement.hasSupporterBadge }
  var hasPaidAccess: Bool { entitlement.hasPaidAccess }
  var badgeTitle: String? { entitlement.badgeTitle }
  var tierTitle: String { entitlement.tierTitle }

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
      purchaseState = .failed(error.localizedDescription)
      logger.error("Purchase failed: \(error.localizedDescription)")
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
      restoreState = .failed(error.localizedDescription)
      logger.error("Restore failed: \(error.localizedDescription)")
    }
  }

  func refreshEntitlements() async {
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
}
