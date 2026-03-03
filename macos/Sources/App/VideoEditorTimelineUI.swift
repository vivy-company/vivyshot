import AppKit
import SwiftUI

// MARK: - TimelineState

@MainActor
final class TimelineState: ObservableObject {
  let session: RustTimelineSession
  let durationMS: UInt32

  @Published var tracks: [TimelineTrackInfo] = []
  @Published var clipsByTrack: [[TimelineClipInfo]] = []
  @Published var playheadMS: UInt32 = 0
  @Published var selectedClipID: UInt32? = nil
  @Published var selectedTrackIndex: Int? = nil
  @Published var zoomLevel: CGFloat = 0.15
  @Published var scrollOffsetMS: CGFloat = 0
  @Published var activeTool: TimelineTool = .select
  @Published var isPlaying: Bool = false

  init(session: RustTimelineSession, durationMS: UInt32) {
    self.session = session
    self.durationMS = durationMS
    refresh()
  }

  func refresh() {
    tracks = session.getTracks()
    clipsByTrack = tracks.indices.map { session.getClips(trackIndex: $0) }
  }

  func msToX(_ ms: UInt32) -> CGFloat {
    return CGFloat(ms) * zoomLevel
  }

  func xToMS(_ x: CGFloat) -> UInt32 {
    return UInt32(max(0, min(x / zoomLevel, CGFloat(durationMS))))
  }

  var totalWidth: CGFloat {
    return CGFloat(durationMS) * zoomLevel
  }

  func addTrack(kind: TimelineTrackKind) {
    _ = session.addTrack(kind: kind)
    refresh()
  }

  func removeTrack(at index: Int) {
    _ = session.removeTrack(at: index)
    if selectedTrackIndex == index { selectedTrackIndex = nil; selectedClipID = nil }
    refresh()
  }

  func toggleTrackVisibility(at index: Int) {
    guard index < tracks.count else { return }
    _ = session.setTrackVisible(at: index, visible: !tracks[index].visible)
    refresh()
  }

  func addClip(trackIndex: Int, startMS: UInt32, endMS: UInt32, kind: TimelineTrackKind) -> UInt32? {
    let clipID = session.addClip(trackIndex: trackIndex, startMS: startMS, endMS: endMS, kind: kind)
    refresh()
    return clipID
  }

  func removeClip(trackIndex: Int, clipID: UInt32) {
    _ = session.removeClip(trackIndex: trackIndex, clipID: clipID)
    if selectedClipID == clipID { selectedClipID = nil }
    refresh()
  }

  func moveClip(trackIndex: Int, clipID: UInt32, newStartMS: UInt32) {
    _ = session.moveClip(trackIndex: trackIndex, clipID: clipID, newStartMS: newStartMS)
    refresh()
  }

  func resizeClip(trackIndex: Int, clipID: UInt32, newStartMS: UInt32, newEndMS: UInt32) {
    _ = session.resizeClip(trackIndex: trackIndex, clipID: clipID, newStartMS: newStartMS, newEndMS: newEndMS)
    refresh()
  }

  func undo() {
    _ = session.undo()
    refresh()
  }

  func redo() {
    _ = session.redo()
    refresh()
  }

  func visibleClips(atTimeMS: UInt32) -> [TimelineClipInfo] {
    return session.getVisibleClips(atTimeMS: atTimeMS)
  }
}

// MARK: - Timeline Colors & Metrics

private enum TimelineColors {
  static let background = Color(nsColor: .controlBackgroundColor)
  static let trackEven = Color(nsColor: .controlBackgroundColor)
  static let trackOdd = Color(nsColor: .separatorColor).opacity(0.05)
  static let headerBackground = Color(nsColor: .windowBackgroundColor)
  static let playhead = Color.red

