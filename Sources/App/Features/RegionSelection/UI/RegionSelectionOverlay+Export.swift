import AppKit
import CoreGraphics
import Foundation

@MainActor
extension RegionSelectionView {
  func performCopy() {
    canvasView.finishInlineTextEditing(commit: true)
    guard ensureCaptureTargetIsResolved(forRecording: false) else {
      return
    }

    guard let image = exportImageForCurrentSelection() else {
      NSSound.beep()
      return
    }

    let encodedPNG = encodedImageForCurrentSelection(format: .png, jpegQuality: 100)
    let copied = copyImageToPasteboard(image, encodedPNG: encodedPNG)

    guard copied else {
      NSSound.beep()
      return
    }

    let autoSaveResult = autoSaveCopiedScreenshot(image)
    let completionContext = currentScreenshotStatisticsCompletionContext()
    let finishedAt = Date()
    finishEditing(animatedClose: false)
    recordScreenshotStatisticsCompletionIfNeeded(completionContext, finishedAt: finishedAt)
    showCopyResultToast(autoSaveResult: autoSaveResult)
  }

  func performSave() {
    canvasView.finishInlineTextEditing(commit: true)
    guard ensureCaptureTargetIsResolved(forRecording: false) else {
      return
    }

    guard let image = exportImageForCurrentSelection() else {
      NSSound.beep()
      return
    }

    let completionContext = currentScreenshotStatisticsCompletionContext()
    if settings.alwaysSaveToDefaultDirectory,
       let directory = settings.defaultSaveDirectoryURL
    {
      let destination = Self.makeAutoSaveURL(in: directory, ext: "png")
      let finishedAt = Date()
      finishEditing(animatedClose: false)
      if saveImageToDisk(image, to: destination) {
        recordScreenshotStatisticsCompletionIfNeeded(completionContext, finishedAt: finishedAt)
      }
      return
    }

    let suggestedDirectory = settings.defaultSaveDirectoryURL
    let imageToSave = image
    finishEditing(animatedClose: false)
    Task { @MainActor [imageToSave, suggestedDirectory, completionContext] in
      await Task.yield()
      self.presentSavePanel(
        for: imageToSave,
        suggestedDirectory: suggestedDirectory
      ) {
        self.recordScreenshotStatisticsCompletionIfNeeded(completionContext, finishedAt: Date())
      }
    }
  }
}
