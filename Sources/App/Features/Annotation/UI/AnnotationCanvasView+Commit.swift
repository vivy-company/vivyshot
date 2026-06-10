import CoreGraphics

@MainActor
extension AnnotationCanvasView {
  func commitDrawingGesture(
    committedViewRect: CGRect?,
    committedViewLine: (CGPoint, CGPoint)?,
    committedViewPoint: CGPoint?
  ) {
    switch tool {
    case .move:
      return
    case .rect:
      commitRectGesture(committedViewRect, as: .rect)
    case .filledRect:
      commitRectGesture(committedViewRect, as: .filledRect)
    case .circle:
      commitRectGesture(committedViewRect, as: .circle)
    case .filledCircle:
      commitRectGesture(committedViewRect, as: .filledCircle)
    case .line:
      commitLineGesture(committedViewLine, as: .line)
    case .arrow:
      commitLineGesture(committedViewLine, as: .arrow)
    case .paint:
      return
    case .text:
      guard let pointInView = committedViewPoint,
            let imagePoint = imagePointFromViewPoint(pointInView) else {
        return
      }
      beginInlineTextEditor(at: pointInView, imagePoint: imagePoint)
    case .pixelate:
      commitRectGesture(committedViewRect, as: .pixelate)
    case .blur:
      commitRectGesture(committedViewRect, as: .blur)
    }
  }

  private func commitRectGesture(_ viewRect: CGRect?, as commitKind: RectCommitKind) {
    guard let viewRect, let imageRect = imageRectFromViewRect(viewRect) else {
      return
    }
    switch commitKind {
    case .rect:
      delegate?.annotationCanvasView(self, didCommit: .rect(imageRect))
    case .filledRect:
      delegate?.annotationCanvasView(self, didCommit: .filledRect(imageRect))
    case .circle:
      delegate?.annotationCanvasView(self, didCommit: .circle(imageRect))
    case .filledCircle:
      delegate?.annotationCanvasView(self, didCommit: .filledCircle(imageRect))
    case .pixelate:
      delegate?.annotationCanvasView(self, didCommit: .pixelate(imageRect))
    case .blur:
      delegate?.annotationCanvasView(self, didCommit: .blur(imageRect))
    }
  }

  private func commitLineGesture(_ viewLine: (CGPoint, CGPoint)?, as commitKind: LineCommitKind) {
    guard let (start, end) = viewLine,
          let imageStart = imagePointFromViewPoint(start),
          let imageEnd = imagePointFromViewPoint(end) else {
      return
    }
    switch commitKind {
    case .line:
      delegate?.annotationCanvasView(self, didCommit: .line(imageStart, imageEnd))
    case .arrow:
      delegate?.annotationCanvasView(self, didCommit: .arrow(imageStart, imageEnd))
    }
  }
}

private enum RectCommitKind {
  case rect
  case filledRect
  case circle
  case filledCircle
  case pixelate
  case blur
}

private enum LineCommitKind {
  case line
  case arrow
}
