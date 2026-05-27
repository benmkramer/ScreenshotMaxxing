//
//  AppDelegate.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/26/26.
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private let captureController = CaptureController()

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
            startAreaCapture()
        case .quit:
            NSApp.terminate(nil)
        case .captureWindow, .captureFullscreen, .openHistory, .openPreferences:
            break
        }
    }

    private func startAreaCapture() {
        Task {
            do {
                _ = try await captureController.captureArea()
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
}
