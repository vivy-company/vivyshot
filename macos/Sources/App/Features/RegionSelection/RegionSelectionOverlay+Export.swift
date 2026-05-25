import AppKit
import CoreGraphics
import Foundation
import UniformTypeIdentifiers

private struct ScreenshotStatisticsCompletionContext {
  let captureID: String
  let startedAt: Date
}

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
      if Self.saveImageToDisk(image, to: destination) {
        recordScreenshotStatisticsCompletionIfNeeded(completionContext, finishedAt: finishedAt)
      }
      return
    }

    let suggestedDirectory = settings.defaultSaveDirectoryURL
    let imageToSave = image
    finishEditing(animatedClose: false)
    Task { @MainActor [imageToSave, suggestedDirectory, completionContext] in
      await Task.yield()
      Self.presentSavePanel(
        for: imageToSave,
        suggestedDirectory: suggestedDirectory
      ) {
        self.recordScreenshotStatisticsCompletionIfNeeded(completionContext, finishedAt: Date())
      }
    }
  }

  static func presentSavePanel(
    for image: CGImage,
    suggestedDirectory: URL?,
    onSuccessfulSave: (() -> Void)? = nil
  ) {
    let panel = NSSavePanel()
    panel.title = "Save Annotation"
    panel.canCreateDirectories = true
    panel.allowedContentTypes = [.png, .jpeg]
    panel.allowsOtherFileTypes = false
    let defaultExt = "png"
    if let directory = suggestedDirectory {
      let suggested = Self.makeAutoSaveURL(in: directory, ext: defaultExt)
      panel.directoryURL = directory
      panel.nameFieldStringValue = suggested.lastPathComponent
    } else {
      panel.nameFieldStringValue = "\(Self.makeTimestampedBaseName()).\(defaultExt)"
    }

    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    NSApp.activate(ignoringOtherApps: true)
    let response = panel.runModal()
    defer {
      panel.orderOut(nil)
      panel.close()
    }

    guard response == .OK, let url = panel.url else {
      return
    }

    if Self.saveImageToDisk(image, to: url) {
      onSuccessfulSave?()
    }
  }

  func exportImageForCurrentSelection() -> CGImage? {
    guard let image = canvasView.image else {
      return nil
    }

    guard let cropRect = exportCropRectForCurrentSelection(in: image) else {
      return image
    }

    return RustCoreBridge.shared.cropImage(image, imageRect: cropRect) ?? image.cropping(to: cropRect) ?? image
  }

  func encodedImageForCurrentSelection(format: RustImageEncodeFormat, jpegQuality: Int) -> Data? {
    guard let image = canvasView.image else {
      return nil
    }

    if let cropRect = exportCropRectForCurrentSelection(in: image) {
      if let encoded = RustCoreBridge.shared.encodeImage(
        image,
        imageRect: cropRect,
        format: format,
        jpegQuality: jpegQuality
      ) {
        return encoded
      }

      guard let cropped = RustCoreBridge.shared.cropImage(image, imageRect: cropRect) ?? image.cropping(to: cropRect) else {
        return nil
      }
      return RustCoreBridge.shared.encodeImage(cropped, format: format, jpegQuality: jpegQuality)
    }

    return RustCoreBridge.shared.encodeImage(image, format: format, jpegQuality: jpegQuality)
  }

  func copyImageToPasteboard(_ image: CGImage, encodedPNG: Data?) -> Bool {
    autoreleasepool { () -> Bool in
      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()

      if let encodedPNG {
        let item = NSPasteboardItem()
        item.setData(encodedPNG, forType: .png)
        if pasteboard.writeObjects([item]) {
          return true
        }
      }

      let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
      return pasteboard.writeObjects([nsImage])
    }
  }

  func autoSaveCopiedScreenshot(_ image: CGImage) -> Bool? {
    guard settings.saveCopiedScreenshotsToDefaultDirectory,
          let directory = settings.defaultSaveDirectoryURL
    else {
      return nil
    }

    let destination = Self.makeAutoSaveURL(in: directory, ext: "png")
    return Self.saveImageToDisk(image, to: destination, showsToast: false)
  }

  func showCopyResultToast(autoSaveResult: Bool?) {
    switch autoSaveResult {
    case .some(true):
      TransientToast.show(String(localized: "Copied and Saved", bundle: AppLocalizer.shared.bundle))
    case .some(false):
      TransientToast.show(String(localized: "Copied. Auto-save failed.", bundle: AppLocalizer.shared.bundle))
    case .none:
      TransientToast.show(String(localized: "Copied to Clipboard", bundle: AppLocalizer.shared.bundle))
    }
  }

  func exportCropRectForCurrentSelection(in image: CGImage) -> CGRect? {
    guard !stitchModeEnabled else {
      return nil
    }
    guard let selection = committedSelectionRect?.standardized else {
      return nil
    }

    let selectionInCanvas = convert(selection, to: canvasView)
    guard let imageRect = canvasView.exportImageRect(fromViewRect: selectionInCanvas) else {
      return nil
    }

    let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    let cropRect = imageRect.standardized.integral.intersection(imageBounds)
    guard !cropRect.isNull, cropRect.width >= 1, cropRect.height >= 1 else {
      return nil
    }
    if cropRect.equalTo(imageBounds) {
      return nil
    }
    return cropRect
  }

  func ensureCaptureTargetIsResolved(forRecording: Bool) -> Bool {
    if !forRecording, resolvePendingCaptureTargetForStillShortcut() {
      return true
    }

    if selectedCaptureMode == .window, windowCapturePickPending {
      NSSound.beep()
      if forRecording {
        TransientToast.show("Click a window to start recording")
      } else {
        TransientToast.show("Click a window to capture first")
      }
      return false
    }

    if selectedCaptureMode == .screen, screenCapturePickPending {
      NSSound.beep()
      if forRecording {
        TransientToast.show("Click anywhere to start full-screen recording")
      } else {
        TransientToast.show("Click anywhere to capture full screen")
      }
      return false
    }

    return true
  }

  func resolvePendingVideoCaptureTargetForDefaultAction() -> Bool {
    guard mode == .editing, selectedCaptureType == .video else {
      return true
    }

    if selectedCaptureMode == .screen, screenCapturePickPending {
      return applyCaptureRect(bounds, as: .screen, rememberAsArea: false)
    }

    if selectedCaptureMode == .window, windowCapturePickPending {
      guard let windowRect = captureRectForWindowPick(atScreenPoint: NSEvent.mouseLocation) else {
        NSSound.beep()
        TransientToast.show("Move the pointer over a window to start recording")
        return false
      }
      return applyCaptureRect(windowRect, as: .window, rememberAsArea: false)
    }

    return true
  }

  func resolvePendingCaptureTargetForStillShortcut() -> Bool {
    guard mode == .editing, selectedCaptureType == .screenshot else {
      return false
    }

    if selectedCaptureMode == .screen, screenCapturePickPending {
      return applyCaptureRect(bounds, as: .screen, rememberAsArea: false)
    }

    if selectedCaptureMode == .window, windowCapturePickPending {
      if let windowRect = captureRectForWindowPick(atScreenPoint: NSEvent.mouseLocation) {
        return applyCaptureRect(windowRect, as: .window, rememberAsArea: false)
      }
      return false
    }

    return false
  }

  static func saveImageToDisk(_ image: CGImage, to url: URL, showsToast: Bool = true) -> Bool {
    let ext = url.pathExtension.lowercased()
    let extType = UTType(filenameExtension: ext)
    let selectedType: UTType = (extType == .jpeg || ext == "jpg") ? .jpeg : .png
    let targetURL: URL

    if ext.isEmpty, let preferredExt = selectedType.preferredFilenameExtension {
      targetURL = url.appendingPathExtension(preferredExt)
    } else {
      targetURL = url
    }

    let format: RustImageEncodeFormat = selectedType == .jpeg ? .jpeg : .png
    let quality = selectedType == .jpeg ? 88 : 100
    guard let encoded = RustCoreBridge.shared.encodeImage(image, format: format, jpegQuality: quality) else {
      NSSound.beep()
      return false
    }

    do {
      try encoded.write(to: targetURL, options: .atomic)
    } catch {
      NSSound.beep()
      return false
    }

    if showsToast {
      TransientToast.show(String(localized: "Saved", bundle: AppLocalizer.shared.bundle))
    }
    return true
  }

  static func makeAutoSaveURL(in directory: URL, ext: String) -> URL {
    let baseName = makeTimestampedBaseName()
    let normalizedExt = ext.lowercased()

    var candidate = directory.appendingPathComponent(baseName).appendingPathExtension(normalizedExt)
    var suffix = 2
    while FileManager.default.fileExists(atPath: candidate.path) {
      candidate = directory
        .appendingPathComponent("\(baseName)-\(suffix)")
        .appendingPathExtension(normalizedExt)
      suffix += 1
    }
    return candidate
  }

  static func makeTimestampedBaseName() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
    let timestamp = formatter.string(from: Date())
    return "vivyshot_\(timestamp)"
  }

  func beginScreenshotStatisticsSessionIfNeeded() {
    guard selectedCaptureType == .screenshot else {
      currentScreenshotCaptureID = nil
      screenshotEditorEnteredAt = nil
      return
    }
    guard currentScreenshotCaptureID == nil else {
      return
    }

    let captureID = UUID().uuidString
    currentScreenshotCaptureID = captureID
    screenshotEditorEnteredAt = Date()
    let bytesProduced = Int64(encodedImageForCurrentSelection(format: .png, jpegQuality: 100)?.count ?? 0)
    let occurredAt = screenshotEditorEnteredAt ?? Date()
    Task {
      await CaptureStatisticsStore.shared.recordScreenshotCaptured(
        captureID: captureID,
        occurredAt: occurredAt,
        bytesProduced: bytesProduced
      )
    }
  }

  fileprivate func currentScreenshotStatisticsCompletionContext() -> ScreenshotStatisticsCompletionContext? {
    guard let captureID = currentScreenshotCaptureID, let startedAt = screenshotEditorEnteredAt else {
      return nil
    }
    return ScreenshotStatisticsCompletionContext(captureID: captureID, startedAt: startedAt)
  }

  fileprivate func recordScreenshotStatisticsCompletionIfNeeded(
    _ context: ScreenshotStatisticsCompletionContext?,
    finishedAt: Date
  ) {
    guard let context else {
      return
    }
    Task {
      await CaptureStatisticsStore.shared.recordScreenshotSessionCompleted(
        captureID: context.captureID,
        startedAt: context.startedAt,
        finishedAt: finishedAt
      )
    }
  }

  func recordStandaloneScreenshotCapture(_ image: CGImage, occurredAt: Date = Date()) {
    let captureID = UUID().uuidString
    let bytesProduced = Int64(RustCoreBridge.shared.encodeImage(image, format: .png, jpegQuality: 100)?.count ?? 0)
    Task {
      await CaptureStatisticsStore.shared.recordScreenshotCaptured(
        captureID: captureID,
        occurredAt: occurredAt,
        bytesProduced: bytesProduced
      )
    }
  }
}
