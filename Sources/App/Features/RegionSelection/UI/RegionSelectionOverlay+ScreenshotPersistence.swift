import AppKit
import CoreGraphics
import Foundation
import UniformTypeIdentifiers

@MainActor
extension RegionSelectionView {
  func presentSavePanel(
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

    if saveImageToDisk(image, to: url) {
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

    return ScreenshotImage.crop(image, imageRect: cropRect) ?? image.cropping(to: cropRect) ?? image
  }

  func encodedImageForCurrentSelection(format: ImageEncodeFormat, jpegQuality: Int) -> Data? {
    guard let image = canvasView.image else {
      return nil
    }

    if let cropRect = exportCropRectForCurrentSelection(in: image) {
      if let encoded = ScreenshotImage.encode(
        image,
        imageRect: cropRect,
        format: format,
        jpegQuality: jpegQuality
      ) {
        return encoded
      }

      guard let cropped = ScreenshotImage.crop(image, imageRect: cropRect) ?? image.cropping(to: cropRect) else {
        return nil
      }
      return ScreenshotImage.encode(cropped, format: format, jpegQuality: jpegQuality)
    }

    return ScreenshotImage.encode(image, format: format, jpegQuality: jpegQuality)
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
    return saveImageToDisk(image, to: destination, showsToast: false)
  }

  func showCopyResultToast(autoSaveResult: Bool?) {
    switch autoSaveResult {
    case .some(true):
      toastPresenter.show(String(localized: "Copied and Saved", bundle: AppLocalizer.shared.bundle))
    case .some(false):
      toastPresenter.show(String(localized: "Copied. Auto-save failed.", bundle: AppLocalizer.shared.bundle))
    case .none:
      toastPresenter.show(String(localized: "Copied to Clipboard", bundle: AppLocalizer.shared.bundle))
    }
  }

  func exportCropRectForCurrentSelection(in image: CGImage) -> CGRect? {
    guard !stitchState.modeEnabled else {
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

  func saveImageToDisk(_ image: CGImage, to url: URL, showsToast: Bool = true) -> Bool {
    let ext = url.pathExtension.lowercased()
    let extType = UTType(filenameExtension: ext)
    let selectedType: UTType = (extType == .jpeg || ext == "jpg") ? .jpeg : .png
    let targetURL: URL

    if ext.isEmpty, let preferredExt = selectedType.preferredFilenameExtension {
      targetURL = url.appendingPathExtension(preferredExt)
    } else {
      targetURL = url
    }

    let format: ImageEncodeFormat = selectedType == .jpeg ? .jpeg : .png
    let quality = selectedType == .jpeg ? 88 : 100
    guard let encoded = ScreenshotImage.encode(image, format: format, jpegQuality: quality) else {
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
      toastPresenter.show(String(localized: "Saved", bundle: AppLocalizer.shared.bundle))
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
}
