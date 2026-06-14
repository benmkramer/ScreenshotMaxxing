//
//  RecordingSelectionOverlays.swift
//  ScreenshotMaxxing
//
//  Created by Codex on 5/29/26.
//

import AppKit

struct RecordingAreaSelection {
    let rect: CGRect
    let screen: NSScreen
}

enum RecordingAreaFocusOverlayGeometry {
    static func localClearRect(for recordingRect: CGRect, in screenFrame: CGRect) -> CGRect {
        recordingRect.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
    }
}

enum RecordingSelectionError: LocalizedError, Equatable {
    case cancelled

    var errorDescription: String? {
        switch self {
        case .cancelled:
            "Recording selection canceled."
        }
    }
}

@MainActor
final class RecordingAreaFocusWindowController: NSWindowController {
    init(screen: NSScreen, recordingRect: CGRect) {
        let panel = RecordingAreaFocusWindowController.makeOverlayPanel(frame: screen.frame)
        super.init(window: panel)

        panel.contentView = RecordingAreaFocusView(
            clearRect: RecordingAreaFocusOverlayGeometry.localClearRect(
                for: recordingRect,
                in: screen.frame
            )
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        showWindow(nil)
        window?.orderFrontRegardless()
    }

    private static func makeOverlayPanel(frame: CGRect) -> NSPanel {
        let panel = RecordingFocusPanel(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.sharingType = .none
        return panel
    }
}

@MainActor
final class RecordingAreaSelectionWindowController: NSWindowController {
    private let screen: NSScreen
    private var continuation: CheckedContinuation<RecordingAreaSelection, Error>?

    init(screen: NSScreen) {
        self.screen = screen
        let panel = RecordingSelectionWindowController.makeOverlayPanel(frame: screen.frame)
        super.init(window: panel)

        let selectionView = RecordingAreaSelectionView()
        selectionView.onComplete = { [weak self] rect in
            self?.finish(rect: rect)
        }
        selectionView.onCancel = { [weak self] in
            self?.cancel()
        }
        panel.contentView = selectionView
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func select() async throws -> RecordingAreaSelection {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            NSApp.activate(ignoringOtherApps: true)
            showWindow(nil)
            window?.makeKeyAndOrderFront(nil)
            window?.orderFrontRegardless()
            window?.makeFirstResponder(window?.contentView)
            NSCursor.crosshair.set()
        }
    }

    private func finish(rect: CGRect) {
        NSCursor.arrow.set()
        close()
        continuation?.resume(returning: RecordingAreaSelection(rect: rect, screen: screen))
        continuation = nil
    }

    private func cancel() {
        NSCursor.arrow.set()
        close()
        continuation?.resume(throwing: RecordingSelectionError.cancelled)
        continuation = nil
    }
}

private enum RecordingSelectionWindowController {
    static func makeOverlayPanel(frame: CGRect) -> NSPanel {
        let panel = RecordingSelectionPanel(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.isReleasedWhenClosed = false
        panel.sharingType = .none
        return panel
    }
}

private final class RecordingSelectionPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}

private final class RecordingFocusPanel: NSPanel {
    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }
}

private final class RecordingAreaSelectionView: NSView {
    var onComplete: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    private let minimumSelectionSide: CGFloat = 12

    override var acceptsFirstResponder: Bool {
        true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.28).setFill()
        bounds.fill()

        guard let selectionRect else {
            return
        }

        NSGraphicsContext.current?.cgContext.clear(selectionRect)
        NSColor.controlAccentColor.setStroke()
        let path = NSBezierPath(rect: selectionRect)
        path.lineWidth = 2
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)

        guard let window, let selectionRect,
            selectionRect.width >= minimumSelectionSide,
            selectionRect.height >= minimumSelectionSide
        else {
            onCancel?()
            return
        }

        onComplete?(window.convertToScreen(selectionRect))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    private var selectionRect: CGRect? {
        guard let startPoint, let currentPoint else {
            return nil
        }

        return CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(currentPoint.x - startPoint.x),
            height: abs(currentPoint.y - startPoint.y)
        )
    }
}

private final class RecordingAreaFocusView: NSView {
    private let clearRect: CGRect

    init(clearRect: CGRect) {
        self.clearRect = clearRect
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.30).setFill()
        bounds.fill()

        NSGraphicsContext.current?.cgContext.clear(clearRect)

        NSColor.controlAccentColor.setStroke()
        let path = NSBezierPath(rect: clearRect.insetBy(dx: -1, dy: -1))
        path.lineWidth = 2
        path.stroke()
    }
}
