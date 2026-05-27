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
    private let statusItem: NSStatusItem
    private let actionHandler: @MainActor (MenuBarAction) -> Void
    private var areaCaptureShortcut: GlobalKeyboardShortcut

    init(
        statusItem: NSStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength),
        areaCaptureShortcut: GlobalKeyboardShortcut? = nil,
        actionHandler: @escaping @MainActor (MenuBarAction) -> Void = MenuBarController.defaultActionHandler
    ) {
        self.statusItem = statusItem
        self.areaCaptureShortcut = areaCaptureShortcut ?? .defaultAreaCapture
        self.actionHandler = actionHandler
        super.init()

        configureStatusItem()
    }

    static func visibleMenuTitles(areaCaptureShortcut: GlobalKeyboardShortcut? = nil) -> [String] {
        return [
            areaCaptureMenuTitle(areaCaptureShortcut: areaCaptureShortcut),
            "Capture Window...",
            "Capture Fullscreen",
            "Open History",
            "Preferences...",
            "Quit ScreenshotMaxxing"
        ]
    }

    func updateAreaCaptureShortcut(_ shortcut: GlobalKeyboardShortcut) {
        areaCaptureShortcut = shortcut
        statusItem.button?.toolTip = "ScreenshotMaxxing - Capture Area: \(Self.areaCaptureShortcutSummary(areaCaptureShortcut: shortcut))"
        statusItem.menu = MenuBarController.makeMenu(target: self, areaCaptureShortcut: shortcut)
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
        statusItem.button?.toolTip = "ScreenshotMaxxing - Capture Area: \(Self.areaCaptureShortcutSummary(areaCaptureShortcut: areaCaptureShortcut))"
        statusItem.menu = MenuBarController.makeMenu(target: self, areaCaptureShortcut: areaCaptureShortcut)
    }

    static func makeMenu(
        target: AnyObject?,
        areaCaptureShortcut: GlobalKeyboardShortcut? = nil
    ) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(
            title: areaCaptureMenuTitle(areaCaptureShortcut: areaCaptureShortcut),
            action: #selector(captureArea),
            keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem(title: "Capture Window...", action: #selector(captureWindow), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Capture Fullscreen", action: #selector(captureFullscreen), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Open History", action: #selector(openHistory), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit ScreenshotMaxxing", action: #selector(quit), keyEquivalent: "q"))

        menu.items.forEach { item in
            item.target = target
        }

        return menu
    }

    private static func areaCaptureMenuTitle(areaCaptureShortcut: GlobalKeyboardShortcut? = nil) -> String {
        "Capture Area (\(areaCaptureShortcutSummary(areaCaptureShortcut: areaCaptureShortcut)))"
    }

    private static func areaCaptureShortcutSummary(areaCaptureShortcut: GlobalKeyboardShortcut? = nil) -> String {
        (areaCaptureShortcut ?? GlobalKeyboardShortcut.defaultAreaCapture).displayString
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
