import AppKit
import AVFoundation
import CoreGraphics
import CoreMedia
import SwiftUI
import UniformTypeIdentifiers

struct PostRecordingSaveRequest {
  let allowedContentTypes: [UTType]
  let defaultName: String
  let suggestedDirectory: URL?

  init(
    allowedContentTypes: [UTType],
    defaultName: String,
    suggestedDirectory: URL? = nil
  ) {
    self.allowedContentTypes = allowedContentTypes
    self.defaultName = defaultName
    self.suggestedDirectory = suggestedDirectory
  }
}

struct PostRecordingExportProgressUpdate {
  let phase: String
  let fraction: Double?
}

typealias PostRecordingExportProgressHandler = @MainActor (PostRecordingExportProgressUpdate) -> Void

enum PostRecordingExportProgress {
  private static let pollingIntervalNanoseconds: UInt64 = 120_000_000

  @MainActor
  static func update(
    _ progress: PostRecordingExportProgressHandler?,
    phase: String,
    fraction: Double?
  ) {
    progress?(PostRecordingExportProgressUpdate(phase: phase, fraction: fraction))
  }

  static func pollExportSession(
    _ exportSession: AVAssetExportSession,
    phase: String,
    progressBase: Double = 0,
    progressScale: Double = 1,
    progress: PostRecordingExportProgressHandler?
  ) -> Task<Void, Never>? {
    guard let progress else {
      return nil
    }

    nonisolated(unsafe) let unsafeExportSession = exportSession
    return Task { @MainActor in
      while !Task.isCancelled {
        let fraction = progressBase + Double(unsafeExportSession.progress) * progressScale
        progress(PostRecordingExportProgressUpdate(phase: phase, fraction: fraction))
        try? await Task.sleep(nanoseconds: pollingIntervalNanoseconds)
      }
    }
  }
}

@MainActor
private final class PostRecordingExportProgressState: ObservableObject {
  @Published var title: String
  @Published var phase: String
  @Published var filename: String
  @Published var fraction: Double?

  init(title: String, phase: String, filename: String, fraction: Double? = nil) {
    self.title = title
    self.phase = phase
    self.filename = filename
    self.fraction = fraction
  }

  func update(_ progress: PostRecordingExportProgressUpdate) {
    phase = progress.phase
    fraction = progress.fraction.map { min(1, max(0, $0)) }
  }
}

private struct PostRecordingExportProgressView: View {
  @ObservedObject var state: PostRecordingExportProgressState

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(state.title)
          .font(.headline)
        Text(state.filename)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }

      if let fraction = state.fraction {
        ProgressView(value: fraction)
      } else {
        ProgressView()
          .progressViewStyle(.linear)
      }

      Text(state.phase)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding(20)
    .frame(width: 380)
  }
}

@MainActor
private final class PostRecordingExportProgressPanel: NSWindowController {
  private let progressState: PostRecordingExportProgressState
  private var dockPresenceReason: AppDockPresenceReason {
    .postRecordingExportProgress(ObjectIdentifier(self))
  }

