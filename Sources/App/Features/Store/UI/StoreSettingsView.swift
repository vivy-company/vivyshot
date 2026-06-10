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
            Text("VivyShot Access")
              .font(.headline)

            Text(storeHeadline)
              .font(.subheadline)
              .foregroundStyle(.secondary)

            if let badgeTitle = storeManager.badgeTitle(localizer: localizer) {
              Text("\(badgeTitle) is active on this Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }

          Spacer(minLength: 0)

          if let badgeTitle = storeManager.badgeTitle(localizer: localizer) {
            StoreBadgeChip(title: badgeTitle, prominence: badgeTitle == "Supporter" ? .supporter : .lifetime)
          } else {
            Button("Purchase License") {
              presentPaywall()
            }
            .buttonStyle(.borderedProminent)
          }
        }
        .padding(.vertical, 6)
      }

      Section("Access") {
        LabeledContent("Current Plan") {
          HStack(spacing: 8) {
            if let badgeTitle = storeManager.badgeTitle(localizer: localizer) {
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
            presentPaywall()
          }
          .buttonStyle(.bordered)
        }
      }

      Section("Actions") {
        Button(primaryActionTitle) {
          presentPaywall()
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
      return String(localized: "License Details", bundle: localizer.bundle)
    }
    if storeManager.hasLifetimeUnlock {
      return String(localized: "License Options", bundle: localizer.bundle)
    }
    return String(localized: "Purchase License", bundle: localizer.bundle)
  }

  private var storeHeadline: String {
    if storeManager.hasSupporterBadge {
      return String(localized: "Thanks for supporting VivyShot.", bundle: localizer.bundle)
    }
    if storeManager.hasLifetimeUnlock {
      return String(localized: "Lifetime access is unlocked.", bundle: localizer.bundle)
    }
    return String(localized: "Free forever for the core workflow.", bundle: localizer.bundle)
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
