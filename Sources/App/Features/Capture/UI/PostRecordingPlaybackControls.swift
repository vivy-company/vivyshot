import SwiftUI

struct PostRecordingPlaybackControls: View {
  @ObservedObject var reviewState: PostRecordingReviewState
  @ObservedObject var playbackState: PostRecordingPreviewPlaybackState
  @State private var isScrubbing = false
  @State private var scrubbedTrimmedSeconds = 0.0

  private var isTrimModeActive: Bool {
    reviewState.editState.isTrimModeActive
  }

  private var selectedDurationSeconds: Double {
    max(0, playbackState.selectedDurationSeconds)
  }

  private var trimmedCurrentSeconds: Double {
    let current = playbackState.currentSeconds - playbackState.trimStartSeconds
    return max(0, min(selectedDurationSeconds, current))
  }

  private var displayedTrimmedSeconds: Double {
    isScrubbing ? scrubbedTrimmedSeconds : trimmedCurrentSeconds
  }

  var body: some View {
    VStack(spacing: isTrimModeActive ? 8 : 0) {
      if isTrimModeActive {
        trimSummary
      }

      HStack(spacing: 12) {
        Button {
          playbackState.skip(by: -5)
        } label: {
          Image(systemName: "gobackward.5")
        }
        .help(String(localized: "Back 5 seconds", bundle: AppLocalizer.shared.bundle))

        Button {
          playbackState.togglePlayback()
        } label: {
          Image(systemName: playbackState.isPlaying ? "pause.fill" : "play.fill")
            .font(.system(size: 16, weight: .semibold))
            .frame(width: 28, height: 28)
        }
        .help(playbackState.isPlaying
          ? String(localized: "Pause", bundle: AppLocalizer.shared.bundle)
          : String(localized: "Play", bundle: AppLocalizer.shared.bundle))

        Button {
          playbackState.skip(by: 5)
        } label: {
          Image(systemName: "goforward.5")
        }
        .help(String(localized: "Forward 5 seconds", bundle: AppLocalizer.shared.bundle))

        Text(Self.formatTime(isTrimModeActive ? playbackState.currentSeconds : displayedTrimmedSeconds))
          .font(.system(size: 12, weight: .medium, design: .monospaced))
          .foregroundStyle(.white.opacity(0.78))
          .frame(width: 46, alignment: .trailing)

        if isTrimModeActive {
          PostRecordingTrimTimeline(
            reviewState: reviewState,
            playbackState: playbackState,
            isTrimModeActive: true
          )
          .frame(height: 42)
          .disabled(playbackState.durationSeconds <= 0)
        } else {
          Slider(
            value: Binding(
              get: { displayedTrimmedSeconds },
              set: { value in
                scrubbedTrimmedSeconds = value
                if !isScrubbing {
                  seekWithinTrimmedClip(to: value)
                }
              }
            ),
            in: 0...max(0.1, selectedDurationSeconds),
            onEditingChanged: { editing in
              isScrubbing = editing
              if editing {
                scrubbedTrimmedSeconds = trimmedCurrentSeconds
              } else {
                seekWithinTrimmedClip(to: scrubbedTrimmedSeconds)
              }
            }
          )
          .disabled(playbackState.durationSeconds <= 0 || selectedDurationSeconds <= 0)
        }

        Text(Self.formatTime(isTrimModeActive ? playbackState.selectedDurationSeconds : selectedDurationSeconds))
          .font(.system(size: 12, weight: .medium, design: .monospaced))
          .foregroundStyle(.white.opacity(0.55))
          .frame(width: 46, alignment: .leading)

        Button {
          reviewState.setTrimModeActive(!isTrimModeActive)
        } label: {
          Image(systemName: "scissors")
            .frame(width: 24, height: 24)
            .foregroundStyle(isTrimModeActive ? Color.accentColor : Color.white.opacity(0.86))
        }
        .help(String(localized: "Trim", bundle: AppLocalizer.shared.bundle))

        if reviewState.hasAudio {
          Button {
            reviewState.toggleOutputAudio()
          } label: {
            Image(systemName: reviewState.editState.isOutputAudioEnabled ? "speaker.wave.2" : "speaker.slash")
              .frame(width: 24, height: 24)
          }
          .help(reviewState.editState.isOutputAudioEnabled
            ? String(localized: "Mute final output", bundle: AppLocalizer.shared.bundle)
            : String(localized: "Include sound in final output", bundle: AppLocalizer.shared.bundle))
        }
      }
    }
    .buttonStyle(.plain)
    .foregroundStyle(.white.opacity(0.86))
    .padding(.horizontal, 16)
    .padding(.vertical, isTrimModeActive ? 12 : 0)
    .frame(minHeight: isTrimModeActive ? 88 : 52)
    .background(Color.black)
  }

  private var trimSummary: some View {
    HStack(spacing: 8) {
      Image(systemName: "scissors")
        .foregroundStyle(Color.accentColor)
      Text(trimRangeText)
        .font(.system(size: 12, weight: .medium, design: .monospaced))
        .foregroundStyle(.white.opacity(0.75))
      Spacer()

      Button(String(localized: "Reset Trim", bundle: AppLocalizer.shared.bundle)) {
        reviewState.resetTrim()
        playbackState.configure(durationSeconds: reviewState.durationSeconds, exportState: reviewState.exportState())
        playbackState.seek(to: 0)
      }
      .buttonStyle(.plain)
      .font(.system(size: 12, weight: .semibold))
      .foregroundStyle(Color.accentColor)

      Button(String(localized: "Done", bundle: AppLocalizer.shared.bundle)) {
        reviewState.setTrimModeActive(false)
        playbackState.seek(to: playbackState.trimStartSeconds)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.small)
    }
  }

