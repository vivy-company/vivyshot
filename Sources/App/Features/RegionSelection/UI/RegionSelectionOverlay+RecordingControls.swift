import AppKit
import SwiftUI

@MainActor
extension RegionSelectionView {
  func refreshRecordingSourceOptions() {
    webcamSourceOptions = RecordingSourceProvider.webcamSources()
    microphoneSourceOptions = RecordingSourceProvider.microphoneSources()
  }

  func updateRecordingFocusPresentation() {
    if let window = window as? RegionSelectionWindow {
      window.passesEventsThrough = recordingActive
    } else {
      window?.ignoresMouseEvents = recordingActive
    }
    if recordingActive {
      showRecordingControlPanel()
    } else {
      closeRecordingControlPanel()
    }
    layoutEditorChrome()
    needsDisplay = true
    window?.invalidateCursorRects(for: self)
  }

  func makeRecordingControlBar() -> RecordingControlBar {
    return RecordingControlBar(
      state: recordingControlBarState,
      usesExternalGlassSurface: true,
      onAction: { [weak self] action in
        self?.handleRecordingControlBarAction(action)
      }
    )
  }

  var recordingControlBarState: RecordingControlBarState {
    RecordingControlBarState(
      startedAt: recordingStartedAt ?? Date(),
      liveControls: currentRecordingLiveControlState,
      selectedMicrophoneID: settings.microphoneDeviceID,
      selectedWebcamID: settings.webcamDeviceID,
      microphoneSources: microphoneSourceOptions,
      webcamSources: webcamSourceOptions,
      toolOrder: availableRecordingTools.filter { $0 != .countdown },
      accentColor: Color(settings.toolbarAccentColor)
    )
  }

  func handleRecordingControlBarAction(_ action: RecordingControlBarAction) {
    switch action {
    case .toggleTool(let tool):
      switch tool {
      case .microphone where !microphoneFeatureVisible:
        return
      case .webcam where !webcamFeatureVisible:
        return
      case .keystrokes where !keystrokesFeatureVisible:
        return
      case .systemAudio, .mouseClicks, .countdown, .microphone, .webcam, .keystrokes:
        break
      }
      toggleLiveRecordingTool(tool)
    case .selectMicrophoneSource(let deviceID):
      selectMicrophoneSource(deviceID)
    case .selectWebcamSource(let deviceID):
      selectWebcamSource(deviceID)
    case .stop:
      stopVideoRecordingFromEditor()
    case .drag(let mouseLocation):
      updateRecordingControlDrag(mouseLocation: mouseLocation)
    case .dragEnded:
      finishRecordingControlDrag()
    }
  }

  func toggleLiveRecordingTool(_ tool: RecordingTool) {
    guard recordingActive else {
      return
    }
    let currentState = currentRecordingLiveControlState
    guard !currentState.disabledTools.contains(tool) else {
      return
    }
    let requestedEnabled = !currentState.isEnabled(tool)
    Task { @MainActor [weak self] in
      guard let self else {
        return
      }
      guard let recordingController else {
        return
      }
      let updatedState = await recordingController.setLiveRecordingTool(tool, enabled: requestedEnabled)
      self.recordingLiveControlState = updatedState
      self.recordingControlPanelSize = nil
      self.recordingControlHost?.rootView = self.makeRecordingControlBar()
      self.layoutRecordingControlPanel()
    }
  }

  var currentRecordingLiveControlState: RecordingLiveControlState {
    recordingLiveControlState ?? RecordingLiveControlState(
      recordSystemAudio: settings.recordSystemAudio,
      recordMicrophone: microphoneFeatureVisible && settings.recordMicrophone,
      showWebcam: webcamFeatureVisible && settings.showWebcam,
      highlightMouseClicks: settings.highlightMouseClicks,
      highlightKeystrokes: keystrokesFeatureVisible && settings.highlightKeystrokes
    )
  }

