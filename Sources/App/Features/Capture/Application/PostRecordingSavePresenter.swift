import AppKit
import AVFoundation
import CoreGraphics
import CoreMedia
import UniformTypeIdentifiers

struct PostRecordingSaveRequest {
  let allowedContentTypes: [UTType]
  let defaultName: String
}

@MainActor
final class PostRecordingSavePresenter {
  typealias SaveURLProvider = @MainActor (PostRecordingSaveRequest) -> URL?

  private let settings: AppSettings
  private let storeManager: StoreManager
  private let proExportTrialStore: ProExportTrialStore
  private let toastPresenter: ToastPresenting
  private let presentPaywall: () -> Void
  private let saveURLProvider: SaveURLProvider
  private var postRecordingPanels: [PostRecordingActionPanel] = []

  init(
    settings: AppSettings,
    storeManager: StoreManager,
    proExportTrialStore: ProExportTrialStore,
    toastPresenter: ToastPresenting,
    presentPaywall: @escaping () -> Void,
    saveURLProvider: @escaping SaveURLProvider
  ) {
    self.settings = settings
    self.storeManager = storeManager
    self.proExportTrialStore = proExportTrialStore
    self.toastPresenter = toastPresenter
    self.presentPaywall = presentPaywall
    self.saveURLProvider = saveURLProvider
  }

  func present(project: PostRecordingProject, thumbnail: NSImage?) {
    var panelRef: PostRecordingActionPanel?
    let panel = PostRecordingActionPanel(
      inputURL: project.inputURL,
      project: project,
      details: project.details,
      durationSeconds: project.durationSeconds,
      thumbnail: thumbnail,
      videoSize: project.videoSize,
      settings: settings,
      storeManager: storeManager,
      proExportTrialStore: proExportTrialStore,
      presentPaywall: presentPaywall
    ) { [self] action in
      if let panelRef {
        postRecordingPanels.removeAll(where: { $0 === panelRef })
      }
      switch action {
      case .saveVideo(let options, let exportState, container: let container, consumesFreeProExportTrial: let consumesTrial):
        quickSaveVideo(
          project: project,
          options: options,
          exportState: exportState,
          container: container,
          consumesFreeProExportTrial: consumesTrial
        )
      case .saveGIF(let exportState, let consumesTrial):
        quickSaveGIF(
          project: project,
          exportState: exportState,
          consumesFreeProExportTrial: consumesTrial
        )
      case .discard:
        discardTemporaryRecording(project: project)
      }
    }
    panelRef = panel
    postRecordingPanels.append(panel)
    panel.present()
  }

  private func quickSaveVideo(
    project: PostRecordingProject,
    options: PostRecordingExportOptions,
    exportState: PostRecordingExportState,
    container: PostRecordingVideoSaveContainer?,
    consumesFreeProExportTrial: Bool
  ) {
    let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
      .replacingOccurrences(of: ":", with: "-")
    let contentType = container?.contentType ?? ExportPlanner.preferredSaveContentType(codec: options.codec)
    let defaultName = "VivyShot \(timestamp).\(container?.fileExtension ?? contentType.preferredFilenameExtension ?? "mp4")"

    let allowedContentTypes = container.map { [$0.contentType] }
      ?? ExportPlanner.allowedSaveContentTypes(codec: options.codec)
    guard let outputURL = saveURLProvider(
      PostRecordingSaveRequest(
        allowedContentTypes: allowedContentTypes,
        defaultName: defaultName
      )
    ) else { return }

    Task {
      do {
        if exportDecision(project: project, target: .mp4).useCustomCompositor {
          try await PostRecordingProjectExporter.exportCompositedVideo(
            project: project,
            options: options,
            exportState: exportState,
            container: container,
            outputURL: outputURL
          )
          markProExportTrialConsumedIfNeeded(consumesFreeProExportTrial)
          cleanupTemporaryAssets(project: project)
          toastPresenter.show("Saved video to \(outputURL.lastPathComponent)", duration: 2.5)
          return
        }

        try await exportSourceRecordingVideo(
          project: project,
          options: options,
          exportState: exportState,
          container: container,
          outputURL: outputURL
        )
        markProExportTrialConsumedIfNeeded(consumesFreeProExportTrial)
        cleanupTemporaryAssets(project: project)
        toastPresenter.show("Saved video to \(outputURL.lastPathComponent)", duration: 2.5)
      } catch {
        toastPresenter.show("Video save failed: \(error.localizedDescription)", duration: 2.5)
      }
    }
  }

