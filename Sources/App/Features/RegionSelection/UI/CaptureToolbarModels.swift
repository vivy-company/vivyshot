import CoreGraphics
import Foundation
import SwiftUI

enum CaptureAnnotationToolbarAction {
  case selectCaptureMode(CaptureMode)
  case closeCapture
  case selectTool(AnnotationTool)
  case changeColor(Color)
  case undo
  case redo
  case copy
  case save
  case addStitchSegment
  case resetStitch
  case mainAction
  case drag(CGSize)
  case dragEnded
}

struct StitchToolbarState {
  let canReset: Bool
  let isRecordingActive: Bool
  let isCaptureInProgress: Bool
}

enum CaptureVideoToolbarAction {
  case selectCaptureMode(CaptureMode)
  case closeCapture
  case toggleTool(RecordingTool)
  case selectMicrophoneSource(String)
  case selectWebcamSource(String)
  case selectCountdown(RecordingCountdown)
  case toggleRecording
  case drag(CGSize)
  case dragEnded
}

struct CaptureVideoToolbarState {
  let recordingControls: RecordingLiveControlState
  let selectedMicrophoneID: String
  let selectedWebcamID: String
  let microphoneSources: [RecordingSourceOption]
  let webcamSources: [RecordingSourceOption]
  let toolOrder: [RecordingTool]
  let lockedTools: Set<RecordingTool>
  let accentColor: Color
  let isRecordingActive: Bool
  let isRecordingPending: Bool
  let countdown: RecordingCountdown

  var isConfigurationLocked: Bool {
    isRecordingActive || isRecordingPending
  }
}

enum RecordingControlBarAction {
  case toggleTool(RecordingTool)
  case selectMicrophoneSource(String)
  case selectWebcamSource(String)
  case stop
  case drag(CGSize)
  case dragEnded
}

struct RecordingControlBarState {
  let startedAt: Date
  let liveControls: RecordingLiveControlState
  let selectedMicrophoneID: String
  let selectedWebcamID: String
  let microphoneSources: [RecordingSourceOption]
  let webcamSources: [RecordingSourceOption]
  let toolOrder: [RecordingTool]
  let accentColor: Color
}
