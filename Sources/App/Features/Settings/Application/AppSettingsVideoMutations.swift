import CoreGraphics
import Foundation

@MainActor
extension AppSettings {
  func setRecordingEncoder(_ encoder: RecordingEncoder) {
    guard recordingEncoder != encoder else {
      return
    }
    recordingEncoder = encoder
    if encoder != .smallerFileHEVC && recordingColorProfile.requiresHEVC {
      recordingColorProfile = .automatic
    }
    persistVideoCaptureSettings()
  }

  func setRecordingFrameRate(_ frameRate: RecordingFrameRate) {
    guard recordingFrameRate != frameRate else {
      return
    }
    recordingFrameRate = frameRate
    persistVideoCaptureSettings()
  }

  func setRecordingCountdown(_ countdown: RecordingCountdown) {
    guard recordingCountdown != countdown else {
      return
    }
    recordingCountdown = countdown
    persistVideoCaptureSettings()
  }

  func setRecordingColorProfile(_ profile: RecordingColorProfile) {
    guard recordingColorProfile != profile else {
      return
    }
    recordingColorProfile = profile
    if profile.requiresHEVC {
      recordingEncoder = .smallerFileHEVC
    }
    persistVideoCaptureSettings()
  }

  func setRecordingCaptureResolution(_ resolution: RecordingCaptureResolution) {
    guard recordingCaptureResolution != resolution else {
      return
    }
    recordingCaptureResolution = resolution
    persistVideoCaptureSettings()
  }

  func setRecordingCaptureBuffering(_ buffering: RecordingCaptureBuffering) {
    guard recordingCaptureBuffering != buffering else {
      return
    }
    recordingCaptureBuffering = buffering
    persistVideoCaptureSettings()
  }

  func setRecordingShowsPointer(_ enabled: Bool) {
    guard recordingShowsPointer != enabled else {
      return
    }
    recordingShowsPointer = enabled
    persistVideoCaptureSettings()
  }

  func setRecordingShowsSystemClickRings(_ enabled: Bool) {
    guard recordingShowsSystemClickRings != enabled else {
      return
    }
    recordingShowsSystemClickRings = enabled
    persistVideoCaptureSettings()
  }

  func setRecordingWindowCaptureStyle(_ style: RecordingWindowCaptureStyle) {
    guard recordingWindowCaptureStyle != style else {
      return
    }
    recordingWindowCaptureStyle = style
    persistVideoCaptureSettings()
  }

  func setRecordingIncludesAppAudio(_ enabled: Bool) {
    guard recordingIncludesAppAudio != enabled else {
      return
    }
    recordingIncludesAppAudio = enabled
    persistVideoCaptureSettings()
  }

  func setVideoExportCodec(_ codec: PostRecordingExportCodec) {
    guard exportCodec != codec else {
      return
    }
    exportCodec = codec
    persistVideoCaptureSettings()
  }

  func setVideoExportFrameRate(_ frameRate: PostRecordingExportFrameRate) {
    guard exportFrameRate != frameRate else {
      return
    }
    exportFrameRate = frameRate
    persistVideoCaptureSettings()
  }

  func setVideoExportQuality(_ quality: PostRecordingExportQuality) {
    guard exportQuality != quality else {
      return
    }
    exportQuality = quality
    persistVideoCaptureSettings()
  }

  func setVideoExportScale(_ scale: PostRecordingExportScale) {
    guard exportScale != scale else {
      return
    }
    exportScale = scale
    persistVideoCaptureSettings()
  }

  func setVideoExportBitrate(_ bitrate: PostRecordingExportBitratePreset) {
    guard exportBitrate != bitrate else {
      return
    }
    exportBitrate = bitrate
    persistVideoCaptureSettings()
  }

  func setVideoRecordSystemAudio(_ enabled: Bool) {
    guard recordSystemAudio != enabled else {
      return
    }
    recordSystemAudio = enabled
    persistVideoCaptureSettings()
  }

  func setVideoRecordMicrophone(_ enabled: Bool) {
    guard recordMicrophone != enabled else {
      return
    }
    recordMicrophone = enabled
    persistVideoCaptureSettings()
  }

  func setVideoMicrophoneDeviceID(_ deviceID: String) {
    let normalized = deviceID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard microphoneDeviceID != normalized else {
      return
    }
    microphoneDeviceID = normalized
    persistVideoCaptureSettings()
  }

  func setVideoShowWebcam(_ enabled: Bool) {
    guard showWebcam != enabled else {
      return
    }
    showWebcam = enabled
    persistVideoCaptureSettings()
  }

  func setVideoWebcamDeviceID(_ deviceID: String) {
    let normalized = deviceID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard webcamDeviceID != normalized else {
      return
    }
    webcamDeviceID = normalized
    persistVideoCaptureSettings()
  }

