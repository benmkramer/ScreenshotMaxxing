//
//  RecordingSelectionOverlays.swift
//  ScreenshotMaxxing
//
//  Created by Codex on 5/29/26.
//

import AppKit
import ScreenCaptureKit

struct RecordingAreaSelection {
    let rect: CGRect
    let screen: NSScreen
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

@MainActor
final class RecordingWindowSelectionWindowController: NSWindowController {
    private let screen: NSScreen
    private let windows: [SCWindow]
    private var continuation: CheckedContinuation<SCWindow, Error>?

    init(screen: NSScreen, windows: [SCWindow]) {
        self.screen = screen
        self.windows = windows
        let panel = RecordingSelectionWindowController.makeOverlayPanel(frame: screen.frame)
        super.init(window: panel)

        let selectionView = RecordingWindowSelectionView(screen: screen, windows: windows)
        selectionView.onComplete = { [weak self] window in
            self?.finish(window: window)
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

    func select() async throws -> SCWindow {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            NSApp.activate(ignoringOtherApps: true)
            showWindow(nil)
            window?.makeKeyAndOrderFront(nil)
            window?.makeFirstResponder(window?.contentView)
            NSCursor.pointingHand.set()
        }
    }

    private func finish(window: SCWindow) {
        NSCursor.arrow.set()
        close()
        continuation?.resume(returning: window)
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

private final class RecordingAreaSelectionView: NSView {
    var onComplete: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    private let minimumSelectionSide: CGFloat = 12

    override var acceptsFirstResponder: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.28).setFill()
        bounds.fill()

        guard let selectionRect else {
            return
        }

        NSColor.clear.setFill()
        selectionRect.fill(using: .clear)
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
              selectionRect.height >= minimumSelectionSide else {
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

private final class RecordingWindowSelectionView: NSView {
    var onComplete: ((SCWindow) -> Void)?
    var onCancel: (() -> Void)?

    private let screen: NSScreen
    private let windows: [SCWindow]
    private var hoveredWindowID: CGWindowID?

    init(screen: NSScreen, windows: [SCWindow]) {
        self.screen = screen
        self.windows = Self.visibleWindows(windows, on: screen)
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .inVisibleRect],
            owner: self
        ))
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.22).setFill()
        bounds.fill()

        for window in windows.reversed() {
            let rect = rectInView(for: window)
            guard rect.intersects(bounds), rect.width > 16, rect.height > 16 else {
                continue
            }

            let path = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
            if window.windowID == hoveredWindowID {
                NSColor.controlAccentColor.withAlphaComponent(0.22).setFill()
                path.fill()
                NSColor.controlAccentColor.setStroke()
            } else {
                NSColor.white.withAlphaComponent(0.32).setStroke()
            }
            path.lineWidth = window.windowID == hoveredWindowID ? 3 : 1
            path.stroke()
        }
    }

    override func mouseMoved(with event: NSEvent) {
        guard let screenPoint = self.screenPoint(for: event),
              let window = window(at: screenPoint) else {
            hoveredWindowID = nil
            needsDisplay = true
            return
        }

        if hoveredWindowID != window.windowID {
            hoveredWindowID = window.windowID
            needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let screenPoint = self.screenPoint(for: event),
              let window = window(at: screenPoint) else {
            return
        }

        onComplete?(window)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    private func screenPoint(for event: NSEvent) -> CGPoint? {
        guard let window else {
            return nil
        }

        let point = convert(event.locationInWindow, from: nil)
        return window.convertPoint(toScreen: point)
    }

    private func window(at screenPoint: CGPoint) -> SCWindow? {
        windows.first { candidate in
            rectInScreenCoordinates(for: candidate).contains(screenPoint)
        }
    }

    private func rectInView(for window: SCWindow) -> CGRect {
        let screenRect = Self.rectInScreenCoordinates(for: window, on: screen)
        let origin = CGPoint(
            x: screenRect.minX - screen.frame.minX,
            y: screenRect.minY - screen.frame.minY
        )
        return CGRect(origin: origin, size: screenRect.size)
    }

    private func rectInScreenCoordinates(for window: SCWindow) -> CGRect {
        Self.rectInScreenCoordinates(for: window, on: screen)
    }

    private static func visibleWindows(_ windows: [SCWindow], on screen: NSScreen) -> [SCWindow] {
        let windowOrder = frontToBackWindowOrder()
        let orderedWindows = windows
            .filter { windowOrder[$0.windowID] != nil }
            .sorted { lhs, rhs in
                (windowOrder[lhs.windowID] ?? Int.max) < (windowOrder[rhs.windowID] ?? Int.max)
            }

        return orderedWindows.filter { candidate in
            samplePoints(in: rectInScreenCoordinates(for: candidate, on: screen)).contains { point in
                orderedWindows.first { window in
                    rectInScreenCoordinates(for: window, on: screen).contains(point)
                }?.windowID == candidate.windowID
            }
        }
    }

    private static func frontToBackWindowOrder() -> [CGWindowID: Int] {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return [:]
        }

        var windowOrder: [CGWindowID: Int] = [:]

        for windowInfo in windowList {
            guard let windowID = (windowInfo[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let layer = (windowInfo[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  layer == 0,
                  windowOrder[windowID] == nil else {
                continue
            }

            windowOrder[windowID] = windowOrder.count
        }

        return windowOrder
    }

    private static func samplePoints(in rect: CGRect) -> [CGPoint] {
        guard rect.width > 0, rect.height > 0 else {
            return []
        }

        let insetX = min(max(rect.width * 0.18, 8), rect.width / 2)
        let insetY = min(max(rect.height * 0.18, 8), rect.height / 2)
        let minX = rect.minX + insetX
        let midX = rect.midX
        let maxX = rect.maxX - insetX
        let minY = rect.minY + insetY
        let midY = rect.midY
        let maxY = rect.maxY - insetY

        return [
            CGPoint(x: midX, y: midY),
            CGPoint(x: minX, y: minY),
            CGPoint(x: midX, y: minY),
            CGPoint(x: maxX, y: minY),
            CGPoint(x: minX, y: midY),
            CGPoint(x: maxX, y: midY),
            CGPoint(x: minX, y: maxY),
            CGPoint(x: midX, y: maxY),
            CGPoint(x: maxX, y: maxY)
        ]
    }

    private static func rectInScreenCoordinates(for window: SCWindow, on screen: NSScreen) -> CGRect {
        let frame = window.frame

        if screen.frame.intersects(frame) {
            return frame
        }

        return CGRect(
            x: frame.minX,
            y: screen.frame.maxY - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }
}
