import XCTest

final class VivyShotUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  private func launchInUITestMode() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments.append("--uitest-mode")
    app.launch()
    return app
  }

  @discardableResult
  private func waitForLabel(_ element: XCUIElement, value: String, timeout: TimeInterval) -> Bool {
    let predicate = NSPredicate(format: "label == %@", value)
    let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
    return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
  }

  func testHarnessShowsIdleOnLaunch() {
    let app = launchInUITestMode()

    let stateLabel = app.staticTexts["recordingStateLabel"]
    XCTAssertTrue(stateLabel.waitForExistence(timeout: 5))
    XCTAssertEqual(stateLabel.label, "idle")
  }

  func testCaptureButtonTogglesRecordingState() {
    let app = launchInUITestMode()

    let stateLabel = app.staticTexts["recordingStateLabel"]
    let captureButton = app.buttons["captureStopButton"]

    XCTAssertTrue(stateLabel.waitForExistence(timeout: 5))
    XCTAssertTrue(captureButton.waitForExistence(timeout: 5))
    XCTAssertEqual(stateLabel.label, "idle")

    captureButton.tap()
    XCTAssertTrue(waitForLabel(stateLabel, value: "recording", timeout: 3))

    captureButton.tap()
    XCTAssertTrue(waitForLabel(stateLabel, value: "idle", timeout: 3))
  }
}
