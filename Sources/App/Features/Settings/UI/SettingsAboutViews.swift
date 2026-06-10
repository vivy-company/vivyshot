import SwiftUI

struct AboutLinkRow: View {
  let title: String
  var subtitle: String?
  var systemImage: String?
  var assetImage: String?
  let url: URL

  var body: some View {
    Link(destination: url) {
      HStack(spacing: 14) {
        icon
          .frame(width: 28, height: 28)

        VStack(alignment: .leading, spacing: 2) {
          Text(title)
          if let subtitle {
            Text(subtitle)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  @ViewBuilder
  private var icon: some View {
    if let assetImage {
      Image(assetImage)
        .resizable()
        .interpolation(.high)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    } else if let systemImage {
      Image(systemName: systemImage)
        .font(.system(size: 20, weight: .regular))
    }
  }
}
