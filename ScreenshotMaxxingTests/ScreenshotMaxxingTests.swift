//
//  ScreenshotMaxxingTests.swift
//  ScreenshotMaxxingTests
//
//  Created by Ben Kramer on 5/26/26.
//

import Testing
import AppKit
@testable import ScreenshotMaxxing

struct ScreenshotMaxxingTests {

    @MainActor
    @Test func menuBarMenuContainsRequiredItems() async throws {
        let menu = MenuBarController.makeMenu(target: nil)
        let visibleTitles = menu.items.compactMap { item in
            item.isSeparatorItem ? nil : item.title
        }

        #expect(visibleTitles == MenuBarController.visibleMenuTitles)
    }

}
