import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

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

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    guard pasteboard.writeObjects([nsImage]) else {
      NSSound.beep()
      return
    }

    finishEditing()
    TransientToast.show("Copied to Clipboard")
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

    if settings.alwaysSaveToDefaultDirectory,
       let directory = settings.defaultSaveDirectoryURL
    {
      finishEditing(animatedClose: false)
      let destination = Self.makeAutoSaveURL(in: directory, ext: "png")
      Self.saveImageToDisk(image, to: destination)
      return
    }

    let suggestedDirectory = settings.defaultSaveDirectoryURL
    let imageToSave = image
    finishEditing(animatedClose: false)
    Task { @MainActor [imageToSave, suggestedDirectory] in
      await Task.yield()
      Self.presentSavePanel(for: imageToSave, suggestedDirectory: suggestedDirectory)
    }
  }

  static func presentSavePanel(for image: CGImage, suggestedDirectory: URL?) {
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

    Self.saveImageToDisk(image, to: url)
  }

  func exportImageForCurrentSelection() -> CGImage? {
    guard let image = canvasView.image else {
      return nil
    }

    if stitchModeEnabled {
      return image
    }

    guard let selection = committedSelectionRect?.standardized else {
      return image
    }

    let selectionInCanvas = convert(selection, to: canvasView)
    guard let imageRect = canvasView.exportImageRect(fromViewRect: selectionInCanvas) else {
      return image
    }

    let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    let cropRect = imageRect.standardized.integral.intersection(imageBounds)
    guard !cropRect.isNull, cropRect.width >= 1, cropRect.height >= 1 else {
      return image
    }

    return RustCoreBridge.shared.cropImage(image, imageRect: cropRect) ?? image.cropping(to: cropRect) ?? image
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

  static func saveImageToDisk(_ image: CGImage, to url: URL) {
    let ext = url.pathExtension.lowercased()
    let extType = UTType(filenameExtension: ext)
    let selectedType: UTType = (extType == .jpeg || ext == "jpg") ? .jpeg : .png
    let targetURL: URL

    if ext.isEmpty, let preferredExt = selectedType.preferredFilenameExtension {
      targetURL = url.appendingPathExtension(preferredExt)
    } else {
      targetURL = url
    }

    guard let destination = CGImageDestinationCreateWithURL(
      targetURL as CFURL,
      selectedType.identifier as CFString,
      1,
      nil
    ) else {
      NSSound.beep()
      return
    }

    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
      NSSound.beep()
      return
    }

    TransientToast.show("Saved")
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
