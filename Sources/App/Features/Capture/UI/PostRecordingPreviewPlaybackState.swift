import AVFoundation
import CoreMedia
import Foundation

final class PostRecordingPreviewPlaybackState: ObservableObject {
  @Published var currentSeconds: Double = 0
  @Published var durationSeconds: Double = 0
  @Published var isPlaying = false
  @Published private(set) var trimStartSeconds: Double = 0
  @Published private(set) var trimEndSeconds: Double = 0

  weak var player: AVPlayer?

  var selectedDurationSeconds: Double {
    max(0, activeTrimEndSeconds - activeTrimStartSeconds)
  }

  private var activeTrimStartSeconds: Double {
    max(0, min(durationSeconds, trimStartSeconds))
  }

  private var activeTrimEndSeconds: Double {
    let fallbackEnd = durationSeconds > 0 ? durationSeconds : trimEndSeconds
    let end = trimEndSeconds > trimStartSeconds ? trimEndSeconds : fallbackEnd
    let upperBound = durationSeconds > 0 ? durationSeconds : end
    return max(activeTrimStartSeconds, min(upperBound, end))
  }

  func attach(player: AVPlayer) {
    self.player = player
  }

  func detach(player: AVPlayer?) {
    guard self.player === player else {
      return
    }
    self.player = nil
    isPlaying = false
  }

  func configure(durationSeconds: Double, exportState: PostRecordingExportState) {
    let safeDuration = max(0, durationSeconds)
    self.durationSeconds = safeDuration
    trimStartSeconds = Double(exportState.trimStartMS) / 1000.0
    trimEndSeconds = Double(exportState.trimEndMS) / 1000.0

    if currentSeconds < activeTrimStartSeconds {
      seek(to: activeTrimStartSeconds)
    } else if currentSeconds > activeTrimEndSeconds {
      seek(to: activeTrimEndSeconds)
    }
  }

  func updateFromPlayer(seconds: Double, isPlaying: Bool) {
    let safeSeconds = seconds.isFinite ? max(0, seconds) : 0
    currentSeconds = safeSeconds
    self.isPlaying = isPlaying

    guard isPlaying, safeSeconds >= activeTrimEndSeconds - 0.015 else {
      return
    }
    player?.pause()
    self.isPlaying = false
    seek(to: activeTrimEndSeconds)
  }

  func togglePlayback() {
    guard let player else {
      return
    }
    if isPlaying {
      player.pause()
      isPlaying = false
      return
    }
    if currentSeconds < activeTrimStartSeconds || currentSeconds >= activeTrimEndSeconds - 0.05 {
      seek(to: activeTrimStartSeconds)
    }
    player.play()
    isPlaying = true
  }

  func seek(to seconds: Double) {
    let upper = activeTrimEndSeconds > activeTrimStartSeconds ? activeTrimEndSeconds : durationSeconds
    let clamped = max(activeTrimStartSeconds, min(upper, seconds))
    currentSeconds = clamped
    player?.seek(
      to: CMTime(seconds: clamped, preferredTimescale: 600),
      toleranceBefore: .zero,
      toleranceAfter: .zero
    )
  }

  func skip(by deltaSeconds: Double) {
    seek(to: currentSeconds + deltaSeconds)
  }
}