  private func exportSourceRecordingVideo(
    project: PostRecordingProject,
    options: PostRecordingExportOptions,
    exportState: PostRecordingExportState,
    container: PostRecordingVideoSaveContainer?,
    outputURL: URL
  ) async throws {
    if FileManager.default.fileExists(atPath: outputURL.path) {
      try FileManager.default.removeItem(at: outputURL)
    }

    let asset = AVURLAsset(url: project.inputURL)
    let durationTime = try await asset.load(.duration)
    let durationSeconds = max(0, CMTimeGetSeconds(durationTime))
    let trimRange = exportState.trimRange(durationSeconds: durationSeconds)

    if exportState.includesAudio {
      let exportSession = try AVAssetExportSession.recordingExport(
        asset: asset,
        options: options,
        container: container,
        outputURL: outputURL,
        timeRange: trimRange,
        estimatedDurationSeconds: exportState.trimmedDurationSeconds,
        creationError: NSError(
          domain: "VivyShot.Export",
          code: -201,
          userInfo: [NSLocalizedDescriptionKey: "Unable to create video export session."]
        )
      )
      if let videoComposition = try await makePostRecordingVideoComposition(asset: asset, options: options) {
        exportSession.videoComposition = videoComposition
      }
      try await exportSession.exportChecked()
      return
    }

    let composition = AVMutableComposition()
    guard let sourceVideoTrack = try await asset.loadTracks(withMediaType: .video).first,
          let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
          )
    else {
      throw NSError(
        domain: "VivyShot.Export",
        code: -202,
        userInfo: [NSLocalizedDescriptionKey: "Recording video track is missing."]
      )
    }

    let naturalSize = try await sourceVideoTrack.load(.naturalSize)
    let preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
    compositionVideoTrack.preferredTransform = preferredTransform
    try compositionVideoTrack.insertTimeRange(trimRange, of: sourceVideoTrack, at: .zero)

