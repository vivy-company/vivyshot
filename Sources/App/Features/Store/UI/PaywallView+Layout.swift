import SwiftUI

@MainActor
extension PaywallView {
  var contentStack: some View {
    VStack(alignment: .leading, spacing: 18) {
      if storeManager.hasSupporterBadge {
        PaywallLicenseDetailsSection(localizer: localizer)
      } else {
        comparisonSection
        planSection
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  var comparisonSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      sectionHeader(
        title: localized("Compare plans"),
        subtitle: localized("Try Pro features before buying. Your first Pro export is free.")
      )

      NativeSectionCard(padding: 0) {
        ComparisonTable(rows: comparisonRows, localizer: localizer)
      }
    }
  }

  var planSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      sectionHeader(title: localized("Choose a license"))

      if availablePlans.isEmpty {
        NativeSectionCard {
          HStack(spacing: 10) {
            ProgressView()
            Text(localized("Loading plans..."))
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity, minHeight: 82)
        }
      } else {
        VStack(spacing: 12) {
          ForEach(availablePlans) { plan in
            if let product = product(for: plan) {
              PlanSelectionCard(
                product: product,
                plan: plan,
                localizer: localizer,
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

  var purchaseFooter: some View {
    VStack(spacing: 5) {
      if shouldShowPurchaseButton {
        purchaseButton
      }

      footerSupportRow

      if !storeManager.hasSupporterBadge {
        Text(localized("One-time purchase. No subscription renewal."))
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

  var purchaseButton: some View {
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

          Text(localized("Processing..."))
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

  var footerSupportRow: some View {
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

  var restoreButton: some View {
    Button {
      Task { await storeManager.restorePurchases() }
    } label: {
      ZStack(alignment: .leading) {
        HStack(spacing: 5) {
          restoreIcon(isRestoring: false)
          Text(localized("Restore Purchases"))
        }
        .hidden()

        HStack(spacing: 5) {
          restoreIcon(isRestoring: storeManager.restoreState == .restoring)
          Text(storeManager.restoreState == .restoring
               ? localized("Restoring...")
               : localized("Restore Purchases"))
        }
      }
      .font(.footnote.weight(.semibold))
      .foregroundStyle(.secondary)
    }
    .buttonStyle(.plain)
    .disabled(storeManager.restoreState == .restoring)
    .animation(nil, value: storeManager.restoreState)
  }

  @ViewBuilder
  func restoreIcon(isRestoring: Bool) -> some View {
    ZStack {
      Image(systemName: "arrow.clockwise.circle")
        .imageScale(.small)
        .opacity(isRestoring ? 0 : 1)

      ProgressView()
        .progressViewStyle(.circular)
        .controlSize(.mini)
        .scaleEffect(0.58)
        .opacity(isRestoring ? 1 : 0)
    }
    .frame(width: 12, height: 12)
  }

  var successOverlay: some View {
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

  func sectionHeader(title: String, subtitle: String? = nil) -> some View {
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

  func legalLink(title: String, url: String) -> some View {
    Link(destination: URL(string: url)!) {
      Text(title)
        .underline()
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }
  }

  var sheetWidth: CGFloat {
    520
  }

  var sheetHeight: CGFloat {
    storeManager.hasSupporterBadge ? 360 : 720
  }

  var minimumSheetWidth: CGFloat {
    520
  }

  var minimumSheetHeight: CGFloat {
    storeManager.hasSupporterBadge ? 360 : 560
  }

  var sheetBackground: Color {
    Color(nsColor: .windowBackgroundColor)
  }

  func localized(_ value: String.LocalizationValue) -> String {
    String(localized: value, bundle: localizer.bundle)
  }
}
