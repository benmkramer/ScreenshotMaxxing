//
//  ScreenshotMaxxingTests.swift
//  ScreenshotMaxxingTests
//
//  Created by Ben Kramer on 5/26/26.
//

import Testing
import AppKit
import Carbon
import Foundation
import SwiftData
@testable import ScreenshotMaxxing

@Suite(.serialized)
struct ScreenshotMaxxingTests {

    @MainActor
    @Test func menuBarMenuContainsRequiredItems() async throws {
        let menu = MenuBarController.makeMenu(target: nil)
        let visibleTitles = menu.items.compactMap { item in
            item.isSeparatorItem ? nil : item.title
        }

        #expect(visibleTitles == MenuBarController.visibleMenuTitles())
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

        #expect(fileManager.fileExists(atPath: directories.originals.fileSystemPath))
        #expect(fileManager.fileExists(atPath: directories.edited.fileSystemPath))
        #expect(originalURL.deletingLastPathComponent() == directories.originals)
        #expect(originalURL.lastPathComponent == "capture-area-19700101-000000-00000000.png")

        try Data("png".utf8).write(to: originalURL)
        #expect(fileManager.fileExists(atPath: originalURL.fileSystemPath))
    }

    @MainActor
    @Test func areaCaptureRunsInteractiveSelectionAndReturnsFile() async throws {
        let fileManager = FileManager.default
        let baseDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("ScreenshotMaxxing Tests-\(UUID().uuidString)", isDirectory: true)
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
        #expect(recordedCommand.arguments == ["-i", "-s", "-x", result.fileURL.fileSystemPath])
        #expect(!recordedCommand.arguments.joined(separator: " ").contains("%20"))
        #expect(result.fileURL.deletingLastPathComponent().lastPathComponent == "originals")
        #expect(fileManager.fileExists(atPath: result.fileURL.fileSystemPath))
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
        let outputURL = URL(fileURLWithPath: "/tmp/Application Support/screenshot.png")

        #expect(CaptureMode.area.screencaptureArguments(outputURL: outputURL) == ["-i", "-s", "-x", "/tmp/Application Support/screenshot.png"])
        #expect(CaptureMode.window.screencaptureArguments(outputURL: outputURL) == ["-i", "-w", "-x", "/tmp/Application Support/screenshot.png"])
        #expect(CaptureMode.fullscreen.screencaptureArguments(outputURL: outputURL) == ["-x", "/tmp/Application Support/screenshot.png"])
    }

    @Test func defaultAreaCaptureShortcutUsesControlShiftFour() {
        let shortcut = GlobalKeyboardShortcut.defaultAreaCapture

        #expect(shortcut.displayString == "Control-Shift-4")
    }

    @Test func commandShiftScreenshotShortcutsAreReservedForMacOS() {
        let commandShiftFour = GlobalKeyboardShortcut(
            keyCode: UInt32(kVK_ANSI_4),
            carbonModifiers: UInt32(cmdKey | shiftKey)
        )
        let commandShiftFive = GlobalKeyboardShortcut(
            keyCode: UInt32(kVK_ANSI_5),
            carbonModifiers: UInt32(cmdKey | shiftKey)
        )

        #expect(commandShiftFour.isReservedSystemScreenshotShortcut)
        #expect(commandShiftFive.isReservedSystemScreenshotShortcut)
        #expect(!GlobalKeyboardShortcut.defaultAreaCapture.isReservedSystemScreenshotShortcut)
    }

    @MainActor
    @Test func menuBarMenuReflectsCustomAreaCaptureShortcut() {
        let shortcut = GlobalKeyboardShortcut(
            keyCode: UInt32(kVK_ANSI_A),
            carbonModifiers: UInt32(cmdKey | optionKey)
        )
        let menu = MenuBarController.makeMenu(target: nil, areaCaptureShortcut: shortcut)
        let visibleTitles = menu.items.compactMap { item in
            item.isSeparatorItem ? nil : item.title
        }

        #expect(visibleTitles == MenuBarController.visibleMenuTitles(areaCaptureShortcut: shortcut))
        #expect(visibleTitles.first == "Capture Area (Option-Command-A)")
    }

    @Test func editorToolbarOnlyShowsImplementedTools() {
        #expect(EditorTool.implementedTools == [.select, .blur])
    }

    @Test func hotKeyManagerRunsAreaCaptureHandlerForRegisteredHotKeyID() {
        var triggerCount = 0
        let manager = HotKeyManager {
            triggerCount += 1
        }

        manager.handleHotKeyPressed(id: HotKeyManager.areaCaptureHotKeyID)
        manager.handleHotKeyPressed(id: 999)

        #expect(triggerCount == 1)
    }