    let exportSession = try AVAssetExportSession.recordingExport(
      asset: composition,
      options: options,
      container: container,
      outputURL: outputURL,
      timeRange: CMTimeRange(start: .zero, duration: trimRange.duration),
      estimatedDurationSeconds: exportState.trimmedDurationSeconds,
      creationError: NSError(
        domain: "VivyShot.Export",
        code: -203,
        userInfo: [NSLocalizedDescriptionKey: "Unable to create muted video export session."]
      )
    )
    if let videoComposition = makePostRecordingVideoComposition(
      videoTrack: compositionVideoTrack,
      naturalSize: naturalSize,
      preferredTransform: preferredTransform,
      duration: trimRange.duration,
      options: options
    ) {
      exportSession.videoComposition = videoComposition
    }
    nonisolated(unsafe) let unsafeExportSession = exportSession
    try await unsafeExportSession.exportChecked()
  }

  private func makePostRecordingVideoComposition(
    asset: AVAsset,
    options: PostRecordingExportOptions
  ) async throws -> AVMutableVideoComposition? {
    let tracks = try await asset.loadTracks(withMediaType: .video)
    guard let videoTrack = tracks.first else {
      return nil
    }

    let naturalSize = try await videoTrack.load(.naturalSize)
    let preferredTransform = try await videoTrack.load(.preferredTransform)
    let duration = try await asset.load(.duration)

    return makePostRecordingVideoComposition(
      videoTrack: videoTrack,
      naturalSize: naturalSize,
      preferredTransform: preferredTransform,
      duration: duration,
      options: options
    )
  }

  private func makePostRecordingVideoComposition(
    videoTrack: AVAssetTrack,
    naturalSize: CGSize,
    preferredTransform: CGAffineTransform,
    duration: CMTime,
    options: PostRecordingExportOptions
  ) -> AVMutableVideoComposition? {
    guard let plan = ExportPlanner.compositionPlan(
      naturalSize: naturalSize,
      preferredTransform: preferredTransform,
      scale: options.scale
    ) else {
      return nil
    }

    let instruction = AVMutableVideoCompositionInstruction()
    instruction.timeRange = CMTimeRange(start: .zero, duration: duration)

    let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
    layerInstruction.setTransform(plan.transform, at: .zero)
    instruction.layerInstructions = [layerInstruction]

    let composition = AVMutableVideoComposition()
    composition.instructions = [instruction]
    composition.renderSize = plan.renderSize
    composition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(options.frameRate.rawValue))
    return composition
  }

  private func quickSaveGIF(
    project: PostRecordingProject,
    exportState: PostRecordingExportState,
    consumesFreeProExportTrial: Bool
  ) {
    let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
      .replacingOccurrences(of: ":", with: "-")

    guard let outputURL = saveURLProvider(
      PostRecordingSaveRequest(
        allowedContentTypes: [.gif],
        defaultName: "VivyShot \(timestamp).gif"
      )
    ) else { return }

    Task {
      do {
        try await PostRecordingProjectExporter.exportGIF(
          project: project,
          exportState: exportState,
          outputURL: outputURL
        )
        markProExportTrialConsumedIfNeeded(consumesFreeProExportTrial)
        cleanupTemporaryAssets(project: project)
        toastPresenter.show("Saved GIF to \(outputURL.lastPathComponent)", duration: 2.5)
      } catch {
        toastPresenter.show("GIF save failed: \(error.localizedDescription)", duration: 2.8)
      }
    }
  }

  private func markProExportTrialConsumedIfNeeded(_ shouldConsume: Bool) {
    guard shouldConsume else {
      return
    }
    proExportTrialStore.markConsumed()
  }

  private func cleanupTemporaryAssets(project: PostRecordingProject) {
    if FileManager.default.fileExists(atPath: project.inputURL.path) {
      try? FileManager.default.removeItem(at: project.inputURL)
    }
    if let webcamURL = project.webcamURL, FileManager.default.fileExists(atPath: webcamURL.path) {
      try? FileManager.default.removeItem(at: webcamURL)
    }
  }

  private func discardTemporaryRecording(project: PostRecordingProject) {
    Task {
      do {
        if FileManager.default.fileExists(atPath: project.inputURL.path) {
          try FileManager.default.removeItem(at: project.inputURL)
        }
        if let webcamURL = project.webcamURL, FileManager.default.fileExists(atPath: webcamURL.path) {
          try FileManager.default.removeItem(at: webcamURL)
        }
        toastPresenter.show("Recording discarded.", duration: 2.0)
      } catch {
        toastPresenter.show("Unable to discard recording: \(error.localizedDescription)", duration: 2.5)
      }
    }
  }

  private func exportDecision(project: PostRecordingProject, target: ExportTarget) -> ExportDecision {
    if !project.overlaysBurnedIn, let plan = project.videoProject.exportPlan(),
       let decision = ExportPlanner.decision(target: target, plan: plan) {
      return decision
    }
    let needsCompositor = project.videoProject.hasMouseClickOverlays
      || (!project.overlaysBurnedIn && project.hasNativeCompositedOverlays)
    return ExportDecision(
      useCustomCompositor: needsCompositor,
      requiresIntermediateForGIF: needsCompositor,
      includeAudio: true,
      includeWebcam: false
    )
  }

}
