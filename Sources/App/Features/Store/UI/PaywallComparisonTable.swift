import SwiftUI

struct ComparisonFeature: Identifiable {
  let icon: String
  let title: String
  let free: ComparisonValue
  let pro: ComparisonValue

  var id: String { title }
}

enum ComparisonValue {
  case included(accessibilityLabel: String)
  case notIncluded(accessibilityLabel: String)
  case text(String, emphasized: Bool)
}

extension PaidFeature {
  static let paywallComparisonOrder: [PaidFeature] = [
    .microphoneAudioExport,
    .webcamOverlay,
    .keystrokeOverlay,
    .captureTransitions,
    .gifExport,
    .hevcExport,
    .sixtyFPSExport,
    .highQualityExport,
    .highBitrateExport,
    .statistics
  ]

  static var paywallComparisonFeatures: [ComparisonFeature] {
    paywallComparisonOrder.map(\.paywallComparisonFeature)
  }

  var paywallComparisonFeature: ComparisonFeature {
    switch self {
    case .captureTransitions:
      return ComparisonFeature(
        icon: PaidFeature.captureTransitions.symbolName,
        title: PaidFeature.captureTransitions.comparisonTitle,
        free: .text(String(localized: "Preview", bundle: AppLocalizer.shared.bundle), emphasized: false),
        pro: .included(accessibilityLabel: PaidFeature.captureTransitions.includedAccessibilityLabel)
      )
    case .hevcExport:
      return ComparisonFeature(
        icon: PaidFeature.hevcExport.symbolName,
        title: PaidFeature.hevcExport.comparisonTitle,
        free: .text("H.264", emphasized: false),
        pro: .text("H.264 + HEVC", emphasized: true)
      )
    case .sixtyFPSExport:
      return ComparisonFeature(
        icon: PaidFeature.sixtyFPSExport.symbolName,
        title: PaidFeature.sixtyFPSExport.comparisonTitle,
        free: .text("30 fps", emphasized: false),
        pro: .text("30/60 fps", emphasized: true)
      )
    case .highQualityExport:
      return ComparisonFeature(
        icon: PaidFeature.highQualityExport.symbolName,
        title: PaidFeature.highQualityExport.comparisonTitle,
        free: .text(String(localized: "Standard", bundle: AppLocalizer.shared.bundle), emphasized: false),
        pro: .text(String(localized: "High", bundle: AppLocalizer.shared.bundle), emphasized: true)
      )
    case .highBitrateExport:
      return ComparisonFeature(
        icon: PaidFeature.highBitrateExport.symbolName,
        title: PaidFeature.highBitrateExport.comparisonTitle,
        free: .text(String(localized: "Standard", bundle: AppLocalizer.shared.bundle), emphasized: false),
        pro: .text(String(localized: "High bitrate", bundle: AppLocalizer.shared.bundle), emphasized: true)
      )
    case .microphoneAudioExport, .webcamOverlay, .keystrokeOverlay, .gifExport, .statistics:
      return .paidOnly(self)
    }
  }

  var includedAccessibilityLabel: String {
    String(format: String(localized: "%@ included on Paid", bundle: AppLocalizer.shared.bundle), comparisonTitle)
  }

  var notIncludedAccessibilityLabel: String {
    String(format: String(localized: "%@ not included on Free", bundle: AppLocalizer.shared.bundle), comparisonTitle)
  }
}

extension ComparisonFeature {
  static func paidOnly(_ feature: PaidFeature) -> ComparisonFeature {
    ComparisonFeature(
      icon: feature.symbolName,
      title: feature.comparisonTitle,
      free: .notIncluded(accessibilityLabel: feature.notIncludedAccessibilityLabel),
      pro: .included(accessibilityLabel: feature.includedAccessibilityLabel)
    )
  }
}

struct ComparisonTable: View {
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
