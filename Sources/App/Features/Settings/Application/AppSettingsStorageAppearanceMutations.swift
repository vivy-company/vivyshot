import AppKit
import Foundation

@MainActor
extension AppSettings {
  func setDefaultSaveDirectory(_ url: URL?) {
    let normalizedPath = url?.standardizedFileURL.path ?? ""
    guard defaultSaveDirectoryPath != normalizedPath else {
      return
    }
    defaultSaveDirectoryPath = normalizedPath
    if normalizedPath.isEmpty {
      alwaysSaveToDefaultDirectory = false
      saveCopiedScreenshotsToDefaultDirectory = false
    }
    persistSaveSettings()
  }

  func setAlwaysSaveToDefaultDirectory(_ enabled: Bool) {
    let normalizedEnabled = enabled && !defaultSaveDirectoryPath.isEmpty
    guard alwaysSaveToDefaultDirectory != normalizedEnabled else {
      return
    }
    alwaysSaveToDefaultDirectory = normalizedEnabled
    persistSaveSettings()
  }

  func setSaveCopiedScreenshotsToDefaultDirectory(_ enabled: Bool) {
    let normalizedEnabled = enabled && !defaultSaveDirectoryPath.isEmpty
    guard saveCopiedScreenshotsToDefaultDirectory != normalizedEnabled else {
      return
    }
    saveCopiedScreenshotsToDefaultDirectory = normalizedEnabled
    persistSaveSettings()
  }

  func setToolbarAccentColor(_ color: NSColor) {
    let normalized = Self.normalizedAccentComponents(from: color)
    let nextRed = Self.clampedUnit(normalized.red)
    let nextGreen = Self.clampedUnit(normalized.green)
    let nextBlue = Self.clampedUnit(normalized.blue)
    let nextAlpha = Self.clampedUnit(normalized.alpha)
    let changed = abs(toolbarAccentRed - nextRed) > .ulpOfOne
      || abs(toolbarAccentGreen - nextGreen) > .ulpOfOne
      || abs(toolbarAccentBlue - nextBlue) > .ulpOfOne
      || abs(toolbarAccentAlpha - nextAlpha) > .ulpOfOne
    guard changed else {
      return
    }
    toolbarAccentRed = nextRed
    toolbarAccentGreen = nextGreen
    toolbarAccentBlue = nextBlue
    toolbarAccentAlpha = nextAlpha
    persistAppearanceSettings()
  }

  func setScreenshotMainAction(_ action: ScreenshotMainAction) {
    guard screenshotMainAction != action else {
      return
    }
    screenshotMainAction = action
    persistAppearanceSettings()
  }

  func setCaptureTransitionStyle(_ style: CaptureTransitionStyle) {
    guard captureTransitionStyle != style else {
      return
    }
    captureTransitionStyle = style
    persistCaptureTransitionSettings()
  }

  func setCaptureTransitionSpeed(_ speed: Double) {
    let clamped = Self.clampedCaptureTransitionSpeed(speed)
    guard abs(captureTransitionSpeed - clamped) > .ulpOfOne else {
      return
    }
    captureTransitionSpeed = clamped
    persistCaptureTransitionSettings()
  }

  func setCaptureTransitionIntensity(_ intensity: Double) {
    let clamped = Self.clampedCaptureTransitionIntensity(intensity)
    guard abs(captureTransitionIntensity - clamped) > .ulpOfOne else {
      return
    }
    captureTransitionIntensity = clamped
    persistCaptureTransitionSettings()
  }

  func resetCaptureTransitionSettings() {
    captureTransitionStyle = .ripple
    captureTransitionSpeed = 1.25
    captureTransitionIntensity = 0.72
    persistCaptureTransitionSettings()
  }
}
