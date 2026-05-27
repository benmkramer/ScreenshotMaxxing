//
//  ScreenshotEditorWindowController.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/26/26.
//

import AppKit
import SwiftUI

@MainActor
final class ScreenshotEditorWindowController: NSObject, NSWindowDelegate {
    private let imageURL: URL
    private(set) var window: NSWindow?
    var onClose: ((ScreenshotEditorWindowController) -> Void)?

    init(imageURL: URL) {
        self.imageURL = imageURL
        super.init()
        self.window = makeWindow(imageURL: imageURL)
        self.window?.delegate = self
    }

    nonisolated static func windowTitle(for imageURL: URL) -> String {
        "ScreenshotMaxxing - \(imageURL.lastPathComponent)"
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?(self)
        window = nil
    }

    private func makeWindow(imageURL: URL) -> NSWindow {
        let hostingController = NSHostingController(rootView: ScreenshotEditorView(imageURL: imageURL))
        let window = NSWindow(contentViewController: hostingController)
        window.title = ScreenshotEditorWindowController.windowTitle(for: imageURL)
        window.setContentSize(NSSize(width: 900, height: 620))
        window.minSize = NSSize(width: 640, height: 420)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        return window
    }
}
