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

  func smartWindowRectForInitialSelection(at point: CGPoint) -> CGRect? {
    guard mode == .selecting, settings.captureSmartWindowSelectionEnabled, !smartDragActivated else {
      return nil
    }
    guard !captureTypeHost.frame.contains(point) else {
      return nil
    }
    return captureRectForWindowPick(at: point)?.standardized.integral
  }

  func updateSmartWindowHover(at point: CGPoint?) {
    guard mode == .selecting, settings.captureSmartWindowSelectionEnabled, !smartDragActivated, let point else {
      if smartWindowHoverRect != nil {
        smartWindowHoverRect = nil
        needsLayout = true
        needsDisplay = true
      }
      return
    }

    let nextHover = smartWindowRectForInitialSelection(at: point)
    if nextHover != smartWindowHoverRect {
      smartWindowHoverRect = nextHover
      needsLayout = true
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
    let targetPickActive = mode == .editing && (windowCapturePickPending || screenCapturePickPending)

    guard let hostWindow = window else {
      return
    }

    // Keep target-pick clicks in the overlay so the underlying app cannot steal keyboard focus.
    hostWindow.ignoresMouseEvents = false

    if targetPickActive {
      if windowCapturePickPending {
        updateWindowCaptureHover(atScreenPoint: NSEvent.mouseLocation)
      } else {
        updateWindowCaptureHover(at: nil)
      }
      applyEditingHoverCursor(at: localPoint(fromScreenPoint: NSEvent.mouseLocation))
      needsLayout = true
      needsDisplay = true
    } else {
      updateWindowCaptureHover(at: nil)
      window?.invalidateCursorRects(for: self)
    }
  }
}
