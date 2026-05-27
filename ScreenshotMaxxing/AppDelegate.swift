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

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureApplicationIcon()
        NSApp.setActivationPolicy(.regular)
        let areaCaptureShortcut = shortcutSettingsStore.areaCaptureShortcut()
        menuBarController = MenuBarController(areaCaptureShortcut: areaCaptureShortcut) { [weak self] action in
            self?.handleMenuBarAction(action)
        }
        hotKeyManager = HotKeyManager { [weak self] action in
            self?.handleHotKeyAction(action)
        }
        registerCaptureHotKeys()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func configureApplicationIcon() {
        guard let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let icon = NSImage(contentsOf: iconURL) else {
            return
        }

        NSApp.applicationIconImage = icon
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

    func captureArea() {
        startCapture(.area)
    }

    func openHistoryWindow() {
        openHistory()
    }

    func openPreferencesWindow() {
        openPreferences()
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
            try hotKeyManager?.registerCaptureOptionsShortcut()
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
            let preferences = try PreferencesData.current(
                areaCaptureShortcut: hotKeyManager?.registeredAreaCaptureShortcut ?? shortcutSettingsStore.areaCaptureShortcut(),
                captureOptionsShortcut: hotKeyManager?.registeredCaptureOptionsShortcut ?? .defaultCaptureOptions
            )
            let rootView = PreferencesView(preferences: preferences) { [weak self] shortcut in
                self?.updateAreaCaptureShortcut(shortcut) ?? false
            }
            let hostingController = NSHostingController(rootView: rootView)
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Preferences - ScreenshotMaxxing"
            window.setContentSize(NSSize(width: 560, height: 320))
            window.minSize = NSSize(width: 520, height: 300)
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
