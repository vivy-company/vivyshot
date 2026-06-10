import SwiftUI

let toolbarNeutralForeground = Color.white.opacity(0.9)
let toolbarSecondaryForeground = Color.white.opacity(0.72)

func captureModeHelpText(_ mode: CaptureMode) -> String {
  switch mode {
  case .screen:
    return "Full screen (⌃Tab modes)"
  case .window:
    return "Selected window (⌃Tab modes)"
  case .selection:
    return "Selected area (⌃Tab modes)"
  }
}

@ViewBuilder
@MainActor
func recordingSourceMenuItems(
  selectedSourceID: String,
  sources: [RecordingSourceOption],
  isSourceEnabled: Bool,
  onToggleSource: @escaping () -> Void,
  onSelectSource: @escaping (String) -> Void
) -> some View {
  let selectSource: (String) -> Void = { sourceID in
    if !isSourceEnabled {
      onToggleSource()
    }
    onSelectSource(sourceID)
  }

  Button {
    if isSourceEnabled {
      onToggleSource()
    }
  } label: {
    recordingSourceMenuLabel("Off", isSelected: !isSourceEnabled)
  }

  Divider()

  Button {
    selectSource(RecordingSourceOption.systemDefault.id)
  } label: {
    recordingSourceMenuLabel(
      RecordingSourceOption.systemDefault.name,
      isSelected: isSourceEnabled && selectedSourceID.isEmpty
    )
  }
  if sources.isEmpty {
    Text("No devices found")
      .disabled(true)
  } else {
    ForEach(sources) { source in
      Button {
        selectSource(source.id)
      } label: {
        recordingSourceMenuLabel(source.name, isSelected: isSourceEnabled && source.id == selectedSourceID)
      }
    }
  }
}

@ViewBuilder
@MainActor
func recordingSourceMenuLabel(_ title: String, isSelected: Bool) -> some View {
  if isSelected {
    Label(title, systemImage: "checkmark")
  } else {
    Text(title)
  }
}

struct RecordingSourceMenuButton: View {
  let title: String
  let labelText: String
  let symbol: String
  let help: String
  let isDisabled: Bool
  let isLocked: Bool
  let accentColor: Color
  let selectedSourceID: String
  let sources: [RecordingSourceOption]
  let isSourceEnabled: Bool
  let onToggle: () -> Void
  let onSelectSource: (String) -> Void

  var body: some View {
    Menu {
      recordingSourceMenuItems(
        selectedSourceID: selectedSourceID,
        sources: sources,
        isSourceEnabled: isSourceEnabled,
        onToggleSource: onToggle,
        onSelectSource: onSelectSource
      )
    } label: {
      label
    }
    .buttonStyle(.plain)
    .disabled(isDisabled || isLocked)
    .help(help)
    .accessibilityLabel(title)
  }

  private var label: some View {
    HStack(spacing: 4) {
      Image(systemName: symbol)
        .font(.system(size: 13.5, weight: .semibold))
        .foregroundStyle(isSourceEnabled ? accentColor : toolbarNeutralForeground)

      Text(labelText)
        .font(.system(size: 11.5, weight: .semibold))
        .foregroundStyle(isSourceEnabled ? accentColor : toolbarNeutralForeground)

      if isLocked {
        Image(systemName: "lock.fill")
          .font(.system(size: 9, weight: .bold))
          .foregroundStyle(Color.yellow.opacity(0.92))
      } else {
        Image(systemName: "chevron.down")
          .font(.system(size: 9, weight: .bold))
          .foregroundStyle(toolbarSecondaryForeground)
      }
    }
    .frame(height: 26)
    .padding(.horizontal, 10)
    .contentShape(Rectangle())
    .opacity((isDisabled || isLocked) ? 0.45 : 1)
  }
}

@MainActor
final class CaptureModeSelectionState: ObservableObject {
  @Published private(set) var selectedMode: CaptureMode

  init(selectedMode: CaptureMode = .selection) {
    self.selectedMode = selectedMode
  }

  func setSelectedMode(_ mode: CaptureMode, animated: Bool) {
    guard selectedMode != mode else {
      return
    }

    if animated {
      withAnimation(.smooth(duration: 0.22)) {
        selectedMode = mode
      }
    } else {
      selectedMode = mode
    }
  }
}

extension Array where Element == RecordingTool {
  func shouldSeparateInputSources(after index: Int) -> Bool {
    guard indices.contains(index), self[index].isInputSource else {
      return false
    }

    let nextIndex = index + 1
    return indices.contains(nextIndex) && !self[nextIndex].isInputSource
  }
}
