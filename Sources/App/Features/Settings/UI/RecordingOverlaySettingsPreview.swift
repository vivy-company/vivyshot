import AppKit
import SwiftUI

enum RecordingOverlaySettingsPreviewKind: String {
  case webcam
  case keystroke
}

@MainActor
final class RecordingOverlaySettingsPreviewCoordinator {
  private var controllers: [RecordingOverlaySettingsPreviewKind: RecordingOverlaySettingsPreviewController] = [:]

  func show(
    _ kind: RecordingOverlaySettingsPreviewKind,
    settings: AppSettings,
    onClose: @escaping (RecordingOverlaySettingsPreviewKind) -> Void
  ) {
    close(kind)
    let controller = RecordingOverlaySettingsPreviewController(kind: kind, settings: settings) { [weak self] closedKind in
      self?.controllers[closedKind] = nil
      onClose(closedKind)
    }
    controllers[kind] = controller
    controller.show()
  }

  func close(_ kind: RecordingOverlaySettingsPreviewKind) {
    controllers.removeValue(forKey: kind)?.close()
  }

  func closeAll() {
    let activeControllers = Array(controllers.values)
    controllers.removeAll()
    for controller in activeControllers {
      controller.close()
    }
  }
}
