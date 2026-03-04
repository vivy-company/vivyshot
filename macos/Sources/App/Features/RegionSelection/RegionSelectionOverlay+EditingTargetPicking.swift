import AppKit
import ApplicationServices

@MainActor
extension RegionSelectionView {
  func captureRectForWindowPick(at localPoint: CGPoint) -> CGRect? {
    guard let hostWindow = window else {
      return nil
    }
    let screenPoint = CGPoint(
      x: hostWindow.frame.minX + localPoint.x,
      y: hostWindow.frame.minY + localPoint.y
    )

    let selfPID = ProcessInfo.processInfo.processIdentifier
    guard let windowInfo = CGWindowListCopyWindowInfo(
      [.optionOnScreenOnly, .excludeDesktopElements],
      kCGNullWindowID
    ) as? [[String: Any]]
    else {
      return nil
    }

    struct WindowPickCandidate {
      let rect: CGRect
      let layer: Int
      let order: Int
      let area: CGFloat
      let isFrontmostOwner: Bool
    }

    let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
    var candidates: [WindowPickCandidate] = []

    for (order, info) in windowInfo.enumerated() {
      guard let ownerPIDNumber = info[kCGWindowOwnerPID as String] as? NSNumber else {
        continue
      }
      let ownerPID = ownerPIDNumber.int32Value
      if ownerPIDNumber.int32Value == selfPID {
        continue
      }

      let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
      if layer != 0 {
        continue
      }

      if let ownerName = info[kCGWindowOwnerName as String] as? String,
         ownerName == "Dock" || ownerName == "Window Server"
      {
        continue
      }

      if let onscreen = info[kCGWindowIsOnscreen as String] as? NSNumber, !onscreen.boolValue {
        continue
      }

      if let alpha = info[kCGWindowAlpha as String] as? NSNumber, alpha.doubleValue < 0.05 {
        continue
      }

      guard let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
            let cgBounds = CGRect(dictionaryRepresentation: boundsDict),
            cgBounds.width >= 40,
            cgBounds.height >= 30
      else {
        continue
      }

      let screenBounds = overlayCGDisplayRectToCocoaRect(cgBounds)
      guard screenBounds.contains(screenPoint) else {
        continue
      }

      let rect = screenBounds
        .offsetBy(dx: -hostWindow.frame.minX, dy: -hostWindow.frame.minY)
        .integral
      let area = max(1, rect.width * rect.height)
      let isFrontmostOwner = frontmostPID.map { Int32($0) == ownerPID } ?? false

      candidates.append(
        WindowPickCandidate(
          rect: rect,
          layer: layer,
          order: order,
          area: area,
          isFrontmostOwner: isFrontmostOwner
        )
      )
    }

    guard !candidates.isEmpty else {
      return nil
    }

    candidates.sort { lhs, rhs in
      if lhs.isFrontmostOwner != rhs.isFrontmostOwner {
        return lhs.isFrontmostOwner && !rhs.isFrontmostOwner
      }
      if lhs.layer != rhs.layer {
        return lhs.layer < rhs.layer
      }
      if lhs.order != rhs.order {
        return lhs.order < rhs.order
      }
      return lhs.area < rhs.area
    }

    return candidates.first?.rect
  }

  func currentMousePointInView() -> CGPoint? {
    guard let window else {
      return nil
    }
    return convert(window.mouseLocationOutsideOfEventStream, from: nil)
  }

  func localPoint(fromScreenPoint screenPoint: CGPoint) -> CGPoint? {
    guard let hostWindow = window else {
      return nil
    }
    return CGPoint(
      x: screenPoint.x - hostWindow.frame.minX,
      y: screenPoint.y - hostWindow.frame.minY
    )
  }

  func updateWindowCaptureHover(at point: CGPoint?) {
    guard mode == .editing, selectedCaptureMode == .window, windowCapturePickPending, let point else {
      if windowCaptureHoverRect != nil {
        windowCaptureHoverRect = nil
        needsDisplay = true
      }
      return
    }

    let nextHover = captureRectForWindowPick(at: point)?.standardized.integral
    if nextHover != windowCaptureHoverRect {
      windowCaptureHoverRect = nextHover
      needsDisplay = true
    }
  }

