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

  private func openHarnessWindow(_ app: XCUIApplication) {
    app.activate()
    app.typeKey(",", modifierFlags: .command)
  }

  @discardableResult
  private func waitForLabel(_ element: XCUIElement, value: String, timeout: TimeInterval) -> Bool {
    let predicate = NSPredicate(format: "label == %@ OR value == %@", value, value)
    let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
    return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
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
    let app = launchInUITestMode()
    openHarnessWindow(app)

    let stateLabel = app.staticTexts.matching(identifier: "recordingStateLabel").firstMatch
    XCTAssertTrue(stateLabel.waitForExistence(timeout: 5))
    XCTAssertEqual(currentLabelValue(stateLabel), "idle")
  }

  func testCaptureButtonTogglesRecordingState() {
    let app = launchInUITestMode()
    openHarnessWindow(app)

    let stateLabel = app.staticTexts.matching(identifier: "recordingStateLabel").firstMatch
    let captureButton = app.buttons["captureStopButton"]

    XCTAssertTrue(stateLabel.waitForExistence(timeout: 5))
    XCTAssertTrue(captureButton.waitForExistence(timeout: 5))
    XCTAssertEqual(currentLabelValue(stateLabel), "idle")

    captureButton.tap()
    XCTAssertTrue(waitForLabel(stateLabel, value: "recording", timeout: 3))

    captureButton.tap()
    XCTAssertTrue(waitForLabel(stateLabel, value: "idle", timeout: 3))
  }
}