  func setWebcamOverlayShape(_ shape: WebcamShape) {
    guard webcamOverlayShape != shape else {
      return
    }
    webcamOverlayShape = shape
    if shape == .circle {
      webcamOverlayAspectRatio = .square
    }
    persistVideoCaptureSettings()
  }

  func setWebcamOverlayAspectRatio(_ aspectRatio: WebcamAspectRatio) {
    let normalized = webcamOverlayShape == .circle ? .square : aspectRatio
    guard webcamOverlayAspectRatio != normalized else {
      return
    }
    webcamOverlayAspectRatio = normalized
    persistVideoCaptureSettings()
  }

  func setWebcamOverlayFrame(_ frame: CGRect) {
    let source = Self.normalizedOverlayFrame(frame, fallback: Self.defaultWebcamOverlayFrame)
    let width = Self.clampedWebcamOverlayWidth(Double(source.width))
    let height = Self.clampedWebcamOverlayHeight(Double(source.height))
    let normalized = Self.resizedNormalizedOverlayFrame(
      source,
      width: CGFloat(width),
      height: CGFloat(height)
    )
    let changed = abs(webcamOverlayNormalizedX - normalized.minX) > .ulpOfOne
      || abs(webcamOverlayNormalizedY - normalized.minY) > .ulpOfOne
      || abs(webcamOverlayNormalizedWidth - normalized.width) > .ulpOfOne
      || abs(webcamOverlayNormalizedHeight - normalized.height) > .ulpOfOne
    guard changed else {
      return
    }
    webcamOverlayNormalizedX = normalized.minX
    webcamOverlayNormalizedY = normalized.minY
    webcamOverlayNormalizedWidth = normalized.width
    webcamOverlayNormalizedHeight = normalized.height
    persistWebcamOverlayFrame()
  }

  func setWebcamOverlayWidth(_ width: Double) {
    let current = webcamOverlayNormalizedFrame
    let normalizedWidth = Self.clampedWebcamOverlayWidth(width)
    setWebcamOverlayFrame(
      CGRect(
        x: current.midX - normalizedWidth * 0.5,
        y: current.minY,
        width: normalizedWidth,
        height: current.height
      )
    )
  }

  func resetWebcamOverlayPlacement() {
    setWebcamOverlayFrame(Self.defaultWebcamOverlayFrame)
  }

  func setVideoHighlightMouseClicks(_ enabled: Bool) {
    guard highlightMouseClicks != enabled else {
      return
    }
    highlightMouseClicks = enabled
    persistVideoCaptureSettings()
  }

  func setMouseClickHighlightStyle(_ style: MouseClickHighlightStyle) {
    guard mouseClickHighlightStyle != style else {
      return
    }
    mouseClickHighlightStyle = style
    persistVideoCaptureSettings()
  }

  func setVideoHighlightKeystrokes(_ enabled: Bool) {
    guard highlightKeystrokes != enabled else {
      return
    }
    highlightKeystrokes = enabled
    persistVideoCaptureSettings()
  }

  func setKeystrokeOverlayStyle(_ style: KeystrokeStyle) {
    guard keystrokeOverlayStyle != style else {
      return
    }
    keystrokeOverlayStyle = style
    persistVideoCaptureSettings()
  }

  func setKeystrokeOverlayFrame(_ frame: CGRect) {
    let source = Self.normalizedOverlayFrame(frame, fallback: Self.defaultKeystrokeOverlayFrame)
    let normalized = Self.resizedNormalizedOverlayFrame(
      source,
      width: CGFloat(Self.clampedKeystrokeOverlayWidth(Double(source.width))),
      height: CGFloat(Self.clampedKeystrokeOverlayHeight(Double(source.height)))
    )
    let changed = abs(keystrokeOverlayNormalizedX - normalized.minX) > .ulpOfOne
      || abs(keystrokeOverlayNormalizedY - normalized.minY) > .ulpOfOne
      || abs(keystrokeOverlayNormalizedWidth - normalized.width) > .ulpOfOne
      || abs(keystrokeOverlayNormalizedHeight - normalized.height) > .ulpOfOne
    guard changed else {
      return
    }
    keystrokeOverlayNormalizedX = normalized.minX
    keystrokeOverlayNormalizedY = normalized.minY
    keystrokeOverlayNormalizedWidth = normalized.width
    keystrokeOverlayNormalizedHeight = normalized.height
    persistKeystrokeOverlayFrame()
  }

