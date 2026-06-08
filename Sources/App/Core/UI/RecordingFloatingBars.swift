import AppKit
import SwiftUI

/// Floating control shown during long scrolling screenshot capture.
@MainActor
struct StitchRecordingFloatingBar: View {
  let onStop: () -> Void

  var body: some View {
    Group {
      if #available(macOS 26.0, *) {
        GlassEffectContainer(spacing: 0) {
          barContent
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .glassEffect(.regular.tint(Color.red.opacity(0.08)).interactive(), in: .capsule)
        }
      } else {
        barContent
          .padding(.horizontal, 8)
          .padding(.vertical, 8)
          .background(.ultraThinMaterial, in: Capsule(style: .continuous))
          .overlay(
            Capsule(style: .continuous)
              .stroke(Color.primary.opacity(0.12), lineWidth: 1)
          )
      }
    }
    .fixedSize()
  }

  private var barContent: some View {
    HStack(spacing: 4) {
      Image(systemName: "record.circle.fill")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(Color.red)
        .frame(width: 18, height: 18)

      Text("Scrolling")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.primary)

      Rectangle()
        .fill(Color.primary.opacity(0.16))
        .frame(width: 1, height: 20)

      HoverTooltipIconButton(
        symbol: "stop.circle.fill",
        help: "Stop scrolling capture",
        isSelected: false,
        isDisabled: false,
        size: CGSize(width: 26, height: 24),
        cornerRadius: 7,
        selectedFillOpacity: 0.18,
        selectedStrokeOpacity: 0.34,
        action: onStop
      )
    }
  }
}

/// Floating recording status bar with timer, audio indicators, and stop action.
@MainActor
struct RecordingFloatingBar: View {
  let elapsedSeconds: Int
  let recordSystemAudio: Bool
  let recordMicrophone: Bool
  let onStop: () -> Void

  var body: some View {
    Group {
      if #available(macOS 26.0, *) {
        GlassEffectContainer(spacing: 0) {
          barContent
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .glassEffect(.regular.tint(Color.red.opacity(0.08)).interactive(), in: .capsule)
        }
      } else {
        barContent
          .padding(.horizontal, 10)
          .padding(.vertical, 10)
          .background(.ultraThinMaterial, in: Capsule(style: .continuous))
          .overlay(
            Capsule(style: .continuous)
              .stroke(Color.primary.opacity(0.12), lineWidth: 1)
          )
      }
    }
    .fixedSize()
  }

  private var barContent: some View {
    HStack(spacing: 5) {
      recordingIndicator

      timerChip

      separator

      toolbarPassiveIcon(symbol: "display", help: "Screen capture")
      if recordSystemAudio {
        toolbarPassiveIcon(symbol: "speaker.wave.2.fill", help: "System audio enabled")
      }
      if recordMicrophone {
        toolbarPassiveIcon(symbol: "mic.fill", help: "Microphone enabled")
      }

      separator

      stopButton
    }
  }

  private var recordingIndicator: some View {
    HStack(spacing: 5) {
      Image(systemName: "record.circle.fill")
        .font(.system(size: 14, weight: .semibold))

      Text("REC")
        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
    }
    .foregroundStyle(Color.red)
    .frame(height: 28)
    .padding(.horizontal, 4)
    .help("Recording")
  }

  private var timerChip: some View {
    Text(formattedElapsedTime)
      .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
      .foregroundStyle(.primary)
      .frame(minWidth: elapsedSeconds >= 3600 ? 78 : 58, minHeight: 28)
      .padding(.horizontal, 8)
      .background(
        RoundedRectangle(cornerRadius: 7, style: .continuous)
          .fill(Color.primary.opacity(0.06))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 7, style: .continuous)
          .stroke(Color.primary.opacity(0.12), lineWidth: 1)
      )
  }

  private var separator: some View {
    Rectangle()
      .fill(Color.primary.opacity(0.16))
      .frame(width: 1, height: 22)
  }

  private func toolbarPassiveIcon(
    symbol: String,
    help: String,
    highlighted: Bool = false
  ) -> some View {
    HoverTooltipIconButton(
      symbol: symbol,
      help: help,
      isSelected: true,
      isDisabled: false,
      symbolFontSize: 15,
      size: CGSize(width: 30, height: 28),
      cornerRadius: 7,
      selectedFillOpacity: 0.18,
      selectedStrokeOpacity: 0.34,
      tintOverride: highlighted ? Color.red : nil,
      showsInlineTooltip: false,
      action: {}
    )
  }

  private var stopButton: some View {
    HoverTooltipIconButton(
      symbol: "stop.fill",
      help: "Stop recording",
      isSelected: true,
      isDisabled: false,
      symbolFontSize: 14,
      size: CGSize(width: 30, height: 28),
      cornerRadius: 7,
      selectedFillOpacity: 0.22,
      selectedStrokeOpacity: 0.36,
      tintOverride: Color.red,
      showsInlineTooltip: false,
      action: onStop
    )
    .padding(.leading, 2)
  }

  private var formattedElapsedTime: String {
    let totalSeconds = max(0, elapsedSeconds)
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds / 60) % 60
    let seconds = totalSeconds % 60
    if hours > 0 {
      return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
    return String(format: "%02d:%02d", minutes, seconds)
  }
}
