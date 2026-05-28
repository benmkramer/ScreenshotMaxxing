//
//  MenuBarController.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/26/26.
//

import AppKit

enum MenuBarAction: Equatable {
    case captureArea
    case captureOptions
    case captureWindow
    case captureFullscreen
    case openHistory
    case openPreferences
    case quit
}

@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let statusBar: NSStatusBar
    private let actionHandler: @MainActor (MenuBarAction) -> Void
    private var areaCaptureShortcut: GlobalKeyboardShortcut
    private var captureOptionsShortcut: GlobalKeyboardShortcut
    private var isRemovedFromStatusBar = false

    init(
        statusBar: NSStatusBar = .system,
        areaCaptureShortcut: GlobalKeyboardShortcut? = nil,
        captureOptionsShortcut: GlobalKeyboardShortcut = .defaultCaptureOptions,
        actionHandler: @escaping @MainActor (MenuBarAction) -> Void = MenuBarController.defaultActionHandler
    ) {
        self.statusBar = statusBar
        self.statusItem = statusBar.statusItem(withLength: NSStatusItem.squareLength)
        self.areaCaptureShortcut = areaCaptureShortcut ?? .defaultAreaCapture
        self.captureOptionsShortcut = captureOptionsShortcut
        self.actionHandler = actionHandler
        super.init()

        configureStatusItem()
    }

    static func visibleMenuTitles(
        areaCaptureShortcut: GlobalKeyboardShortcut? = nil,
        captureOptionsShortcut: GlobalKeyboardShortcut = .defaultCaptureOptions
    ) -> [String] {
        return [
            areaCaptureMenuTitle(areaCaptureShortcut: areaCaptureShortcut),
            captureOptionsMenuTitle(captureOptionsShortcut: captureOptionsShortcut),
            "Capture Window...",
            "Capture Fullscreen",
            "Open History",
            "Preferences...",
            "Quit ScreenshotMaxxing"
        ]
    }

    func updateAreaCaptureShortcut(_ shortcut: GlobalKeyboardShortcut) {
        areaCaptureShortcut = shortcut
        refreshShortcutDisplay()
    }

    func updateCaptureOptionsShortcut(_ shortcut: GlobalKeyboardShortcut) {
        captureOptionsShortcut = shortcut
        refreshShortcutDisplay()
    }

    func removeFromStatusBar() {
        guard !isRemovedFromStatusBar else {
            return
        }

        statusBar.removeStatusItem(statusItem)
        isRemovedFromStatusBar = true
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
        refreshShortcutDisplay()
    }

    private func refreshShortcutDisplay() {
        statusItem.button?.toolTip = Self.statusItemToolTip(
            areaCaptureShortcut: areaCaptureShortcut,
            captureOptionsShortcut: captureOptionsShortcut
        )
        statusItem.menu = MenuBarController.makeMenu(
            target: self,
            areaCaptureShortcut: areaCaptureShortcut,
            captureOptionsShortcut: captureOptionsShortcut
        )
    }

    static func makeMenu(
        target: AnyObject?,
        areaCaptureShortcut: GlobalKeyboardShortcut? = nil,
        captureOptionsShortcut: GlobalKeyboardShortcut = .defaultCaptureOptions
    ) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(
            title: areaCaptureMenuTitle(areaCaptureShortcut: areaCaptureShortcut),
            action: #selector(captureArea),
            keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem(
            title: captureOptionsMenuTitle(captureOptionsShortcut: captureOptionsShortcut),
            action: #selector(captureOptions),
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

    private static func captureOptionsMenuTitle(captureOptionsShortcut: GlobalKeyboardShortcut) -> String {
        "Capture Options (\(captureOptionsShortcut.displayString))"
    }

    private static func areaCaptureShortcutSummary(areaCaptureShortcut: GlobalKeyboardShortcut? = nil) -> String {
        (areaCaptureShortcut ?? GlobalKeyboardShortcut.defaultAreaCapture).displayString
    }

    private static func statusItemToolTip(
        areaCaptureShortcut: GlobalKeyboardShortcut,
        captureOptionsShortcut: GlobalKeyboardShortcut
    ) -> String {
        "ScreenshotMaxxing - Capture Area: \(areaCaptureShortcut.displayString), Options: \(captureOptionsShortcut.displayString)"
    }

    @objc private func captureArea() {
        actionHandler(.captureArea)
    }

    @objc private func captureOptions() {
        actionHandler(.captureOptions)
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