  func updateWindowCaptureHover(atScreenPoint screenPoint: CGPoint?) {
    guard let screenPoint else {
      updateWindowCaptureHover(at: nil)
      return
    }
    updateWindowCaptureHover(at: localPoint(fromScreenPoint: screenPoint))
  }

  func captureRectForWindowPick(atScreenPoint screenPoint: CGPoint) -> CGRect? {
    guard let localPoint = localPoint(fromScreenPoint: screenPoint) else {
      return nil
    }
    return captureRectForWindowPick(at: localPoint)
  }

  func syncLiveCaptureTargetPickingState() {
    let shouldPassThrough = mode == .editing && (windowCapturePickPending || screenCapturePickPending)

    guard let hostWindow = window else {
      teardownGlobalTargetPickMonitors()
      return
    }

    hostWindow.ignoresMouseEvents = shouldPassThrough

    if shouldPassThrough {
      installGlobalTargetPickMonitors()
      if windowCapturePickPending {
        updateWindowCaptureHover(atScreenPoint: NSEvent.mouseLocation)
      } else {
        updateWindowCaptureHover(at: nil)
      }
      if selectedCaptureMode == .screen || selectedCaptureMode == .window {
        Self.captureCameraCursor.set()
      }
      needsLayout = true
      needsDisplay = true
    } else {
      teardownGlobalTargetPickMonitors()
      updateWindowCaptureHover(at: nil)
      window?.invalidateCursorRects(for: self)
    }
  }

  func installGlobalTargetPickMonitors() {
    if globalMouseMovedMonitor == nil {
      globalMouseMovedMonitor = NSEvent.addGlobalMonitorForEvents(
        matching: [.mouseMoved, .leftMouseDragged]
      ) { [weak self] event in
        let screenPoint = event.locationInWindow
        Task { @MainActor [weak self, screenPoint] in
          self?.handleGlobalTargetPickMouseMove(screenPoint: screenPoint)
        }
      }
    }

    if globalMouseDownMonitor == nil {
      globalMouseDownMonitor = NSEvent.addGlobalMonitorForEvents(
        matching: [.leftMouseDown]
      ) { [weak self] event in
        let screenPoint = event.locationInWindow
        Task { @MainActor [weak self, screenPoint] in
          self?.handleGlobalTargetPickClick(screenPoint: screenPoint)
        }
      }
    }
  }

  func teardownGlobalTargetPickMonitors() {
    if let globalMouseMovedMonitor {
      NSEvent.removeMonitor(globalMouseMovedMonitor)
      self.globalMouseMovedMonitor = nil
    }

    if let globalMouseDownMonitor {
      NSEvent.removeMonitor(globalMouseDownMonitor)
      self.globalMouseDownMonitor = nil
    }
  }

  func handleGlobalTargetPickMouseMove(screenPoint: CGPoint) {
    guard mode == .editing else {
      return
    }
    guard windowCapturePickPending || screenCapturePickPending else {
      return
    }

    if windowCapturePickPending {
      updateWindowCaptureHover(atScreenPoint: screenPoint)
    }

    if selectedCaptureMode == .screen || selectedCaptureMode == .window {
      Self.captureCameraCursor.set()
    }
  }

  func handleGlobalTargetPickClick(screenPoint: CGPoint) {
    guard mode == .editing else {
      return
    }

    if windowCapturePickPending {
      guard let windowRect = captureRectForWindowPick(atScreenPoint: screenPoint) else {
        NSSound.beep()
        return
      }
      if applyCaptureRect(windowRect, as: .window, rememberAsArea: false),
         selectedCaptureType == .video
      {
        startVideoRecordingFromEditor()
      }
      return
    }

    if screenCapturePickPending {
      if applyCaptureRect(bounds, as: .screen, rememberAsArea: false),
         selectedCaptureType == .video
      {
        startVideoRecordingFromEditor()
      }
    }
  }
}
