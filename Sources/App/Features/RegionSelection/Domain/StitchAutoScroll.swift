/// Keeps long-screenshot auto-scroll moving when no new stitched content appears.
enum StitchAutoScroll {
  /// Starts by scrolling upward, matching the capture overlay's initial long-screenshot direction.
  static func resetState() -> StitchAutoScrollState {
    StitchAutoScrollState(directionSign: -1, noMotionTicks: 0, didFlipDirection: false)
  }

  /// Advances auto-scroll state and flips direction after repeated no-motion ticks when direction is not locked.
  static func nextState(
    enabled: Bool,
    directionLocked: Bool,
    didMerge: Bool,
    thresholdTicks: UInt32,
    state: StitchAutoScrollState
  ) -> StitchAutoScrollState {
    guard enabled else {
      return resetState()
    }
    var next = state
    if didMerge {
      next.noMotionTicks = 0
      return next
    }
    next.noMotionTicks += 1
    if !directionLocked, next.noMotionTicks >= thresholdTicks {
      next.directionSign = next.directionSign >= 0 ? -1 : 1
      next.noMotionTicks = 0
      next.didFlipDirection = true
    }
    return next
  }
}
