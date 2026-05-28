//
//  PermissionOnboardingWindowController.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/27/26.
//

import AppKit
import SwiftUI

@MainActor
final class PermissionOnboardingWindowController: NSWindowController, NSWindowDelegate {
    var onClose: ((PermissionOnboardingWindowController) -> Void)?

    private let model: PermissionOnboardingModel

    init(permissionController: AppPermissionController) {
        self.model = PermissionOnboardingModel(permissionController: permissionController)

        let hostingController = NSHostingController(rootView: PermissionOnboardingView(model: model))
        if #available(macOS 13.0, *) {
            hostingController.sizingOptions = []
        }

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Set Up ScreenshotMaxxing"
        window.setContentSize(NSSize(width: 560, height: 430))
        window.contentMinSize = NSSize(width: 520, height: 390)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false

        super.init(window: window)

        window.delegate = self
        model.onComplete = { [weak self] in
            self?.close()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func refresh() {
        model.refresh()
    }

    func windowWillClose(_ notification: Notification) {
        onClose?(self)
    }
}
