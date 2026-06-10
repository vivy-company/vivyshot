import CoreGraphics
import Foundation

struct ScreenshotStatisticsCompletionContext {
  let captureID: String
  let startedAt: Date
}

@MainActor
extension RegionSelectionView {
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
      await statisticsStore.recordScreenshotCaptured(
        captureID: captureID,
        occurredAt: occurredAt,
        bytesProduced: bytesProduced
      )
    }
  }

  func currentScreenshotStatisticsCompletionContext() -> ScreenshotStatisticsCompletionContext? {
    guard let captureID = currentScreenshotCaptureID, let startedAt = screenshotEditorEnteredAt else {
      return nil
    }
    return ScreenshotStatisticsCompletionContext(captureID: captureID, startedAt: startedAt)
  }

  func recordScreenshotStatisticsCompletionIfNeeded(
    _ context: ScreenshotStatisticsCompletionContext?,
    finishedAt: Date
  ) {
    guard let context else {
      return
    }
    Task {
      await statisticsStore.recordScreenshotSessionCompleted(
        captureID: context.captureID,
        startedAt: context.startedAt,
        finishedAt: finishedAt
      )
    }
  }

  func recordStandaloneScreenshotCapture(_ image: CGImage, occurredAt: Date = Date()) {
    let captureID = UUID().uuidString
    let bytesProduced = Int64(ScreenshotImage.encode(image, format: .png, jpegQuality: 100)?.count ?? 0)
    Task {
      await statisticsStore.recordScreenshotCaptured(
        captureID: captureID,
        occurredAt: occurredAt,
        bytesProduced: bytesProduced
      )
    }
  }
}
