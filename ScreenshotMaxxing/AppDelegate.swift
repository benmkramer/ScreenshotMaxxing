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
    private var videoEditorWindowControllers: [VideoEditorWindowController] = []
    private var captureOptionsWindowController: CaptureOptionsWindowController?
    private var historyWindowController: NSWindowController?
    private var preferencesWindowController: NSWindowController?
    private var hotKeyManager: HotKeyManager?
    private let captureController = CaptureController()
    private let recordingController = RecordingController()
    private let metadataStore = CaptureMetadataStore()
    private let shortcutSettingsStore = ShortcutSettingsStore()
    private let recordingSettingsStore = RecordingSettingsStore()
    private let loginItemController = LoginItemController()
    private let permissionController = AppPermissionController()
    private var permissionOnboardingWindowController: PermissionOnboardingWindowController?
    private var accessoryPolicyRefreshWorkItem: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureApplicationIcon()
        NSApp.setActivationPolicy(.accessory)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
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
        if !isRunningUnderTests {
            DispatchQueue.main.async { [weak self] in
                self?.showPermissionOnboardingIfNeeded()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        permissionOnboardingWindowController?.refresh()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func configureApplicationIcon() {
        guard let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let icon = NSImage(contentsOf: iconURL) else {
            return
        }

        NSApp.applicationIconImage = icon
    }

    private var isRunningUnderTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
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
        guard hasRequiredPermissionsForCapture() else {
            return
        }

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
            } catch RecordingSelectionError.cancelled {
                return
            } catch {
                presentError(error, title: "Capture Failed")
            }
        }
    }

    private func startRecording(_ options: RecordingOptions) {
        guard hasRequiredPermissionsForCapture() else {
            return
        }

        accessoryPolicyRefreshWorkItem?.cancel()
        accessoryPolicyRefreshWorkItem = nil
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        Task {
            do {
                let result = try await recordingController.record(options: options)
                let capture = try metadataStore.saveCapture(result: result)
                openVideoEditor(for: result.fileURL, capture: capture)
            } catch RecordingSelectionError.cancelled {
                refreshAccessoryPolicyAfterWindowClose()
                return
            } catch {
                refreshAccessoryPolicyAfterWindowClose()
                presentError(error, title: "Recording Failed")
            }
        }
    }

    private func hasRequiredPermissionsForCapture() -> Bool {
        guard permissionController.hasAllRequiredPermissions() else {
            openPermissionOnboarding()
            return false
        }

        return true
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

    private var userFacingWindows: [NSWindow] {
        var windows = editorWindowControllers.compactMap { $0.window }

        if let window = captureOptionsWindowController?.window {
            windows.append(window)
        }

        if let window = historyWindowController?.window {
            windows.append(window)
        }

        if let window = preferencesWindowController?.window {
            windows.append(window)
        }

        if let window = permissionOnboardingWindowController?.window {
            windows.append(window)
        }

        return windows
    }

    private var hasOpenUserFacingWindows: Bool {
        userFacingWindows.contains { window in
            window.isVisible || window.isMiniaturized
        }
    }

    private func activateForUserFacingWindow(_ window: NSWindow) {
        accessoryPolicyRefreshWorkItem?.cancel()
        accessoryPolicyRefreshWorkItem = nil
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func activateForUserFacingWindowController(_ windowController: NSWindowController) {
        guard let window = windowController.window else {
            return
        }

        accessoryPolicyRefreshWorkItem?.cancel()
        accessoryPolicyRefreshWorkItem = nil
        NSApp.setActivationPolicy(.regular)
        windowController.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func refreshAccessoryPolicyAfterWindowClose() {
        accessoryPolicyRefreshWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.accessoryPolicyRefreshWorkItem = nil
            if self?.hasOpenUserFacingWindows == false {
                NSApp.setActivationPolicy(.accessory)
            }
        }

        accessoryPolicyRefreshWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              userFacingWindows.contains(where: { $0 === window }) else {
            return
        }

        refreshAccessoryPolicyAfterWindowClose()
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
            activateForUserFacingWindow(window)
            return
        }

        let controller = CaptureOptionsWindowController(
            microphoneEnabled: recordingSettingsStore.microphoneEnabled(),
            onSelectCapture: { [weak self] mode in
                self?.startCapture(mode)
            },
            onSelectRecording: { [weak self] options in
                self?.startRecording(options)
            },
            onMicrophoneChange: { [weak self] isEnabled in
                do {
                    try self?.recordingSettingsStore.saveMicrophoneEnabled(isEnabled)
                } catch {
                    self?.presentError(error, title: "Recording Setting Failed")
                }
            }
        )
        controller.onClose = { [weak self] closedController in
            if self?.captureOptionsWindowController === closedController {
                self?.captureOptionsWindowController = nil
            }
            self?.refreshAccessoryPolicyAfterWindowClose()
        }
        captureOptionsWindowController = controller
        NSApp.setActivationPolicy(.regular)
        controller.show()
    }

    private func showPermissionOnboardingIfNeeded() {
        if !permissionController.hasAllRequiredPermissions() {
            openPermissionOnboarding()
        }
    }

    private func openPermissionOnboarding() {
        if let window = permissionOnboardingWindowController?.window {
            permissionOnboardingWindowController?.refresh()
            activateForUserFacingWindow(window)
            return
        }

        let controller = PermissionOnboardingWindowController(permissionController: permissionController)
        controller.onClose = { [weak self] closedController in
            if self?.permissionOnboardingWindowController === closedController {
                self?.permissionOnboardingWindowController = nil
            }
            self?.refreshAccessoryPolicyAfterWindowClose()
        }
        permissionOnboardingWindowController = controller
        NSApp.setActivationPolicy(.regular)
        controller.show()
    }

    private func openEditor(for imageURL: URL, capture: Capture?) {
        let controller = ScreenshotEditorWindowController(imageURL: imageURL, capture: capture)
        controller.onClose = { [weak self] closedController in
            self?.editorWindowControllers.removeAll { $0 === closedController }
            self?.refreshAccessoryPolicyAfterWindowClose()
        }
        editorWindowControllers.append(controller)
        NSApp.setActivationPolicy(.regular)
        controller.show()
    }

    private func openVideoEditor(for videoURL: URL, capture: Capture?) {
        let controller = VideoEditorWindowController(videoURL: videoURL, capture: capture)
        controller.onClose = { [weak self] closedController in
            self?.videoEditorWindowControllers.removeAll { $0 === closedController }
            self?.refreshAccessoryPolicyAfterWindowClose()
        }
        videoEditorWindowControllers.append(controller)
        NSApp.setActivationPolicy(.regular)
        controller.show()
    }

    private func openHistory() {
        if let window = historyWindowController?.window {
            activateForUserFacingWindow(window)
            return
        }

        let rootView = CaptureHistoryView { [weak self] capture in
            switch CaptureHistoryData.mediaType(for: capture) {
            case .image:
                self?.openEditor(for: CaptureHistoryData.contentFileURL(for: capture), capture: capture)
            case .video:
                self?.openVideoEditor(for: CaptureHistoryData.contentFileURL(for: capture), capture: capture)
            }
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
        activateForUserFacingWindowController(windowController)
    }

    private func openPreferences() {
        if let window = preferencesWindowController?.window {
            activateForUserFacingWindow(window)
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
            activateForUserFacingWindowController(windowController)
        } catch {
            presentError(error, title: "Preferences Unavailable")
        }
    }
}