    @MainActor
    @Test func preferencesDataShowsShortcutAndSaveLocations() throws {
        let fileManager = FileManager.default
        let baseDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("ScreenshotMaxxingTests-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? fileManager.removeItem(at: baseDirectory)
        }

        let preferences = try PreferencesData.current(
            areaCaptureShortcut: .defaultAreaCapture,
            baseDirectory: baseDirectory,
            fileManager: fileManager
        )

        #expect(preferences.areaCaptureShortcut.displayString == "Control-Shift-4")
        #expect(URL(fileURLWithPath: preferences.originalsFolderPath).lastPathComponent == "originals")
        #expect(URL(fileURLWithPath: preferences.originalsFolderPath).deletingLastPathComponent().lastPathComponent == "Captures")
        #expect(URL(fileURLWithPath: preferences.editedFolderPath).lastPathComponent == "edited")
        #expect(URL(fileURLWithPath: preferences.editedFolderPath).deletingLastPathComponent().lastPathComponent == "Captures")
        #expect(fileManager.fileExists(atPath: preferences.originalsFolderPath))
        #expect(fileManager.fileExists(atPath: preferences.editedFolderPath))
    }

    @Test func shortcutSettingsStorePersistsAreaCaptureShortcut() throws {
        let suiteName = "ScreenshotMaxxingTests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        let shortcut = GlobalKeyboardShortcut(
            keyCode: UInt32(kVK_ANSI_A),
            carbonModifiers: UInt32(cmdKey | optionKey)
        )

        let store = ShortcutSettingsStore(userDefaults: userDefaults)
        try store.saveAreaCaptureShortcut(shortcut)

        let reloadedStore = ShortcutSettingsStore(userDefaults: userDefaults)

