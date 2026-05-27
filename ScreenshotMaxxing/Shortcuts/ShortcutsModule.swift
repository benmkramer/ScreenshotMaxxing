//
//  ShortcutsModule.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/26/26.
//

import AppKit
import Carbon
import SwiftUI

struct ShortcutRecorderView: NSViewRepresentable {
    let shortcut: GlobalKeyboardShortcut
    let onShortcutChange: (GlobalKeyboardShortcut) -> Bool

    init(
        shortcut: GlobalKeyboardShortcut,
        onShortcutChange: @escaping (GlobalKeyboardShortcut) -> Bool
    ) {
        self.shortcut = shortcut
        self.onShortcutChange = onShortcutChange
    }

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        ShortcutRecorderButton(shortcut: shortcut, onShortcutChange: onShortcutChange)
    }

    func updateNSView(_ nsView: ShortcutRecorderButton, context: Context) {
        nsView.setShortcut(shortcut)
        nsView.onShortcutChange = onShortcutChange
    }
}

final class ShortcutRecorderButton: NSButton {
    var onShortcutChange: (GlobalKeyboardShortcut) -> Bool

    private var shortcut: GlobalKeyboardShortcut
    private var isRecording = false

    init(
        shortcut: GlobalKeyboardShortcut,
        onShortcutChange: @escaping (GlobalKeyboardShortcut) -> Bool
    ) {
        self.shortcut = shortcut
        self.onShortcutChange = onShortcutChange
        super.init(frame: .zero)

        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(startRecording)
        focusRingType = .default
        refreshTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    func setShortcut(_ shortcut: GlobalKeyboardShortcut) {
        self.shortcut = shortcut

        if !isRecording {
            refreshTitle()
        }
    }

    @objc private func startRecording() {
        isRecording = true
        title = "Type shortcut"
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if Int(event.keyCode) == kVK_Escape {
            stopRecording()
            return
        }

        guard let newShortcut = GlobalKeyboardShortcut(event: event) else {
            NSSound.beep()
            return
        }

        if onShortcutChange(newShortcut) {
            shortcut = newShortcut
        }

        stopRecording()
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        refreshTitle()
        return super.resignFirstResponder()
    }

    private func stopRecording() {
        isRecording = false
        refreshTitle()
        window?.makeFirstResponder(nil)
    }

    private func refreshTitle() {
        title = shortcut.displayString
    }
}