  static func clipColor(for kind: TimelineTrackKind) -> Color {
    switch kind {
    case .video: return Color(red: 0x4A / 255.0, green: 0x90 / 255.0, blue: 0xD9 / 255.0)
    case .audio: return Color(red: 0x4C / 255.0, green: 0xAF / 255.0, blue: 0x50 / 255.0)
    case .webcam: return Color(red: 0x9C / 255.0, green: 0x27 / 255.0, blue: 0xB0 / 255.0)
    case .text: return Color(red: 0xFF / 255.0, green: 0x98 / 255.0, blue: 0x00 / 255.0)
    case .shape: return Color(red: 0x79 / 255.0, green: 0x79 / 255.0, blue: 0x79 / 255.0)
    case .cursor: return Color(red: 0x00 / 255.0, green: 0xBC / 255.0, blue: 0xD4 / 255.0)
    case .zoom: return Color(red: 0xFF / 255.0, green: 0xEB / 255.0, blue: 0x3B / 255.0)
    }
  }
}

private enum TimelineMetrics {
  static let trackHeight: CGFloat = 44
  static let headerWidth: CGFloat = 100
  static let rulerHeight: CGFloat = 26
  static let playheadWidth: CGFloat = 2
  static let clipCornerRadius: CGFloat = 5
  static let edgeHandle: CGFloat = 8
}

// MARK: - Timeline Editor Views

@MainActor
struct TimelineEditorView: View {
  @ObservedObject var state: TimelineState
  var thumbnailImages: [NSImage]
  var onSeek: (UInt32) -> Void
  var isBusy: Bool
  var onPlayPause: () -> Void = {}
  var onSaveMP4: () -> Void = {}
  var onSaveGIF: () -> Void = {}
  var onDone: () -> Void = {}

  var body: some View {
    VStack(spacing: 0) {
      inlineToolbar

      Divider()

      ScrollView([.horizontal, .vertical], showsIndicators: true) {
        ZStack(alignment: .topLeading) {
          VStack(spacing: 0) {
            TimeRulerView(state: state, onSeek: onSeek)
              .frame(height: TimelineMetrics.rulerHeight)

            Divider()

            ForEach(Array(state.tracks.enumerated()), id: \.offset) { index, track in
              TrackLaneView(
                state: state,
                trackIndex: index,
                track: track,
                clips: index < state.clipsByTrack.count ? state.clipsByTrack[index] : [],
                thumbnailImages: track.kind == .video ? thumbnailImages : [],
                onSeek: onSeek
              )
              if index < state.tracks.count - 1 {
                Divider()
              }
            }
          }
          .frame(width: max(state.totalWidth + TimelineMetrics.headerWidth, 600))

          PlayheadLineView(state: state)
            .offset(x: TimelineMetrics.headerWidth, y: TimelineMetrics.rulerHeight + 1)
        }
      }
      .background(TimelineColors.background)
      .gesture(
        MagnifyGesture()
          .onChanged { value in
            let newZoom = state.zoomLevel * value.magnification
            state.zoomLevel = min(1.0, max(0.02, newZoom))
          }
      )

      selectedTextClipEditor
    }
    .frame(minHeight: 200)
  }

