import Carbon
import Foundation

final class GlobalHotKeyManager {
  private var hotKeyRef: EventHotKeyRef?
  private var eventHandlerRef: EventHandlerRef?

  var onTrigger: (() -> Void)?

  private let hotKeySignature: OSType = 0x56535653 // "VSVS"
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
      signature: hotKeySignature,
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
      keyCode: UInt32(kVK_ANSI_2),
      modifiers: UInt32(cmdKey | shiftKey)
    )
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

    if eventHotKeyID.signature == manager.hotKeySignature && eventHotKeyID.id == manager.hotKeyIdentifier {
      let runLoop = CFRunLoopGetMain()
      CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) {
        manager.onTrigger?()
      }
      CFRunLoopWakeUp(runLoop)
    }

    return noErr
  }
}
