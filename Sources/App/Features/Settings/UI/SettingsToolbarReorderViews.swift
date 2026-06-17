import SwiftUI

protocol SettingsToolbarTool: Identifiable, Equatable {
  var title: String { get }
  var symbolName: String { get }
  var dragRepresentation: String { get }
}

extension SettingsToolbarTool where Self: RawRepresentable {
  var dragRepresentation: String {
    "\(rawValue)"
  }
}

extension AnnotationTool: SettingsToolbarTool {}
extension RecordingTool: SettingsToolbarTool {}

struct ReorderHandleGlyph: View {
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

@MainActor
struct SettingsToolbarReorderList<Tool: SettingsToolbarTool>: View {
  let displayedTools: [Tool]
  let currentOrder: [Tool]
  @Binding var draggingTool: Tool?
  let visibilityBinding: (Tool) -> Binding<Bool>
  let onMove: (IndexSet, Int) -> Void

  var body: some View {
    VStack(spacing: 0) {
      ForEach(displayedTools) { tool in
        SettingsToolbarReorderRow(
          tool: tool,
          draggingTool: $draggingTool,
          visibilityBinding: visibilityBinding(tool)
        )
        .onDrop(
          of: ["public.text"],
          delegate: SettingsToolDropDelegate(
            target: tool,
            currentOrder: currentOrder,
            draggingTool: $draggingTool,
            onMove: onMove
          )
        )

        if tool != displayedTools.last {
          Divider().opacity(0.35)
        }
      }
    }
    .padding(4)
    .onDrop(of: ["public.text"], isTargeted: nil) { _ in
      draggingTool = nil
      return false
    }
  }
}

@MainActor
private struct SettingsToolbarReorderRow<Tool: SettingsToolbarTool>: View {
  let tool: Tool
  @Binding var draggingTool: Tool?
  let visibilityBinding: Binding<Bool>
  @ObservedObject private var localizer = AppLocalizer.shared

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: tool.symbolName)
        .frame(width: 18)
        .foregroundStyle(.secondary)

      Text(tool.title)
        .frame(maxWidth: .infinity, alignment: .leading)

      Toggle("", isOn: visibilityBinding)
        .toggleStyle(.checkbox)
        .labelsHidden()

      ReorderHandleGlyph(active: draggingTool == tool)
        .onDrag {
          draggingTool = tool
          return NSItemProvider(object: NSString(string: tool.dragRepresentation))
        }
        .help(String(localized: "Drag to reorder", bundle: localizer.bundle))
    }
    .padding(.horizontal, 4)
    .padding(.vertical, 5)
    .contentShape(Rectangle())
    .background(
      RoundedRectangle(cornerRadius: 7)
        .fill(draggingTool == tool ? Color.primary.opacity(0.08) : .clear)
    )
  }
}

struct SettingsToolDropDelegate<Tool: Equatable>: DropDelegate {
  let target: Tool
  let currentOrder: [Tool]
  @Binding var draggingTool: Tool?
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
