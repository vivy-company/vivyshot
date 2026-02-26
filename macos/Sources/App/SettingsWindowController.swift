import AppKit
import Carbon
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
  init(settings: AppSettings = .shared) {
    let host = NSHostingController(rootView: SettingsView(settings: settings))
    let window = NSWindow(contentViewController: host)
    window.title = "VivyShot Settings"
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
    window.level = .normal
    window.center()
    window.setContentSize(NSSize(width: 560, height: 700))
    window.minSize = NSSize(width: 500, height: 620)
    window.isReleasedWhenClosed = false
    super.init(window: window)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  func present() {
    showWindow(nil)
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
}

@MainActor
private struct SettingsView: View {
  @ObservedObject var settings: AppSettings
  @State private var isRecordingShortcut = false
  @State private var availableFamilies: [String] = AppSettings.availableTextFontFamilyNames()
  @State private var draggingTool: AnnotationTool?

  var body: some View {
    ScrollView {
      Form {
        Section("Capture") {
          HStack(spacing: 10) {
            Text("Shortcut")
              .frame(width: 78, alignment: .leading)

            ShortcutRecorderFieldRepresentable(
              displayText: settings.captureShortcutDisplay,
              isRecording: $isRecordingShortcut,
              onCapture: { keyCode, flags in
                settings.setCaptureShortcut(keyCode: keyCode, modifierFlags: flags)
              }
            )
            .frame(minWidth: 180, maxWidth: .infinity, minHeight: 28)
            .layoutPriority(1)

            Button(isRecordingShortcut ? "Stop" : "Record") {
              isRecordingShortcut.toggle()
            }
            .buttonStyle(.bordered)
            .frame(width: 92)

            Button("Reset") {
              settings.resetCaptureShortcut()
              isRecordingShortcut = false
            }
            .buttonStyle(.bordered)
            .frame(width: 86)
          }

          Text(isRecordingShortcut
               ? "Press a key combination now. Esc cancels."
               : "Hold Command/Shift/Option/Control while pressing a key.")
            .font(.caption)
            .foregroundStyle(.secondary)

          Toggle("Show Capture Helper", isOn: captureShowHelperBinding)
            .toggleStyle(.switch)
            .controlSize(.small)
        }

        Section("Toolbar") {
          Text("Drag rows to reorder. Hidden tools won’t appear in capture toolbar.")
            .font(.caption)
            .foregroundStyle(.secondary)

          VStack(spacing: 0) {
            ForEach(settings.toolOrder) { tool in
              HStack(spacing: 10) {
                Image(systemName: tool.symbolName)
                  .frame(width: 18)
                  .foregroundStyle(.secondary)

                Text(tool.title)
                  .frame(maxWidth: .infinity, alignment: .leading)

                Toggle("", isOn: visibilityBinding(for: tool))
                  .toggleStyle(.checkbox)
                  .labelsHidden()

                ReorderHandleGlyph(active: draggingTool == tool)
                  .onDrag {
                    draggingTool = tool
                    return NSItemProvider(object: NSString(string: "\(tool.rawValue)"))
                  }
                  .help("Drag to reorder")
              }
              .padding(.horizontal, 4)
              .padding(.vertical, 5)
              .contentShape(Rectangle())
              .background(
                RoundedRectangle(cornerRadius: 7)
                  .fill(draggingTool == tool ? Color.primary.opacity(0.08) : .clear)
              )
              .onDrop(
                of: ["public.text"],
                delegate: ToolbarToolDropDelegate(
                  target: tool,
                  currentOrder: settings.toolOrder,
                  draggingTool: $draggingTool,
                  onMove: settings.moveTools
                )
              )

              if tool != settings.toolOrder.last {
                Divider().opacity(0.35)
              }
            }
          }
          .padding(4)
          .onDrop(of: ["public.text"], isTargeted: nil) { _ in
            draggingTool = nil
            return false
          }

          HStack {
            Spacer()
            Button("Reset Toolbar") {
              settings.resetToolbarConfiguration()
            }
          }
        }

        Section("Text Tool") {
          HStack(spacing: 10) {
            Text("Font")
              .frame(width: 78, alignment: .leading)
            Spacer(minLength: 0)
            Picker("Font", selection: textFontNameBinding) {
              ForEach(availableFamilies, id: \.self) { family in
                Text(family).tag(family)
              }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 190, alignment: .trailing)
          }

          HStack(spacing: 10) {
            Text("Size")
              .frame(width: 78, alignment: .leading)
            Slider(value: textFontSizeBinding, in: 10 ... 48, step: 1)
            Text("\(Int(settings.textFontSize)) pt")
              .font(.system(.callout, design: .monospaced).weight(.semibold))
              .frame(width: 48, alignment: .trailing)
          }

          LabeledContent("Preview") {
            textPreview
              .frame(maxWidth: .infinity, alignment: .leading)
          }

          HStack {
            Spacer()
            Button("Reset Text") {
              settings.resetTextSettings()
            }
          }
        }

        Section("Effects") {
          HStack(spacing: 10) {
            Text("Transition")
              .frame(width: 78, alignment: .leading)
            Spacer(minLength: 0)
            Picker("Transition", selection: captureTransitionStyleBinding) {
              ForEach(CaptureTransitionStyle.allCases) { style in
                Text(style.title).tag(style)
              }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 150, alignment: .trailing)
          }

          LabeledContent("Speed") {
            HStack(spacing: 10) {
              Slider(
                value: captureTransitionSpeedBinding,
                in: 0.8 ... 2.4,
                step: 0.05
              )
              .disabled(settings.captureTransitionStyle == .none)
              Text(String(format: "%.2fx", settings.captureTransitionSpeed))
                .font(.system(.callout, design: .monospaced).weight(.semibold))
                .frame(width: 54, alignment: .trailing)
            }
          }

          LabeledContent("Strength") {
            HStack(spacing: 10) {
              Slider(
                value: captureTransitionIntensityBinding,
                in: 0.2 ... 1,
                step: 0.05
              )
              .disabled(settings.captureTransitionStyle == .none)
              Text(String(format: "%.0f%%", settings.captureTransitionIntensity * 100))
                .font(.system(.callout, design: .monospaced).weight(.semibold))
                .frame(width: 54, alignment: .trailing)
            }
          }

          HStack {
            Text("Applied on capture enter and exit.")
              .font(.caption)
              .foregroundStyle(.secondary)
            Spacer()
            Button("Reset Effects") {
              settings.resetCaptureTransitionSettings()
            }
          }
        }
      }
      .formStyle(.grouped)
      .frame(maxWidth: 560)
      .padding(14)
    }
    .frame(minWidth: 500, minHeight: 620)
    .onAppear {
      availableFamilies = AppSettings.availableTextFontFamilyNames()
    }
  }

  private func visibilityBinding(for tool: AnnotationTool) -> Binding<Bool> {
    Binding(
      get: { settings.isToolVisible(tool) },
      set: { settings.setToolVisible(tool, isVisible: $0) }
    )
  }

  @ViewBuilder
  private var textPreview: some View {
    if settings.textFontName == AppSettings.systemFontFamilyName {
      Text("The quick brown fox jumps over 123")
        .font(.system(size: settings.textFontSize, weight: .regular))
    } else {
      Text("The quick brown fox jumps over 123")
        .font(.custom(settings.textFontName, size: settings.textFontSize))
    }
  }

  private var textFontSizeBinding: Binding<Double> {
    Binding(
      get: { settings.textFontSize },
      set: { settings.setTextFontSize($0) }
    )
  }

  private var textFontNameBinding: Binding<String> {
    Binding(
      get: { settings.textFontName },
      set: { settings.setTextFontName($0) }
    )
  }

  private var captureTransitionStyleBinding: Binding<CaptureTransitionStyle> {
    Binding(
      get: { settings.captureTransitionStyle },
      set: { settings.setCaptureTransitionStyle($0) }
    )
  }

  private var captureTransitionSpeedBinding: Binding<Double> {
    Binding(
      get: { settings.captureTransitionSpeed },
      set: { settings.setCaptureTransitionSpeed($0) }
    )
  }

  private var captureTransitionIntensityBinding: Binding<Double> {
    Binding(
      get: { settings.captureTransitionIntensity },
      set: { settings.setCaptureTransitionIntensity($0) }
    )
  }

  private var captureShowHelperBinding: Binding<Bool> {
    Binding(
      get: { settings.captureShowHelper },
      set: { settings.setCaptureShowHelper($0) }
    )
  }
}

private struct ReorderHandleGlyph: View {
  let active: Bool

  var body: some View {
    VStack(spacing: 2) {
      ForEach(0 ..< 4, id: \.self) { _ in
        Capsule(style: .continuous)
          .frame(width: 11, height: 1.5)
      }
    }
    .foregroundStyle(active ? .primary : .tertiary)
    .frame(width: 18, height: 18)
    .padding(.trailing, 2)
  }
}

private struct ToolbarToolDropDelegate: DropDelegate {
  let target: AnnotationTool
  let currentOrder: [AnnotationTool]
  @Binding var draggingTool: AnnotationTool?
  let onMove: (IndexSet, Int) -> Void

  func dropEntered(info: DropInfo) {
    guard let draggingTool else {
      return
    }
    guard draggingTool != target else {
      return
    }
    guard let fromIndex = currentOrder.firstIndex(of: draggingTool),
          let toIndex = currentOrder.firstIndex(of: target)
    else {
      return
    }
    guard currentOrder[toIndex] != draggingTool else {
      return
    }

    let destination = toIndex > fromIndex ? toIndex + 1 : toIndex
    withAnimation(.easeInOut(duration: 0.12)) {
      onMove(IndexSet(integer: fromIndex), destination)
    }
  }

  func dropUpdated(info: DropInfo) -> DropProposal? {
    DropProposal(operation: .move)
  }

  func performDrop(info: DropInfo) -> Bool {
    draggingTool = nil
    return true
  }
}

private struct ShortcutRecorderFieldRepresentable: NSViewRepresentable {
  let displayText: String
  @Binding var isRecording: Bool
  let onCapture: (UInt32, NSEvent.ModifierFlags) -> Void

  @MainActor
  final class Coordinator {
    var parent: ShortcutRecorderFieldRepresentable

    init(parent: ShortcutRecorderFieldRepresentable) {
      self.parent = parent
    }

    func handleCapture(keyCode: UInt32, flags: NSEvent.ModifierFlags) {
      parent.onCapture(keyCode, flags)
      parent.isRecording = false
    }

    func handleRecordingChange(_ active: Bool) {
      if parent.isRecording != active {
        parent.isRecording = active
      }
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  func makeNSView(context: Context) -> ShortcutRecorderTextField {
    let field = ShortcutRecorderTextField(frame: .zero)
    field.displayString = displayText
    field.stringValue = displayText
    field.onCapture = { keyCode, flags in
      context.coordinator.handleCapture(keyCode: keyCode, flags: flags)
    }
    field.onRecordingChange = { isActive in
      context.coordinator.handleRecordingChange(isActive)
    }
    return field
  }

  func updateNSView(_ nsView: ShortcutRecorderTextField, context: Context) {
    context.coordinator.parent = self

    nsView.displayString = displayText
    if !nsView.isRecording, nsView.stringValue != displayText {
      nsView.stringValue = displayText
    }

    if nsView.isRecording != isRecording {
      nsView.isRecording = isRecording
    }

    if isRecording, nsView.window?.firstResponder !== nsView {
      DispatchQueue.main.async {
        nsView.window?.makeFirstResponder(nsView)
      }
    }
  }
}

private final class ShortcutRecorderTextField: NSTextField {
  var onCapture: ((UInt32, NSEvent.ModifierFlags) -> Void)?
  var onRecordingChange: ((Bool) -> Void)?
  var displayString: String = ""

  var isRecording: Bool = false {
    didSet {
      guard oldValue != isRecording else {
        return
      }
      if isRecording {
        stringValue = "Press Shortcut"
        window?.makeFirstResponder(self)
      } else {
        stringValue = displayString
      }
      updateAppearance()
      onRecordingChange?(isRecording)
    }
  }

  override var acceptsFirstResponder: Bool { true }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    isEditable = false
    isSelectable = false
    isBezeled = true
    bezelStyle = .roundedBezel
    focusRingType = .none
    alignment = .center
    lineBreakMode = .byTruncatingTail
    font = .systemFont(ofSize: 12, weight: .semibold)
    updateAppearance()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  override func keyDown(with event: NSEvent) {
    guard isRecording else {
      super.keyDown(with: event)
      return
    }

    let keyCode = UInt32(event.keyCode)
    if keyCode == UInt32(kVK_Escape) {
      isRecording = false
      return
    }

    if Self.modifierOnlyKeyCodes.contains(keyCode) {
      return
    }

    let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
    onCapture?(keyCode, flags)
    isRecording = false
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    guard isRecording else {
      return super.performKeyEquivalent(with: event)
    }
    keyDown(with: event)
    return true
  }

  override func resignFirstResponder() -> Bool {
    let resigned = super.resignFirstResponder()
    if resigned, isRecording {
      isRecording = false
    }
    return resigned
  }

  private func updateAppearance() {
    textColor = isRecording ? NSColor.controlAccentColor : NSColor.labelColor
  }

  private static let modifierOnlyKeyCodes: Set<UInt32> = [
    UInt32(kVK_Command),
    UInt32(kVK_RightCommand),
    UInt32(kVK_Shift),
    UInt32(kVK_RightShift),
    UInt32(kVK_Option),
    UInt32(kVK_RightOption),
    UInt32(kVK_Control),
    UInt32(kVK_RightControl),
    UInt32(kVK_CapsLock),
    UInt32(kVK_Function),
  ]
}
