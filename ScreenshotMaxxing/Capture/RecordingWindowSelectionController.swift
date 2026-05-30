//
//  RecordingWindowSelectionController.swift
//  ScreenshotMaxxing
//
//  Created by Codex on 5/30/26.
//

import AppKit
import ScreenCaptureKit

struct RecordingWindowCandidate: Equatable {
    let windowID: CGWindowID
    let processID: pid_t?
    let layer: Int
    let bounds: CGRect
}

struct RecordingDisplayCoordinateSpace: Equatable {
    let displayID: CGDirectDisplayID
    let cgFrame: CGRect
    let appKitFrame: CGRect
}

enum RecordingWindowSelectionResolver {
    static func selectedWindowID(
        at screenPoint: CGPoint,
        candidates: [RecordingWindowCandidate],
        displays: [RecordingDisplayCoordinateSpace],
        excludingProcessID processID: pid_t? = nil
    ) -> CGWindowID? {
        candidates.first { candidate in
            isSelectable(candidate, excludingProcessID: processID) &&
                appKitRect(forCGWindowBounds: candidate.bounds, displays: displays).contains(screenPoint)
        }?.windowID
    }

    static func appKitRect(
        forCGWindowBounds bounds: CGRect,
        displays: [RecordingDisplayCoordinateSpace]
    ) -> CGRect {
        guard let display = display(containing: bounds, displays: displays) else {
            return bounds
        }

        let x = display.appKitFrame.minX + (bounds.minX - display.cgFrame.minX)
        let y = display.appKitFrame.maxY - (bounds.maxY - display.cgFrame.minY)

        return CGRect(x: x, y: y, width: bounds.width, height: bounds.height)
    }

    static func currentWindowCandidates() -> [RecordingWindowCandidate] {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        return windowList.compactMap { windowInfo in
            guard let windowID = (windowInfo[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let layer = (windowInfo[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  let boundsDictionary = windowInfo[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary) else {
                return nil
            }

            let processID = (windowInfo[kCGWindowOwnerPID as String] as? NSNumber)
                .map { pid_t($0.int32Value) }

            return RecordingWindowCandidate(
                windowID: windowID,
                processID: processID,
                layer: layer,
                bounds: bounds
            )
        }
    }

    static func currentDisplayCoordinateSpaces(
        screens: [NSScreen] = NSScreen.screens
    ) -> [RecordingDisplayCoordinateSpace] {
        screens.compactMap { screen in
            guard let displayID = screen.displayID else {
                return nil
            }

            return RecordingDisplayCoordinateSpace(
                displayID: displayID,
                cgFrame: CGDisplayBounds(displayID),
                appKitFrame: screen.frame
            )
        }
    }

    private static func isSelectable(
        _ candidate: RecordingWindowCandidate,
        excludingProcessID processID: pid_t?
    ) -> Bool {
        candidate.layer == 0 &&
            candidate.bounds.width >= 48 &&
            candidate.bounds.height >= 48 &&
            candidate.processID != processID
    }

    private static func display(
        containing bounds: CGRect,
        displays: [RecordingDisplayCoordinateSpace]
    ) -> RecordingDisplayCoordinateSpace? {
        displays.max { lhs, rhs in
            intersectionArea(lhs.cgFrame, bounds) < intersectionArea(rhs.cgFrame, bounds)
        }.flatMap { display in
            intersectionArea(display.cgFrame, bounds) > 0 ? display : nil
        }
    }

    private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else {
            return 0
        }

        return intersection.width * intersection.height
    }
}

@MainActor
struct RecordingWindowSelectionController {
    typealias ScreencaptureRunner = @MainActor ([String]) async throws -> Int32

    private let fileManager: FileManager
    private let runScreencapture: ScreencaptureRunner

    init(
        fileManager: FileManager = .default,
        runScreencapture: @escaping ScreencaptureRunner = RecordingWindowSelectionController.runScreencapture
    ) {
        self.fileManager = fileManager
        self.runScreencapture = runScreencapture
    }

    func selectWindowID(excludingProcessID processID: pid_t) async throws -> CGWindowID {
        let outputURL = temporarySelectionURL()
        defer {
            try? fileManager.removeItem(at: outputURL)
        }

        let status = try await runScreencapture(CaptureMode.window.screencaptureArguments(outputURL: outputURL))
        let fileExists = fileManager.fileExists(atPath: outputURL.fileSystemPath)

        guard fileExists else {
            throw RecordingSelectionError.cancelled
        }

        guard status == 0 else {
            throw RecordingError.windowSelectionFailed(status: status)
        }

        guard let windowID = RecordingWindowSelectionResolver.selectedWindowID(
            at: NSEvent.mouseLocation,
            candidates: RecordingWindowSelectionResolver.currentWindowCandidates(),
            displays: RecordingWindowSelectionResolver.currentDisplayCoordinateSpaces(),
            excludingProcessID: processID
        ) else {
            throw RecordingError.selectedWindowUnavailable
        }

        return windowID
    }

    private func temporarySelectionURL() -> URL {
        fileManager.temporaryDirectory
            .appendingPathComponent("ScreenshotMaxxing-window-selection-\(UUID().uuidString)")
            .appendingPathExtension("png")
    }

    private static func runScreencapture(arguments: [String]) async throws -> Int32 {
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = arguments
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        }.value
    }
}
