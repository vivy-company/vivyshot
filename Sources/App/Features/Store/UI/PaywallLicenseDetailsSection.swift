import SwiftUI

struct PaywallLicenseDetailsSection: View {
  let localizer: AppLocalizer

  var body: some View {
    NativeSectionCard {
      VStack(alignment: .leading, spacing: 14) {
        HStack(alignment: .top, spacing: 12) {
          Image(systemName: "heart.circle.fill")
            .font(.system(size: 28, weight: .semibold))
            .foregroundStyle(.orange)
            .frame(width: 36, height: 36)

          VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
              Text(PlanKind.supporter.title(localizer: localizer))
                .font(.headline)
                .fontWeight(.semibold)

              StoreBadgeChip(title: PlanKind.supporter.title(localizer: localizer), prominence: .supporter)
            }

            Text(String(localized: "Supporter badge and Lifetime features are active.", bundle: localizer.bundle))
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }

          Spacer(minLength: 0)
        }

        Divider()

        VStack(alignment: .leading, spacing: 8) {
          Text(String(localized: "Included paid features", bundle: localizer.bundle))
            .font(.subheadline.weight(.semibold))

          LazyVGrid(columns: licenseFeatureColumns, alignment: .leading, spacing: 7) {
            ForEach(PaidFeature.licenseFeatures, id: \.self) { feature in
              LicenseFeatureItem(feature: feature, localizer: localizer)
            }
          }
        }

        Divider()

        LicenseDetailRow(
          icon: "creditcard",
          title: String(localized: "Billing", bundle: localizer.bundle),
          detail: String(localized: "One-time purchase. No subscription renewal.", bundle: localizer.bundle)
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
}

private struct LicenseFeatureItem: View {
  let feature: PaidFeature
  let localizer: AppLocalizer

  var body: some View {
    HStack(spacing: 7) {
      Image(systemName: icon)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .frame(width: 16)

      Text(feature.title(localizer: localizer))
        .font(.caption)
        .foregroundStyle(.primary)
        .lineLimit(1)
        .minimumScaleFactor(0.82)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var icon: String {
    feature.symbolName
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