  init(title: String, filename: String) {
    progressState = PostRecordingExportProgressState(
      title: title,
      phase: String(localized: "Preparing...", bundle: AppLocalizer.shared.bundle),
      filename: filename
    )

    let panel = NSPanel(
      contentRect: CGRect(x: 0, y: 0, width: 380, height: 140),
      styleMask: [.titled],
      backing: .buffered,
      defer: false
    )
    panel.title = title
    panel.contentView = NSHostingView(rootView: PostRecordingExportProgressView(state: progressState))
    panel.isReleasedWhenClosed = false
    panel.level = .floating
    panel.collectionBehavior.insert([.moveToActiveSpace, .fullScreenAuxiliary])

    super.init(window: panel)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  func present() {
    guard let window else {
      return
    }
    AppDockPresence.track(dockPresenceReason, window: window)
    window.center()
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()
  }

  func update(_ progress: PostRecordingExportProgressUpdate) {
    progressState.update(progress)
  }
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
      switch action {
      case .saveVideo(let options, let exportState, container: let container, consumesFreeProExportTrial: let consumesTrial):
        quickSaveVideo(
          project: project,
          options: options,
          exportState: exportState,
          container: container,
          consumesFreeProExportTrial: consumesTrial
        )
      case .copyVideo(let options, let exportState, container: let container, consumesFreeProExportTrial: let consumesTrial):
        copyVideo(
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
    panel.onWindowClosed = { [weak self, weak panel] in
      guard let self, let panel else {
        return
      }
      postRecordingPanels.removeAll(where: { $0 === panel })
    }
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
    let contentType = container?.contentType ?? ExportPlanner.preferredSaveContentType(codec: options.codec)
    let fileExtension = container?.fileExtension ?? contentType.preferredFilenameExtension ?? "mp4"
    let defaultName = Self.defaultVideoSaveName(fileExtension: fileExtension)

    let allowedContentTypes = container.map { [$0.contentType] }
      ?? ExportPlanner.allowedSaveContentTypes(codec: options.codec)
    guard let outputURL = videoSaveURL(allowedContentTypes: allowedContentTypes, defaultName: defaultName) else {
      return
    }

    let (progressPanel, progressHandler) = makeProgressPanel(
      title: String(localized: "Saving Video", bundle: AppLocalizer.shared.bundle),
      filename: outputURL.lastPathComponent
    )

    Task {
      defer {
        progressPanel.close()
      }
      do {
        if exportDecision(project: project, target: .mp4).useCustomCompositor {
          try await PostRecordingProjectExporter.exportCompositedVideo(
            project: project,
            options: options,
            exportState: exportState,
            container: container,
            outputURL: outputURL,
            progress: progressHandler
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
          outputURL: outputURL,
          progress: progressHandler
        )
        markProExportTrialConsumedIfNeeded(consumesFreeProExportTrial)
        cleanupTemporaryAssets(project: project)
        toastPresenter.show("Saved video to \(outputURL.lastPathComponent)", duration: 2.5)
      } catch {
        toastPresenter.show("Video save failed: \(error.localizedDescription)", duration: 2.5)
      }
    }
  }

  private func copyVideo(
    project: PostRecordingProject,
    options: PostRecordingExportOptions,
    exportState: PostRecordingExportState,
    container: PostRecordingVideoSaveContainer?,
    consumesFreeProExportTrial: Bool
  ) {
    let fileExtension = container?.fileExtension ?? "mp4"
    let copiedVideoDestination = copiedVideoDestination(fileExtension: fileExtension)
    let outputURL = copiedVideoDestination.url
    let (progressPanel, progressHandler) = makeProgressPanel(
      title: String(localized: "Copying Video", bundle: AppLocalizer.shared.bundle),
      filename: outputURL.lastPathComponent
    )

    Task {
      defer {
        progressPanel.close()
      }
      do {
        if exportDecision(project: project, target: .mp4).useCustomCompositor {
          try await PostRecordingProjectExporter.exportCompositedVideo(
            project: project,
            options: options,
            exportState: exportState,
            container: container,
            outputURL: outputURL,
            progress: progressHandler
          )
        } else {
          try await exportSourceRecordingVideo(
            project: project,
            options: options,
            exportState: exportState,
            container: container,
            outputURL: outputURL,
            progress: progressHandler
          )
        }

        guard self.copyVideoFileToPasteboard(outputURL) else {
          throw NSError(
            domain: "VivyShot.Export",
            code: -301,
            userInfo: [NSLocalizedDescriptionKey: "Unable to copy video to clipboard."]
          )
        }

        markProExportTrialConsumedIfNeeded(consumesFreeProExportTrial)
        cleanupTemporaryAssets(project: project)
        showCopiedVideoToast(savedToVideoFolder: copiedVideoDestination.isStoredInVideoFolder)
      } catch {
        if FileManager.default.fileExists(atPath: outputURL.path) {
          try? FileManager.default.removeItem(at: outputURL)
        }
        toastPresenter.show("Video copy failed: \(error.localizedDescription)", duration: 2.8)
      }
    }
  }

  private func exportSourceRecordingVideo(
    project: PostRecordingProject,
    options: PostRecordingExportOptions,
    exportState: PostRecordingExportState,
    container: PostRecordingVideoSaveContainer?,
    outputURL: URL,
    progress: PostRecordingExportProgressHandler?
  ) async throws {
    PostRecordingExportProgress.update(
      progress,
      phase: String(localized: "Preparing video...", bundle: AppLocalizer.shared.bundle),
      fraction: nil
    )
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
      try await exportChecked(
        exportSession,
        phase: String(localized: "Saving video...", bundle: AppLocalizer.shared.bundle),
        progress: progress
      )
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
    try await exportChecked(
      unsafeExportSession,
      phase: String(localized: "Saving video...", bundle: AppLocalizer.shared.bundle),
      progress: progress
    )
  }

  private func exportChecked(
    _ exportSession: AVAssetExportSession,
    phase: String,
    progress: PostRecordingExportProgressHandler?
  ) async throws {
    PostRecordingExportProgress.update(progress, phase: phase, fraction: 0)
    let progressTask = PostRecordingExportProgress.pollExportSession(
      exportSession,
      phase: phase,
      progress: progress
    )
    defer {
      progressTask?.cancel()
    }
    nonisolated(unsafe) let unsafeExportSession = exportSession
    try await unsafeExportSession.exportChecked()
    PostRecordingExportProgress.update(progress, phase: phase, fraction: 1)
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
    VideoRecordingColorPolicy.apply(to: composition, for: options.codec)
    return composition
  }

  private func quickSaveGIF(
    project: PostRecordingProject,
    exportState: PostRecordingExportState,
    consumesFreeProExportTrial: Bool
  ) {
    guard let outputURL = videoSaveURL(
      allowedContentTypes: [.gif],
      defaultName: Self.defaultVideoSaveName(fileExtension: "gif")
    ) else {
      return
    }

    let (progressPanel, progressHandler) = makeProgressPanel(
      title: String(localized: "Saving GIF", bundle: AppLocalizer.shared.bundle),
      filename: outputURL.lastPathComponent
    )

    Task {
      defer {
        progressPanel.close()
      }
      do {
        try await PostRecordingProjectExporter.exportGIF(
          project: project,
          exportState: exportState,
          outputURL: outputURL,
          progress: progressHandler
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

  private func makeProgressPanel(
    title: String,
    filename: String
  ) -> (PostRecordingExportProgressPanel, PostRecordingExportProgressHandler) {
    let progressPanel = PostRecordingExportProgressPanel(title: title, filename: filename)
    let progressHandler: PostRecordingExportProgressHandler = { progress in
      progressPanel.update(progress)
    }
    progressPanel.present()
    return (progressPanel, progressHandler)
  }

  private func copiedVideoDestination(fileExtension: String) -> (url: URL, isStoredInVideoFolder: Bool) {
    guard settings.saveCopiedVideosToDefaultDirectory,
          let directory = settings.videoSaveDirectoryURL
    else {
      return (CaptureTemporaryFiles.clipboardURL(pathExtension: fileExtension), false)
    }

    return (
      Self.uniqueSaveURL(
        in: directory,
        defaultName: Self.defaultVideoSaveName(fileExtension: fileExtension)
      ),
      true
    )
  }

  private func videoSaveURL(allowedContentTypes: [UTType], defaultName: String) -> URL? {
    if settings.videoSaveSkipsDialog, let directory = settings.videoSaveDirectoryURL {
      return Self.uniqueSaveURL(in: directory, defaultName: defaultName)
    }

    return saveURLProvider(
      PostRecordingSaveRequest(
        allowedContentTypes: allowedContentTypes,
        defaultName: defaultName,
        suggestedDirectory: settings.videoSaveDirectoryURL
      )
    )
  }

  private func showCopiedVideoToast(savedToVideoFolder: Bool) {
    if savedToVideoFolder {
      toastPresenter.show("Copied video and saved", duration: 2.2)
    } else {
      toastPresenter.show("Copied video to Clipboard", duration: 2.2)
    }
  }

  static func defaultVideoSaveName(fileExtension: String) -> String {
    let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
      .replacingOccurrences(of: ":", with: "-")
    return "VivyShot \(timestamp).\(fileExtension)"
  }

  static func uniqueSaveURL(in directory: URL, defaultName: String) -> URL {
    let baseURL = directory.appendingPathComponent(defaultName)
    let pathExtension = baseURL.pathExtension
    let baseName = baseURL.deletingPathExtension().lastPathComponent
    var candidate = baseURL
    var suffix = 2

    while FileManager.default.fileExists(atPath: candidate.path) {
      let suffixedName = "\(baseName)-\(suffix)"
      candidate = pathExtension.isEmpty
        ? directory.appendingPathComponent(suffixedName)
        : directory.appendingPathComponent(suffixedName).appendingPathExtension(pathExtension)
      suffix += 1
    }

    return candidate
  }

  private func copyVideoFileToPasteboard(_ url: URL) -> Bool {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    return pasteboard.writeObjects([url as NSURL])
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
