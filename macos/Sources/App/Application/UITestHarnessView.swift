import SwiftUI

struct UITestHarnessView: View {
  @ObservedObject var statusController: StatusItemController

  private var recordingStateText: String {
    statusController.isRecordingActive ? "recording" : "idle"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("VivyShot UI Test Harness")
        .font(.headline)

      Text(recordingStateText)
        .font(.system(size: 14, weight: .semibold, design: .monospaced))
        .accessibilityLabel(recordingStateText)
        .accessibilityValue(recordingStateText)
        .accessibilityIdentifier("recordingStateLabel")

      Button(statusController.isRecordingActive ? "Stop Recording" : "Capture Region") {
        statusController.captureOrStopPressed()
      }
      .accessibilityIdentifier("captureStopButton")
    }
    .padding(20)
  }
}
