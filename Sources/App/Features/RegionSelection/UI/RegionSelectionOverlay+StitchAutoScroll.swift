import AppKit
import CoreGraphics

@MainActor
extension RegionSelectionView {
  func resetStitchAutoScrollState() {
    let state = StitchAutoScroll.resetState()
    applyStitchAutoScrollState(state)
    stitchState.autoScrollTrusted = false
    stitchState.targetApp = nil
  }

  func currentStitchAutoScrollState() -> StitchAutoScrollState {
    StitchAutoScrollState(
      directionSign: stitchState.autoScrollDirectionSign,
      noMotionTicks: UInt32(max(0, stitchState.autoScrollNoMotionTicks)),
      didFlipDirection: stitchState.autoScrollDidFlipDirection
    )
  }

  func applyStitchAutoScrollState(_ state: StitchAutoScrollState) {
    stitchState.autoScrollDirectionSign = state.directionSign == 0 ? -1 : state.directionSign
    stitchState.autoScrollNoMotionTicks = Int(state.noMotionTicks)
    stitchState.autoScrollDidFlipDirection = state.didFlipDirection
  }

  func refreshAutoScrollTrust(promptIfNeeded: Bool) {
    guard stitchState.autoScrollEnabled else {
      stitchState.autoScrollTrusted = false
      return
    }

    if promptIfNeeded, !stitchState.autoScrollPromptAttempted {
      stitchState.autoScrollPromptAttempted = true
      stitchState.autoScrollTrusted = AccessibilityPermission.isTrusted(promptIfNeeded: true)
    } else {
      stitchState.autoScrollTrusted = AccessibilityPermission.isTrusted(promptIfNeeded: false)
    }
  }

  func resolveStitchTargetAppUnderCursor() -> NSRunningApplication? {
    resolveStitchTargetApp(at: NSEvent.mouseLocation)
  }

  func resolveStitchTargetApp(at point: CGPoint) -> NSRunningApplication? {
    guard let windowInfo = CGWindowListCopyWindowInfo(
      [.optionOnScreenOnly, .excludeDesktopElements],
      kCGNullWindowID
    ) as? [[String: Any]]
    else {
      return nil
    }

    let selfPID = ProcessInfo.processInfo.processIdentifier
    for info in windowInfo {
      guard let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
            let bounds = CGRect(dictionaryRepresentation: boundsDict),
            bounds.contains(point),
            let ownerPIDNumber = info[kCGWindowOwnerPID as String] as? NSNumber
      else {
        continue
      }

      let ownerPID = ownerPIDNumber.int32Value
      if ownerPID == selfPID {
        continue
      }
      if let app = NSRunningApplication(processIdentifier: ownerPID), !app.isTerminated {
        return app
      }
    }
    return nil
  }

  func performAutoScrollTickIfNeeded(captureRectInScreen: CGRect) -> Bool {
    guard stitchState.autoScrollEnabled else {
      return false
    }

    guard stitchState.autoScrollTrusted else {
      return false
    }

    if stitchState.targetApp == nil || stitchState.targetApp?.isTerminated == true {
      let targetPoint = CGPoint(x: captureRectInScreen.midX, y: captureRectInScreen.midY)
      stitchState.targetApp = resolveStitchTargetApp(at: targetPoint)
    }

    let delta = max(1, stitchAutoScrollStepLines) * stitchState.autoScrollDirectionSign
    guard let scrollEvent = CGEvent(
      scrollWheelEvent2Source: nil,
      units: .line,
      wheelCount: 1,
      wheel1: delta,
      wheel2: 0,
      wheel3: 0
      ) else {
      return false
    }

    if let targetApp = stitchState.targetApp, !targetApp.isTerminated {
      if !targetApp.isActive {
        targetApp.activate(options: [])
      }
      scrollEvent.postToPid(targetApp.processIdentifier)
    } else {
      scrollEvent.post(tap: .cghidEventTap)
    }

    return true
  }

  func updateAutoScrollFeedback(didMerge: Bool) {
    let next = StitchAutoScroll.nextState(
      enabled: stitchState.autoScrollEnabled,
      directionLocked: stitchState.directionLocked,
      didMerge: didMerge,
      thresholdTicks: 4,
      state: currentStitchAutoScrollState()
    )
    applyStitchAutoScrollState(next)
  }
}
