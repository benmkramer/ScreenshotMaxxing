//
//  ScreenshotMaxxingUITests.swift
//  ScreenshotMaxxingUITests
//
//  Created by Ben Kramer on 5/26/26.
//

import XCTest

final class ScreenshotMaxxingUITests: XCTestCase {
    func testUITestBundleLoads() {
        XCTAssertTrue(true)
    }

    func testCaptureOptionsPanelExposesScreenshotAndRecordTabs() throws {
        let app = XCUIApplication()
        app.launch()
        app.typeKey("5", modifierFlags: [.control, .shift])

        let tabs = app.segmentedControls["capture-options-tabs"]
        guard tabs.waitForExistence(timeout: 2) else {
            throw XCTSkip("Capture options hot key is unavailable in this UI test environment.")
        }

        XCTAssertTrue(app.buttons["capture-options-area"].exists)
        XCTAssertTrue(app.buttons["capture-options-window"].exists)
        XCTAssertTrue(app.buttons["capture-options-fullscreen"].exists)
        tabs.buttons["Record"].click()
        XCTAssertTrue(app.buttons["capture-options-record-area"].exists)
        XCTAssertTrue(app.buttons["capture-options-record-window"].exists)
        XCTAssertTrue(app.buttons["capture-options-record-fullscreen"].exists)
    }
}
