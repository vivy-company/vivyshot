import AppKit
import AVFoundation
import AVKit
import CoreGraphics
import CoreMedia
import ImageIO
import QuartzCore
import ScreenCaptureKit
import UniformTypeIdentifiers
import VideoToolbox

/// Coordinates a full recording session from permissions through capture, overlays, preview, and export handoff.
@MainActor
final class RecordingCoordinator: RegionSelectionRecordingControlling {
  let settings: AppSettings
  let storeManager: StoreManager
  let proExportTrialStore: ProExportTrialStore
  let statisticsRecorder: RecordingStatisticsRecorder
  let toastPresenter: ToastPresenting
  let dependencies: RecordingCoordinatorDependencies
  var recorder: (any RegionRecordingSession)?
  var webcamRecorder: WebcamRecorder?
  var inputMonitor: RecordingInputMonitor?
  var hudController: RecordingHUDController?
  var recordingOverlayController: RecordingOverlayController?
  let postRecordingPresenter: PostRecordingSavePresenter
  weak var flowHandler: (any RecordingFlowHandling)?
  var recordingRect: CGRect = .zero
  var recordingStartUptime: TimeInterval?
  var webcamPlacementChanges: [OverlayPlacementChange] = []
  var keystrokePlacementChanges: [OverlayPlacementChange] = []
  var webcamOverlayUsedInSession = false
  var keystrokeOverlayEnabledInSession = false
  var mouseClickHighlightStyleInSession: MouseClickHighlightStyle?
  var systemAudioEnabledInSession = false
  var microphoneEnabledInSession = false
  var liveControlState = RecordingLiveControlState(
    recordSystemAudio: false,
    recordMicrophone: false,
    showWebcam: false,
    highlightMouseClicks: false,
    highlightKeystrokes: false
  )
  var isStoppingRecording = false
  weak var recordingStateObserver: (any RecordingStateObserving)?

  var isRecordingActive = false {
    didSet {
      if oldValue != isRecordingActive {
        recordingStateObserver?.recordingStateDidChange(isRecording: isRecordingActive)
      }
    }
  }

  init(
    settings: AppSettings,
    storeManager: StoreManager,
    proExportTrialStore: ProExportTrialStore,
    statisticsStore: StatisticsStore,
    toastPresenter: ToastPresenting,
    presentPaywall: @escaping () -> Void,
    dependencies: RecordingCoordinatorDependencies = .live
  ) {
    self.settings = settings
    self.storeManager = storeManager
    self.proExportTrialStore = proExportTrialStore
    self.statisticsRecorder = RecordingStatisticsRecorder(statisticsStore: statisticsStore)
    self.toastPresenter = toastPresenter
    self.dependencies = dependencies
    postRecordingPresenter = dependencies.makePostRecordingPresenter(
      settings,
      storeManager,
      proExportTrialStore,
      toastPresenter,
      presentPaywall
    )
  }

  func makeVideoProject(
    assetInfo: PostRecordingAssetInfo,
    webcamURL: URL?,
    monitorResult: RecordingInputResult
  ) -> RecordingProject {
    RecordingProjectBuilder(
      fallbackSize: recordingRect.size,
      frameRate: settings.recordingFrameRate.rawValue,
      systemAudioEnabled: systemAudioEnabledInSession,
      microphoneEnabled: microphoneEnabledInSession,
      webcamAssetAvailable: webcamURL != nil,
      webcamOverlayEnabled: webcamOverlayUsedInSession,
      webcamShape: settings.webcamOverlayShape,
      webcamAspectRatio: settings.webcamOverlayAspectRatio,
      webcamPlacementChanges: webcamPlacementChanges,
      keystrokeOverlayEnabled: keystrokeOverlayEnabledInSession,
      keystrokeStyle: settings.keystrokeOverlayStyle,
      keystrokeSize: settings.keystrokeOverlaySize,
      keystrokePlacementChanges: keystrokePlacementChanges,
      mouseClickHighlightStyle: mouseClickHighlightStyleInSession,
      monitorResult: monitorResult
    ).makeProject(
      durationSeconds: assetInfo.durationSeconds,
      videoSize: assetInfo.videoSize
    )
  }

  func recordWebcamPlacementChange(_ frame: CGRect) {
    let timestamp = currentRecordingOverlayTimestamp()
    settings.setWebcamOverlayFrame(frame)
    webcamPlacementChanges.append(OverlayPlacementChange(timestampSeconds: timestamp, normalizedFrame: frame))
  }

  func recordKeystrokePlacementChange(_ frame: CGRect) {
    let timestamp = currentRecordingOverlayTimestamp()
    settings.setKeystrokeOverlayFrame(frame)
    keystrokePlacementChanges.append(OverlayPlacementChange(timestampSeconds: timestamp, normalizedFrame: frame))
  }

  func currentRecordingOverlayTimestamp() -> TimeInterval {
    guard let recordingStartUptime else {
      return 0
    }
    return max(0, ProcessInfo.processInfo.systemUptime - recordingStartUptime)
  }

  func makeTemporaryRecordingURL() -> URL {
    CaptureTemporaryFiles.recordingURL()
  }

  func makeTemporaryWebcamURL() -> URL {
    CaptureTemporaryFiles.webcamURL()
  }

  var runtimePermissions: RecordingRuntimePermissions {
    RecordingRuntimePermissions(settings: settings, storeManager: storeManager)
  }

}
