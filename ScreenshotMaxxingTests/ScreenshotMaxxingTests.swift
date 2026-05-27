//
//  ScreenshotMaxxingTests.swift
//  ScreenshotMaxxingTests
//
//  Created by Ben Kramer on 5/26/26.
//

import Testing
import AppKit
import Foundation
import SwiftData
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

    @MainActor
    @Test func captureMetadataStorePersistsImageDetails() throws {
        let fileManager = FileManager.default
        let baseDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("ScreenshotMaxxingTests-\(UUID().uuidString)", isDirectory: true)
        let imageURL = baseDirectory.appendingPathComponent("area.png")
        defer {
            try? fileManager.removeItem(at: baseDirectory)
        }

        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        try makePNGData(width: 2, height: 3).write(to: imageURL)

        let modelContainer = try PersistenceController.makeModelContainer(inMemory: true)
        let store = CaptureMetadataStore(modelContainer: modelContainer)
        let capture = try store.saveCapture(result: CaptureResult(mode: .area, fileURL: imageURL))
        let captures = try modelContainer.mainContext.fetch(FetchDescriptor<Capture>())

        #expect(capture.fileName == "area.png")
        #expect(capture.captureMode == "area")
        #expect(capture.width == 2)
        #expect(capture.height == 3)
        #expect(capture.originalFilePath == imageURL.path())
        #expect(captures.count == 1)
    }

    private func makePNGData(width: Int, height: Int) throws -> Data {
        let imageRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )

        guard let pngData = imageRep?.representation(using: .png, properties: [:]) else {
            throw CaptureMetadataError.unreadableImage(URL(fileURLWithPath: "/tmp/test.png"))
        }

        return pngData
    }

    @Test func editorWindowTitleUsesCapturedFileName() {
        let imageURL = URL(fileURLWithPath: "/tmp/example-capture.png")

        #expect(ScreenshotEditorWindowController.windowTitle(for: imageURL) == "ScreenshotMaxxing - example-capture.png")
    }

    @Test func imageCanvasFitsImageWithoutDistortion() {
        let geometry = ImageCanvasGeometry(
            imageSize: CGSize(width: 200, height: 100),
            containerSize: CGSize(width: 100, height: 100)
        )

        #expect(geometry.imageRect == CGRect(x: 0, y: 25, width: 100, height: 50))
    }

    @Test func imageCanvasConvertsViewRectToImageCoordinates() throws {
        let geometry = ImageCanvasGeometry(
            imageSize: CGSize(width: 200, height: 100),
            containerSize: CGSize(width: 100, height: 100)
        )

        let imageRect = try #require(geometry.imageRect(forViewRect: CGRect(x: 25, y: 25, width: 50, height: 25)))

        #expect(imageRect == CGRect(x: 50, y: 0, width: 100, height: 50))
        #expect(geometry.viewRect(forImageRect: imageRect) == CGRect(x: 25, y: 25, width: 50, height: 25))
    }

    @MainActor
    @Test func editorStateStoresBlurRectAnnotationsInImageCoordinates() throws {
        let imageURL = URL(fileURLWithPath: "/tmp/capture.png")
        let annotationID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
        var state = ScreenshotEditorState(originalImageURL: imageURL)

        let addedAnnotation = state.addBlurRect(CGRect(x: 20, y: 30, width: 40, height: 50), id: annotationID)
        let annotation = try #require(addedAnnotation)

        #expect(state.originalImageURL == imageURL)
        #expect(state.selectedTool == .blur)
        #expect(annotation == Annotation(id: annotationID, type: .blur, rect: CGRect(x: 20, y: 30, width: 40, height: 50)))
        #expect(state.annotations == [annotation])
    }

}
