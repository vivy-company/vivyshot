import CoreGraphics
import Foundation

/// In-memory timeline model for a finished recording and its editable overlay state.
final class RecordingProject {
  private let recordingInfo: RecordingInfo
  private var keyEvents: [KeyEvent] = []
  private var clickEvents: [ClickEvent] = []
  private var mouseClickHighlightStyle: MouseClickHighlightStyle?
  private var webcamOverlay = WebcamOverlayState()
  private var keystrokeOverlay = KeystrokeOverlayState()
  /// How long the most recent captured key label remains visible on the timeline.
  private static let keyLabelVisibleWindowMS: UInt32 = 1_350
  /// Rects with coordinates under this value are treated as normalized overlay frames.
  private static let normalizedFrameUpperBound: CGFloat = 1.5

  init?(recordingInfo: RecordingInfo) {
    guard recordingInfo.durationMS > 0, recordingInfo.width > 0, recordingInfo.height > 0 else {
      return nil
    }
    self.recordingInfo = recordingInfo
  }

  func addKeyEvent(timestampMS: UInt32, token: String) -> Bool {
    let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return false
    }
    keyEvents.append(KeyEvent(timestampMS: timestampMS, token: trimmed))
    keyEvents.sort { $0.timestampMS < $1.timestampMS }
    return true
  }

  var hasMouseClickOverlays: Bool {
    mouseClickHighlightStyle != nil && !clickEvents.isEmpty
  }

  func setMouseClickOverlay(style: MouseClickHighlightStyle?) -> Bool {
    mouseClickHighlightStyle = style
    return true
  }

  func addClickEvent(timestampMS: UInt32, normalizedX: CGFloat, normalizedY: CGFloat, button: UInt32) -> Bool {
    guard normalizedX.isFinite, normalizedY.isFinite else {
      return false
    }
    let x = min(max(0, normalizedX), 1)
    let y = min(max(0, normalizedY), 1)
    clickEvents.append(ClickEvent(timestampMS: timestampMS, normalizedX: x, normalizedY: y, button: button))
    clickEvents.sort { $0.timestampMS < $1.timestampMS }
    return true
  }

  func setWebcamOverlay(
    enabled: Bool,
    shape: WebcamShape,
    aspectRatio: WebcamAspectRatio,
    assetID: UInt32 = 1
  ) -> Bool {
    webcamOverlay.enabled = enabled
    webcamOverlay.shape = shape.rawValue
    webcamOverlay.aspectRatio = aspectRatio.rawValue
    webcamOverlay.assetID = assetID
    return true
  }

  func pushWebcamPlacement(timestampMS: UInt32, frame: CGRect) -> Bool {
    guard frame.isFiniteAndNonEmpty else {
      return false
    }
    webcamOverlay.placements.append(OverlayPlacement(timestampMS: timestampMS, frame: frame))
    webcamOverlay.placements.sort { $0.timestampMS < $1.timestampMS }
    return true
  }

  func setKeystrokeOverlay(
    enabled: Bool,
    style: KeystrokeStyle,
    size: KeystrokeSize
  ) -> Bool {
    keystrokeOverlay.enabled = enabled
    keystrokeOverlay.style = style.rawValue
    keystrokeOverlay.size = size.rawValue
    return true
  }

  func pushKeystrokePlacement(timestampMS: UInt32, frame: CGRect) -> Bool {
    guard frame.isFiniteAndNonEmpty else {
      return false
    }
    keystrokeOverlay.placements.append(OverlayPlacement(timestampMS: timestampMS, frame: frame))
    keystrokeOverlay.placements.sort { $0.timestampMS < $1.timestampMS }
    return true
  }

  func renderPlan(
    timeSeconds: Double,
    renderSize: CGSize,
    target _: RenderTarget
  ) -> RenderPlan? {
    guard renderSize.width.isFinite, renderSize.height.isFinite, renderSize.width > 0, renderSize.height > 0 else {
      return nil
    }
    let timeMS = Self.milliseconds(fromSeconds: timeSeconds)
    var items: [RenderItem] = []

    if webcamOverlay.enabled, recordingInfo.hasWebcamAsset {
      let rect = absoluteRect(
        for: webcamOverlay.frame(at: timeMS) ?? defaultWebcamFrame(),
        renderSize: renderSize
      )
      items.append(
        RenderItem(
          kind: .webcam,
          rect: rect,
          opacity: 1,
          styleFlags: RenderItem.styleFlags(
            primary: UInt32(webcamOverlay.shape),
            secondary: UInt32(webcamOverlay.aspectRatio)
          ),
          text: "",
          assetID: webcamOverlay.assetID
        )
      )
    }

    if keystrokeOverlay.enabled, let token = visibleKeyToken(at: timeMS) {
      let fallback = Self.keyOverlayFrame(text: token, renderSize: renderSize)
      let rect = absoluteRect(
        for: keystrokeOverlay.frame(at: timeMS) ?? fallback,
        renderSize: renderSize
      )
      items.append(
        RenderItem(
          kind: .keystroke,
          rect: rect,
          opacity: 1,
          styleFlags: RenderItem.styleFlags(
            primary: UInt32(keystrokeOverlay.style),
            secondary: UInt32(keystrokeOverlay.size)
          ),
          text: token,
          assetID: 0
        )
      )
    }

    if let mouseClickHighlightStyle {
      let clickDurationMS = mouseClickHighlightStyle.clickVisibleWindowMS
      for clickEvent in visibleClickEvents(at: timeMS, durationMS: clickDurationMS) {
        let elapsed = timeMS.saturatingSubtract(clickEvent.timestampMS)
        let progress = min(1, CGFloat(elapsed) / CGFloat(clickDurationMS))
        let center = CGPoint(
          x: clickEvent.normalizedX * renderSize.width,
          y: clickEvent.normalizedY * renderSize.height
        )
        let base = min(renderSize.width, renderSize.height)
        let diameter = mouseClickHighlightStyle.clickDiameter(base: base, progress: progress)
        let rect = CGRect(
          x: center.x - diameter * 0.5,
          y: center.y - diameter * 0.5,
          width: diameter,
          height: diameter
        ).integral
        items.append(
          RenderItem(
            kind: .mouseClick,
            rect: rect,
            opacity: mouseClickHighlightStyle.clickOpacity(progress: progress),
            styleFlags: RenderItem.styleFlags(
              primary: UInt32(mouseClickHighlightStyle.rawValue),
              secondary: clickEvent.button
            ),
            text: "",
            assetID: 0
          )
        )
      }
    }

    return RenderPlan(items: items)
  }

  func exportPlan() -> ExportPlan? {
    let context = ExportContext(
      sourceHasAudio: recordingInfo.hasAudio,
      sourceHasWebcamAsset: recordingInfo.hasWebcamAsset,
      audioTrackVisible: recordingInfo.hasAudio,
      webcamTrackVisible: webcamOverlay.enabled,
      textOverlayCount: keystrokeOverlay.enabled ? keyEvents.count : 0,
      clickOverlaysVisible: hasMouseClickOverlays
    )
    return ExportPlanner.exportPlan(
      trimStartMS: 0,
      trimEndMS: Int(recordingInfo.durationMS),
      keyEventCount: keyEvents.count,
      clickEventCount: clickEvents.count,
      context: context
    )
  }

  func proRequirement(
    target: PostRecordingExportTarget,
    options: PostRecordingExportOptions?
  ) -> [PaidFeature]? {
    var features: [PaidFeature] = []
    if webcamOverlay.enabled { features.append(.webcamOverlay) }
    if keystrokeOverlay.enabled { features.append(.keystrokeOverlay) }
    if recordingInfo.hasMicrophoneAudio { features.append(.microphoneAudioExport) }
    if let feature = target.paidFeature { features.append(feature) }
    if let feature = options?.codec.paidFeature { features.append(feature) }
    if let feature = options?.frameRate.paidFeature { features.append(feature) }
    if let feature = options?.quality.paidFeature { features.append(feature) }
    if let feature = options?.bitrate.paidFeature { features.append(feature) }
    return features
  }

  private func visibleKeyToken(at timeMS: UInt32) -> String? {
    return keyEvents.last { event in
      event.timestampMS <= timeMS && timeMS <= event.timestampMS.saturatingAdd(Self.keyLabelVisibleWindowMS)
    }?.token
  }

  private func visibleClickEvents(at timeMS: UInt32, durationMS: UInt32) -> [ClickEvent] {
    clickEvents.filter { event in
      event.timestampMS <= timeMS && timeMS <= event.timestampMS.saturatingAdd(durationMS)
    }
  }

  private func absoluteRect(for rect: CGRect, renderSize: CGSize) -> CGRect {
    let standardized = rect.standardized
    guard standardized.maxX <= Self.normalizedFrameUpperBound, standardized.maxY <= Self.normalizedFrameUpperBound else {
      return standardized
    }
    return CGRect(
      x: standardized.minX * renderSize.width,
      y: standardized.minY * renderSize.height,
      width: standardized.width * renderSize.width,
      height: standardized.height * renderSize.height
    ).integral
  }

  private func defaultWebcamFrame() -> CGRect {
    CGRect(x: 0.74, y: 0.68, width: 0.22, height: 0.22)
  }

  private static func keyOverlayFrame(text: String, renderSize: CGSize) -> CGRect {
    guard let layout = OverlayLayout.keyLabel(renderSize: renderSize, charCount: text.count) else {
      return CGRect(x: 0.5 - 0.16, y: 0.08, width: 0.32, height: 0.08)
    }
    return CGRect(
      x: (renderSize.width - layout.width) * 0.5,
      y: layout.y,
      width: layout.width,
      height: layout.height
    )
  }

  private static func milliseconds(fromSeconds seconds: Double) -> UInt32 {
    guard seconds.isFinite, seconds > 0 else {
      return 0
    }
    return UInt32(min(Double(UInt32.max), (seconds * 1000).rounded()))
  }

}
