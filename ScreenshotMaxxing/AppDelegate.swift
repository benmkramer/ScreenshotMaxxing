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
                switch mode {
                case .area:
                    _ = try await captureController.captureArea()
                case .window:
                    _ = try await captureController.captureWindow()
                case .fullscreen:
                    _ = try await captureController.captureFullscreen()
                }
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
