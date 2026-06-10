import AppKit
import SwiftUI

/// Non-interactive capture hint shown near the selection overlay.
@MainActor
struct CaptureHintGlassCard: View {
  let selectedType: CaptureContentType
  var usesExternalGlassSurface = false

  var body: some View {
    Group {
      if usesExternalGlassSurface {
        panelContent
          .padding(.horizontal, 12)
          .padding(.vertical, 9)
      } else if #available(macOS 26.0, *) {
        GlassEffectContainer(spacing: 0) {
          panelContent
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .glassEffect(.regular.tint(Color.white.opacity(0.08)), in: .rect(cornerRadius: 12, style: .continuous))
        }
      } else {
        panelContent
          .padding(.horizontal, 12)
          .padding(.vertical, 9)
          .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .fill(.ultraThinMaterial)
              .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                  .stroke(Color.primary.opacity(0.12), lineWidth: 1)
              )
          )
      }
    }
    .fixedSize()
    .allowsHitTesting(false)
    .shadow(color: Color.black.opacity(0.26), radius: 12, x: 0, y: 5)
  }

  private var panelContent: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(primaryHintText)
        .font(.system(size: 12.5, weight: .semibold))
        .foregroundStyle(.primary)

      Text("Esc cancel  •  1 screenshot  •  2 video  •  ⇧Tab switch")
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
    }
  }

  private var primaryHintText: String {
    if selectedType == .screenshot {
      return String(localized: "Click a window or drag an area", bundle: AppLocalizer.shared.bundle)
    }
    return String(localized: "Click a window or drag an area for video", bundle: AppLocalizer.shared.bundle)
  }
}


@MainActor
struct CaptureTypeSidebar: View {
  let selectedType: CaptureContentType
  var usesExternalGlassSurface = false
  let onSelectType: (CaptureContentType) -> Void

  var body: some View {
    Group {
      if usesExternalGlassSurface {
        panelContent
          .padding(6)
      } else if #available(macOS 26.0, *) {
        GlassEffectContainer(spacing: 0) {
          panelContent
            .padding(6)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
      } else {
        panelContent
          .padding(6)
          .background(
            Capsule(style: .continuous)
              .fill(.ultraThinMaterial)
              .overlay(
                Capsule(style: .continuous)
                  .stroke(Color.white.opacity(0.1), lineWidth: 1)
              )
          )
      }
    }
    .fixedSize()
    .shadow(color: Color.black.opacity(0.24), radius: 12, x: 0, y: 6)
  }

  private var panelContent: some View {
    ZStack(alignment: .top) {
      selectionRail

      VStack(spacing: 4) {
        ForEach(CaptureContentType.allCases) { type in
          captureButton(type)
        }
      }
    }
    .frame(width: 44, height: captureRailHeight)
  }

  private var captureRailHeight: CGFloat {
    let count = CGFloat(CaptureContentType.allCases.count)
    return max(44, count * 44 + max(0, count - 1) * 4)
  }

  private var selectedTypeIndex: Int {
    CaptureContentType.allCases.firstIndex(of: selectedType) ?? 0
  }

  private var selectionRail: some View {
    RoundedRectangle(cornerRadius: 17, style: .continuous)
      .fill(Color.accentColor.opacity(0.07))
      .overlay(
        RoundedRectangle(cornerRadius: 17, style: .continuous)
          .stroke(Color.accentColor.opacity(0.24), lineWidth: 1)
      )
      .frame(width: 36, height: 36)
      .offset(y: CGFloat(selectedTypeIndex) * 48 + 4)
      .animation(.smooth(duration: 0.20), value: selectedType)
      .allowsHitTesting(false)
  }

  private func captureButton(_ type: CaptureContentType) -> some View {
    let isSelected = type == selectedType

    return Button {
      onSelectType(type)
    }
    label: {
      ZStack(alignment: .bottomTrailing) {
        Image(systemName: type.symbolName)
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(isSelected ? Color.accentColor : Color.primary.opacity(0.82))

        if isSelected {
          Circle()
            .fill(Color.accentColor)
            .frame(width: 5, height: 5)
            .offset(x: -7, y: -7)
        }
      }
      .frame(width: 44, height: 44)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(captureTypeHelp(type))
  }

  private func captureTypeHelp(_ type: CaptureContentType) -> String {
    switch type {
    case .screenshot:
      return "Screenshot (1, ⇧Tab)"
    case .video:
      return "Video (2, ⇧Tab)"
    }
  }
}
