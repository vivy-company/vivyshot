import SwiftUI

func paywallComparisonRows(localizer: AppLocalizer) -> [ComparisonFeature] {
  let paidRowsBeforeExportScale = PaidFeature.paywallComparisonOrder
    .prefix { $0 != .statistics }
    .map { $0.paywallComparisonFeature(localizer: localizer) }
  let paidRowsAfterExportScale = PaidFeature.paywallComparisonOrder
    .drop { $0 != .statistics }
    .map { $0.paywallComparisonFeature(localizer: localizer) }

  return [
    ComparisonFeature(
      icon: "camera.viewfinder",
      title: String(localized: "Screenshots", bundle: localizer.bundle),
      free: .included(accessibilityLabel: String(localized: "Screenshots included on Free", bundle: localizer.bundle)),
      pro: .included(accessibilityLabel: String(localized: "Screenshots included on Paid", bundle: localizer.bundle))
    ),
    ComparisonFeature(
      icon: "pencil.and.outline",
      title: String(localized: "Annotation tools", bundle: localizer.bundle),
      free: .included(accessibilityLabel: String(localized: "Annotation tools included on Free", bundle: localizer.bundle)),
      pro: .included(accessibilityLabel: String(localized: "Annotation tools included on Paid", bundle: localizer.bundle))
    ),
    ComparisonFeature(
      icon: "record.circle",
      title: String(localized: "Screen recording", bundle: localizer.bundle),
      free: .included(accessibilityLabel: String(localized: "Screen recording included on Free", bundle: localizer.bundle)),
      pro: .included(accessibilityLabel: String(localized: "Screen recording included on Paid", bundle: localizer.bundle))
    ),
    ComparisonFeature(
      icon: "speaker.wave.2.fill",
      title: String(localized: "System audio", bundle: localizer.bundle),
      free: .included(accessibilityLabel: String(localized: "System audio included on Free", bundle: localizer.bundle)),
      pro: .included(accessibilityLabel: String(localized: "System audio included on Paid", bundle: localizer.bundle))
    ),
  ] + paidRowsBeforeExportScale + [
    ComparisonFeature(
      icon: "arrow.down.right.and.arrow.up.left",
      title: String(localized: "Export scale", bundle: localizer.bundle),
      free: .text("100/75/50", emphasized: false),
      pro: .text("100/75/50", emphasized: true)
    )
  ] + paidRowsAfterExportScale + [
    ComparisonFeature(
      icon: "lock.shield",
      title: String(localized: "Local-only data", bundle: localizer.bundle),
      free: .included(accessibilityLabel: String(localized: "Local-only data included on Free", bundle: localizer.bundle)),
      pro: .included(accessibilityLabel: String(localized: "Local-only data included on Paid", bundle: localizer.bundle))
    )
  ]
}
