//
//  ScreenshotMaxxingTests.swift
//  ScreenshotMaxxingTests
//
//  Created by Ben Kramer on 5/26/26.
//

import Testing
import AppKit
import Foundation
@testable import ScreenshotMaxxing

struct ScreenshotMaxxingTests {

    @MainActor
    @Test func menuBarMenuContainsRequiredItems() async throws {
        let menu = MenuBarController.makeMenu(target: nil)
        let visibleTitles = menu.items.compactMap { item in
            item.isSeparatorItem ? nil : item.title
        }

        #expect(visibleTitles == MenuBarController.visibleMenuTitles)
    }

    @MainActor
    @Test func fileLocationsCreateWritableCaptureDirectories() throws {
        let fileManager = FileManager.default
        let baseDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("ScreenshotMaxxingTests-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? fileManager.removeItem(at: baseDirectory)
        }

        let directories = try FileLocations.ensureCaptureDirectories(
            baseDirectory: baseDirectory,
            fileManager: fileManager
        )
        let originalURL = FileLocations.uniqueOriginalFileURL(
            captureMode: "Capture Area",
            directories: directories,
            date: Date(timeIntervalSince1970: 0),
            uuid: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        )

        #expect(fileManager.fileExists(atPath: directories.originals.path()))
        #expect(fileManager.fileExists(atPath: directories.edited.path()))
        #expect(originalURL.deletingLastPathComponent() == directories.originals)
        #expect(originalURL.lastPathComponent == "capture-area-19700101-000000-00000000.png")

        try Data("png".utf8).write(to: originalURL)
        #expect(fileManager.fileExists(atPath: originalURL.path()))
    }

    @MainActor
    @Test func areaCaptureRunsInteractiveSelectionAndReturnsFile() async throws {
        let fileManager = FileManager.default
        let baseDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("ScreenshotMaxxingTests-\(UUID().uuidString)", isDirectory: true)
        final class RecordedCommand {
            var arguments: [String] = []
        }
        let recordedCommand = RecordedCommand()
        defer {
            try? fileManager.removeItem(at: baseDirectory)
        }

        let controller = CaptureController(fileManager: fileManager) { arguments in
            recordedCommand.arguments = arguments
            guard let outputPath = arguments.last else {
                throw CaptureError.missingOutput(baseDirectory)
            }

            let outputURL = URL(fileURLWithPath: outputPath)
            try Data("png".utf8).write(to: outputURL)
            return 0
        }
        let result = try await controller.captureArea(baseDirectory: baseDirectory)

        #expect(result.mode == .area)
        #expect(recordedCommand.arguments == ["-i", "-s", "-x", result.fileURL.path()])
        #expect(result.fileURL.deletingLastPathComponent().lastPathComponent == "originals")
        #expect(fileManager.fileExists(atPath: result.fileURL.path()))
    }

    @MainActor
    @Test func areaCaptureTreatsMissingOutputAsCancellationWhenCommandFails() async throws {
        let fileManager = FileManager.default
        let baseDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("ScreenshotMaxxingTests-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? fileManager.removeItem(at: baseDirectory)
        }

        let controller = CaptureController(fileManager: fileManager) { _ in
            1
        }

        do {
            _ = try await controller.captureArea(baseDirectory: baseDirectory)
        } catch CaptureError.cancelled {
            return
        }

        Issue.record("Expected canceled capture to throw CaptureError.cancelled")
    }

    @Test func captureModesBuildExpectedScreencaptureArguments() {
        let outputURL = URL(fileURLWithPath: "/tmp/screenshot.png")

        #expect(CaptureMode.area.screencaptureArguments(outputURL: outputURL) == ["-i", "-s", "-x", "/tmp/screenshot.png"])
        #expect(CaptureMode.window.screencaptureArguments(outputURL: outputURL) == ["-i", "-w", "-x", "/tmp/screenshot.png"])
        #expect(CaptureMode.fullscreen.screencaptureArguments(outputURL: outputURL) == ["-x", "/tmp/screenshot.png"])
    }

}
