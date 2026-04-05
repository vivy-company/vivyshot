import AppKit
import StoreKit
import SwiftUI

@MainActor
struct VivyShotStoreSettingsView: View {
  @ObservedObject private var storeManager = StoreManager.shared
  var body: some View {
    Form {
      Section {
        HStack(spacing: 14) {
          ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
              .fill(headerGradient)
              .frame(width: 48, height: 48)

            Image(systemName: storeManager.hasPaidAccess ? "checkmark.seal.fill" : "sparkles")
              .font(.system(size: 20, weight: .semibold))
              .foregroundStyle(.white)
          }

          VStack(alignment: .leading, spacing: 4) {
            Text("VivyShot Access")
              .font(.headline)

            Text(storeHeadline)
              .font(.subheadline)
              .foregroundStyle(.secondary)

            if let badgeTitle = storeManager.badgeTitle {
              Text("\(badgeTitle) is active on this Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }

          Spacer(minLength: 0)

          if let badgeTitle = storeManager.badgeTitle {
            StoreBadgeChip(title: badgeTitle, prominence: badgeTitle == "Supporter" ? .supporter : .lifetime)
          } else {
            Button("Upgrade") {
              presentPaywallWindow()
            }
            .buttonStyle(.borderedProminent)
          }
        }
        .padding(.vertical, 6)
      }

      Section("Access") {
        LabeledContent("Current Plan") {
          HStack(spacing: 8) {
            if let badgeTitle = storeManager.badgeTitle {
              StoreBadgeChip(
                title: badgeTitle,
                prominence: badgeTitle == "Supporter" ? .supporter : .lifetime
              )
            } else {
              StoreBadgeChip(title: "Free", prominence: .free)
            }
          }
        }

        LabeledContent("Paid Features") {
          Text(storeManager.hasPaidAccess ? "Available" : "Not unlocked")
            .foregroundStyle(.secondary)
        }

        LabeledContent("Supporter Badge") {
          Text(storeManager.hasSupporterBadge ? "Active" : "Not active")
            .foregroundStyle(.secondary)
        }
      }

      if storeManager.hasLifetimeUnlock && !storeManager.hasSupporterBadge {
        Section("Supporter") {
          Text("Lifetime is already active. Supporter can still be purchased separately if you want the badge and an extra way to support the project.")
            .foregroundStyle(.secondary)

          Button("Get Supporter Badge") {
            presentPaywallWindow()
          }
          .buttonStyle(.bordered)
        }
      }

      Section("Actions") {
        Button(primaryActionTitle) {
          presentPaywallWindow()
        }

        Button("Restore Purchases") {
          Task { await storeManager.restorePurchases() }
        }
        .disabled(storeManager.restoreState == .restoring)
      }
    }
    .task {
      await storeManager.loadProducts()
      await storeManager.refreshEntitlements()
    }
    .formStyle(.grouped)
  }

  private var primaryActionTitle: String {
    if storeManager.hasSupporterBadge {
      return "Manage Access"
    }
    if storeManager.hasLifetimeUnlock {
      return "Supporter Options"
    }
    return "View Pricing"
  }

  private var storeHeadline: String {
    if storeManager.hasSupporterBadge {
      return "Thanks for supporting VivyShot."
    }
    if storeManager.hasLifetimeUnlock {
      return "Lifetime access is unlocked."
    }
    return "Free today, ready for paid features later."
  }

  private var headerGradient: LinearGradient {
    if storeManager.hasSupporterBadge {
      return LinearGradient(colors: [Color.orange, Color(red: 0.78, green: 0.42, blue: 0.18)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    if storeManager.hasLifetimeUnlock {
      return LinearGradient(colors: [Color.accentColor, Color(red: 0.18, green: 0.45, blue: 0.96)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    return LinearGradient(colors: [Color.accentColor, Color(red: 0.26, green: 0.54, blue: 0.98)], startPoint: .topLeading, endPoint: .bottomTrailing)
  }
}

@MainActor
struct VivyShotPaywallView: View {
  @ObservedObject private var storeManager = StoreManager.shared

  @State private var selectedProduct: Product?
  @State private var showSuccess = false
  @State private var alertInfo: AlertInfo?

  private struct AlertInfo: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let isRestore: Bool
  }

  private var features: [(icon: String, title: String, description: String, color: Color)] {
    [
      ("wand.and.stars", "Lifetime unlock", "A one-time purchase for paid access as premium features arrive.", .accentColor),
      ("heart.circle", "Supporter tier", "Same access as Lifetime, plus a small supporter badge in the app.", .orange),
      ("arrow.clockwise.circle", "Restorable purchases", "Everything is handled with standard StoreKit restore and entitlement updates.", .green),
      ("shippingbox", "No subscription", "This store setup is intentionally simple: one-time purchases only.", .secondary)
    ]
  }

  var body: some View {
    VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 24) {
        featuresSection
        pricingPane
      }
      .padding(.horizontal, 24)
      .padding(.top, 22)
      .padding(.bottom, 20)
    }
    .frame(width: 720)
    .fixedSize(horizontal: false, vertical: true)
    .background(Color(nsColor: .windowBackgroundColor))
    .task {
      await storeManager.loadProducts()
      await storeManager.refreshEntitlements()
      selectedProduct = defaultSelectedProduct
    }
    .onChange(of: storeManager.purchaseState) { _, newState in
      handlePurchaseStateChange(newState)
    }
    .onChange(of: storeManager.restoreState) { _, newState in
      handleRestoreStateChange(newState)
    }
    .overlay {
      if showSuccess {
        successOverlay
      }
    }
    .alert(alertInfo?.title ?? "", isPresented: .init(
      get: { alertInfo != nil },
      set: { isPresented in
        if !isPresented {
          if alertInfo?.isRestore == true {
            storeManager.restoreState = .idle
          } else {
            storeManager.purchaseState = .idle
          }
          alertInfo = nil
        }
      }
    ), presenting: alertInfo) { info in
      Button("OK") {
        if info.isRestore {
          storeManager.restoreState = .idle
        } else {
          storeManager.purchaseState = .idle
        }
        alertInfo = nil
      }
    } message: { info in
      Text(info.message)
    }
  }

  private var successOverlay: some View {
    ZStack {
      Color.black.opacity(0.6)
        .ignoresSafeArea()

      VStack(spacing: 16) {
        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: 60))
          .foregroundStyle(Color.accentColor)

        Text(successTitle)
          .font(.title2)
          .fontWeight(.semibold)
          .foregroundStyle(.white)

        Text(successSubtitle)
          .font(.subheadline)
          .foregroundStyle(.white.opacity(0.8))
      }
      .padding(32)
      .background(
        RoundedRectangle(cornerRadius: 20, style: .continuous)
          .fill(.ultraThinMaterial)
      )
    }
    .transition(.opacity)
  }

  private var successTitle: String {
    storeManager.lastPurchasedProductID == VivyShotProducts.supporter ? "You are now a supporter" : "Lifetime unlocked"
  }

  private var successSubtitle: String {
    storeManager.lastPurchasedProductID == VivyShotProducts.supporter
      ? "Supporter badge and paid access are active."
      : "Paid access is now active."
  }

  private var featuresSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      ForEach(Array(features.enumerated()), id: \.element.title) { index, feature in
        HStack(spacing: 16) {
          Image(systemName: feature.icon)
            .font(.system(size: 22, weight: .medium))
            .foregroundStyle(feature.color)
            .frame(width: 32, height: 32)

          VStack(alignment: .leading, spacing: 3) {
            Text(feature.title)
              .font(.body)
              .fontWeight(.semibold)
              .fixedSize(horizontal: false, vertical: true)
            Text(feature.description)
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }

          Spacer()
        }
        .padding(.vertical, 4)

        if index < features.count - 1 {
          Divider()
            .overlay(Color.primary.opacity(0.08))
        }
      }
    }
    .padding(.horizontal, 4)
    .padding(.vertical, 6)
  }

  private var planOptionsSection: some View {
    HStack(alignment: .top, spacing: 12) {
      if let lifetime = storeManager.lifetimeProduct {
        PlanOptionRow(
          product: lifetime,
          title: "Lifetime",
          subtitle: "One-time unlock for paid access",
          badge: PlanBadge(title: "FOREVER", style: .forever),
          isSelected: selectedProduct?.id == lifetime.id,
          isOwned: storeManager.hasLifetimeUnlock
        ) {
          selectedProduct = lifetime
        }
        .frame(maxWidth: .infinity)
      }

      if let supporter = storeManager.supporterProduct {
        PlanOptionRow(
          product: supporter,
          title: "Supporter",
          subtitle: "Same unlock, plus supporter badge",
          badge: PlanBadge(title: "SUPPORT", style: .support),
          isSelected: selectedProduct?.id == supporter.id,
          isOwned: storeManager.hasSupporterBadge
        ) {
          selectedProduct = supporter
        }
        .frame(maxWidth: .infinity)
      }
    }
  }

  private var pricingPane: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        Text(pricingPaneTitle)
          .font(.headline)

        Text(pricingPaneSubtitle)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      planOptionsSection

      subscribeButton

      HStack {
        Spacer()
        restoreButton
        Spacer()
      }

      legalFooter
        .padding(.top, 2)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var restoreButton: some View {
    Button {
      Task { await storeManager.restorePurchases() }
    } label: {
      HStack(spacing: 8) {
        if storeManager.restoreState == .restoring {
          ProgressView()
            .progressViewStyle(.circular)
            .scaleEffect(0.8)
        }
        Text(storeManager.restoreState == .restoring ? "Restoring..." : "Restore Purchases")
      }
    }
    .buttonStyle(.bordered)
    .disabled(storeManager.restoreState == .restoring)
  }

  private var legalFooter: some View {
    VStack(spacing: 8) {
      Text("No subscription. Purchases are one-time and restorable.")
        .font(.callout)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)

      HStack(spacing: 10) {
        legalLink(title: "Terms of Use", url: "https://vivyshot.com/terms")
        Text(verbatim: "•")
          .foregroundStyle(.tertiary)
        legalLink(title: "Privacy Policy", url: "https://vivyshot.com/privacy")
        Text(verbatim: "•")
          .foregroundStyle(.tertiary)
        legalLink(title: "Refund Policy", url: "https://vivyshot.com/refund")
      }
      .font(.callout)
      .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .center)
  }

