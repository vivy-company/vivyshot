import StoreKit
import SwiftUI

enum PlanKind: String, CaseIterable, Identifiable {
  case lifetime
  case supporter

  static let displayOrder: [PlanKind] = [.lifetime, .supporter]

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

struct PlanSelectionCard: View {
  let product: Product
  let plan: PlanKind
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

struct NativeSectionCard<Content: View>: View {
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

var paywallCardFillColor: Color {
  Color(nsColor: .controlBackgroundColor)
}

var paywallCardBorderColor: Color {
  Color.primary.opacity(0.16)
}
