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
    private let capture: Capture?
    private let presentWindow: @MainActor (NSWindow) -> Void
    private(set) var window: NSWindow?
    var onClose: ((ScreenshotEditorWindowController) -> Void)?

    init(
        imageURL: URL,
        capture: Capture? = nil,
        presentWindow: @escaping @MainActor (NSWindow) -> Void = AppWindowPresenter.activateAndOrderFront
    ) {
        self.imageURL = imageURL
        self.capture = capture
        self.presentWindow = presentWindow
        super.init()
        self.window = makeWindow(imageURL: imageURL, capture: capture)
        self.window?.delegate = self
    }

    nonisolated static func windowTitle(for imageURL: URL) -> String {
        "\(imageURL.lastPathComponent) - ScreenshotMaxxing"
    }

    func isEditingImage(at candidateURL: URL) -> Bool {
        imageURL.canonicalFileIdentityURL == candidateURL.canonicalFileIdentityURL
    }

    func show() {
        guard let window else {
            return
        }

        presentWindow(window)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?(self)
        window = nil
    }

    private func makeWindow(imageURL: URL, capture: Capture?) -> NSWindow {
        let rootView = ScreenshotEditorView(imageURL: imageURL, capture: capture) { [weak self] in
            self?.window?.close()
        }
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = ScreenshotEditorWindowController.windowTitle(for: imageURL)
        window.setContentSize(NSSize(width: 900, height: 620))
        window.minSize = NSSize(width: 640, height: 420)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        return window
    }
}