  func setKeystrokeOverlayScale(_ width: Double) {
    let current = keystrokeOverlayNormalizedFrame
    let normalizedWidth = Self.clampedKeystrokeOverlayWidth(width)
    let ratio = current.width > 0
      ? current.height / current.width
      : Self.defaultKeystrokeOverlayFrame.height / Self.defaultKeystrokeOverlayFrame.width
    let normalizedHeight = Self.clampedKeystrokeOverlayHeight(normalizedWidth * Double(ratio))
    setKeystrokeOverlayFrame(
      CGRect(
        x: current.midX - normalizedWidth * 0.5,
        y: current.midY - normalizedHeight * 0.5,
        width: normalizedWidth,
        height: normalizedHeight
      )
    )
  }

  func resetKeystrokeOverlayPlacement() {
    setKeystrokeOverlayFrame(Self.defaultKeystrokeOverlayFrame)
  }

  func setVideoHideNotificationsBestEffort(_ enabled: Bool) {
    guard hideNotificationsBestEffort != enabled else {
      return
    }
    hideNotificationsBestEffort = enabled
    persistVideoCaptureSettings()
  }

  func resetVideoCaptureSettings() {
    applyVideoSettings(VideoSettingsSnapshot.defaultValues)
    persistVideoCaptureSettings()
  }

  func isRecordingToolVisible(_ tool: RecordingTool) -> Bool {
    !hiddenRecordingTools.contains(tool)
  }

  func setRecordingToolVisible(_ tool: RecordingTool, isVisible: Bool) {
    var updated = hiddenRecordingTools
    if isVisible {
      updated.remove(tool)
    } else {
      updated.insert(tool)
    }

    guard updated != hiddenRecordingTools else {
      return
    }

    hiddenRecordingTools = updated
    persistVideoToolbarConfiguration()
  }

  func moveVideoTools(from source: IndexSet, to destination: Int) {
    guard let updated = Self.reordered(recordingToolOrder, moving: source, to: destination) else { return }
    guard updated != recordingToolOrder else {
      return
    }

    recordingToolOrder = updated
    persistVideoToolbarConfiguration()
  }

  func resetVideoToolbarConfiguration() {
    recordingToolOrder = RecordingTool.allCases
    hiddenRecordingTools = []
    persistVideoToolbarConfiguration()
  }

  private func applyVideoSettings(_ snapshot: VideoSettingsSnapshot) {
    defaultCaptureType = snapshot.defaultCaptureType
    recordingEncoder = snapshot.recordingEncoder
    recordingFrameRate = snapshot.recordingFrameRate
    recordingCountdown = snapshot.recordingCountdown
    recordingColorProfile = snapshot.recordingColorProfile
    recordingCaptureResolution = snapshot.recordingCaptureResolution
    recordingCaptureBuffering = snapshot.recordingCaptureBuffering
    recordingShowsPointer = snapshot.recordingShowsPointer
    recordingShowsSystemClickRings = snapshot.recordingShowsSystemClickRings
    recordingWindowCaptureStyle = snapshot.recordingWindowCaptureStyle
    recordingIncludesAppAudio = snapshot.recordingIncludesAppAudio
    exportCodec = snapshot.exportCodec
    exportFrameRate = snapshot.exportFrameRate
    exportQuality = snapshot.exportQuality
    exportScale = snapshot.exportScale
    exportBitrate = snapshot.exportBitrate
    recordSystemAudio = snapshot.recordSystemAudio
    recordMicrophone = snapshot.recordMicrophone
    microphoneDeviceID = snapshot.microphoneDeviceID
    showWebcam = snapshot.showWebcam
    webcamDeviceID = snapshot.webcamDeviceID
    webcamOverlayShape = snapshot.webcamOverlayShape
    webcamOverlayAspectRatio = snapshot.webcamOverlayAspectRatio
    webcamOverlayNormalizedX = snapshot.webcamOverlayFrame.minX
    webcamOverlayNormalizedY = snapshot.webcamOverlayFrame.minY
    webcamOverlayNormalizedWidth = snapshot.webcamOverlayFrame.width
    webcamOverlayNormalizedHeight = snapshot.webcamOverlayFrame.height
    highlightMouseClicks = snapshot.highlightMouseClicks
    mouseClickHighlightStyle = snapshot.mouseClickHighlightStyle
    highlightKeystrokes = snapshot.highlightKeystrokes
    keystrokeOverlayStyle = snapshot.keystrokeOverlayStyle
    keystrokeOverlaySize = snapshot.keystrokeOverlaySize
    keystrokeOverlayNormalizedX = snapshot.keystrokeOverlayFrame.minX
    keystrokeOverlayNormalizedY = snapshot.keystrokeOverlayFrame.minY
    keystrokeOverlayNormalizedWidth = snapshot.keystrokeOverlayFrame.width
    keystrokeOverlayNormalizedHeight = snapshot.keystrokeOverlayFrame.height
    hideNotificationsBestEffort = snapshot.hideNotificationsBestEffort
  }
}