  private var inlineToolbar: some View {
    HStack(spacing: 8) {
      // Left: tool buttons
      HStack(spacing: 2) {
        inlineToolButton(symbol: "arrow.uturn.up", isActive: state.activeTool == .select) {
          state.activeTool = .select
        }
        inlineToolButton(symbol: "scissors", isActive: state.activeTool == .cut) {
          state.activeTool = .cut
        }
        inlineToolButton(symbol: "hand.raised", isActive: state.activeTool == .hand) {
          state.activeTool = .hand
        }
      }

      Divider().frame(height: 18)

      HStack(spacing: 2) {
        inlineToolButton(symbol: "arrow.uturn.backward") { state.undo() }
        inlineToolButton(symbol: "arrow.uturn.forward") { state.redo() }
      }

      Divider().frame(height: 18)

      HStack(spacing: 2) {
        inlineToolButton(symbol: "textformat") { state.addTrack(kind: .text) }
        inlineToolButton(symbol: "rectangle") { state.addTrack(kind: .shape) }
      }

      Spacer()

      // Center: play + timecode
      HStack(spacing: 6) {
        Button(action: onPlayPause) {
          Image(systemName: (state.isPlaying) ? "pause.fill" : "play.fill")
            .font(.system(size: 12))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(isBusy)

        Text(Self.formatTimeCompact(ms: state.playheadMS) + " / " + Self.formatTimeCompact(ms: state.durationMS))
          .font(.system(size: 10, weight: .medium, design: .monospaced))
          .foregroundStyle(.secondary)
      }

      Spacer()

      // Right: zoom + done dropdown
      HStack(spacing: 2) {
        inlineToolButton(symbol: "minus.magnifyingglass") {
          state.zoomLevel = max(0.02, state.zoomLevel * 0.8)
        }
        inlineToolButton(symbol: "plus.magnifyingglass") {
          state.zoomLevel = min(1.0, state.zoomLevel * 1.25)
        }
      }

      Divider().frame(height: 18)

      Menu {
        Button("Save MP4", action: onSaveMP4)
        Button("Save GIF", action: onSaveGIF)
        Divider()
        Button("Close", action: onDone)
      } label: {
        Text("Done")
          .font(.system(size: 11, weight: .medium))
      }
      .menuStyle(.borderlessButton)
      .fixedSize()
      .disabled(isBusy)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(.ultraThinMaterial)
  }

  private func inlineToolButton(symbol: String, isActive: Bool = false, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 11))
        .frame(width: 24, height: 24)
    }
    .buttonStyle(.bordered)
    .tint(isActive ? .accentColor : nil)
    .controlSize(.small)
    .disabled(isBusy)
  }

  @ViewBuilder
  private var selectedTextClipEditor: some View {
    if let clipID = state.selectedClipID,
       let trackIdx = state.selectedTrackIndex,
       trackIdx < state.tracks.count,
       state.tracks[trackIdx].kind == .text,
       let clip = state.clipsByTrack[safe: trackIdx]?.first(where: { $0.id == clipID })
    {
      let currentText = state.session.getClipText(trackIndex: trackIdx, clipID: clipID) ?? ""
      Divider()
      VStack(spacing: 4) {
        HStack(spacing: 8) {
          TextField(
            "Text overlay",
            text: Binding(
              get: { currentText },
              set: { newValue in
                _ = state.session.setClipText(trackIndex: trackIdx, clipID: clipID, text: String(newValue.prefix(80)))
                state.refresh()
              }
            )
          )
          .textFieldStyle(.roundedBorder)
          .disabled(isBusy)

          Text(TimelineEditorView.formatTimeCompact(ms: clip.startMS) + " - " + TimelineEditorView.formatTimeCompact(ms: clip.endMS))
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)

          Button {
            state.removeClip(trackIndex: trackIdx, clipID: clipID)
          } label: {
            Image(systemName: "trash")
              .font(.system(size: 11))
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .disabled(isBusy)
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .background(.ultraThinMaterial)
    }
  }

  static func formatTimeCompact(ms: UInt32) -> String {
    let totalSeconds = Int(ms) / 1000
    let minutes = totalSeconds / 60
    let seconds = totalSeconds % 60
    let frames = (Int(ms) % 1000) / 33
    return String(format: "%02d:%02d:%02d", minutes, seconds, frames)
  }
}

@MainActor
private struct TimeRulerView: View {
  @ObservedObject var state: TimelineState
  var onSeek: (UInt32) -> Void

  var body: some View {
    GeometryReader { geometry in
      Canvas { context, size in
        let headerWidth = TimelineMetrics.headerWidth
        let tickAreaWidth = size.width - headerWidth
        guard tickAreaWidth > 0 else { return }

        let pixelsPerSecond = state.zoomLevel * 1000
        let tickInterval: UInt32
        if pixelsPerSecond > 200 {
          tickInterval = 100
        } else if pixelsPerSecond > 50 {
          tickInterval = 500
        } else if pixelsPerSecond > 20 {
          tickInterval = 1000
        } else if pixelsPerSecond > 5 {
          tickInterval = 5000
        } else {
          tickInterval = 10000
        }

        var ms: UInt32 = 0
        while ms <= state.durationMS {
          let x = headerWidth + state.msToX(ms)
          guard x < size.width else { break }

          let isMajor = ms % (tickInterval * 5) == 0 || ms == 0
          let tickHeight: CGFloat = isMajor ? 12 : 6

          var path = Path()
          path.move(to: CGPoint(x: x, y: size.height))
          path.addLine(to: CGPoint(x: x, y: size.height - tickHeight))
          context.stroke(path, with: .color(.secondary.opacity(isMajor ? 0.6 : 0.25)), lineWidth: 0.5)

          if isMajor {
            let totalSeconds = Int(ms) / 1000
            let label = String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
            let text = Text(label).font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)
            context.draw(text, at: CGPoint(x: x, y: 6))
          }

          ms += tickInterval
        }

        // Playhead triangle
        let playheadX = headerWidth + state.msToX(state.playheadMS)
        var triangle = Path()
        triangle.move(to: CGPoint(x: playheadX - 5, y: 0))
        triangle.addLine(to: CGPoint(x: playheadX + 5, y: 0))
        triangle.addLine(to: CGPoint(x: playheadX, y: 8))
        triangle.closeSubpath()
        context.fill(triangle, with: .color(TimelineColors.playhead))

        // Playhead line through ruler
        var playheadLine = Path()
        playheadLine.move(to: CGPoint(x: playheadX, y: 8))
        playheadLine.addLine(to: CGPoint(x: playheadX, y: size.height))
        context.stroke(playheadLine, with: .color(TimelineColors.playhead), lineWidth: TimelineMetrics.playheadWidth)
      }
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            let ms = state.xToMS(value.location.x - TimelineMetrics.headerWidth)
            state.playheadMS = ms
            onSeek(ms)
          }
      )
    }
  }
}

