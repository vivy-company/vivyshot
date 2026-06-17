import Foundation

enum PostRecordingAction {
  case saveVideo(
    PostRecordingExportOptions,
    PostRecordingExportState,
    container: PostRecordingVideoSaveContainer?,
    consumesFreeProExportTrial: Bool
  )
  case copyVideo(
    PostRecordingExportOptions,
    PostRecordingExportState,
    container: PostRecordingVideoSaveContainer?,
    consumesFreeProExportTrial: Bool
  )
  case saveGIF(PostRecordingExportState, consumesFreeProExportTrial: Bool)
  case discard
}


struct PostRecordingExportState: Equatable {
  var trimStartMS: UInt32
  var trimEndMS: UInt32
  var includesAudio: Bool

  var trimmedDurationSeconds: Double {
    Double(max(1, trimEndMS - trimStartMS)) / 1000.0
  }
}

/// Mutable edit state for the post-recording review timeline.
struct PostRecordingReviewEditState: Equatable {
  var trimStartMS: UInt32
  var trimEndMS: UInt32
  var isTrimModeActive: Bool
  var isOutputAudioEnabled: Bool

  var exportState: PostRecordingExportState {
    PostRecordingExportState(
      trimStartMS: trimStartMS,
      trimEndMS: trimEndMS,
      includesAudio: isOutputAudioEnabled
    )
  }
}

enum PostRecordingVideoSaveContainer: String, CaseIterable {
  case mp4
  case mov

  var exportContainer: ExportContainer {
    switch self {
    case .mp4:
      return .mp4
    case .mov:
      return .mov
    }
  }
}

struct ProExportRequirement: Equatable {
  let features: [PaidFeature]

  var requiresPro: Bool {
    !features.isEmpty
  }

  func isSatisfied(canUse: (PaidFeature) -> Bool) -> Bool {
    features.allSatisfy(canUse)
  }

  static func evaluate(
    project: PostRecordingProject,
    options: PostRecordingExportOptions?,
    target: PostRecordingExportTarget,
    includesAudio: Bool = true
  ) -> ProExportRequirement {
    var features = project.videoProject.proRequirement(target: target, options: options) ?? []
    if !includesAudio {
      features.removeAll { $0 == .microphoneAudioExport }
    }
    return ProExportRequirement(
      features: features
    )
  }
}

struct PostRecordingDetails {
  let frameRate: Int
  let systemAudioEnabled: Bool
  let microphoneEnabled: Bool
  let webcamEnabled: Bool
  let mouseClicksEnabled: Bool
  let keystrokesEnabled: Bool
  let keyEventCount: Int
  let clickEventCount: Int

  var hasAudio: Bool {
    systemAudioEnabled || microphoneEnabled
  }
}
