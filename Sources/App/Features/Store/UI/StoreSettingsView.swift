import SwiftUI

@MainActor
struct StoreSettingsView: View {
  @ObservedObject var storeManager: StoreManager
  @ObservedObject var localizer: AppLocalizer
  let presentPaywall: () -> Void

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
            Text(localized("VivyShot Access"))
              .font(.headline)

            Text(storeHeadline)
              .font(.subheadline)
              .foregroundStyle(.secondary)

            if let badgeTitle = storeManager.badgeTitle(localizer: localizer) {
              Text(String(format: localized("%@ is active on this Mac."), badgeTitle))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }

          Spacer(minLength: 0)

          if let badgeTitle = storeManager.badgeTitle(localizer: localizer) {
            StoreBadgeChip(title: badgeTitle, prominence: badgeTitle == "Supporter" ? .supporter : .lifetime)
          } else {
            Button(localized("Purchase License")) {
              presentPaywall()
            }
            .buttonStyle(.borderedProminent)
          }
        }
        .padding(.vertical, 6)
      }

      Section(localized("Access")) {
        LabeledContent(localized("Current Plan")) {
          HStack(spacing: 8) {
            if let badgeTitle = storeManager.badgeTitle(localizer: localizer) {
              StoreBadgeChip(
                title: badgeTitle,
                prominence: badgeTitle == "Supporter" ? .supporter : .lifetime
              )
            } else {
              StoreBadgeChip(title: localized("Free"), prominence: .free)
            }
          }
        }

        LabeledContent(localized("Lifetime Features")) {
          Text(localized(storeManager.hasPaidAccess ? "Available" : "Not unlocked"))
            .foregroundStyle(.secondary)
        }

        LabeledContent(localized("Supporter Badge")) {
          Text(localized(storeManager.hasSupporterBadge ? "Active" : "Not active"))
            .foregroundStyle(.secondary)
        }
      }

      if storeManager.hasLifetimeUnlock && !storeManager.hasSupporterBadge {
        Section(localized("Supporter")) {
          Text(localized("Lifetime is already active. Supporter can still be purchased separately if you want the badge and an extra way to fund VivyShot development."))
            .foregroundStyle(.secondary)

          Button(localized("Purchase Supporter Badge")) {
            presentPaywall()
          }
          .buttonStyle(.bordered)
        }
      }

      Section(localized("Actions")) {
        Button(primaryActionTitle) {
          presentPaywall()
        }

        Button(localized("Restore Purchases")) {
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
      return localized("License Details")
    }
    if storeManager.hasLifetimeUnlock {
      return localized("License Options")
    }
    return localized("Purchase License")
  }

  private func localized(_ value: String.LocalizationValue) -> String {
    localizer.string(value)
  }

  private func localized(_ value: String) -> String {
    localizer.string(value)
  }

  private var storeHeadline: String {
    if storeManager.hasSupporterBadge {
      return localized("Thanks for supporting VivyShot.")
    }
    if storeManager.hasLifetimeUnlock {
      return localized("Lifetime access is unlocked.")
    }
    return localized("Free forever for the core workflow.")
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
