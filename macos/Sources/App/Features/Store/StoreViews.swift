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
            Button("Purchase License") {
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

        LabeledContent("Lifetime Features") {
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
          Text("Lifetime is already active. Supporter can still be purchased separately if you want the badge and an extra way to fund VivyShot development.")
            .foregroundStyle(.secondary)

          Button("Purchase Supporter Badge") {
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
      return String(localized: "License Details", bundle: AppLocalizer.shared.bundle)
    }
    if storeManager.hasLifetimeUnlock {
      return String(localized: "License Options", bundle: AppLocalizer.shared.bundle)
    }
    return String(localized: "Purchase License", bundle: AppLocalizer.shared.bundle)
  }

  private var storeHeadline: String {
    if storeManager.hasSupporterBadge {
      return String(localized: "Thanks for supporting VivyShot.", bundle: AppLocalizer.shared.bundle)
    }
    if storeManager.hasLifetimeUnlock {
      return String(localized: "Lifetime access is unlocked.", bundle: AppLocalizer.shared.bundle)
    }
    return String(localized: "Free forever for the core workflow.", bundle: AppLocalizer.shared.bundle)
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

  @State private var selectedPlan: VivyShotPlanKind = .lifetime
  @State private var showSuccess = false
  @State private var alertInfo: AlertInfo?

  private struct AlertInfo: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let isRestore: Bool
  }

  var body: some View {
    VStack(spacing: 0) {
      ScrollView {
        contentStack
          .padding(.horizontal, 22)
          .padding(.top, 18)
          .padding(.bottom, 18)
      }
      .scrollIndicators(.automatic)

      purchaseFooter
    }
    .frame(width: sheetWidth, height: sheetHeight)
    .background(sheetBackground)
    .task {
      await storeManager.loadProducts()
      await storeManager.refreshEntitlements()
      selectedPlan = defaultPlan
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
      Button(LocalizedStringKey("OK")) {
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

  private var contentStack: some View {
    VStack(alignment: .leading, spacing: 18) {
      if storeManager.hasSupporterBadge {
        licenseDetailsSection
      } else {
        comparisonSection
        planSection
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var comparisonSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      sectionHeader(
        title: String(localized: "Compare plans", bundle: AppLocalizer.shared.bundle),
        subtitle: String(localized: "Try Pro features before buying. Your first Pro export is free.", bundle: AppLocalizer.shared.bundle)
      )

      NativeSectionCard(padding: 0) {
        ComparisonTable(rows: comparisonRows)
      }
    }
  }

  private var planSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      sectionHeader(title: String(localized: "Choose a license", bundle: AppLocalizer.shared.bundle))

      if availablePlans.isEmpty {
        NativeSectionCard {
          HStack(spacing: 10) {
            ProgressView()
            Text("Loading plans...")
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity, minHeight: 82)
        }
      } else {
        VStack(spacing: 12) {
          ForEach(availablePlans) { plan in
            if let product = product(for: plan) {
              VivyShotPlanSelectionCard(
                product: product,
                plan: plan,
                isSelected: selectedPlan == plan,
                isOwned: isOwned(plan)
              ) {
                selectedPlan = plan
              }
            }
          }
        }
      }
    }
  }

  private var licenseDetailsSection: some View {
    NativeSectionCard {
      VStack(alignment: .leading, spacing: 14) {
        HStack(alignment: .top, spacing: 12) {
          Image(systemName: "heart.circle.fill")
            .font(.system(size: 28, weight: .semibold))
            .foregroundStyle(.orange)
            .frame(width: 36, height: 36)

          VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
              Text(VivyShotPlanKind.supporter.title)
                .font(.headline)
                .fontWeight(.semibold)

              StoreBadgeChip(title: VivyShotPlanKind.supporter.title, prominence: .supporter)
            }

            Text(String(localized: "Supporter badge and Lifetime features are active.", bundle: AppLocalizer.shared.bundle))
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }

          Spacer(minLength: 0)
        }

        Divider()

        VStack(alignment: .leading, spacing: 8) {
          Text("Included paid features")
            .font(.subheadline.weight(.semibold))

          LazyVGrid(columns: licenseFeatureColumns, alignment: .leading, spacing: 7) {
            ForEach(VivyShotPaidFeature.allCases, id: \.self) { feature in
              LicenseFeatureItem(feature: feature)
            }
          }
        }

        Divider()

        LicenseDetailRow(
          icon: "creditcard",
          title: String(localized: "Billing", bundle: AppLocalizer.shared.bundle),
          detail: String(localized: "One-time purchase. No subscription renewal.", bundle: AppLocalizer.shared.bundle)
        )
      }
    }
  }

  private var licenseFeatureColumns: [GridItem] {
    [
      GridItem(.flexible(), spacing: 10, alignment: .leading),
      GridItem(.flexible(), spacing: 10, alignment: .leading)
    ]
  }

  private struct LicenseFeatureItem: View {
    let feature: VivyShotPaidFeature

    var body: some View {
      HStack(spacing: 7) {
        Image(systemName: icon)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .frame(width: 16)

        Text(feature.title)
          .font(.caption)
          .foregroundStyle(.primary)
          .lineLimit(1)
          .minimumScaleFactor(0.82)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var icon: String {
      switch feature {
      case .captureTransitions:
        return "sparkles"
      case .microphone:
        return "mic.fill"
      case .webcamOverlay:
        return "video.fill"
      case .keystrokeOverlay:
        return "keyboard"
      case .gifExport:
        return "photo.stack"
      case .advancedExport:
        return "slider.horizontal.3"
      case .statistics:
        return "chart.bar.xaxis"
      }
    }
  }

  private struct LicenseDetailRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: icon)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.secondary)
          .frame(width: 18, height: 18)

        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.subheadline.weight(.semibold))

          Text(detail)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        Spacer(minLength: 0)
      }
    }
  }

  private var purchaseFooter: some View {
    VStack(spacing: 5) {
      if shouldShowPurchaseButton {
        purchaseButton
      }

      footerSupportRow

      if !storeManager.hasSupporterBadge {
        Text("One-time purchase. No subscription renewal.")
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }
    }
    .padding(.horizontal, 20)
    .padding(.top, 8)
    .padding(.bottom, 4)
    .overlay(alignment: .top) {
      Divider()
        .opacity(0.55)
    }
    .background(sheetBackground)
  }

  private var purchaseButton: some View {
    Button {
      if let product = selectedProduct {
        Task { await storeManager.purchase(product) }
      }
    } label: {
      ZStack {
        Text(purchaseButtonTitle)
          .fontWeight(.semibold)
          .opacity(storeManager.purchaseState == .purchasing ? 0 : 1)

        HStack(spacing: 8) {
          ProgressView()
            .progressViewStyle(.circular)
            .controlSize(.small)
            .tint(.white)

          Text("Processing...")
            .fontWeight(.semibold)
        }
        .opacity(storeManager.purchaseState == .purchasing ? 1 : 0)
      }
      .frame(maxWidth: .infinity)
      .frame(height: 24)
    }
    .buttonStyle(.borderedProminent)
    .controlSize(.large)
    .disabled(selectedProduct == nil || isSelectedPlanAlreadyOwned)
    .allowsHitTesting(storeManager.purchaseState != .purchasing)
  }

  private var footerSupportRow: some View {
    HStack(spacing: 6) {
      restoreButton

      Text(verbatim: "•")
        .foregroundStyle(.tertiary)

      legalLink(title: "Terms", url: "https://vivyshot.com/terms")

      Text(verbatim: "•")
        .foregroundStyle(.tertiary)

      legalLink(title: "Privacy", url: "https://vivyshot.com/privacy")

      Text(verbatim: "•")
        .foregroundStyle(.tertiary)

      legalLink(title: "Refund", url: "https://vivyshot.com/refund")
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .lineLimit(1)
    .minimumScaleFactor(0.75)
  }

  private var restoreButton: some View {
    Button {
      Task { await storeManager.restorePurchases() }
    } label: {
      HStack(spacing: 8) {
        if storeManager.restoreState == .restoring {
          ProgressView()
            .progressViewStyle(.circular)
            .scaleEffect(0.85)
        } else {
          Image(systemName: "arrow.clockwise.circle")
            .imageScale(.small)
        }
        Text(storeManager.restoreState == .restoring
             ? String(localized: "Restoring...", bundle: AppLocalizer.shared.bundle)
             : String(localized: "Restore Purchases", bundle: AppLocalizer.shared.bundle))
      }
      .font(.footnote.weight(.semibold))
      .foregroundStyle(.secondary)
    }
    .buttonStyle(.plain)
    .disabled(storeManager.restoreState == .restoring)
  }

  private var successOverlay: some View {
    ZStack {
      Color.black.opacity(0.45)
        .ignoresSafeArea()

      VStack(spacing: 16) {
        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: 56))
          .foregroundStyle(.green)

        Text(successTitle)
          .font(.title3)
          .fontWeight(.semibold)

        Text(successSubtitle)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      .padding(28)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
      .padding(24)
    }
    .transition(.opacity)
  }

  private var successTitle: String {
    storeManager.lastPurchasedProductID == VivyShotProducts.supporter
      ? String(localized: "You are now a supporter", bundle: AppLocalizer.shared.bundle)
      : String(localized: "Lifetime unlocked", bundle: AppLocalizer.shared.bundle)
  }

  private var successSubtitle: String {
    storeManager.lastPurchasedProductID == VivyShotProducts.supporter
      ? String(localized: "Supporter badge and Lifetime features are active.", bundle: AppLocalizer.shared.bundle)
      : String(localized: "Lifetime features are now active.", bundle: AppLocalizer.shared.bundle)
  }

  private var availablePlans: [VivyShotPlanKind] {
    if storeManager.hasSupporterBadge {
      return []
    }
    return VivyShotPlanKind.displayOrder.filter { plan in
      product(for: plan) != nil && !isOwned(plan)
    }
  }

  private var selectedProduct: Product? {
    guard availablePlans.contains(selectedPlan), !isOwned(selectedPlan) else {
      return nil
    }
    return product(for: selectedPlan)
  }

  private var defaultPlan: VivyShotPlanKind {
    if let firstAvailablePlan = availablePlans.first {
      return firstAvailablePlan
    }
    if storeManager.hasSupporterBadge { return .supporter }
    return .lifetime
  }

  private func product(for plan: VivyShotPlanKind) -> Product? {
    switch plan {
    case .lifetime:
      return storeManager.lifetimeProduct
    case .supporter:
      return storeManager.supporterProduct
    }
  }

  private func isOwned(_ plan: VivyShotPlanKind) -> Bool {
    switch plan {
    case .lifetime:
      return storeManager.hasLifetimeUnlock || storeManager.hasSupporterBadge
    case .supporter:
      return storeManager.hasSupporterBadge
    }
  }

  private var isSelectedPlanAlreadyOwned: Bool {
    isOwned(selectedPlan)
  }

  private var shouldShowPurchaseButton: Bool {
    !storeManager.hasSupporterBadge
  }

  private var purchaseButtonTitle: String {
    guard let product = selectedProduct else { return String(localized: "Select a License", bundle: AppLocalizer.shared.bundle) }
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

  private var comparisonRows: [ComparisonFeature] {
    [
      ComparisonFeature(
        icon: "camera.viewfinder",
        title: String(localized: "Screenshots", bundle: AppLocalizer.shared.bundle),
        free: .included(accessibilityLabel: String(localized: "Screenshots included on Free", bundle: AppLocalizer.shared.bundle)),
        pro: .included(accessibilityLabel: String(localized: "Screenshots included on Paid", bundle: AppLocalizer.shared.bundle))
      ),
      ComparisonFeature(
        icon: "pencil.and.outline",
        title: String(localized: "Annotation tools", bundle: AppLocalizer.shared.bundle),
        free: .included(accessibilityLabel: String(localized: "Annotation tools included on Free", bundle: AppLocalizer.shared.bundle)),
        pro: .included(accessibilityLabel: String(localized: "Annotation tools included on Paid", bundle: AppLocalizer.shared.bundle))
      ),
      ComparisonFeature(
        icon: "record.circle",
        title: String(localized: "Screen recording", bundle: AppLocalizer.shared.bundle),
        free: .included(accessibilityLabel: String(localized: "Screen recording included on Free", bundle: AppLocalizer.shared.bundle)),
        pro: .included(accessibilityLabel: String(localized: "Screen recording included on Paid", bundle: AppLocalizer.shared.bundle))
      ),
      ComparisonFeature(
        icon: "speaker.wave.2.fill",
        title: String(localized: "System audio", bundle: AppLocalizer.shared.bundle),
        free: .included(accessibilityLabel: String(localized: "System audio included on Free", bundle: AppLocalizer.shared.bundle)),
        pro: .included(accessibilityLabel: String(localized: "System audio included on Paid", bundle: AppLocalizer.shared.bundle))
      ),
      ComparisonFeature(
        icon: "mic.fill",
        title: String(localized: "Microphone audio export", bundle: AppLocalizer.shared.bundle),
        free: .notIncluded(accessibilityLabel: String(localized: "Microphone audio export not included on Free", bundle: AppLocalizer.shared.bundle)),
        pro: .included(accessibilityLabel: String(localized: "Microphone audio export included on Paid", bundle: AppLocalizer.shared.bundle))
      ),
      ComparisonFeature(
        icon: "video.fill",
        title: String(localized: "Webcam overlay export", bundle: AppLocalizer.shared.bundle),
        free: .notIncluded(accessibilityLabel: String(localized: "Webcam overlay export not included on Free", bundle: AppLocalizer.shared.bundle)),
        pro: .included(accessibilityLabel: String(localized: "Webcam overlay export included on Paid", bundle: AppLocalizer.shared.bundle))
      ),
      ComparisonFeature(
        icon: "keyboard",
        title: String(localized: "Keystroke overlay export", bundle: AppLocalizer.shared.bundle),
        free: .notIncluded(accessibilityLabel: String(localized: "Keystroke overlay export not included on Free", bundle: AppLocalizer.shared.bundle)),
        pro: .included(accessibilityLabel: String(localized: "Keystroke overlay export included on Paid", bundle: AppLocalizer.shared.bundle))
      ),
      ComparisonFeature(
        icon: "sparkles",
        title: String(localized: "Capture transitions", bundle: AppLocalizer.shared.bundle),
        free: .text(String(localized: "Preview", bundle: AppLocalizer.shared.bundle), emphasized: false),
        pro: .included(accessibilityLabel: String(localized: "Capture transitions included on Paid", bundle: AppLocalizer.shared.bundle))
      ),
      ComparisonFeature(
        icon: "photo.stack",
        title: String(localized: "GIF export", bundle: AppLocalizer.shared.bundle),
        free: .notIncluded(accessibilityLabel: String(localized: "GIF export not included on Free", bundle: AppLocalizer.shared.bundle)),
        pro: .included(accessibilityLabel: String(localized: "GIF export included on Paid", bundle: AppLocalizer.shared.bundle))
      ),
      ComparisonFeature(
        icon: "film",
        title: String(localized: "Video codec", bundle: AppLocalizer.shared.bundle),
        free: .text("H.264", emphasized: false),
        pro: .text("H.264 + HEVC", emphasized: true)
      ),
      ComparisonFeature(
        icon: "gauge.with.dots.needle.bottom.50percent",
        title: String(localized: "Frame rate", bundle: AppLocalizer.shared.bundle),
        free: .text("30 fps", emphasized: false),
        pro: .text("30/60 fps", emphasized: true)
      ),
      ComparisonFeature(
        icon: "slider.horizontal.3",
        title: String(localized: "Export quality", bundle: AppLocalizer.shared.bundle),
        free: .text(String(localized: "Standard", bundle: AppLocalizer.shared.bundle), emphasized: false),
        pro: .text(String(localized: "High bitrate", bundle: AppLocalizer.shared.bundle), emphasized: true)
      ),
      ComparisonFeature(
        icon: "arrow.down.right.and.arrow.up.left",
        title: String(localized: "Export scale", bundle: AppLocalizer.shared.bundle),
        free: .text("100/75/50", emphasized: false),
        pro: .text("100/75/50", emphasized: true)
      ),
      ComparisonFeature(
        icon: "chart.bar.xaxis",
        title: String(localized: "Statistics", bundle: AppLocalizer.shared.bundle),
        free: .notIncluded(accessibilityLabel: String(localized: "Statistics not included on Free", bundle: AppLocalizer.shared.bundle)),
        pro: .included(accessibilityLabel: String(localized: "Statistics included on Paid", bundle: AppLocalizer.shared.bundle))
      ),
      ComparisonFeature(
        icon: "lock.shield",
        title: String(localized: "Local-only data", bundle: AppLocalizer.shared.bundle),
        free: .included(accessibilityLabel: String(localized: "Local-only data included on Free", bundle: AppLocalizer.shared.bundle)),
        pro: .included(accessibilityLabel: String(localized: "Local-only data included on Paid", bundle: AppLocalizer.shared.bundle))
      )
    ]
  }

  private func handlePurchaseStateChange(_ newState: PurchaseState) {
    switch newState {
    case .purchased:
      withAnimation(.easeInOut(duration: 0.3)) {
        showSuccess = true
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
        dismissPaywallWindow()
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

  private func handleRestoreStateChange(_ newState: RestoreState) {
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

  private func sectionHeader(title: String, subtitle: String? = nil) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title)
        .font(.headline)
      if let subtitle {
        Text(subtitle)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
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

  private var sheetWidth: CGFloat {
    520
  }

  private var sheetHeight: CGFloat {
    storeManager.hasSupporterBadge ? 360 : 720
  }

  private var sheetBackground: Color {
    Color(nsColor: .windowBackgroundColor)
  }
}

private enum VivyShotPlanKind: String, CaseIterable, Identifiable {
  case lifetime
  case supporter

  static let displayOrder: [VivyShotPlanKind] = [.lifetime, .supporter]

  var id: String { rawValue }

  var title: String {
    switch self {
    case .lifetime:
      return String(localized: "Lifetime", bundle: AppLocalizer.shared.bundle)
    case .supporter:
      return String(localized: "Supporter", bundle: AppLocalizer.shared.bundle)
    }
  }

  var detail: String {
    switch self {
    case .lifetime:
      return String(localized: "Unlock capture effects, overlays, GIF, statistics, HEVC, 60 fps, and high-bitrate exports.", bundle: AppLocalizer.shared.bundle)
    case .supporter:
      return String(localized: "Everything in Lifetime, plus a supporter badge and extra support for independent development.", bundle: AppLocalizer.shared.bundle)
    }
  }

  var badge: String? {
    switch self {
    case .lifetime:
      return nil
    case .supporter:
      return String(localized: "Supporter", bundle: AppLocalizer.shared.bundle)
    }
  }
}

private struct VivyShotPlanSelectionCard: View {
  let product: Product
  let plan: VivyShotPlanKind
  let isSelected: Bool
  let isOwned: Bool
  let onSelect: () -> Void

  var body: some View {
    Button(action: onSelect) {
      HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 3) {
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(plan.title)
              .font(.headline)
              .fontWeight(.semibold)

            if let badge = plan.badge {
              Text(badge)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.quaternary, in: Capsule())
            }
          }

          Text(priceLine)
            .font(.body)
            .foregroundStyle(.primary)

          Text(plan.detail)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        Spacer()

        Image(systemName: selectionSymbolName)
          .font(.title3)
          .symbolRenderingMode(.hierarchical)
          .foregroundStyle(selectionColor)
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(cardFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .stroke(isSelected ? Color.accentColor : cardStroke, lineWidth: isSelected ? 3 : 0.5)
      }
    }
    .buttonStyle(.plain)
  }

  private var selectionSymbolName: String {
    if isOwned {
      return "checkmark.seal.fill"
    }
    return isSelected ? "checkmark.circle.fill" : "circle"
  }

  private var selectionColor: Color {
    if isOwned {
      return Color.accentColor
    }
    return isSelected ? Color.accentColor : .secondary.opacity(0.5)
  }

  private var priceLine: String {
    if isOwned {
      return String(localized: "Owned", bundle: AppLocalizer.shared.bundle)
    }
    return String(format: String(localized: "%@ one time", bundle: AppLocalizer.shared.bundle), product.displayPrice)
  }

  private var cardFill: Color {
    paywallCardFillColor
  }

  private var cardStroke: Color {
    paywallCardBorderColor
  }
}

private struct ComparisonFeature: Identifiable {
  let icon: String
  let title: String
  let free: ComparisonValue
  let pro: ComparisonValue

  var id: String { title }
}

private enum ComparisonValue {
  case included(accessibilityLabel: String)
  case notIncluded(accessibilityLabel: String)
  case text(String, emphasized: Bool)
}

private struct ComparisonTable: View {
  let rows: [ComparisonFeature]

  var body: some View {
    VStack(spacing: 0) {
      ComparisonTableRow(isHeader: true) {
        ComparisonHeaderCell(title: String(localized: "Feature", bundle: AppLocalizer.shared.bundle), alignment: .leading)
      } free: {
        ComparisonHeaderCell(title: String(localized: "Free", bundle: AppLocalizer.shared.bundle), alignment: .center)
      } pro: {
        ComparisonHeaderCell(title: String(localized: "Paid", bundle: AppLocalizer.shared.bundle), alignment: .center)
      }

      separator

      ForEach(rows) { row in
        ComparisonTableRow {
          ComparisonFeatureCell(feature: row)
        } free: {
          ComparisonValueCell(value: row.free)
        } pro: {
          ComparisonValueCell(value: row.pro)
        }

        if row.id != rows.last?.id {
          separator
        }
      }
    }
    .overlay {
      GeometryReader { proxy in
        Path { path in
          let featureBoundary = proxy.size.width - (ComparisonTableLayout.valueColumnWidth * 2)
          let proBoundary = proxy.size.width - ComparisonTableLayout.valueColumnWidth

          path.move(to: CGPoint(x: featureBoundary, y: 0))
          path.addLine(to: CGPoint(x: featureBoundary, y: proxy.size.height))
          path.move(to: CGPoint(x: proBoundary, y: 0))
          path.addLine(to: CGPoint(x: proBoundary, y: proxy.size.height))
        }
        .stroke(paywallTableGridColor, lineWidth: 0.5)
      }
      .allowsHitTesting(false)
    }
  }

  private var separator: some View {
    Rectangle()
      .fill(paywallTableGridColor)
      .frame(height: 0.5)
  }
}

private struct ComparisonTableRow<Feature: View, Free: View, Pro: View>: View {
  var isHeader = false
  @ViewBuilder let feature: Feature
  @ViewBuilder let free: Free
  @ViewBuilder let pro: Pro

  var body: some View {
    HStack(spacing: 0) {
      feature
        .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, verticalPadding)

      free
        .frame(width: ComparisonTableLayout.valueColumnWidth, alignment: .center)
        .frame(minHeight: rowHeight, alignment: .center)
        .padding(.vertical, verticalPadding)

      pro
        .frame(width: ComparisonTableLayout.valueColumnWidth, alignment: .center)
        .frame(minHeight: rowHeight, alignment: .center)
        .padding(.vertical, verticalPadding)
    }
  }

  private var rowHeight: CGFloat {
    isHeader ? 20 : 20
  }

  private var verticalPadding: CGFloat {
    isHeader ? 6 : 4
  }
}

private enum ComparisonTableLayout {
  static let valueColumnWidth: CGFloat = 96
}

private struct ComparisonFeatureCell: View {
  let feature: ComparisonFeature

  var body: some View {
    HStack(spacing: 7) {
      Image(systemName: feature.icon)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .frame(width: 15)

      Text(feature.title)
        .font(.caption)
        .fontWeight(.medium)
        .foregroundStyle(.primary)
        .lineLimit(1)
        .minimumScaleFactor(0.82)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

private struct ComparisonHeaderCell: View {
  let title: String
  let alignment: Alignment

  var body: some View {
    Text(title)
      .font(.caption)
      .fontWeight(.semibold)
      .foregroundStyle(.secondary)
      .textCase(.uppercase)
      .frame(maxWidth: .infinity, alignment: alignment)
  }
}

private struct ComparisonValueCell: View {
  let value: ComparisonValue

  var body: some View {
    Group {
      switch value {
      case .included(let accessibilityLabel):
        Image(systemName: "checkmark")
          .font(.caption.weight(.bold))
          .foregroundStyle(.tint)
          .accessibilityLabel(accessibilityLabel)

      case .notIncluded(let accessibilityLabel):
        Text(verbatim: "-")
          .font(.caption)
          .fontWeight(.semibold)
          .foregroundStyle(.tertiary)
          .accessibilityLabel(accessibilityLabel)

      case .text(let text, let emphasized):
        Text(text)
          .font(.caption2)
          .fontWeight(emphasized ? .semibold : .regular)
          .foregroundStyle(emphasized ? .primary : .secondary)
          .lineLimit(1)
          .minimumScaleFactor(0.75)
      }
    }
    .frame(maxWidth: .infinity, alignment: .center)
  }
}

private var paywallTableGridColor: Color {
  Color.primary.opacity(0.13)
}

private var paywallCardFillColor: Color {
  Color(nsColor: .controlBackgroundColor)
}

private var paywallCardBorderColor: Color {
  Color.primary.opacity(0.16)
}

private struct NativeSectionCard<Content: View>: View {
  var padding: CGFloat = 14
  @ViewBuilder let content: Content

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

    content
      .padding(padding)
      .background(
        shape.fill(cardFill)
      )
      .clipShape(shape)
      .overlay(
        shape.stroke(cardStroke, lineWidth: 0.5)
      )
  }

  private var cardFill: Color {
    paywallCardFillColor
  }

  private var cardStroke: Color {
    paywallCardBorderColor
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
