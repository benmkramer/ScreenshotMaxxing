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
    private let editorWindowControllers = AppWindowControllerStore<ScreenshotEditorWindowController>()
    private let videoEditorWindowControllers = AppWindowControllerStore<VideoEditorWindowController>()
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
    private lazy var captureOrchestrator = AppCaptureOrchestrator(
        hasRequiredPermissions: { [permissionController] in
            permissionController.hasAllRequiredPermissions()
        },
        capture: { [captureController] mode in
            switch mode {
            case .area:
                return try await captureController.captureArea()
            case .window:
                return try await captureController.captureWindow()
            case .fullscreen:
                return try await captureController.captureFullscreen()
            }
        },
        record: { [recordingController] options in
            try await recordingController.record(options: options)
        },
        saveCapture: { [metadataStore] result in
            try metadataStore.saveCapture(result: result)
        },
        saveRecording: { [metadataStore] result in
            try metadataStore.saveCapture(result: result)
        },
        openPermissionOnboarding: { [weak self] in
            self?.openPermissionOnboarding()
        },
        openEditor: { [weak self] imageURL, capture in
            self?.openEditor(for: imageURL, capture: capture)
        },
        openVideoEditor: { [weak self] videoURL, capture in
            self?.openVideoEditor(for: videoURL, capture: capture)
        },
        prepareForRecording: { [weak self] in
            self?.prepareForRecordingPresentation()
        },
        restoreAfterRecordingStops: { [weak self] in
            self?.refreshAccessoryPolicyAfterWindowClose()
        },
        presentError: { [weak self] error, title in
            self?.presentError(error, title: title)
        }
    )

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
        let openHistoryShortcut = shortcutSettingsStore.openHistoryShortcut()
        showMenuBarController(
            areaCaptureShortcut: areaCaptureShortcut,
            captureOptionsShortcut: captureOptionsShortcut,
            openHistoryShortcut: openHistoryShortcut
        )
        hotKeyManager = HotKeyManager { [weak self] action in
            self?.handleHotKeyAction(action)
        }
        if !isRunningUITests {
            registerGlobalHotKeys()
        }
        if !isRunningUnderTests && !isRunningUITests {
            DispatchQueue.main.async { [weak self] in
                self?.showPermissionOnboardingIfNeeded()
            }
        }
        if isRunningUITests {
            DispatchQueue.main.async { [weak self] in
                self?.handleUITestLaunchAction()
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
            let icon = NSImage(contentsOf: iconURL)
        else {
            return
        }

        NSApp.applicationIconImage = icon
    }

    private var isRunningUnderTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private var isRunningUITests: Bool {
        ProcessInfo.processInfo.arguments.contains("--screenshotmaxxing-ui-testing")
    }

    private func handleUITestLaunchAction() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--screenshotmaxxing-ui-test-open-capture-options") {
            let selectedPane: CaptureOptionsPane? =
                arguments.contains("--screenshotmaxxing-ui-test-record-pane") ? .record : nil
            openCaptureOptions(selectedPane: selectedPane)
        } else if arguments.contains("--screenshotmaxxing-ui-test-open-history") {
            openHistory()
        } else if arguments.contains("--screenshotmaxxing-ui-test-open-preferences") {
            openPreferences()
        }
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
        case .openHistory:
            openHistory()
        }
    }

    private func startCapture(_ mode: CaptureMode) {
        captureOrchestrator.startCapture(mode)
    }

    private func startRecording(_ options: RecordingOptions) {
        captureOrchestrator.startRecording(options)
    }

    private func prepareForRecordingPresentation() {
        accessoryPolicyRefreshWorkItem?.cancel()
        accessoryPolicyRefreshWorkItem = nil
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
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

    private func registerOpenHistoryHotKey() {
        do {
            try hotKeyManager?.registerOpenHistoryShortcut(shortcutSettingsStore.openHistoryShortcut())
        } catch {
            presentError(error, title: "Shortcut Unavailable")
        }
    }

    private func registerGlobalHotKeys() {
        registerAreaCaptureHotKey()
        registerCaptureOptionsHotKey()
        registerOpenHistoryHotKey()
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

    private func resetAreaCaptureShortcut() -> GlobalKeyboardShortcut {
        let shortcut = GlobalKeyboardShortcut.defaultAreaCapture
        do {
            try hotKeyManager?.registerAreaCaptureShortcut(shortcut)
            shortcutSettingsStore.resetAreaCaptureShortcut()
            menuBarController?.updateAreaCaptureShortcut(shortcut)
        } catch {
            presentError(error, title: "Shortcut Unavailable")
        }
        return hotKeyManager?.registeredAreaCaptureShortcut ?? shortcutSettingsStore.areaCaptureShortcut()
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

    private func resetCaptureOptionsShortcut() -> GlobalKeyboardShortcut {
        let shortcut = GlobalKeyboardShortcut.defaultCaptureOptions
        do {
            try hotKeyManager?.registerCaptureOptionsShortcut(shortcut)
            shortcutSettingsStore.resetCaptureOptionsShortcut()
            menuBarController?.updateCaptureOptionsShortcut(shortcut)
        } catch {
            presentError(error, title: "Shortcut Unavailable")
        }
        return hotKeyManager?.registeredCaptureOptionsShortcut ?? shortcutSettingsStore.captureOptionsShortcut()
    }

    private func updateOpenHistoryShortcut(_ shortcut: GlobalKeyboardShortcut) -> Bool {
        do {
            try hotKeyManager?.registerOpenHistoryShortcut(shortcut)
            try shortcutSettingsStore.saveOpenHistoryShortcut(shortcut)
            menuBarController?.updateOpenHistoryShortcut(shortcut)
            return true
        } catch {
            presentError(error, title: "Shortcut Unavailable")
            return false
        }
    }

    private func resetOpenHistoryShortcut() -> GlobalKeyboardShortcut {
        let shortcut = GlobalKeyboardShortcut.defaultOpenHistory
        do {
            try hotKeyManager?.registerOpenHistoryShortcut(shortcut)
            shortcutSettingsStore.resetOpenHistoryShortcut()
            menuBarController?.updateOpenHistoryShortcut(shortcut)
        } catch {
            presentError(error, title: "Shortcut Unavailable")
        }
        return hotKeyManager?.registeredOpenHistoryShortcut ?? shortcutSettingsStore.openHistoryShortcut()
    }

    private func showMenuBarController(
        areaCaptureShortcut: GlobalKeyboardShortcut? = nil,
        captureOptionsShortcut: GlobalKeyboardShortcut? = nil,
        openHistoryShortcut: GlobalKeyboardShortcut? = nil
    ) {
        guard menuBarController == nil else {
            return
        }

        menuBarController = MenuBarController(
            areaCaptureShortcut: areaCaptureShortcut ?? shortcutSettingsStore.areaCaptureShortcut(),
            captureOptionsShortcut: captureOptionsShortcut ?? shortcutSettingsStore.captureOptionsShortcut(),
            openHistoryShortcut: openHistoryShortcut ?? shortcutSettingsStore.openHistoryShortcut()
        ) { [weak self] action in
            self?.handleMenuBarAction(action)
        }
    }

    private var userFacingWindows: [NSWindow] {
        var windows = editorWindowControllers.controllers.compactMap { $0.window }
        windows.append(contentsOf: videoEditorWindowControllers.controllers.compactMap { $0.window })

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
        AppWindowPresenter.activateAndOrderFront(window)
    }

    private func activateForUserFacingWindowController(_ windowController: NSWindowController) {
        guard let window = windowController.window else {
            return
        }

        accessoryPolicyRefreshWorkItem?.cancel()
        accessoryPolicyRefreshWorkItem = nil
        windowController.showWindow(nil)
        AppWindowPresenter.activateAndOrderFront(window)
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
            userFacingWindows.contains(where: { $0 === window })
        else {
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
            areaCaptureShortcut: hotKeyManager?.registeredAreaCaptureShortcut
                ?? shortcutSettingsStore.areaCaptureShortcut(),
            captureOptionsShortcut: hotKeyManager?.registeredCaptureOptionsShortcut
                ?? shortcutSettingsStore.captureOptionsShortcut(),
            openHistoryShortcut: hotKeyManager?.registeredOpenHistoryShortcut
                ?? shortcutSettingsStore.openHistoryShortcut(),
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
            onOpenHistoryShortcutChange: { [weak self] shortcut in
                self?.updateOpenHistoryShortcut(shortcut) ?? false
            },
            onAreaCaptureShortcutReset: { [weak self] in
                self?.resetAreaCaptureShortcut() ?? .defaultAreaCapture
            },
            onCaptureOptionsShortcutReset: { [weak self] in
                self?.resetCaptureOptionsShortcut() ?? .defaultCaptureOptions
            },
            onOpenHistoryShortcutReset: { [weak self] in
                self?.resetOpenHistoryShortcut() ?? .defaultOpenHistory
            },
            onLaunchAtLoginChange: { [weak self] isEnabled in
                self?.updateLaunchAtLoginEnabled(isEnabled) ?? false
            }
        )
    }

    private func openCaptureOptions(selectedPane: CaptureOptionsPane? = nil) {
        if let window = captureOptionsWindowController?.window {
            activateForUserFacingWindow(window)
            return
        }

        let controller = CaptureOptionsWindowController(
            selectedPane: selectedPane ?? recordingSettingsStore.captureOptionsPane(),
            microphoneEnabled: recordingSettingsStore.microphoneEnabled(),
            systemAudioEnabled: recordingSettingsStore.systemAudioEnabled(),
            onSelectCapture: { [weak self] mode in
                self?.startCapture(mode)
            },
            onSelectRecording: { [weak self] options in
                self?.startRecording(options)
            },
            onPaneChange: { [weak self] pane in
                do {
                    try self?.recordingSettingsStore.saveCaptureOptionsPane(pane)
                } catch {
                    self?.presentError(error, title: "Capture Setting Failed")
                }
            },
            onMicrophoneChange: { [weak self] isEnabled in
                do {
                    try self?.recordingSettingsStore.saveMicrophoneEnabled(isEnabled)
                } catch {
                    self?.presentError(error, title: "Recording Setting Failed")
                }
            },
            onSystemAudioChange: { [weak self] isEnabled in
                do {
                    try self?.recordingSettingsStore.saveSystemAudioEnabled(isEnabled)
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
        editorWindowControllers.open(
            matching: { $0.isEditingImage(at: imageURL) },
            makeController: {
                ScreenshotEditorWindowController(imageURL: imageURL, capture: capture)
            },
            installCloseHandler: { [weak self] controller, removeController in
                controller.onClose = { closedController in
                    removeController(closedController)
                    self?.refreshAccessoryPolicyAfterWindowClose()
                }
            },
            showExisting: { [weak self] controller in
                guard let window = controller.window else {
                    return
                }
                self?.activateForUserFacingWindow(window)
            },
            showNew: { [weak self] controller in
                guard let window = controller.window else {
                    return
                }
                self?.activateForUserFacingWindow(window)
            }
        )
    }

    private func openVideoEditor(for videoURL: URL, capture: Capture?) {
        videoEditorWindowControllers.open(
            matching: { $0.isEditingVideo(at: videoURL) },
            makeController: {
                VideoEditorWindowController(videoURL: videoURL, capture: capture)
            },
            installCloseHandler: { [weak self] controller, removeController in
                controller.onClose = { closedController in
                    removeController(closedController)
                    self?.refreshAccessoryPolicyAfterWindowClose()
                }
            },
            showExisting: { [weak self] controller in
                guard let window = controller.window else {
                    return
                }
                self?.activateForUserFacingWindow(window)
            },
            showNew: { [weak self] controller in
                guard let window = controller.window else {
                    return
                }
                self?.activateForUserFacingWindow(window)
            }
        )
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
