import AppKit
import AVFoundation
import CoreMedia
import SwiftUI

@MainActor
final class VideoRecordingHUDController: NSWindowController {
  private let recordSystemAudio: Bool
  private let recordMicrophone: Bool
  private let onStop: () -> Void
  private let timerLabel = NSTextField(labelWithString: "● 00:00")
  private var timer: Timer?
  private var startedAt = Date()

  init(
    recordSystemAudio: Bool,
    recordMicrophone: Bool,
    onStop: @escaping () -> Void
  ) {
    self.recordSystemAudio = recordSystemAudio
    self.recordMicrophone = recordMicrophone
    self.onStop = onStop

    let panel = NSPanel(
      contentRect: CGRect(x: 0, y: 0, width: 230, height: 92),
      styleMask: [.nonactivatingPanel, .hudWindow],
      backing: .buffered,
      defer: false
    )
    panel.isReleasedWhenClosed = false
    panel.level = .statusBar
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    panel.hidesOnDeactivate = false
    panel.titleVisibility = .hidden
    panel.titlebarAppearsTransparent = true

    super.init(window: panel)
    configureUI()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  func show(near rect: CGRect) {
    guard let panel = window else {
      return
    }

    let size = panel.frame.size
    let x = rect.midX - size.width * 0.5
    let y = rect.maxY + 12
    panel.setFrame(CGRect(x: x, y: y, width: size.width, height: size.height).integral, display: false)
    panel.orderFrontRegardless()
    startedAt = Date()
    updateTimerLabel()

    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      guard let self else {
        return
      }
      MainActor.assumeIsolated {
        self.updateTimerLabel()
      }
    }
  }

  override func close() {
    timer?.invalidate()
    timer = nil
    super.close()
  }

  private func configureUI() {
    guard let content = window?.contentView else {
      return
    }

    timerLabel.font = .monospacedDigitSystemFont(ofSize: 16, weight: .semibold)
    timerLabel.textColor = .systemRed
    timerLabel.alignment = .left

    let sourceLabel = NSTextField(labelWithString: sourceSummaryText())
    sourceLabel.font = .systemFont(ofSize: 11, weight: .medium)
    sourceLabel.textColor = .secondaryLabelColor

    let stopButton = NSButton(title: "Stop", target: self, action: #selector(stopPressed))
    stopButton.bezelStyle = .rounded
    stopButton.keyEquivalent = "\r"

    let topRow = NSStackView(views: [timerLabel, NSView(), stopButton])
    topRow.orientation = .horizontal
    topRow.alignment = .centerY
    topRow.spacing = 8
    topRow.translatesAutoresizingMaskIntoConstraints = false

    sourceLabel.translatesAutoresizingMaskIntoConstraints = false
    content.addSubview(topRow)
    content.addSubview(sourceLabel)

    NSLayoutConstraint.activate([
      topRow.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
      topRow.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
      topRow.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
      sourceLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
      sourceLabel.topAnchor.constraint(equalTo: topRow.bottomAnchor, constant: 8),
      sourceLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
    ])
  }

  private func sourceSummaryText() -> String {
    var parts: [String] = ["Screen"]
    if recordSystemAudio {
      parts.append("System Audio")
    }
    if recordMicrophone {
      parts.append("Microphone")
    }
    return parts.joined(separator: " + ")
  }

  private func updateTimerLabel() {
    let elapsed = max(0, Int(Date().timeIntervalSince(startedAt)))
    let minutes = elapsed / 60
    let seconds = elapsed % 60
    timerLabel.stringValue = String(format: "● %02d:%02d", minutes, seconds)
  }

  @objc
  private func stopPressed() {
    onStop()
  }
}

// MARK: - Post-Recording Action Dialog

enum PostRecordingAction {
  case saveMP4
  case saveGIF
  case editVideo
}

@MainActor
final class PostRecordingActionPanel: NSWindowController, NSWindowDelegate {
  private let inputURL: URL
  private let onAction: (PostRecordingAction) -> Void
  private var didPickAction = false

  init(inputURL: URL, onAction: @escaping (PostRecordingAction) -> Void) {
    self.inputURL = inputURL
    self.onAction = onAction

    let panel = NSPanel(
      contentRect: CGRect(x: 0, y: 0, width: 360, height: 280),
      styleMask: [.titled, .closable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    panel.level = .floating
    panel.titlebarAppearsTransparent = true
    panel.titleVisibility = .hidden
    panel.isMovableByWindowBackground = true
    panel.isReleasedWhenClosed = false

    super.init(window: panel)
    panel.delegate = self

    let asset = AVAsset(url: inputURL)
    let durationSeconds = max(0, CMTimeGetSeconds(asset.duration))
    let thumbnail = generateThumbnail(asset: asset)

    let actionView = PostRecordingActionView(
      thumbnail: thumbnail,
      durationSeconds: durationSeconds.isFinite ? durationSeconds : 0
    ) { [weak self] action in
      guard let self, !self.didPickAction else { return }
      self.didPickAction = true
      self.window?.close()
      self.onAction(action)
    }
    panel.contentView = NSHostingView(rootView: actionView)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  func present() {
    window?.center()
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func windowWillClose(_ notification: Notification) {
    if !didPickAction {
      didPickAction = true
      onAction(.editVideo)
    }
  }

  private func generateThumbnail(asset: AVAsset) -> NSImage? {
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: 320, height: 320)
    generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)
    generator.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
    guard let cgImage = try? generator.copyCGImage(at: CMTime(seconds: 0.5, preferredTimescale: 600), actualTime: nil) else {
      return nil
    }
    return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
  }
}

private struct PostRecordingActionView: View {
  let thumbnail: NSImage?
  let durationSeconds: Double
  let onAction: (PostRecordingAction) -> Void

  private var formattedDuration: String {
    let minutes = Int(durationSeconds) / 60
    let seconds = Int(durationSeconds) % 60
    let centiseconds = Int((durationSeconds.truncatingRemainder(dividingBy: 1)) * 100)
    return String(format: "%02d:%02d.%02d", minutes, seconds, centiseconds)
  }

  var body: some View {
    VStack(spacing: 16) {
      if let thumbnail {
        Image(nsImage: thumbnail)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(maxWidth: 280, maxHeight: 160)
          .background(Color.black)
          .cornerRadius(8)
      } else {
        RoundedRectangle(cornerRadius: 8)
          .fill(Color.black)
          .frame(width: 280, height: 160)
          .overlay(
            Image(systemName: "film")
              .font(.system(size: 32))
              .foregroundColor(.secondary)
          )
      }

      Text(formattedDuration)
        .font(.system(.body, design: .monospaced))
        .foregroundColor(.secondary)

      VStack(spacing: 8) {
        Button(action: { onAction(.saveMP4) }) {
          Text("Save as MP4")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .keyboardShortcut(.return, modifiers: [])

        HStack(spacing: 8) {
          Button(action: { onAction(.saveGIF) }) {
            Text("Save as GIF")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered)
          .controlSize(.large)

          Button(action: { onAction(.editVideo) }) {
            Text("Edit Video")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered)
          .controlSize(.large)
        }
      }
    }
    .padding(24)
    .background(
      RoundedRectangle(cornerRadius: 16)
        .fill(.ultraThinMaterial)
        .overlay(
          RoundedRectangle(cornerRadius: 16)
            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
    )
  }
}