@MainActor
private struct TrackLaneView: View {
  @ObservedObject var state: TimelineState
  let trackIndex: Int
  let track: TimelineTrackInfo
  let clips: [TimelineClipInfo]
  let thumbnailImages: [NSImage]
  var onSeek: (UInt32) -> Void

  private var trackLabel: String {
    switch track.kind {
    case .video: return "Video"
    case .webcam: return "Webcam"
    case .audio: return "Audio"
    case .text: return "Text"
    case .shape: return "Shape"
    case .cursor: return "Cursor"
    case .zoom: return "Zoom"
    }
  }

  private var trackIcon: String {
    switch track.kind {
    case .video: return "film"
    case .webcam: return "web.camera"
    case .audio: return "waveform"
    case .text: return "textformat"
    case .shape: return "rectangle"
    case .cursor: return "cursorarrow"
    case .zoom: return "magnifyingglass"
    }
  }

  var body: some View {
    HStack(spacing: 0) {
      // Header
      HStack(spacing: 5) {
        Button(action: { state.toggleTrackVisibility(at: trackIndex) }) {
          Image(systemName: track.visible ? "eye.fill" : "eye.slash")
            .font(.system(size: 10))
            .foregroundColor(track.visible ? .primary : .secondary)
        }
        .buttonStyle(.borderless)
        .frame(width: 18)

        Image(systemName: trackIcon)
          .font(.system(size: 10))
          .foregroundColor(TimelineColors.clipColor(for: track.kind))

        Text(trackLabel)
          .font(.system(size: 10, weight: .semibold))
          .foregroundColor(.primary)
          .lineLimit(1)

        Spacer()
      }
      .frame(width: TimelineMetrics.headerWidth)
      .padding(.horizontal, 6)

      Divider()

      // Clip area
      ZStack(alignment: .leading) {
        Rectangle()
          .fill(trackIndex % 2 == 0 ? TimelineColors.trackEven : TimelineColors.trackOdd)

        if track.kind == .video && !thumbnailImages.isEmpty {
          thumbnailStrip
        }

        if track.kind == .audio {
          audioWaveformVisualization
        }

        ForEach(clips, id: \.id) { clip in
          TimelineClipView(state: state, clip: clip, trackIndex: trackIndex)
        }
      }
      .frame(width: state.totalWidth)
      .clipped()
    }
    .frame(height: TimelineMetrics.trackHeight)
    .background(trackIndex % 2 == 0 ? TimelineColors.trackEven : TimelineColors.trackOdd)
  }

