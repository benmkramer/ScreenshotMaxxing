//
//  MenuBarController.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/26/26.
//

import AppKit
import Carbon

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
    private var openHistoryShortcut: GlobalKeyboardShortcut
    private var isRemovedFromStatusBar = false

    init(
        statusBar: NSStatusBar = .system,
        areaCaptureShortcut: GlobalKeyboardShortcut? = nil,
        captureOptionsShortcut: GlobalKeyboardShortcut = .defaultCaptureOptions,
        openHistoryShortcut: GlobalKeyboardShortcut = .defaultOpenHistory,
        actionHandler: @escaping @MainActor (MenuBarAction) -> Void = MenuBarController.defaultActionHandler
    ) {
        self.statusBar = statusBar
        self.statusItem = statusBar.statusItem(withLength: NSStatusItem.squareLength)
        self.areaCaptureShortcut = areaCaptureShortcut ?? .defaultAreaCapture
        self.captureOptionsShortcut = captureOptionsShortcut
        self.openHistoryShortcut = openHistoryShortcut
        self.actionHandler = actionHandler
        super.init()

        configureStatusItem()
    }

    static func visibleMenuTitles(
        areaCaptureShortcut: GlobalKeyboardShortcut? = nil,
        captureOptionsShortcut: GlobalKeyboardShortcut = .defaultCaptureOptions,
        openHistoryShortcut: GlobalKeyboardShortcut = .defaultOpenHistory
    ) -> [String] {
        return [
            areaCaptureMenuTitle(areaCaptureShortcut: areaCaptureShortcut),
            captureOptionsMenuTitle(captureOptionsShortcut: captureOptionsShortcut),
            "Capture Window...",
            "Capture Fullscreen",
            openHistoryMenuTitle(openHistoryShortcut: openHistoryShortcut),
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

    func updateOpenHistoryShortcut(_ shortcut: GlobalKeyboardShortcut) {
        openHistoryShortcut = shortcut
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
            captureOptionsShortcut: captureOptionsShortcut,
            openHistoryShortcut: openHistoryShortcut
        )
        statusItem.menu = MenuBarController.makeMenu(
            target: self,
            areaCaptureShortcut: areaCaptureShortcut,
            captureOptionsShortcut: captureOptionsShortcut,
            openHistoryShortcut: openHistoryShortcut
        )
    }

    static func makeMenu(
        target: AnyObject?,
        areaCaptureShortcut: GlobalKeyboardShortcut? = nil,
        captureOptionsShortcut: GlobalKeyboardShortcut = .defaultCaptureOptions,
        openHistoryShortcut: GlobalKeyboardShortcut = .defaultOpenHistory
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
        let openHistoryItem = NSMenuItem(
            title: openHistoryMenuTitle(openHistoryShortcut: openHistoryShortcut),
            action: #selector(openHistory),
            keyEquivalent: keyEquivalent(for: openHistoryShortcut)
        )
        openHistoryItem.keyEquivalentModifierMask = keyEquivalentModifierMask(for: openHistoryShortcut)
        menu.addItem(openHistoryItem)
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

    private static func openHistoryMenuTitle(openHistoryShortcut: GlobalKeyboardShortcut) -> String {
        "Open History (\(openHistoryShortcut.displayString))"
    }

    private static func areaCaptureShortcutSummary(areaCaptureShortcut: GlobalKeyboardShortcut? = nil) -> String {
        (areaCaptureShortcut ?? GlobalKeyboardShortcut.defaultAreaCapture).displayString
    }

    private static func statusItemToolTip(
        areaCaptureShortcut: GlobalKeyboardShortcut,
        captureOptionsShortcut: GlobalKeyboardShortcut,
        openHistoryShortcut: GlobalKeyboardShortcut
    ) -> String {
        "ScreenshotMaxxing - Capture Area: \(areaCaptureShortcut.displayString), Options: \(captureOptionsShortcut.displayString), History: \(openHistoryShortcut.displayString)"
    }

    private static func keyEquivalent(for shortcut: GlobalKeyboardShortcut) -> String {
        switch Int(shortcut.keyCode) {
        case kVK_ANSI_A: "a"
        case kVK_ANSI_B: "b"
        case kVK_ANSI_C: "c"
        case kVK_ANSI_D: "d"
        case kVK_ANSI_E: "e"
        case kVK_ANSI_F: "f"
        case kVK_ANSI_G: "g"
        case kVK_ANSI_H: "h"
        case kVK_ANSI_I: "i"
        case kVK_ANSI_J: "j"
        case kVK_ANSI_K: "k"
        case kVK_ANSI_L: "l"
        case kVK_ANSI_M: "m"
        case kVK_ANSI_N: "n"
        case kVK_ANSI_O: "o"
        case kVK_ANSI_P: "p"
        case kVK_ANSI_Q: "q"
        case kVK_ANSI_R: "r"
        case kVK_ANSI_S: "s"
        case kVK_ANSI_T: "t"
        case kVK_ANSI_U: "u"
        case kVK_ANSI_V: "v"
        case kVK_ANSI_W: "w"
        case kVK_ANSI_X: "x"
        case kVK_ANSI_Y: "y"
        case kVK_ANSI_Z: "z"
        case kVK_ANSI_0: "0"
        case kVK_ANSI_1: "1"
        case kVK_ANSI_2: "2"
        case kVK_ANSI_3: "3"
        case kVK_ANSI_4: "4"
        case kVK_ANSI_5: "5"
        case kVK_ANSI_6: "6"
        case kVK_ANSI_7: "7"
        case kVK_ANSI_8: "8"
        case kVK_ANSI_9: "9"
        case kVK_Space: " "
        default: ""
        }
    }

    private static func keyEquivalentModifierMask(for shortcut: GlobalKeyboardShortcut) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []

        if shortcut.carbonModifiers & UInt32(controlKey) != 0 {
            flags.insert(.control)
        }

        if shortcut.carbonModifiers & UInt32(optionKey) != 0 {
            flags.insert(.option)
        }

        if shortcut.carbonModifiers & UInt32(shiftKey) != 0 {
            flags.insert(.shift)
        }

        if shortcut.carbonModifiers & UInt32(cmdKey) != 0 {
            flags.insert(.command)
        }

        return flags
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