  private var subscribeButtonTitle: String {
    guard let product = selectedProduct else { return "Select a Plan" }
    if storeManager.hasLifetimeUnlock && !storeManager.hasSupporterBadge && product.id == VivyShotProducts.supporter {
      return "Add supporter badge - \(product.displayPrice)"
    }
    if product.id == VivyShotProducts.supporter {
      return "Become a supporter - \(product.displayPrice)"
    }
    return "Get lifetime - \(product.displayPrice)"
  }

  @ViewBuilder
  private var subscribeButton: some View {
    Button {
      if let product = selectedProduct {
        Task { await storeManager.purchase(product) }
      }
    } label: {
      HStack(spacing: 8) {
        if storeManager.purchaseState == .purchasing {
          ProgressView()
            .progressViewStyle(.circular)
            .scaleEffect(0.8)
        }

        Text(storeManager.purchaseState == .purchasing ? "Processing..." : subscribeButtonTitle)
          .fontWeight(.semibold)
      }
      .frame(maxWidth: .infinity)
      .frame(height: 48)
    }
    .buttonStyle(.borderedProminent)
    .clipShape(Capsule())
    .disabled(
      selectedProduct == nil ||
      storeManager.purchaseState == .purchasing ||
      isSelectedProductAlreadyOwned
    )
  }

