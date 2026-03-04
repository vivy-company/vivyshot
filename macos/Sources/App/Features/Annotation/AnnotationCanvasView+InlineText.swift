import AppKit
import CoreGraphics

@MainActor
extension AnnotationCanvasView {
  func finishInlineTextEditing(commit: Bool) {
    guard let inlineTextField else {
      return
    }

    if commit {
      commitInlineTextEditor(text: inlineTextField.stringValue)
    } else {
      removeInlineTextEditor()
    }
  }

  func beginInlineTextEditor(at viewPoint: CGPoint, imagePoint: CGPoint) {
    removeInlineTextEditor()

    let editorWidth: CGFloat = 260
    let editorHeight: CGFloat = max(26, textStyle.fontSize + 12)
    let inset: CGFloat = 8
    let x = max(inset, min(viewPoint.x, bounds.width - editorWidth - inset))
    let y = max(inset, min(viewPoint.y, bounds.height - editorHeight - inset))
    let frame = CGRect(x: x, y: y, width: editorWidth, height: editorHeight)

    let field = InlineTextField(frame: frame)
    field.placeholderString = "Type text and press Return"
    field.onCommit = { [weak self] text in
      self?.commitInlineTextEditor(text: text)
    }
    field.onCancel = { [weak self] in
      self?.removeInlineTextEditor()
    }

    inlineTextAnchorInView = imagePoint
    inlineTextField = field
    addSubview(field)
    updateInlineTextFieldStyle()
    window?.makeFirstResponder(field)
    needsDisplay = true
  }

  func updateInlineTextFieldStyle() {
    guard let inlineTextField else {
      return
    }

    inlineTextField.font = resolvedInlineEditorFont()
    inlineTextField.textColor = textStyle.color
    inlineTextField.backgroundColor = NSColor.black.withAlphaComponent(0.45)
    (inlineTextField as? InlineTextField)?.setInsertionPointColor(textStyle.color)
  }

  private func resolvedInlineEditorFont() -> NSFont {
    let size = max(8, textStyle.fontSize)
    if textStyle.fontName == AppSettings.systemFontFamilyName {
      return .systemFont(ofSize: size, weight: .regular)
    }

    if let familyFont = NSFontManager.shared.font(
      withFamily: textStyle.fontName,
      traits: [],
      weight: 5,
      size: size
    ) {
      return familyFont
    }

    if let named = NSFont(name: textStyle.fontName, size: size) {
      return named
    }

    return .systemFont(ofSize: size, weight: .regular)
  }

  private func commitInlineTextEditor(text: String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let imagePoint = inlineTextAnchorInView else {
      removeInlineTextEditor()
      return
    }

    removeInlineTextEditor()

    guard !trimmed.isEmpty else {
      return
    }
    onCommitText?(trimmed, imagePoint)
  }

  private func removeInlineTextEditor() {
    inlineTextField?.removeFromSuperview()
    inlineTextField = nil
    inlineTextAnchorInView = nil
    needsDisplay = true
  }
}

@MainActor
private final class InlineTextField: NSTextField, NSTextFieldDelegate {
  var onCommit: ((String) -> Void)?
  var onCancel: (() -> Void)?

  private var finalized = false
  private var desiredInsertionPointColor: NSColor = .white

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    isEditable = true
    isSelectable = true
    isBezeled = true
    isBordered = true
    bezelStyle = .roundedBezel
    drawsBackground = true
    focusRingType = .none
    delegate = self
    font = .systemFont(ofSize: 16, weight: .regular)
    textColor = .white
    backgroundColor = NSColor.black.withAlphaComponent(0.45)
    translatesAutoresizingMaskIntoConstraints = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  override func textDidBeginEditing(_ notification: Notification) {
    super.textDidBeginEditing(notification)
    if let editor = currentEditor() as? NSTextView {
      editor.insertionPointColor = desiredInsertionPointColor
    }
  }

  override func textDidEndEditing(_ notification: Notification) {
    super.textDidEndEditing(notification)
    finalizeCommit()
  }

  func control(
    _ control: NSControl,
    textView: NSTextView,
    doCommandBy commandSelector: Selector
  ) -> Bool {
    if commandSelector == #selector(NSResponder.insertNewline(_:)) {
      finalizeCommit()
      return true
    }
    if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
      finalizeCancel()
      return true
    }
    return false
  }

  func setInsertionPointColor(_ color: NSColor) {
    desiredInsertionPointColor = color
    if let editor = currentEditor() as? NSTextView {
      editor.insertionPointColor = color
    }
  }

  private func finalizeCommit() {
    guard !finalized else {
      return
    }
    finalized = true
    onCommit?(stringValue)
  }

  private func finalizeCancel() {
    guard !finalized else {
      return
    }
    finalized = true
    onCancel?()
  }
}
