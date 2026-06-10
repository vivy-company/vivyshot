import AVFoundation
import CoreGraphics
import Foundation

@MainActor
struct RecordingOverlayControllerRequest {
  let captureRectInScreen: CGRect
  let webcamPreviewLayer: AVCaptureVideoPreviewLayer?
  let webcamFrame: CGRect
  let webcamShape: WebcamShape
  let webcamAspectRatio: WebcamAspectRatio
  let showKeystrokeOverlay: Bool
  let keystrokeFrame: CGRect
  let keystrokeStyle: KeystrokeStyle
  let keystrokeSize: KeystrokeSize
  let onWebcamFrameChanged: (CGRect) -> Void
  let onKeystrokeFrameChanged: (CGRect) -> Void
}

@MainActor
struct RecordingInputMonitorRequest {
  let captureRectInScreen: CGRect
  let monitorsKeystrokes: Bool
  let monitorsMouseClicks: Bool
  let captureKeystrokes: Bool
  let captureMouseClicks: Bool
  let onKeyEvent: ((RecordedKeystrokeEvent) -> Void)?
}

@MainActor
struct RecordingCoordinatorDependencies {
  let makePostRecordingPresenter:
    (AppSettings, StoreManager, ProExportTrialStore, ToastPresenting, @escaping () -> Void) -> PostRecordingSavePresenter
  let makeWebcamRecorder: (URL, String) throws -> WebcamRecorder
  let makeOverlayController: (RecordingOverlayControllerRequest) -> RecordingOverlayController
  let makeRegionRecorder: (CGRect, RecordingConfig, URL) -> any RegionRecordingSession
  let makeInputMonitor: (RecordingInputMonitorRequest) -> RecordingInputMonitor

  static let live = RecordingCoordinatorDependencies(
    makePostRecordingPresenter: { settings, storeManager, proExportTrialStore, toastPresenter, presentPaywall in
      PostRecordingSavePresenter(
        settings: settings,
        storeManager: storeManager,
        proExportTrialStore: proExportTrialStore,
        toastPresenter: toastPresenter,
        presentPaywall: presentPaywall,
        saveURLProvider: PostRecordingSavePanel.presentSavePanel
      )
    },
    makeWebcamRecorder: { outputURL, preferredDeviceID in
      try WebcamRecorder(outputURL: outputURL, preferredDeviceID: preferredDeviceID)
    },
    makeOverlayController: { request in
      RecordingOverlayController(
        captureRectInScreen: request.captureRectInScreen,
        webcamPreviewLayer: request.webcamPreviewLayer,
        webcamFrame: request.webcamFrame,
        webcamShape: request.webcamShape,
        webcamAspectRatio: request.webcamAspectRatio,
        showKeystrokeOverlay: request.showKeystrokeOverlay,
        keystrokeFrame: request.keystrokeFrame,
        keystrokeStyle: request.keystrokeStyle,
        keystrokeSize: request.keystrokeSize,
        onWebcamFrameChanged: request.onWebcamFrameChanged,
        onKeystrokeFrameChanged: request.onKeystrokeFrameChanged
      )
    },
    makeRegionRecorder: { selectionRectInScreen, config, outputURL in
      ScreenRegionAssetWriterRecorder(
        selectionRectInScreen: selectionRectInScreen,
        config: config,
        outputURL: outputURL
      )
    },
    makeInputMonitor: { request in
      RecordingInputMonitor(
        captureRectInScreen: request.captureRectInScreen,
        monitorsKeystrokes: request.monitorsKeystrokes,
        monitorsMouseClicks: request.monitorsMouseClicks,
        captureKeystrokes: request.captureKeystrokes,
        captureMouseClicks: request.captureMouseClicks,
        onKeyEvent: request.onKeyEvent
      )
    }
  )
}
