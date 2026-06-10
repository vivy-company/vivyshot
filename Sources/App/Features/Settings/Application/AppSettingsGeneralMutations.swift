import AppKit
import Carbon

@MainActor
extension AppSettings {
  func setCaptureShortcut(
    keyCode: UInt32,
    command: Bool,
    shift: Bool,
    option: Bool,
    control: Bool
  ) {
    let changed = captureKeyCode != keyCode
      || captureUseCommand != command
      || captureUseShift != shift
      || captureUseOption != option
      || captureUseControl != control

    guard changed else {
      return
    }

    captureKeyCode = keyCode
    captureUseCommand = command
    captureUseShift = shift
    captureUseOption = option
    captureUseControl = control
    persistCaptureShortcut()
  }

  func setCaptureShortcut(keyCode: UInt32, modifierFlags: NSEvent.ModifierFlags) {
    let flags = modifierFlags.intersection(.deviceIndependentFlagsMask)
    setCaptureShortcut(
      keyCode: keyCode,
      command: flags.contains(.command),
      shift: flags.contains(.shift),
      option: flags.contains(.option),
      control: flags.contains(.control)
    )
  }

  func setCaptureKeyCode(_ keyCode: UInt32) {
    setCaptureShortcut(
      keyCode: keyCode,
      command: captureUseCommand,
      shift: captureUseShift,
      option: captureUseOption,
      control: captureUseControl
    )
  }

  func setCaptureModifierCommand(_ enabled: Bool) {
    setCaptureShortcut(
      keyCode: captureKeyCode,
      command: enabled,
      shift: captureUseShift,
      option: captureUseOption,
      control: captureUseControl
    )
  }

  func setCaptureModifierShift(_ enabled: Bool) {
    setCaptureShortcut(
      keyCode: captureKeyCode,
      command: captureUseCommand,
      shift: enabled,
      option: captureUseOption,
      control: captureUseControl
    )
  }

  func setCaptureModifierOption(_ enabled: Bool) {
    setCaptureShortcut(
      keyCode: captureKeyCode,
      command: captureUseCommand,
      shift: captureUseShift,
      option: enabled,
      control: captureUseControl
    )
  }

  func setCaptureModifierControl(_ enabled: Bool) {
    setCaptureShortcut(
      keyCode: captureKeyCode,
      command: captureUseCommand,
      shift: captureUseShift,
      option: captureUseOption,
      control: enabled
    )
  }

  func resetCaptureShortcut() {
    setCaptureShortcut(
      keyCode: UInt32(kVK_ANSI_C),
      command: true,
      shift: true,
      option: false,
      control: false
    )
  }

  func setCaptureShowHelper(_ enabled: Bool) {
    guard captureShowHelper != enabled else {
      return
    }
    captureShowHelper = enabled
    persistCaptureHelperSetting()
  }

  func setCaptureSmartWindowSelectionEnabled(_ enabled: Bool) {
    guard captureSmartWindowSelectionEnabled != enabled else {
      return
    }
    captureSmartWindowSelectionEnabled = enabled
    persistCaptureSmartWindowSelectionSetting()
  }

  func setDefaultCaptureType(_ type: CaptureContentType) {
    guard defaultCaptureType != type else {
      return
    }
    defaultCaptureType = type
    persistVideoCaptureSettings()
  }

  func setAppLanguage(_ language: AppLanguage) {
    guard appLanguage != language else {
      return
    }
    appLanguage = language
    persistAppLanguage()
  }
}
