//
//  VideoEditorWindowController.swift
//  ScreenshotMaxxing
//
//  Created by Codex on 5/29/26.
//

import AppKit
import SwiftUI

@MainActor
final class VideoEditorWindowController: NSObject, NSWindowDelegate {
    private let videoURL: URL
    private let capture: Capture?
    private let presentWindow: @MainActor (NSWindow) -> Void
    private(set) var window: NSWindow?
    var onClose: ((VideoEditorWindowController) -> Void)?

    init(
        videoURL: URL,
        capture: Capture? = nil,
        presentWindow: @escaping @MainActor (NSWindow) -> Void = AppWindowPresenter.activateAndOrderFront
    ) {
        self.videoURL = videoURL
        self.capture = capture
        self.presentWindow = presentWindow
        super.init()
        self.window = makeWindow(videoURL: videoURL, capture: capture)
        self.window?.delegate = self
    }

    nonisolated static func windowTitle(for videoURL: URL) -> String {
        "\(videoURL.lastPathComponent) - ScreenshotMaxxing"
    }

    func isEditingVideo(at candidateURL: URL) -> Bool {
        videoURL.canonicalFileIdentityURL == candidateURL.canonicalFileIdentityURL
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

    private func makeWindow(videoURL: URL, capture: Capture?) -> NSWindow {
        let rootView = VideoEditorView(videoURL: videoURL, capture: capture) { [weak self] in
            self?.window?.close()
        }
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = Self.windowTitle(for: videoURL)
        window.setContentSize(NSSize(width: 980, height: 660))
        window.minSize = NSSize(width: 720, height: 500)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        return window
    }
}
