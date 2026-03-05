import XCTest

final class VivyShotUITests: XCTestCase {
  private var app: XCUIApplication!

  override func setUpWithError() throws {
    continueAfterFailure = false
    app = XCUIApplication()
    app.launchArguments.append("--uitest-mode")
    app.launch()
    app.activate()
  }

  override func tearDownWithError() throws {
    app.terminate()
    app = nil
  }

  @discardableResult
  private func waitForLabel(_ element: XCUIElement, value: String, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
      if currentLabelValue(element) == value {
        return true
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    } while Date() < deadline
    return false
  }

  private func currentLabelValue(_ element: XCUIElement) -> String {
    if !element.label.isEmpty {
      return element.label
    }
    if let value = element.value as? String {
      return value
    }
    return ""
  }

  func testHarnessShowsIdleOnLaunch() {
    let stateLabel = app.staticTexts.matching(identifier: "recordingStateLabel").firstMatch
    XCTAssertTrue(stateLabel.waitForExistence(timeout: 5))
    XCTAssertEqual(currentLabelValue(stateLabel), "idle")
  }

  func testCaptureButtonTogglesRecordingState() {
    let stateLabel = app.staticTexts.matching(identifier: "recordingStateLabel").firstMatch
    let captureButton = app.buttons.matching(identifier: "captureStopButton").firstMatch

    XCTAssertTrue(stateLabel.waitForExistence(timeout: 5))
    XCTAssertTrue(captureButton.waitForExistence(timeout: 5))
    XCTAssertEqual(currentLabelValue(stateLabel), "idle")

    captureButton.tap()
    XCTAssertTrue(waitForLabel(stateLabel, value: "recording", timeout: 3))

    captureButton.tap()
    XCTAssertTrue(waitForLabel(stateLabel, value: "idle", timeout: 3))
  }
}