        #expect(reloadedStore.areaCaptureShortcut() == shortcut)
        #expect(reloadedStore.areaCaptureShortcut().displayString == "Option-Command-A")
    }

    @Test func shortcutCanBeRecordedFromModifiedKeyEvent() throws {
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.control, .shift],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "7",
            charactersIgnoringModifiers: "7",
            isARepeat: false,
            keyCode: UInt16(kVK_ANSI_7)
        ))

        #expect(GlobalKeyboardShortcut(event: event) == GlobalKeyboardShortcut(
            keyCode: UInt32(kVK_ANSI_7),
            carbonModifiers: UInt32(controlKey | shiftKey)
        ))
    }

    @Test func shortcutRecordingRejectsUnmodifiedKeyEvent() throws {
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "7",
            charactersIgnoringModifiers: "7",
            isARepeat: false,
            keyCode: UInt16(kVK_ANSI_7)
        ))

        #expect(GlobalKeyboardShortcut(event: event) == nil)
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
        #expect(capture.originalFilePath == imageURL.fileSystemPath)
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

        #expect(ScreenshotEditorWindowController.windowTitle(for: imageURL) == "example-capture.png - ScreenshotMaxxing")
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

    @Test func imageCanvasConvertsDragToImageRect() throws {
        let geometry = ImageCanvasGeometry(
            imageSize: CGSize(width: 200, height: 100),
            containerSize: CGSize(width: 100, height: 100)
        )

        let imageRect = try #require(
            geometry.imageRect(
                fromViewStart: CGPoint(x: 75, y: 75),
                toViewEnd: CGPoint(x: 25, y: 25)
            )
        )

        #expect(imageRect == CGRect(x: 50, y: 0, width: 100, height: 100))
    }

    @MainActor
    @Test func imageRendererConvertsEditorRectToCoreImageRect() {
        let renderer = ImageRenderer()

        let coreImageRect = renderer.coreImageRect(
            forImageRect: CGRect(x: 10, y: 20, width: 30, height: 40),
            imageHeight: 100
        )

        #expect(coreImageRect == CGRect(x: 10, y: 40, width: 30, height: 40))
    }

    @MainActor
    @Test func imageRendererBakesBlurAnnotationsIntoPNG() throws {
        let fileManager = FileManager.default
        let baseDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("ScreenshotMaxxingTests-\(UUID().uuidString)", isDirectory: true)
        let imageURL = baseDirectory.appendingPathComponent("split.png")
        defer {
            try? fileManager.removeItem(at: baseDirectory)
        }

        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        let originalPNGData = try makeVerticalSplitPNGData(width: 12, height: 8)
        try originalPNGData.write(to: imageURL)

        let renderer = ImageRenderer()
        let uneditedPNGData = try renderer.renderPNG(imageURL: imageURL, annotations: [])
        let renderedPNGData = try renderer.renderPNG(
            imageURL: imageURL,
            annotations: [
                Annotation(type: .blur, rect: CGRect(x: 4, y: 0, width: 4, height: 8))
            ]
        )
        let changedPixels = try (4...7).contains { x in
            let originalRed = try redChannel(in: uneditedPNGData, x: x, y: 4)
            let renderedRed = try redChannel(in: renderedPNGData, x: x, y: 4)

            return abs(renderedRed - originalRed) > 0.01
        }

        #expect(originalPNGData.count > 0)
        #expect(renderedPNGData != uneditedPNGData)
        #expect(changedPixels)
    }

    @MainActor
    @Test func editorClipboardWritesPNGDataToPasteboard() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("ScreenshotMaxxingTests-\(UUID().uuidString)"))
        defer {
            pasteboard.releaseGlobally()
        }
        let pngData = try makeVerticalSplitPNGData(width: 2, height: 2)

        let copied = EditorClipboard.copyPNGData(pngData, to: pasteboard)

        #expect(copied)
        #expect(pasteboard.data(forType: .png) == pngData)
        #expect(pasteboard.data(forType: .tiff) != nil)
    }

    @MainActor
    @Test func editorFileSaverWritesEditedImageAndUpdatesCaptureMetadata() throws {
        let fileManager = FileManager.default
        let baseDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("ScreenshotMaxxingTests-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? fileManager.removeItem(at: baseDirectory)
        }

        let modelContainer = try PersistenceController.makeModelContainer(inMemory: true)
        let capture = Capture(
            fileName: "original.png",
            captureMode: "area",
            width: 2,
            height: 2,
            originalFilePath: baseDirectory.appendingPathComponent("original.png").fileSystemPath
        )
        modelContainer.mainContext.insert(capture)
        try modelContainer.mainContext.save()

        let saver = EditorFileSaver(
            fileManager: fileManager,
            metadataStore: CaptureMetadataStore(modelContainer: modelContainer)
        )
        let editedFileURL = try saver.saveEditedPNG(
            Data("edited".utf8),
            originalFileName: capture.fileName,
            capture: capture,
            baseDirectory: baseDirectory
        )

        #expect(fileManager.fileExists(atPath: editedFileURL.fileSystemPath))
        #expect(editedFileURL.deletingLastPathComponent().lastPathComponent == "edited")
        #expect(capture.editedFilePath == editedFileURL.fileSystemPath)
    }

    @MainActor
    @Test func captureHistoryFetchesNewestFirstAndFormatsRows() throws {
        let modelContainer = try PersistenceController.makeModelContainer(inMemory: true)
        let olderCapture = Capture(
            createdAt: Date(timeIntervalSince1970: 10),
            fileName: "older.png",
            captureMode: "area",
            width: 20,
            height: 10,
            originalFilePath: "/tmp/older.png"
        )
        let newerCapture = Capture(
            createdAt: Date(timeIntervalSince1970: 20),
            fileName: "newer.png",
            captureMode: "fullscreen",
            width: 40,
            height: 30,
            originalFilePath: "/tmp/newer.png",
            editedFilePath: "/tmp/newer-edited.png"
        )

        modelContainer.mainContext.insert(olderCapture)
        modelContainer.mainContext.insert(newerCapture)
        try modelContainer.mainContext.save()

        let captures = try modelContainer.mainContext.fetch(CaptureHistoryData.newestFirstFetchDescriptor())

        #expect(captures.map(\.fileName) == ["newer.png", "older.png"])
        #expect(CaptureHistoryData.previewFilePath(for: newerCapture) == "/tmp/newer-edited.png")
        #expect(CaptureHistoryData.previewFileURL(for: newerCapture) == URL(fileURLWithPath: "/tmp/newer-edited.png"))
        #expect(CaptureHistoryData.detailText(for: newerCapture) == "Fullscreen - 40x30")
    }

    private func makeVerticalSplitPNGData(width: Int, height: Int) throws -> Data {
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

        guard let imageRep else {
            throw ImageRendererError.renderFailed
        }

        let black = NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 1)
        let white = NSColor(deviceRed: 1, green: 1, blue: 1, alpha: 1)

        for y in 0..<height {
            for x in 0..<width {
                imageRep.setColor(x < width / 2 ? black : white, atX: x, y: y)
            }
        }

        guard let pngData = imageRep.representation(using: .png, properties: [:]) else {
            throw ImageRendererError.renderFailed
        }

        return pngData
    }

    private func redChannel(in pngData: Data, x: Int, y: Int) throws -> CGFloat {
        guard let imageRep = NSBitmapImageRep(data: pngData),
              let color = imageRep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
            throw ImageRendererError.renderFailed
        }

        return color.redComponent
    }

}
