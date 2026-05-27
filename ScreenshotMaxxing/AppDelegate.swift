//
//  AppDelegate.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/26/26.
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private var editorWindowControllers: [ScreenshotEditorWindowController] = []
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
        case .openHistory, .openPreferences:
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

                try metadataStore.saveCapture(result: result)
                openEditor(for: result.fileURL)
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

    private func openEditor(for imageURL: URL) {
        let controller = ScreenshotEditorWindowController(imageURL: imageURL)
        controller.onClose = { [weak self] closedController in
            self?.editorWindowControllers.removeAll { $0 === closedController }
        }
        editorWindowControllers.append(controller)
        controller.show()
    }
}
