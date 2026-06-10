import AppKit
import AVFoundation
import AVKit
import CoreMedia
import SwiftUI

struct PostRecordingWebcamOverlayPreview: NSViewRepresentable {
  let url: URL
  let seconds: Double
  let isPlaying: Bool

  final class Coordinator: @unchecked Sendable {
    var player: AVPlayer?
    var url: URL?
  }

  final class PlayerLayerView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
      super.init(frame: frameRect)
      wantsLayer = true
      playerLayer.videoGravity = .resizeAspectFill
      layer?.addSublayer(playerLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      nil
    }

    override func layout() {
      super.layout()
      playerLayer.frame = bounds
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeNSView(context: Context) -> PlayerLayerView {
    let view = PlayerLayerView()
    configurePlayerIfNeeded(in: view, coordinator: context.coordinator)
    return view
  }

  func updateNSView(_ nsView: PlayerLayerView, context: Context) {
    configurePlayerIfNeeded(in: nsView, coordinator: context.coordinator)
    guard let player = context.coordinator.player else {
      return
    }

    let current = CMTimeGetSeconds(player.currentTime())
    if current.isFinite, abs(current - seconds) > (isPlaying ? 0.35 : 0.05) {
      player.seek(
        to: CMTime(seconds: max(0, seconds), preferredTimescale: 600),
        toleranceBefore: .zero,
        toleranceAfter: .zero
      )
    }

    if isPlaying {
      if player.rate == 0 {
        player.play()
      }
    } else {
      player.pause()
    }
  }

  static func dismantleNSView(_ nsView: PlayerLayerView, coordinator: Coordinator) {
    coordinator.player?.pause()
    nsView.playerLayer.player = nil
    coordinator.player = nil
    coordinator.url = nil
  }

  private func configurePlayerIfNeeded(in view: PlayerLayerView, coordinator: Coordinator) {
    guard coordinator.url != url else {
      return
    }

    let player = AVPlayer(url: url)
    player.isMuted = true
    player.actionAtItemEnd = .pause
    view.playerLayer.player = player
    coordinator.player = player
    coordinator.url = url
  }
}

struct PostRecordingPlayerPreview: NSViewRepresentable {
  let url: URL
  @ObservedObject var playbackState: PostRecordingPreviewPlaybackState
  let isMuted: Bool

  final class Coordinator: @unchecked Sendable {
    var player: AVPlayer?
    var timeObserver: Any?
    weak var playbackState: PostRecordingPreviewPlaybackState?

    func installTimeObserver(on player: AVPlayer) {
      removeTimeObserver()
      timeObserver = player.addPeriodicTimeObserver(
        forInterval: CMTime(seconds: 0.05, preferredTimescale: 600),
        queue: .main
      ) { [weak self, weak player] time in
        guard let self, let playbackState = self.playbackState else {
          return
        }
        let seconds = CMTimeGetSeconds(time)
        playbackState.updateFromPlayer(seconds: seconds, isPlaying: (player?.rate ?? 0) != 0)
      }
    }

    func removeTimeObserver() {
      if let timeObserver, let player {
        player.removeTimeObserver(timeObserver)
      }
      timeObserver = nil
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeNSView(context: Context) -> AVPlayerView {
    let view = AVPlayerView()
    view.controlsStyle = .none
    view.videoGravity = .resizeAspect
    view.showsFullScreenToggleButton = false
    context.coordinator.playbackState = playbackState

    let player = AVPlayer(url: url)
    player.actionAtItemEnd = .pause
    player.isMuted = isMuted
    view.player = player
    context.coordinator.player = player
    playbackState.attach(player: player)
    context.coordinator.installTimeObserver(on: player)
    return view
  }

  func updateNSView(_ nsView: AVPlayerView, context: Context) {
    context.coordinator.playbackState = playbackState
    guard let currentURL = (nsView.player?.currentItem?.asset as? AVURLAsset)?.url else {
      let player = AVPlayer(url: url)
      player.actionAtItemEnd = .pause
      player.isMuted = isMuted
      nsView.player = player
      context.coordinator.player = player
      playbackState.attach(player: player)
      context.coordinator.installTimeObserver(on: player)
      return
    }

    guard currentURL != url else {
      nsView.player?.isMuted = isMuted
      return
    }

    nsView.player?.pause()
    let player = AVPlayer(url: url)
    player.actionAtItemEnd = .pause
    player.isMuted = isMuted
    nsView.player = player
    context.coordinator.player = player
    playbackState.attach(player: player)
    context.coordinator.installTimeObserver(on: player)
  }

  static func dismantleNSView(_ nsView: AVPlayerView, coordinator: Coordinator) {
    nsView.player?.pause()
    coordinator.playbackState?.detach(player: coordinator.player)
    coordinator.removeTimeObserver()
    nsView.player = nil
    coordinator.player = nil
  }
}
