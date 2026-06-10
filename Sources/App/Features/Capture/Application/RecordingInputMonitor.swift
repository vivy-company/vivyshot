import AppKit
import ApplicationServices
import AVFoundation
import AVKit
import CoreGraphics
import CoreMedia
import ImageIO
import QuartzCore
import ScreenCaptureKit
import UniformTypeIdentifiers
import VideoToolbox

final class RecordingInputMonitor {
  private let captureRectInScreen: CGRect
  private let monitorsKeystrokes: Bool
  private let monitorsMouseClicks: Bool
  private let onKeyEvent: ((RecordedKeystrokeEvent) -> Void)?
  private let stateLock = NSLock()
  private var captureKeystrokes: Bool
  private var captureMouseClicks: Bool

  private var startUptime: TimeInterval = 0
  private var globalKeyMonitorToken: Any?
  private var localKeyMonitorToken: Any?
  private var globalClickMonitorToken: Any?
  private var localClickMonitorToken: Any?
  private var keyEvents: [RecordedKeystrokeEvent] = []
  private var clickEvents: [RecordedMouseClickEvent] = []
  private var lastKeyEventSignature: (timestampNS: UInt64, token: String)?
  private var lastClickEventSignature: (timestampNS: UInt64, button: UInt32, x: CGFloat, y: CGFloat)?

  init(
    captureRectInScreen: CGRect,
    monitorsKeystrokes: Bool,
    monitorsMouseClicks: Bool,
    captureKeystrokes: Bool,
    captureMouseClicks: Bool,
    onKeyEvent: ((RecordedKeystrokeEvent) -> Void)? = nil
  ) {
    self.captureRectInScreen = captureRectInScreen.standardized
    self.monitorsKeystrokes = monitorsKeystrokes
    self.monitorsMouseClicks = monitorsMouseClicks
    self.captureKeystrokes = captureKeystrokes
    self.captureMouseClicks = captureMouseClicks
    self.onKeyEvent = onKeyEvent
  }

  deinit {
    stopObservers()
  }

  func start() {
    startUptime = ProcessInfo.processInfo.systemUptime

    if monitorsKeystrokes {
      globalKeyMonitorToken = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
        self?.handleKeyDown(event)
      }
      localKeyMonitorToken = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        self?.handleKeyDown(event)
        return event
      }
    }

    if monitorsMouseClicks {
      let clickMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
      globalClickMonitorToken = NSEvent.addGlobalMonitorForEvents(matching: clickMask) { [weak self] event in
        self?.handleMouseDown(event)
      }
      localClickMonitorToken = NSEvent.addLocalMonitorForEvents(matching: clickMask) { [weak self] event in
        self?.handleMouseDown(event)
        return event
      }
    }
  }

  func stop() -> RecordingInputResult {
    stopObservers()
    stateLock.lock()
    defer { stateLock.unlock() }
    return RecordingInputResult(
      keyEvents: keyEvents,
      clickEvents: clickEvents
    )
  }

  func setCaptureKeystrokes(_ enabled: Bool) {
    stateLock.lock()
    captureKeystrokes = enabled
    stateLock.unlock()
  }

  func setCaptureMouseClicks(_ enabled: Bool) {
    stateLock.lock()
    captureMouseClicks = enabled
    stateLock.unlock()
  }

  private func stopObservers() {
    if let globalKeyMonitorToken {
      NSEvent.removeMonitor(globalKeyMonitorToken)
      self.globalKeyMonitorToken = nil
    }

    if let localKeyMonitorToken {
      NSEvent.removeMonitor(localKeyMonitorToken)
      self.localKeyMonitorToken = nil
    }

    if let globalClickMonitorToken {
      NSEvent.removeMonitor(globalClickMonitorToken)
      self.globalClickMonitorToken = nil
    }

    if let localClickMonitorToken {
      NSEvent.removeMonitor(localClickMonitorToken)
      self.localClickMonitorToken = nil
    }
  }

  private func handleKeyDown(_ event: NSEvent) {
    stateLock.lock()
    let shouldCapture = captureKeystrokes
    stateLock.unlock()
    guard shouldCapture else {
      return
    }

    let token = displayToken(for: event)
    guard !token.isEmpty else {
      return
    }
    let timestampNS = elapsedTimestampNS(for: event)
    stateLock.lock()
    defer { stateLock.unlock() }
    if let last = lastKeyEventSignature,
       InputEventNormalizer.isDuplicateKeyEvent(
         lastTimestampNS: last.timestampNS,
         lastToken: last.token,
         timestampNS: timestampNS,
         token: token
       )
    {
      return
    }
    lastKeyEventSignature = (timestampNS: timestampNS, token: token)

    let event = RecordedKeystrokeEvent(
      timestampNS: timestampNS,
      displayToken: token
    )
    keyEvents.append(event)
    onKeyEvent?(event)
  }

  private func handleMouseDown(_ event: NSEvent) {
    stateLock.lock()
    let shouldCapture = captureMouseClicks
    stateLock.unlock()
    guard shouldCapture else {
      return
    }

    guard captureRectInScreen.width > 0, captureRectInScreen.height > 0 else {
      return
    }

    let point = NSEvent.mouseLocation
    guard captureRectInScreen.contains(point) else {
      return
    }

    let nx = (point.x - captureRectInScreen.minX) / captureRectInScreen.width
    let ny = (point.y - captureRectInScreen.minY) / captureRectInScreen.height
    guard let normalized = InputEventNormalizer.normalizeClickPoint(x: nx, y: ny) else {
      return
    }
    let normalizedX = normalized.x
    let normalizedY = normalized.y

    let button: UInt32
    switch event.type {
    case .leftMouseDown:
      button = 0
    case .rightMouseDown:
      button = 1
    default:
      button = 2
    }
    let timestampNS = elapsedTimestampNS(for: event)
    stateLock.lock()
    defer { stateLock.unlock() }
    if let last = lastClickEventSignature,
       InputEventNormalizer.isDuplicateClickEvent(
         lastTimestampNS: last.timestampNS,
         lastButton: last.button,
         lastX: last.x,
         lastY: last.y,
         timestampNS: timestampNS,
         button: button,
         x: normalizedX,
         y: normalizedY
       )
    {
      return
    }
    lastClickEventSignature = (
      timestampNS: timestampNS,
      button: button,
      x: normalizedX,
      y: normalizedY
    )

    clickEvents.append(
      RecordedMouseClickEvent(
        timestampNS: timestampNS,
        normalizedX: normalizedX,
        normalizedY: normalizedY,
        button: button
      )
    )
  }

  private func elapsedTimestampNS(for event: NSEvent) -> UInt64 {
    let elapsed = max(0, event.timestamp - startUptime)
    return UInt64((elapsed * 1_000_000_000).rounded())
  }

  private func displayToken(for event: NSEvent) -> String {
    let modifiers = keyModifierMask(for: event.modifierFlags)
    return InputEventNormalizer.normalizeKeyToken(
      keyCode: event.keyCode,
      modifiers: modifiers,
      characters: event.charactersIgnoringModifiers
    ) ?? ""
  }

  private func keyModifierMask(for flags: NSEvent.ModifierFlags) -> UInt32 {
    var raw: UInt32 = 0
    if flags.contains(.command) {
      raw |= RecordedInputModifierMask.command
    }
    if flags.contains(.shift) {
      raw |= RecordedInputModifierMask.shift
    }
    if flags.contains(.option) {
      raw |= RecordedInputModifierMask.option
    }
    if flags.contains(.control) {
      raw |= RecordedInputModifierMask.control
    }
    return raw
  }
}
