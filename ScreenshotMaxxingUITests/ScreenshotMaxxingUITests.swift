//
//  ScreenshotMaxxingUITests.swift
//  ScreenshotMaxxingUITests
//
//  Created by Ben Kramer on 5/26/26.
//

import XCTest

final class ScreenshotMaxxingUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCaptureOptionsPanelExposesScreenshotAndRecordControls() throws {
        let app = launchApp(extraArguments: ["--screenshotmaxxing-ui-test-open-capture-options"])

        XCTAssertTrue(app.windows["capture-options-window"].waitForExistence(timeout: 5), app.debugDescription)

        XCTAssertTrue(app.buttons["capture-options-area"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["capture-options-window"].exists)
        XCTAssertTrue(app.buttons["capture-options-fullscreen"].exists)

        app.terminate()
        let recordApp = launchApp(extraArguments: [
            "--screenshotmaxxing-ui-test-open-capture-options",
            "--screenshotmaxxing-ui-test-record-pane"
        ])

        XCTAssertTrue(recordApp.windows["capture-options-window"].waitForExistence(timeout: 5))
        XCTAssertTrue(recordApp.buttons["capture-options-record-area"].waitForExistence(timeout: 5))
        XCTAssertTrue(recordApp.buttons["capture-options-record-window"].exists)
        XCTAssertTrue(recordApp.buttons["capture-options-record-fullscreen"].exists)
        XCTAssertTrue(recordApp.switches["capture-options-record-microphone"].exists)
        XCTAssertTrue(recordApp.switches["capture-options-record-system-audio"].exists)
    }

    func testHistoryOpensThroughAppAction() throws {
        let app = launchApp(extraArguments: ["--screenshotmaxxing-ui-test-open-history"])

        XCTAssertTrue(app.windows["History - ScreenshotMaxxing"].waitForExistence(timeout: 5))
    }

    func testPreferencesOpensThroughAppActionAndShowsShortcutAndStorageSections() throws {
        let app = launchApp(extraArguments: ["--screenshotmaxxing-ui-test-open-preferences"])

        XCTAssertTrue(app.windows["Preferences - ScreenshotMaxxing"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Capture"].exists)
        XCTAssertTrue(app.staticTexts["Storage"].exists)
        XCTAssertTrue(app.staticTexts["Area capture shortcut"].exists)
        XCTAssertTrue(app.staticTexts["Capture options shortcut"].exists)
        XCTAssertTrue(app.staticTexts["Open history shortcut"].exists)
        XCTAssertTrue(app.staticTexts["Original captures"].exists)
        XCTAssertTrue(app.staticTexts["Edited captures"].exists)
    }

    private func launchApp(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = ["--screenshotmaxxing-ui-testing"] + extraArguments
        app.launch()
        return app
    }
}
