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
    private var historyWindowController: NSWindowController?
    private let captureController = CaptureController()
    private let metadataStore = CaptureMetadataStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        menuBarController = MenuBarController { [weak self] action in
            self?.handleMenuBarAction(action)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func handleMenuBarAction(_ action: MenuBarAction) {
        switch action {
        case .captureArea:
            startCapture(.area)
        case .captureWindow:
            startCapture(.window)
        case .captureFullscreen:
            startCapture(.fullscreen)
        case .quit:
            NSApp.terminate(nil)
        case .openHistory:
            openHistory()
        case .openPreferences:
            break
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
                presentCaptureError(error)
            }
        }
    }

    private func presentCaptureError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
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
        window.title = "ScreenshotMaxxing History"
        window.setContentSize(NSSize(width: 620, height: 480))
        window.minSize = NSSize(width: 520, height: 420)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false

        let windowController = NSWindowController(window: window)
        historyWindowController = windowController
        windowController.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
