//
//  AppDelegate.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/26/26.
//

import AppKit
import SwiftData
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private var editorWindowControllers: [ScreenshotEditorWindowController] = []
    private var captureOptionsWindowController: CaptureOptionsWindowController?
    private var historyWindowController: NSWindowController?
    private var preferencesWindowController: NSWindowController?
    private var hotKeyManager: HotKeyManager?
    private let captureController = CaptureController()
    private let metadataStore = CaptureMetadataStore()
    private let shortcutSettingsStore = ShortcutSettingsStore()
    private let loginItemController = LoginItemController()
    private let screenCapturePermissionController = ScreenCapturePermissionController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureApplicationIcon()
        NSApp.setActivationPolicy(.accessory)
        let areaCaptureShortcut = shortcutSettingsStore.areaCaptureShortcut()
        let captureOptionsShortcut = shortcutSettingsStore.captureOptionsShortcut()
        showMenuBarController(
            areaCaptureShortcut: areaCaptureShortcut,
            captureOptionsShortcut: captureOptionsShortcut
        )
        hotKeyManager = HotKeyManager { [weak self] action in
            self?.handleHotKeyAction(action)
        }
        registerCaptureHotKeys()
        requestScreenCaptureAccessOnLaunch()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        false
    }

    private func configureApplicationIcon() {
        guard let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let icon = NSImage(contentsOf: iconURL) else {
            return
        }

        NSApp.applicationIconImage = icon
    }

    private func requestScreenCaptureAccessOnLaunch() {
        screenCapturePermissionController.requestAccessIfNeeded()
    }

    private func handleMenuBarAction(_ action: MenuBarAction) {
        switch action {
        case .captureArea:
            startCapture(.area)
        case .captureOptions:
            openCaptureOptions()
        case .captureWindow:
            startCapture(.window)
        case .captureFullscreen:
            startCapture(.fullscreen)
        case .quit:
            NSApp.terminate(nil)
        case .openHistory:
            openHistory()
        case .openPreferences:
            openPreferences()
        }
    }

    private func handleHotKeyAction(_ action: HotKeyAction) {
        switch action {
        case .captureArea:
            startCapture(.area)
        case .showCaptureOptions:
            openCaptureOptions()
        }
    }

    private func startCapture(_ mode: CaptureMode) {
        Task {
            do {
                let result: CaptureResult

                switch mode {
                case .area:
                    result = try await captureController.captureArea()
                case .window:
                    result = try await captureController.captureWindow()
                case .fullscreen:
                    result = try await captureController.captureFullscreen()
                }

                let capture = try metadataStore.saveCapture(result: result)
                openEditor(for: result.fileURL, capture: capture)
            } catch CaptureError.cancelled {
                return
            } catch {
                presentError(error, title: "Capture Failed")
            }
        }
    }

    private func presentError(_ error: Error, title: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

    private func registerAreaCaptureHotKey() {
        do {
            try hotKeyManager?.registerAreaCaptureShortcut(shortcutSettingsStore.areaCaptureShortcut())
        } catch {
            presentError(error, title: "Shortcut Unavailable")
        }
    }

    private func registerCaptureOptionsHotKey() {
        do {
            try hotKeyManager?.registerCaptureOptionsShortcut(shortcutSettingsStore.captureOptionsShortcut())
        } catch {
            presentError(error, title: "Shortcut Unavailable")
        }
    }

    private func registerCaptureHotKeys() {
        registerAreaCaptureHotKey()
        registerCaptureOptionsHotKey()
    }

    private func updateAreaCaptureShortcut(_ shortcut: GlobalKeyboardShortcut) -> Bool {
        do {
            try hotKeyManager?.registerAreaCaptureShortcut(shortcut)
            try shortcutSettingsStore.saveAreaCaptureShortcut(shortcut)
            menuBarController?.updateAreaCaptureShortcut(shortcut)
            return true
        } catch {
            presentError(error, title: "Shortcut Unavailable")
            return false
        }
    }

    private func updateCaptureOptionsShortcut(_ shortcut: GlobalKeyboardShortcut) -> Bool {
        do {
            try hotKeyManager?.registerCaptureOptionsShortcut(shortcut)
            try shortcutSettingsStore.saveCaptureOptionsShortcut(shortcut)
            menuBarController?.updateCaptureOptionsShortcut(shortcut)
            return true
        } catch {
            presentError(error, title: "Shortcut Unavailable")
            return false
        }
    }

    private func showMenuBarController(
        areaCaptureShortcut: GlobalKeyboardShortcut? = nil,
        captureOptionsShortcut: GlobalKeyboardShortcut? = nil
    ) {
        guard menuBarController == nil else {
            return
        }

        menuBarController = MenuBarController(
            areaCaptureShortcut: areaCaptureShortcut ?? shortcutSettingsStore.areaCaptureShortcut(),
            captureOptionsShortcut: captureOptionsShortcut ?? shortcutSettingsStore.captureOptionsShortcut()
        ) { [weak self] action in
            self?.handleMenuBarAction(action)
        }
    }

    private func updateLaunchAtLoginEnabled(_ isEnabled: Bool) -> Bool {
        do {
            try loginItemController.setLaunchAtLoginEnabled(isEnabled)
            return true
        } catch {
            presentError(error, title: "Login Item Unavailable")
            return false
        }
    }

    func makePreferencesView() throws -> PreferencesView {
        let preferences = try PreferencesData.current(
            areaCaptureShortcut: hotKeyManager?.registeredAreaCaptureShortcut ?? shortcutSettingsStore.areaCaptureShortcut(),
            captureOptionsShortcut: hotKeyManager?.registeredCaptureOptionsShortcut ?? shortcutSettingsStore.captureOptionsShortcut(),
            launchAtLoginEnabled: loginItemController.launchAtLoginEnabled
        )

        return PreferencesView(
            preferences: preferences,
            onAreaCaptureShortcutChange: { [weak self] shortcut in
                self?.updateAreaCaptureShortcut(shortcut) ?? false
            },
            onCaptureOptionsShortcutChange: { [weak self] shortcut in
                self?.updateCaptureOptionsShortcut(shortcut) ?? false
            },
            onLaunchAtLoginChange: { [weak self] isEnabled in
                self?.updateLaunchAtLoginEnabled(isEnabled) ?? false
            }
        )
    }

    private func openCaptureOptions() {
        if let window = captureOptionsWindowController?.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let controller = CaptureOptionsWindowController { [weak self] mode in
            self?.startCapture(mode)
        }
        controller.onClose = { [weak self] closedController in
            if self?.captureOptionsWindowController === closedController {
                self?.captureOptionsWindowController = nil
            }
        }
        captureOptionsWindowController = controller
        controller.show()
    }

    private func openEditor(for imageURL: URL, capture: Capture?) {
        let controller = ScreenshotEditorWindowController(imageURL: imageURL, capture: capture)
        controller.onClose = { [weak self] closedController in
            self?.editorWindowControllers.removeAll { $0 === closedController }
        }
        editorWindowControllers.append(controller)
        controller.show()
    }

    private func openHistory() {
        if let window = historyWindowController?.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let rootView = CaptureHistoryView { [weak self] capture in
            self?.openEditor(for: CaptureHistoryData.previewFileURL(for: capture), capture: capture)
        }
            .modelContainer(PersistenceController.sharedModelContainer)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "History - ScreenshotMaxxing"
        window.setContentSize(NSSize(width: 620, height: 480))
        window.minSize = NSSize(width: 520, height: 420)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false

        let windowController = NSWindowController(window: window)
        historyWindowController = windowController
        windowController.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openPreferences() {
        if let window = preferencesWindowController?.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        do {
            let rootView = try makePreferencesView()
            let hostingController = NSHostingController(rootView: rootView)
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Preferences - ScreenshotMaxxing"
            window.setContentSize(NSSize(width: 560, height: 380))
            window.minSize = NSSize(width: 520, height: 360)
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false

            let windowController = NSWindowController(window: window)
            preferencesWindowController = windowController
            windowController.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
        } catch {
            presentError(error, title: "Preferences Unavailable")
        }
    }
}