  private func seekWithinTrimmedClip(to seconds: Double) {
    let clamped = max(0, min(selectedDurationSeconds, seconds))
    playbackState.seek(to: playbackState.trimStartSeconds + clamped)
  }

  private var trimRangeText: String {
    let state = reviewState.exportState()
    return "\(Self.formatTime(Double(state.trimStartMS) / 1000.0)) - \(Self.formatTime(Double(state.trimEndMS) / 1000.0)) · \(Self.formatTime(state.trimmedDurationSeconds))"
  }

  static func formatTime(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds > 0 else {
      return "00:00"
    }
    let total = Int(seconds.rounded(.down))
    return String(format: "%02d:%02d", total / 60, total % 60)
  }
}

private enum PostRecordingTimelineDragTarget {
  case start
  case end
  case playhead
}

private struct PostRecordingTrimTimeline: View {
  @ObservedObject var reviewState: PostRecordingReviewState
  @ObservedObject var playbackState: PostRecordingPreviewPlaybackState
  let isTrimModeActive: Bool

  @State private var dragTarget: PostRecordingTimelineDragTarget?

  var body: some View {
    GeometryReader { proxy in
      let width = max(1, proxy.size.width)
      let height = proxy.size.height
      let startX = xPosition(forMS: reviewState.editState.trimStartMS, width: width)
      let endX = xPosition(forMS: reviewState.editState.trimEndMS, width: width)
      let playheadX = xPosition(forSeconds: playbackState.currentSeconds, width: width)

      ZStack(alignment: .leading) {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
          .fill(Color.white.opacity(0.16))
          .frame(height: isTrimModeActive ? 26 : 6)
          .frame(maxHeight: .infinity)

        if isTrimModeActive {
          Rectangle()
            .fill(Color.black.opacity(0.48))
            .frame(width: max(0, startX), height: 26)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

          Rectangle()
            .fill(Color.black.opacity(0.48))
            .frame(width: max(0, width - endX), height: 26)
            .offset(x: endX)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.accentColor.opacity(0.24))
            .overlay(
              RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.accentColor.opacity(0.9), lineWidth: 1.5)
            )
            .frame(width: max(2, endX - startX), height: 30)
            .offset(x: startX)

          trimHandle
            .offset(x: max(0, startX - 6))
          trimHandle
            .offset(x: min(width - 12, endX - 6))
        } else {
          RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Color.accentColor.opacity(0.72))
            .frame(width: max(0, min(width, playheadX)), height: 6)
        }

        Rectangle()
          .fill(Color.white)
          .frame(width: 2, height: isTrimModeActive ? 36 : 16)
          .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
          .offset(x: min(width - 1, max(0, playheadX - 1)))
      }
      .frame(width: width, height: height)
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            handleDragChanged(value, width: width, startX: startX, endX: endX)
          }
          .onEnded { _ in
            dragTarget = nil
          }
      )
    }
  }

  private var trimHandle: some View {
    RoundedRectangle(cornerRadius: 3, style: .continuous)
      .fill(Color.white)
      .frame(width: 12, height: 34)
      .shadow(color: .black.opacity(0.34), radius: 3, x: 0, y: 1)
      .overlay(
        RoundedRectangle(cornerRadius: 1, style: .continuous)
          .fill(Color.black.opacity(0.34))
          .frame(width: 2, height: 16)
      )
  }

  private func handleDragChanged(
    _ value: DragGesture.Value,
    width: CGFloat,
    startX: CGFloat,
    endX: CGFloat
  ) {
    let locationX = min(max(0, value.location.x), width)
    let target = dragTarget ?? dragTargetForInitialLocation(locationX, startX: startX, endX: endX)
    dragTarget = target

    let targetMS = UInt32((Double(locationX / width) * Double(reviewState.durationMS)).rounded())
    switch target {
    case .start:
      reviewState.updateTrim(
        startMS: targetMS,
        endMS: reviewState.editState.trimEndMS,
        activeHandle: .start
      )
      playbackState.configure(durationSeconds: reviewState.durationSeconds, exportState: reviewState.exportState())
      playbackState.seek(to: Double(reviewState.editState.trimStartMS) / 1000.0)
    case .end:
      reviewState.updateTrim(
        startMS: reviewState.editState.trimStartMS,
        endMS: targetMS,
        activeHandle: .end
      )
      playbackState.configure(durationSeconds: reviewState.durationSeconds, exportState: reviewState.exportState())
    case .playhead:
      playbackState.seek(to: Double(targetMS) / 1000.0)
    }
  }

  private func dragTargetForInitialLocation(
    _ x: CGFloat,
    startX: CGFloat,
    endX: CGFloat
  ) -> PostRecordingTimelineDragTarget {
    guard isTrimModeActive else {
      return .playhead
    }
    if abs(x - startX) <= 24 {
      return .start
    }
    if abs(x - endX) <= 24 {
      return .end
    }
    return .playhead
  }

  private func xPosition(forMS milliseconds: UInt32, width: CGFloat) -> CGFloat {
    let progress = Double(milliseconds) / Double(max(1, reviewState.durationMS))
    return min(width, max(0, width * CGFloat(progress)))
  }

  private func xPosition(forSeconds seconds: Double, width: CGFloat) -> CGFloat {
    guard reviewState.durationSeconds > 0 else {
      return 0
    }
    let progress = seconds / reviewState.durationSeconds
    return min(width, max(0, width * CGFloat(progress)))
  }
}