  private func handlePurchaseStateChange(_ newState: PurchaseState) {
    switch newState {
    case .purchased:
      withAnimation(.easeInOut(duration: 0.25)) {
        showSuccess = true
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
        showSuccess = false
        dismissPaywallWindow()
      }
    case .failed(let message):
      alertInfo = AlertInfo(title: "Purchase Failed", message: message, isRestore: false)
    default:
      break
    }
  }

  private func handleRestoreStateChange(_ newState: RestoreState) {
    switch newState {
    case .restored(let hasAccess):
      alertInfo = AlertInfo(
        title: "Restore Purchases",
        message: hasAccess ? "Your purchases have been restored." : "No purchases were found for this Apple ID.",
        isRestore: true
      )
    case .failed(let message):
      alertInfo = AlertInfo(title: "Restore Failed", message: message, isRestore: true)
    default:
      break
    }
  }

  private func legalLink(title: String, url: String) -> some View {
    Link(destination: URL(string: url)!) {
      Text(title)
        .underline()
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }
  }

  private var defaultSelectedProduct: Product? {
    if storeManager.hasLifetimeUnlock && !storeManager.hasSupporterBadge {
      return storeManager.supporterProduct ?? storeManager.lifetimeProduct
    }
    if storeManager.hasSupporterBadge {
      return storeManager.supporterProduct ?? storeManager.lifetimeProduct
    }
    return storeManager.lifetimeProduct ?? storeManager.supporterProduct
  }

  private var pricingPaneTitle: String {
    if storeManager.hasSupporterBadge {
      return "You already support VivyShot"
    }
    if storeManager.hasLifetimeUnlock {
      return "Add the supporter badge"
    }
    return "Choose your upgrade"
  }

  private var pricingPaneSubtitle: String {
    if storeManager.hasSupporterBadge {
      return "Supporter and paid access are already active on this Mac."
    }
    if storeManager.hasLifetimeUnlock {
      return "Lifetime is already unlocked. Supporter adds the badge and helps support the project."
    }
    return "Both purchases are one-time. Supporter includes the same unlock plus a badge."
  }