  @ViewBuilder
  private var thumbnailStrip: some View {
    if let firstClip = clips.first {
      let clipWidth = state.msToX(firstClip.endMS) - state.msToX(firstClip.startMS)
      HStack(spacing: 0) {
        ForEach(Array(thumbnailImages.enumerated()), id: \.offset) { _, img in
          Image(nsImage: img)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: clipWidth / CGFloat(max(thumbnailImages.count, 1)), height: TimelineMetrics.trackHeight)
            .clipped()
        }
      }
      .offset(x: state.msToX(firstClip.startMS))
      .opacity(0.25)
    }
  }

  private var audioWaveformVisualization: some View {
    Canvas { context, size in
      let barCount = 50
      let barWidth: CGFloat = max(2, size.width / CGFloat(barCount * 2))
      let spacing: CGFloat = barWidth
      let greenTint = TimelineColors.clipColor(for: .audio)

      for i in 0 ..< barCount {
        let x = CGFloat(i) * (barWidth + spacing)
        guard x < size.width else { break }
        let seed = Double(i * 7 + 13)
        let height = size.height * CGFloat(0.15 + 0.6 * abs(sin(seed * 0.37)))
        let y = (size.height - height) / 2
        let rect = CGRect(x: x, y: y, width: barWidth, height: height)
        context.fill(Path(rect), with: .color(greenTint.opacity(0.3)))
      }
    }
  }
}

@MainActor
private struct TimelineClipView: View {
  @ObservedObject var state: TimelineState
  let clip: TimelineClipInfo
  let trackIndex: Int

  @State private var dragOffset: CGFloat = 0
  @State private var isDragging = false
  @State private var leftEdgeDrag: CGFloat = 0
  @State private var rightEdgeDrag: CGFloat = 0

  private var clipColor: Color {
    TimelineColors.clipColor(for: clip.kind)
  }

  private var isSelected: Bool {
    state.selectedClipID == clip.id && state.selectedTrackIndex == trackIndex
  }

  private var clipWidth: CGFloat {
    state.msToX(clip.endMS) - state.msToX(clip.startMS) + leftEdgeDrag + rightEdgeDrag
  }

  private var clipOffset: CGFloat {
    state.msToX(clip.startMS) + dragOffset - leftEdgeDrag
  }

  private var clipHeight: CGFloat {
    TimelineMetrics.trackHeight - 8
  }

  private var fillGradient: LinearGradient {
    let topOpacity: Double = isSelected ? 0.85 : 0.65
    let bottomOpacity: Double = isSelected ? 0.65 : 0.45
    return LinearGradient(
      colors: [clipColor.opacity(topOpacity), clipColor.opacity(bottomOpacity)],
      startPoint: .top,
      endPoint: .bottom
    )
  }

  var body: some View {
    ZStack(alignment: .leading) {
      RoundedRectangle(cornerRadius: TimelineMetrics.clipCornerRadius)
        .fill(fillGradient)
        .overlay(
          RoundedRectangle(cornerRadius: TimelineMetrics.clipCornerRadius)
            .strokeBorder(isSelected ? Color.white.opacity(0.4) : Color.white.opacity(0.1), lineWidth: 1)
        )

      clipLabel
        .font(.system(size: 9, weight: .semibold))
        .foregroundColor(.white.opacity(0.9))
        .lineLimit(1)
        .padding(.leading, 6)

      if isSelected && state.activeTool == .select {
        HStack {
          edgeHandlePill
          Spacer()
          edgeHandlePill
        }
        .padding(.horizontal, 2)
      }

      if isSelected && state.activeTool == .select {
        HStack {
          Rectangle()
            .fill(Color.white.opacity(0.01))
            .frame(width: TimelineMetrics.edgeHandle)
            .onHover { hovering in
              if hovering {
                NSCursor.resizeLeftRight.push()
              } else {
                NSCursor.pop()
              }
            }
            .gesture(leftEdgeGesture)

          Spacer()

          Rectangle()
            .fill(Color.white.opacity(0.01))
            .frame(width: TimelineMetrics.edgeHandle)
            .onHover { hovering in
              if hovering {
                NSCursor.resizeLeftRight.push()
              } else {
                NSCursor.pop()
              }
            }
            .gesture(rightEdgeGesture)
        }
      }
    }
    .frame(width: max(clipWidth, 4), height: clipHeight)
    .offset(x: clipOffset, y: 0)
    .onTapGesture {
      state.selectedClipID = clip.id
      state.selectedTrackIndex = trackIndex
    }
    .gesture(state.activeTool == .select ? moveGesture : nil)
  }

