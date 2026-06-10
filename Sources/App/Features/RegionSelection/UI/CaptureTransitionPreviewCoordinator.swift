import AppKit
import ApplicationServices
import CoreGraphics

@MainActor
final class CaptureTransitionPreviewCoordinator {
  private let overlay: RegionSelectionOverlayController
  private var previewTask: Task<Void, Never>?

  init(
    settings: AppSettings,
    storeManager: StoreManager,
    statisticsStore: StatisticsStore,
    toastPresenter: ToastPresenting
  ) {
    overlay = RegionSelectionOverlayController(
      settings: settings,
      storeManager: storeManager,
      statisticsStore: statisticsStore,
      toastPresenter: toastPresenter
    )
  }

  func preview() {
    previewTask?.cancel()

    guard let screen = activeScreenForPreview() else {
      return
    }

    let frame = screen.frame
    previewTask = Task { @MainActor in
      let image = await capturePreviewImage(in: frame) ?? makeFallbackFrozenImage(size: frame.size)
      guard !Task.isCancelled, let image else {
        return
      }
      overlay.previewCaptureTransition(onScreenFrame: frame, frozenImage: image)
    }
  }

  private func activeScreenForPreview() -> NSScreen? {
    DisplayCoordinateConversion.activeScreen(containing: NSEvent.mouseLocation)
  }

  private func capturePreviewImage(in rect: CGRect) async -> CGImage? {
    await ScreenCaptureSnapshot.captureImageIfAvailable(inCocoaScreenRect: rect, requiresPermission: true)
  }

  private func makeFallbackFrozenImage(size: CGSize) -> CGImage? {
    let width = max(2, Int(size.width.rounded()))
    let height = max(2, Int(size.height.rounded()))
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

    guard let context = CGContext(
      data: nil,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: width * 4,
      space: colorSpace,
      bitmapInfo: bitmapInfo
    ) else {
      return nil
    }

    let bounds = CGRect(x: 0, y: 0, width: width, height: height)
    context.setFillColor(NSColor.windowBackgroundColor.cgColor)
    context.fill(bounds)

    let panelRect = bounds.insetBy(dx: bounds.width * 0.18, dy: bounds.height * 0.2)
    context.setFillColor(NSColor.controlBackgroundColor.cgColor)
    context.fill(panelRect)

    context.setFillColor(NSColor.labelColor.withAlphaComponent(0.16).cgColor)
    for index in 0 ..< 7 {
      let row = CGRect(
        x: panelRect.minX + 32,
        y: panelRect.minY + 36 + CGFloat(index) * 36,
        width: panelRect.width * CGFloat(index.isMultiple(of: 2) ? 0.72 : 0.52),
        height: 10
      )
      context.fill(row)
    }

    return context.makeImage()
  }
}
