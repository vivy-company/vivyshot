import SwiftUI

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