  private var edgeHandlePill: some View {
    RoundedRectangle(cornerRadius: 1.5)
      .fill(Color.white.opacity(0.6))
      .frame(width: 3, height: 16)
  }

  @ViewBuilder
  private var clipLabel: some View {
    switch clip.kind {
    case .text:
      let text = state.session.getClipText(trackIndex: trackIndex, clipID: clip.id) ?? "Text"
      Text(text)
    case .video:
      Text("Video")
    case .webcam:
      Text("Webcam")
    case .audio:
      Text("Audio")
    case .shape:
      Text("Shape")
    case .cursor:
      Text("Cursor")
    case .zoom:
      Text("Zoom")
    }
  }

  private var moveGesture: some Gesture {
    DragGesture()
      .onChanged { value in
        isDragging = true
        dragOffset = value.translation.width
      }
      .onEnded { value in
        isDragging = false
        let deltaMS = Int32(value.translation.width / state.zoomLevel)
        let newStart = UInt32(max(0, Int64(clip.startMS) + Int64(deltaMS)))
        state.moveClip(trackIndex: trackIndex, clipID: clip.id, newStartMS: newStart)
        dragOffset = 0
      }
  }

  private var leftEdgeGesture: some Gesture {
    DragGesture()
      .onChanged { value in
        leftEdgeDrag = -value.translation.width
      }
      .onEnded { value in
        let deltaMS = Int32(value.translation.width / state.zoomLevel)
        let newStart = UInt32(max(0, Int64(clip.startMS) + Int64(deltaMS)))
        state.resizeClip(trackIndex: trackIndex, clipID: clip.id, newStartMS: min(newStart, clip.endMS - 1), newEndMS: clip.endMS)
        leftEdgeDrag = 0
      }
  }

  private var rightEdgeGesture: some Gesture {
    DragGesture()
      .onChanged { value in
        rightEdgeDrag = value.translation.width
      }
      .onEnded { value in
        let deltaMS = Int32(value.translation.width / state.zoomLevel)
        let newEnd = UInt32(max(Int64(clip.startMS) + 1, Int64(clip.endMS) + Int64(deltaMS)))
        state.resizeClip(trackIndex: trackIndex, clipID: clip.id, newStartMS: clip.startMS, newEndMS: newEnd)
        rightEdgeDrag = 0
      }
  }
}

@MainActor
private struct PlayheadLineView: View {
  @ObservedObject var state: TimelineState

  var body: some View {
    Rectangle()
      .fill(TimelineColors.playhead)
      .frame(width: TimelineMetrics.playheadWidth)
      .shadow(color: TimelineColors.playhead.opacity(0.4), radius: 2, x: 0, y: 0)
      .offset(x: state.msToX(state.playheadMS))
      .allowsHitTesting(false)
  }
}

// MARK: - Timeline Preview Overlay

@MainActor
struct TimelinePreviewOverlay: View {
  @ObservedObject var state: TimelineState

  var body: some View {
    GeometryReader { geometry in
      let clips = state.visibleClips(atTimeMS: state.playheadMS)
      ForEach(clips, id: \.id) { clip in
        switch clip.kind {
        case .text:
          let text = state.session.getClipText(trackIndex: clip.trackIndex, clipID: clip.id) ?? ""
          Text(text)
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.6))
            .cornerRadius(4)
            .position(
              x: geometry.size.width * CGFloat(clip.transform.x + clip.transform.width / 2),
              y: geometry.size.height * CGFloat(clip.transform.y + clip.transform.height / 2)
            )

        case .shape:
          RoundedRectangle(cornerRadius: 8)
            .fill(Color.blue.opacity(0.3))
            .frame(
              width: geometry.size.width * CGFloat(clip.transform.width),
              height: geometry.size.height * CGFloat(clip.transform.height)
            )
            .position(
              x: geometry.size.width * CGFloat(clip.transform.x + clip.transform.width / 2),
              y: geometry.size.height * CGFloat(clip.transform.y + clip.transform.height / 2)
            )

        default:
          EmptyView()
        }
      }
    }
  }
}

// MARK: - Collection safe subscript

private extension Collection {
  subscript(safe index: Index) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}

