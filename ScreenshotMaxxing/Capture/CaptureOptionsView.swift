//
//  CaptureOptionsView.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/27/26.
//

import AppKit
import SwiftUI

struct CaptureOptionsView: View {
    static let availableModes = CaptureMode.allCases

    let onSelect: (CaptureMode) -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Self.availableModes, id: \.self) { mode in
                CaptureOptionButton(mode: mode, onSelect: onSelect)
            }

            Divider()
                .frame(height: 52)
                .padding(.horizontal, 4)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Close")
            .accessibilityIdentifier("capture-options-close")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        }
        .fixedSize()
        .onExitCommand(perform: onDismiss)
    }
}

private struct CaptureOptionButton: View {
    let mode: CaptureMode
    let onSelect: (CaptureMode) -> Void

    @State private var isHovered = false

    var body: some View {
        Button {
            onSelect(mode)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: mode.captureOptionsSymbolName)
                    .font(.system(size: 20, weight: .medium))
                    .frame(width: 26, height: 22)

                Text(mode.captureOptionsDisplayName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(.primary)
            .frame(width: 92, height: 58)
            .background(
                (isHovered ? Color.primary.opacity(0.08) : Color.clear),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(mode.captureOptionsDisplayName)
        .accessibilityIdentifier(mode.captureOptionsAccessibilityIdentifier)
    }
}

@MainActor
final class CaptureOptionsWindowController: NSWindowController, NSWindowDelegate {
    static let windowSize = NSSize(width: 388, height: 82)

    var onClose: ((CaptureOptionsWindowController) -> Void)?

    private let onSelect: (CaptureMode) -> Void

    init(onSelect: @escaping (CaptureMode) -> Void) {
        self.onSelect = onSelect

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.windowSize),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Capture Options"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        super.init(window: panel)

        panel.delegate = self
        panel.contentViewController = NSHostingController(
            rootView: CaptureOptionsView { [weak self] mode in
                self?.select(mode)
            } onDismiss: { [weak self] in
                self?.close()
            }
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else {
            return
        }

        position(window)
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?(self)
    }

    private func select(_ mode: CaptureMode) {
        close()
        onSelect(mode)
    }

    private func position(_ window: NSWindow) {
        guard let screen = NSScreen.main else {
            window.center()
            return
        }

        let visibleFrame = screen.visibleFrame
        let origin = NSPoint(
            x: visibleFrame.midX - Self.windowSize.width / 2,
            y: visibleFrame.minY + 72
        )
        window.setFrameOrigin(origin)
    }
}

private extension CaptureMode {
    var captureOptionsDisplayName: String {
        switch self {
        case .area:
            "Area"
        case .window:
            "Window"
        case .fullscreen:
            "Full Screen"
        }
    }

    var captureOptionsSymbolName: String {
        switch self {
        case .area:
            "rectangle.dashed"
        case .window:
            "macwindow"
        case .fullscreen:
            "display"
        }
    }

    var captureOptionsAccessibilityIdentifier: String {
        "capture-options-\(rawValue)"
    }
}
