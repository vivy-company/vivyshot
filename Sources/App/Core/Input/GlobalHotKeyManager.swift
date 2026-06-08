import Carbon
import Foundation

/// Carbon hotkey bridge for the global capture shortcut.
final class GlobalHotKeyManager {
  private var hotKeyRef: EventHotKeyRef?
  private var eventHandlerRef: EventHandlerRef?

  var onTrigger: (() -> Void)?

  private static let hotKeySignature: OSType = fourCharacterCode("VSVS")
  private let hotKeyIdentifier: UInt32 = 1

  deinit {
    unregister()
  }

  func registerHotKey(keyCode: UInt32, modifiers: UInt32) -> Bool {
    unregister()

    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )

    let handlerStatus = InstallEventHandler(
      GetEventDispatcherTarget(),
      Self.hotKeyHandler,
      1,
      &eventType,
      UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
      &eventHandlerRef
    )

    guard handlerStatus == noErr else {
      return false
    }

    let hotKeyID = EventHotKeyID(
      signature: Self.hotKeySignature,
      id: hotKeyIdentifier
    )

    let registerStatus = RegisterEventHotKey(
      keyCode,
      modifiers,
      hotKeyID,
      GetEventDispatcherTarget(),
      0,
      &hotKeyRef
    )

    if registerStatus != noErr {
      NSLog("[VivyShot] RegisterEventHotKey failed: \(registerStatus)")
      unregister()
      return false
    }

    return true
  }

  func registerDefaultHotKey() -> Bool {
    registerHotKey(
      keyCode: UInt32(kVK_ANSI_C),
      modifiers: UInt32(cmdKey | shiftKey)
    )
  }

  private static func fourCharacterCode(_ string: StaticString) -> OSType {
    let bytes = string.utf8Start
    return OSType(bytes[0]) << 24
      | OSType(bytes[1]) << 16
      | OSType(bytes[2]) << 8
      | OSType(bytes[3])
  }

  func unregister() {
    if let hotKeyRef {
      UnregisterEventHotKey(hotKeyRef)
      self.hotKeyRef = nil
    }

    if let eventHandlerRef {
      RemoveEventHandler(eventHandlerRef)
      self.eventHandlerRef = nil
    }
  }

  private static let hotKeyHandler: EventHandlerUPP = { _, eventRef, userData in
    guard let userData, let eventRef else {
      return noErr
    }

    let manager = Unmanaged<GlobalHotKeyManager>
      .fromOpaque(userData)
      .takeUnretainedValue()

    var eventHotKeyID = EventHotKeyID()
    let status = GetEventParameter(
      eventRef,
      EventParamName(kEventParamDirectObject),
      EventParamType(typeEventHotKeyID),
      nil,
      MemoryLayout<EventHotKeyID>.size,
      nil,
      &eventHotKeyID
    )

    guard status == noErr else {
      return noErr
    }

    if eventHotKeyID.signature == GlobalHotKeyManager.hotKeySignature && eventHotKeyID.id == manager.hotKeyIdentifier {
      let runLoop = CFRunLoopGetMain()
      CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) {
        manager.onTrigger?()
      }
      CFRunLoopWakeUp(runLoop)
    }

    return noErr
  }
}
