import Foundation

/// Observable timeline state for trim handles and output audio toggling.
@MainActor
final class PostRecordingReviewState: ObservableObject {
  @Published private(set) var editState: PostRecordingReviewEditState

  let durationMS: UInt32
  let hasAudio: Bool
  private static let minimumTrimGapMS: UInt32 = 500

  private var minGapMS: UInt32 {
    min(Self.minimumTrimGapMS, max(1, durationMS))
  }

  init(durationSeconds: Double, hasAudio: Bool) {
    durationMS = UInt32(max(1, Int((max(0, durationSeconds) * 1000).rounded())))
    self.hasAudio = hasAudio
    editState = PostRecordingReviewEditState(
      trimStartMS: 0,
      trimEndMS: durationMS,
      isTrimModeActive: false,
      isOutputAudioEnabled: hasAudio
    )
  }

  var durationSeconds: Double {
    Double(durationMS) / 1000.0
  }

  func setTrimModeActive(_ isActive: Bool) {
    editState.isTrimModeActive = isActive
  }

  func toggleOutputAudio() {
    guard hasAudio else {
      return
    }
    editState.isOutputAudioEnabled.toggle()
  }

  func resetTrim() {
    editState.trimStartMS = 0
    editState.trimEndMS = durationMS
  }

  func updateTrim(startMS: UInt32, endMS: UInt32, activeHandle: TrimHandle) {
    let normalized = ExportPlanner.trimRange(
      durationMS: durationMS,
      startMS: startMS,
      endMS: endMS,
      minGapMS: minGapMS,
      activeHandle: activeHandle
    )

    editState.trimStartMS = normalized?.startMS ?? min(startMS, max(0, durationMS - minGapMS))
    editState.trimEndMS = normalized?.endMS ?? max(endMS, min(durationMS, editState.trimStartMS + minGapMS))
  }

  func exportState() -> PostRecordingExportState {
    editState.exportState
  }
}
