import CoreGraphics
import Foundation

/// Computes default overlay frames for recording-preview labels.
enum OverlayLayout {
  /// Keystroke labels sit near the top edge without covering the center of the recording.
  private static let keyLabelTopRatio = 0.07
  /// Text overlays sit slightly lower than keystrokes so the two overlay styles do not visually collide.
  private static let textLabelTopRatio = 0.12
  private static let keyLabelHeightRatio = 0.085
  private static let textLabelHeightRatio = 0.09
  private static let minimumLabelHeight: CGFloat = 34
  private static let maximumKeyLabelHeight: CGFloat = 58
  private static let maximumTextLabelHeight: CGFloat = 62
  private static let keyLabelWidthPerCharacter: CGFloat = 18
  private static let textLabelWidthPerCharacter: CGFloat = 14
  private static let minimumKeyLabelWidth: CGFloat = 84
  private static let minimumTextLabelWidth: CGFloat = 90
  private static let keyLabelMaximumWidthRatio = 0.72
  private static let textLabelMaximumWidthRatio = 0.78
  private static let minimumKeyLabelY: CGFloat = 18
  private static let minimumTextLabelY: CGFloat = 20
  private static let keyLabelFontRatio = 0.46
  private static let textLabelFontRatio = 0.42
  private static let minimumKeyLabelFontSize: CGFloat = 16
  private static let minimumTextLabelFontSize: CGFloat = 15

  static func keyLabel(renderSize: CGSize, charCount: Int) -> OverlayLabelLayout? {
    guard renderSize.width.isFinite, renderSize.height.isFinite, renderSize.width > 0, renderSize.height > 0, charCount >= 0 else {
      return nil
    }
    let height = min(max(renderSize.height * keyLabelHeightRatio, minimumLabelHeight), maximumKeyLabelHeight)
    let width = min(max(CGFloat(charCount) * keyLabelWidthPerCharacter, minimumKeyLabelWidth), renderSize.width * keyLabelMaximumWidthRatio)
    return OverlayLabelLayout(
      width: max(1, width),
      height: height,
      y: max(renderSize.height * keyLabelTopRatio, minimumKeyLabelY),
      fontSize: max(height * keyLabelFontRatio, minimumKeyLabelFontSize)
    )
  }

  static func textLabel(renderSize: CGSize, charCount: Int) -> OverlayLabelLayout? {
    guard renderSize.width.isFinite, renderSize.height.isFinite, renderSize.width > 0, renderSize.height > 0, charCount >= 0 else {
      return nil
    }
    let height = min(max(renderSize.height * textLabelHeightRatio, minimumLabelHeight), maximumTextLabelHeight)
    let width = min(max(CGFloat(charCount) * textLabelWidthPerCharacter, minimumTextLabelWidth), renderSize.width * textLabelMaximumWidthRatio)
    return OverlayLabelLayout(
      width: max(1, width),
      height: height,
      y: max(renderSize.height * textLabelTopRatio, minimumTextLabelY),
      fontSize: max(height * textLabelFontRatio, minimumTextLabelFontSize)
    )
  }

  static func clipWindow(
    clipStartSeconds: Double,
    clipEndSeconds: Double,
    trimStartSeconds: Double,
    minVisibleSeconds: Double = Double(textMinimumVisibleSeconds)
  ) -> OverlayClipWindow? {
    guard clipStartSeconds.isFinite, clipEndSeconds.isFinite, trimStartSeconds.isFinite, minVisibleSeconds.isFinite else {
      return nil
    }
    let start = max(0, clipStartSeconds - trimStartSeconds)
    let end = max(start, clipEndSeconds - trimStartSeconds)
    guard end - start >= max(0, minVisibleSeconds) else {
      return nil
    }
    return OverlayClipWindow(startSeconds: start, endSeconds: end, fadeDurationSeconds: max(end - start, 1.0))
  }
}