  private var isSelectedProductAlreadyOwned: Bool {
    guard let selectedProduct else { return false }
    if selectedProduct.id == VivyShotProducts.lifetime {
      return storeManager.hasLifetimeUnlock
    }
    if selectedProduct.id == VivyShotProducts.supporter {
      return storeManager.hasSupporterBadge
    }
    return false
  }
}

private struct PlanOptionRow: View {
  let product: Product
  let title: String
  let subtitle: String
  let badge: PlanBadge?
  let isSelected: Bool
  let isOwned: Bool
  let onSelect: () -> Void

  var body: some View {
    Button(action: onSelect) {
      VStack(alignment: .leading, spacing: 14) {
        HStack(alignment: .top) {
          Image(systemName: selectionSymbolName)
            .font(.title3)
            .foregroundStyle(selectionColor)

          Spacer(minLength: 10)

          Text(isOwned ? "Owned" : product.displayPrice)
            .font(.headline)
            .fontWeight(.semibold)
            .foregroundStyle(isOwned ? .secondary : .primary)
        }

        VStack(alignment: .leading, spacing: 6) {
          Text(title)
            .font(.title3)
            .fontWeight(.semibold)
            .foregroundStyle(.primary)

          HStack(spacing: 8) {
            if let badge {
              Text(badge.title)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                  Capsule()
                    .fill(badgeBackground(for: badge.style))
                )
            }

            if isOwned {
              Text("ACTIVE")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                  Capsule()
                    .fill(Color.secondary.opacity(0.12))
                )
            }
          }

          Text(subtitle)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .frame(maxWidth: .infinity, minHeight: 154, alignment: .leading)
      .padding(16)
      .background(
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .fill(backgroundFillColor)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .stroke(borderStrokeColor, lineWidth: isSelected ? 2 : 1)
      )
    }
    .buttonStyle(.plain)
    .disabled(isOwned)
  }

  private var selectionSymbolName: String {
    if isOwned {
      return "checkmark.seal.fill"
    }
    return isSelected ? "checkmark.circle.fill" : "circle"
  }

  private var selectionColor: Color {
    if isOwned {
      return .secondary
    }
    return isSelected ? Color.accentColor : .secondary.opacity(0.5)
  }

  private var backgroundFillColor: Color {
    if isOwned {
      return Color.secondary.opacity(0.06)
    }
    return isSelected ? Color.accentColor.opacity(0.10) : Color.clear
  }

  private var borderStrokeColor: Color {
    if isOwned {
      return Color.secondary.opacity(0.18)
    }
    return isSelected ? Color.accentColor : Color(nsColor: .separatorColor).opacity(0.7)
  }
}

private struct PlanBadge {
  let title: String
  let style: PlanBadgeStyle
}

private enum PlanBadgeStyle {
  case forever
  case support
}

private func badgeBackground(for style: PlanBadgeStyle) -> LinearGradient {
  switch style {
  case .forever:
    return LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.75)], startPoint: .leading, endPoint: .trailing)
  case .support:
    return LinearGradient(colors: [Color.orange, Color(red: 0.82, green: 0.4, blue: 0.2)], startPoint: .leading, endPoint: .trailing)
  }
}

struct StoreBadgeChip: View {
  enum Prominence {
    case free
    case lifetime
    case supporter
  }

  let title: String
  let prominence: Prominence

  var body: some View {
    Text(title)
      .font(.caption.weight(.semibold))
      .foregroundStyle(foregroundColor)
      .padding(.horizontal, 10)
      .padding(.vertical, 5)
      .background(backgroundColor, in: Capsule())
      .overlay(
        Capsule()
          .stroke(borderColor, lineWidth: 1)
      )
  }

  private var foregroundColor: Color {
    switch prominence {
    case .free:
      return .secondary
    case .lifetime:
      return .accentColor
    case .supporter:
      return .orange
    }
  }

  private var backgroundColor: Color {
    switch prominence {
    case .free:
      return Color.secondary.opacity(0.1)
    case .lifetime:
      return Color.accentColor.opacity(0.12)
    case .supporter:
      return Color.orange.opacity(0.14)
    }
  }

  private var borderColor: Color {
    switch prominence {
    case .free:
      return Color.secondary.opacity(0.14)
    case .lifetime:
      return Color.accentColor.opacity(0.22)
    case .supporter:
      return Color.orange.opacity(0.24)
    }
  }
}