  func showRecordingControlPanel() {
    guard recordingActive, let parentWindow = window else {
      closeRecordingControlPanel()
      return
    }

    let host: RegionSelectionGlassHostingView<RecordingControlBar>
    if let recordingControlHost {
      host = recordingControlHost
    } else {
      host = RegionSelectionGlassHostingView(rootView: makeRecordingControlBar(), cornerRadius: 28)
      host.translatesAutoresizingMaskIntoConstraints = true
      host.autoresizingMask = [.width, .height]
      host.alphaValue = 1
      recordingControlHost = host
    }

    let panel: NSPanel
    if let recordingControlPanel {
      panel = recordingControlPanel
    } else {
      panel = NSPanel(
        contentRect: .zero,
        styleMask: [.nonactivatingPanel, .borderless],
        backing: .buffered,
        defer: false
      )
      panel.isReleasedWhenClosed = false
      panel.level = NSWindow.Level(rawValue: max(NSWindow.Level.statusBar.rawValue, parentWindow.level.rawValue + 2))
      panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
      panel.backgroundColor = .clear
      panel.isOpaque = false
      panel.hasShadow = false
      panel.ignoresMouseEvents = false
      panel.acceptsMouseMovedEvents = true
      panel.animationBehavior = .none
      panel.appearance = parentWindow.appearance
      panel.contentView = host
      recordingControlPanel = panel
    }

    layoutRecordingControlPanel()
    panel.orderFrontRegardless()
  }

  func closeRecordingControlPanel() {
    recordingControlPanel?.close()
    recordingControlPanel = nil
    recordingControlHost = nil
    recordingControlPanelSize = nil
    recordingControlDragStartOffset = nil
    recordingControlDragStartMouseLocation = nil
  }

  func layoutRecordingControlPanel() {
    guard recordingActive,
          let parentWindow = window,
          let panel = recordingControlPanel,
          let host = recordingControlHost
    else {
      return
    }

    host.layoutSubtreeIfNeeded()
    let panelSize = recordingControlPanelSize ?? resolvedRecordingControlPanelSize(host.fittingSize)
    recordingControlPanelSize = panelSize

    let padding: CGFloat = 12
    let maxX = max(padding, bounds.width - panelSize.width - padding)
    let minY = padding
    let maxY = max(padding, bounds.height - panelSize.height - padding)

    let selection = committedSelectionRect?.standardized.integral
    let defaultX: CGFloat
    let defaultY: CGFloat
    if selectedCaptureMode == .selection, let selection {
      defaultX = min(max(padding, selection.midX - panelSize.width * 0.5), maxX)
      let proposedBelow = selection.minY - panelSize.height - 14
      defaultY = proposedBelow >= padding ? proposedBelow : min(maxY, selection.maxY + 14)
    } else {
      let bottomInset = captureSurfaceBottomInset()
      let bottomY = padding + bottomInset + 8
      defaultX = min(max(padding, bounds.midX - panelSize.width * 0.5), maxX)
      defaultY = min(maxY, bottomY + 26)
    }

    let x = min(max(padding, defaultX + recordingControlOffset.width), maxX)
    let y = min(max(minY, defaultY + recordingControlOffset.height), maxY)
    recordingControlOffset = CGSize(width: x - defaultX, height: y - defaultY)

    let localFrame = CGRect(
      x: x,
      y: y,
      width: panelSize.width,
      height: panelSize.height
    ).integral
    let windowFrame = convert(localFrame, to: nil)
    let screenFrame = parentWindow.convertToScreen(windowFrame)

    panel.setFrame(screenFrame, display: true)
    host.frame = CGRect(origin: .zero, size: panelSize)
    host.needsLayout = true
    host.layoutSubtreeIfNeeded()
  }

  func updateRecordingControlDrag(mouseLocation: CGPoint) {
    guard mode == .editing else {
      return
    }

    if recordingControlDragStartOffset == nil {
      recordingControlDragStartOffset = recordingControlOffset
      recordingControlDragStartMouseLocation = mouseLocation
    }

    let start = recordingControlDragStartOffset ?? .zero
    let startMouseLocation = recordingControlDragStartMouseLocation ?? mouseLocation
    let delta = CGSize(
      width: mouseLocation.x - startMouseLocation.x,
      height: mouseLocation.y - startMouseLocation.y
    )
    recordingControlOffset = CGSize(
      width: start.width + delta.width,
      height: start.height + delta.height
    )
    layoutRecordingControlPanel()
  }

  func finishRecordingControlDrag() {
    recordingControlDragStartOffset = nil
    recordingControlDragStartMouseLocation = nil
    layoutRecordingControlPanel()
  }

  private func resolvedRecordingControlPanelSize(_ fittingSize: CGSize) -> CGSize {
    let fallback = CGSize(width: 230, height: 52)
    guard fittingSize.width.isFinite,
          fittingSize.height.isFinite,
          fittingSize.width >= 120,
          fittingSize.height >= 36
    else {
      return fallback
    }
    return CGSize(
      width: max(fallback.width, fittingSize.width),
      height: max(fallback.height, fittingSize.height)
    )
  }
}
