import AppKit
import CoreGraphics

struct RegionSelectionStitchState {
  var modeEnabled = false
  var captureInProgress = false
  var passThroughOverlayActive = false
  var recordingActive = false
  var segmentCount = 1
  var captureTask: Task<Void, Never>?
  var session: StitchSession?
  var workingImage: CGImage?
  var directionLocked = false
  var captureRectInScreen: CGRect?
  var preImage: CGImage?
  var preSelectionRect: CGRect?
  var postEditorMode = false
  var autoScrollEnabled = true
  var autoScrollDirectionSign: Int32 = -1
  var autoScrollNoMotionTicks = 0
  var autoScrollDidFlipDirection = false
  var autoScrollPromptAttempted = false
  var autoScrollTrusted = false
  var targetApp: NSRunningApplication?
}
