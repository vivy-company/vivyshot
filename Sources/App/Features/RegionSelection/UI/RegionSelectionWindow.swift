import AppKit
import Carbon

enum SelectionCommand {
  case cancel
  case undo
  case redo
  case copy
  case save
  case addStitchSegment
  case resetStitch
  case zoomIn
  case zoomOut
  case zoomReset
  case selectTool(index: Int)
  case cycleTools(reverse: Bool)
  case cycleCaptureType
  case cycleCaptureModes(reverse: Bool)
  case selectCaptureMode(CaptureMode)
  case toggleVideoSystemAudio
  case toggleVideoMicrophone
  case toggleVideoWebcam
  case toggleVideoMouseClicks
  case toggleVideoKeystrokes
  case cycleVideoCountdown
  case toggleVideoRecording
  case performDefaultCaptureAction
}

@MainActor
protocol SelectionCommandHandling: AnyObject {
  func handleSelectionCommand(_ command: SelectionCommand) -> Bool
}

final class RegionSelectionWindow: NSPanel {
  weak var commandHandler: SelectionCommandHandling?
  var passthroughActivationApp: NSRunningApplication?
  var passesEventsThrough = false {
    didSet {
      ignoresMouseEvents = passesEventsThrough
      if passesEventsThrough, isKeyWindow {
        resignKey()
      }
      if passesEventsThrough {
        passthroughActivationApp?.activate(options: [])
      }
    }
  }

  // Native Liquid Glass renders its dark variant correctly here but is washed-out/white in Light
  // Aqua inside this borderless screen-saver-level panel. Pin every overlay window to dark so the
  // glass chrome is consistent and legible regardless of the system theme.
  private static let overlayAppearance = NSAppearance(named: .darkAqua)

  override init(
    contentRect: NSRect,
    styleMask style: NSWindow.StyleMask,
    backing backingStoreType: NSWindow.BackingStoreType,
    defer flag: Bool
  ) {
    super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
    appearance = Self.overlayAppearance
  }

  override var canBecomeKey: Bool { !passesEventsThrough }
  override var canBecomeMain: Bool { !passesEventsThrough }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if handleCommandShortcuts(event) {
      return true
    }
    return super.performKeyEquivalent(with: event)
  }

  override func keyDown(with event: NSEvent) {
    if event.keyCode == 53 { // Esc
      _ = handle(.cancel)
      return
    }
    if isReturnKeyEvent(event), handle(.performDefaultCaptureAction) {
      return
    }
    if event.keyCode == UInt16(kVK_Tab) {
      let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
      let allowedFlags: NSEvent.ModifierFlags = [.shift, .control]
      if flags.subtracting(allowedFlags).isEmpty {
        if flags.contains(.control) {
          let reverse = flags.contains(.shift)
          if handle(.cycleCaptureModes(reverse: reverse)) {
            return
          }
        } else if flags.contains(.shift) {
          if handle(.cycleCaptureType) {
            return
          }
        } else if handle(.cycleTools(reverse: false)) {
          return
        }
      }
    }
    if handleCommandShortcuts(event) {
      return
    }
    super.keyDown(with: event)
  }

  private func handleCommandShortcuts(_ event: NSEvent) -> Bool {
    guard event.type == .keyDown else {
      return false
    }

    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    guard flags.contains(.command) else {
      return false
    }

    let allowedFlags: NSEvent.ModifierFlags = [.command, .shift, .option]
    if !flags.subtracting(allowedFlags).isEmpty {
      return false
    }

    if flags == .command,
       let index = shortcutIndexForToolSelection(from: event)
    {
      if handle(.selectTool(index: index)) {
        return true
      }
    }

    if flags == [.command, .option] {
      switch event.keyCode {
      case UInt16(kVK_ANSI_A):
        return handle(.toggleVideoSystemAudio)
      case UInt16(kVK_ANSI_M):
        return handle(.toggleVideoMicrophone)
      case UInt16(kVK_ANSI_W):
        return handle(.toggleVideoWebcam)
      case UInt16(kVK_ANSI_L):
        return handle(.toggleVideoMouseClicks)
      case UInt16(kVK_ANSI_K):
        return handle(.toggleVideoKeystrokes)
      case UInt16(kVK_ANSI_T):
        return handle(.cycleVideoCountdown)
      case UInt16(kVK_ANSI_R):
        return handle(.toggleVideoRecording)
      default:
        break
      }
    }

    switch event.keyCode {
    case UInt16(kVK_ANSI_Z):
      if flags == [.command, .shift] {
        return handle(.redo)
      }
      if flags == .command {
        return handle(.undo)
      }
    case UInt16(kVK_ANSI_C):
      if flags == .command {
        return handle(.copy)
      }
    case UInt16(kVK_ANSI_S):
      if flags == .command {
        return handle(.save)
      }
    case UInt16(kVK_ANSI_N):
      if flags == .command {
        return handle(.addStitchSegment)
      }
    case UInt16(kVK_ANSI_R):
      if flags == .command {
        return handle(.resetStitch)
      }
    case UInt16(kVK_ANSI_Equal), UInt16(kVK_ANSI_KeypadPlus):
      if flags == .command || flags == [.command, .shift] {
        return handle(.zoomIn)
      }
    case UInt16(kVK_ANSI_Minus), UInt16(kVK_ANSI_KeypadMinus):
      if flags == .command {
        return handle(.zoomOut)
      }
    case UInt16(kVK_ANSI_0), UInt16(kVK_ANSI_Keypad0):
      if flags == .command {
        return handle(.zoomReset)
      }
    default:
      break
    }

    return false
  }

  private func handle(_ command: SelectionCommand) -> Bool {
    commandHandler?.handleSelectionCommand(command) == true
  }

  private func isReturnKeyEvent(_ event: NSEvent) -> Bool {
    guard event.type == .keyDown else {
      return false
    }

    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    let disallowedFlags: NSEvent.ModifierFlags = [.shift, .control, .option, .command]
    guard flags.intersection(disallowedFlags).isEmpty else {
      return false
    }

    switch event.keyCode {
    case UInt16(kVK_Return), UInt16(kVK_ANSI_KeypadEnter):
      return true
    default:
      return false
    }
  }

  private func shortcutIndexForToolSelection(from event: NSEvent) -> Int? {
    let keyCode = event.keyCode

    if keyCode >= UInt16(kVK_ANSI_1), keyCode <= UInt16(kVK_ANSI_9) {
      return Int(keyCode - UInt16(kVK_ANSI_1) + 1)
    }

    if keyCode >= UInt16(kVK_ANSI_Keypad1), keyCode <= UInt16(kVK_ANSI_Keypad9) {
      return Int(keyCode - UInt16(kVK_ANSI_Keypad1) + 1)
    }

    if let chars = event.charactersIgnoringModifiers,
       let value = Int(chars),
       (1...9).contains(value)
    {
      return value
    }

    return nil
  }
}
