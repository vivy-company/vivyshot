import AppKit

enum PostRecordingSavePanel {
  @MainActor
  static func presentSavePanel(request: PostRecordingSaveRequest) -> URL? {
    let panel = NSSavePanel()
    panel.allowedContentTypes = request.allowedContentTypes
    panel.nameFieldStringValue = request.defaultName
    panel.directoryURL = request.suggestedDirectory
    panel.canCreateDirectories = true
    panel.isExtensionHidden = false
    NSApp.activate(ignoringOtherApps: true)
    panel.level = .floating
    panel.center()
    panel.orderFrontRegardless()
    guard panel.runModal() == .OK else {
      return nil
    }
    return panel.url
  }
}
