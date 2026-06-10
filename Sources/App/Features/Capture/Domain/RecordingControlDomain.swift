/// Optional controls that can appear in the recording toolbar.
enum RecordingTool: Int, CaseIterable, Identifiable {
  case microphone = 1
  case webcam = 2
  case systemAudio = 0
  case mouseClicks = 3
  case keystrokes = 4
  case countdown = 5

  var id: Int { rawValue }

  var isInputSource: Bool {
    switch self {
    case .microphone, .webcam:
      return true
    case .systemAudio, .mouseClicks, .keystrokes, .countdown:
      return false
    }
  }
}

/// Runtime controls for an active recording session. This is intentionally separate from
/// `AppSettings`, which configures the next recording.
struct RecordingLiveControlState: Equatable {
  var recordSystemAudio: Bool
  var recordMicrophone: Bool
  var showWebcam: Bool
  var highlightMouseClicks: Bool
  var highlightKeystrokes: Bool
  var disabledTools: Set<RecordingTool> = []

  func isEnabled(_ tool: RecordingTool) -> Bool {
    switch tool {
    case .systemAudio:
      return recordSystemAudio
    case .microphone:
      return recordMicrophone
    case .webcam:
      return showWebcam
    case .mouseClicks:
      return highlightMouseClicks
    case .keystrokes:
      return highlightKeystrokes
    case .countdown:
      return false
    }
  }
}

/// A selectable recording input source. Empty IDs mean the current system default device.
struct RecordingSourceOption: Identifiable, Hashable {
  let id: String
  let name: String
}
