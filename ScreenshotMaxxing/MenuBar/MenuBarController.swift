//
//  MenuBarController.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/26/26.
//

import AppKit

enum MenuBarAction: Equatable {
    case captureArea
    case captureWindow
    case captureFullscreen
    case openHistory
    case openPreferences
    case quit
}

@MainActor
final class MenuBarController: NSObject {
    static let visibleMenuTitles = [
        "Capture Area",
        "Capture Window",
        "Capture Fullscreen",
        "History",
        "Preferences",
        "Quit"
    ]

    private let statusItem: NSStatusItem
    private let actionHandler: @MainActor (MenuBarAction) -> Void

    init(
        statusItem: NSStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength),
        actionHandler: @escaping @MainActor (MenuBarAction) -> Void = MenuBarController.defaultActionHandler
    ) {
        self.statusItem = statusItem
        self.actionHandler = actionHandler
        super.init()

        configureStatusItem()
    }

    private static func defaultActionHandler(action: MenuBarAction) {
        if action == .quit {
            NSApp.terminate(nil)
        }
    }

    private func configureStatusItem() {
        statusItem.button?.image = NSImage(
            systemSymbolName: "camera.viewfinder",
            accessibilityDescription: "ScreenshotMaxxing"
        )
        statusItem.button?.image?.isTemplate = true
        statusItem.button?.toolTip = "ScreenshotMaxxing"
        statusItem.menu = MenuBarController.makeMenu(target: self)
    }

    static func makeMenu(target: AnyObject?) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Capture Area", action: #selector(captureArea), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Capture Window", action: #selector(captureWindow), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Capture Fullscreen", action: #selector(captureFullscreen), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "History", action: #selector(openHistory), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Preferences", action: #selector(openPreferences), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        menu.items.forEach { item in
            item.target = target
        }

        return menu
    }

    @objc private func captureArea() {
        actionHandler(.captureArea)
    }

    @objc private func captureWindow() {
        actionHandler(.captureWindow)
    }

    @objc private func captureFullscreen() {
        actionHandler(.captureFullscreen)
    }

    @objc private func openHistory() {
        actionHandler(.openHistory)
    }

    @objc private func openPreferences() {
        actionHandler(.openPreferences)
    }

    @objc private func quit() {
        actionHandler(.quit)
    }
}
