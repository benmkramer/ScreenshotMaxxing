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

    @MainActor
    @Test func areaCaptureTreatsMissingOutputAsCancellationWhenCommandSucceeds() async throws {
        let fileManager = FileManager.default
        let baseDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("ScreenshotMaxxingTests-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? fileManager.removeItem(at: baseDirectory)
        }

        let controller = CaptureController(fileManager: fileManager) { _ in
            0
        }

        do {
            _ = try await controller.captureArea(baseDirectory: baseDirectory)
        } catch CaptureError.cancelled {
            return
        }

        Issue.record("Expected successful interactive capture without output to be treated as cancellation")
    }

    @MainActor
    @Test func fullscreenCaptureTreatsMissingOutputAsFailureWhenCommandSucceeds() async throws {
        let fileManager = FileManager.default
        let baseDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("ScreenshotMaxxingTests-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? fileManager.removeItem(at: baseDirectory)
        }

        let controller = CaptureController(fileManager: fileManager) { _ in
            0
        }

        do {
            _ = try await controller.captureFullscreen(baseDirectory: baseDirectory)
        } catch CaptureError.missingOutput {
            return
        }

        Issue.record("Expected successful fullscreen capture without output to remain a failure")
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

    @Test func defaultCaptureOptionsShortcutUsesControlShiftFive() {
        let shortcut = GlobalKeyboardShortcut.defaultCaptureOptions

        #expect(shortcut.displayString == "Control-Shift-5")
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
    @Test func menuBarMenuReflectsCustomCaptureShortcuts() {
        let areaCaptureShortcut = GlobalKeyboardShortcut(
            keyCode: UInt32(kVK_ANSI_A),
            carbonModifiers: UInt32(cmdKey | optionKey)
        )
        let captureOptionsShortcut = GlobalKeyboardShortcut(
            keyCode: UInt32(kVK_ANSI_B),
            carbonModifiers: UInt32(controlKey | optionKey)
        )
        let menu = MenuBarController.makeMenu(
            target: nil,
            areaCaptureShortcut: areaCaptureShortcut,
            captureOptionsShortcut: captureOptionsShortcut
        )
        let visibleTitles = menu.items.compactMap { item in
            item.isSeparatorItem ? nil : item.title
        }

        #expect(visibleTitles == MenuBarController.visibleMenuTitles(
            areaCaptureShortcut: areaCaptureShortcut,
            captureOptionsShortcut: captureOptionsShortcut
        ))
        #expect(visibleTitles.first == "Capture Area (Option-Command-A)")
        #expect(visibleTitles[1] == "Capture Options (Control-Option-B)")
    }

    @Test func editorToolbarOnlyShowsImplementedTools() {
        #expect(EditorTool.implementedTools == [.select, .blur, .pen, .highlighter])
    }

    @Test func editorStrokeToolSettingsUseSeparateDefaultSizes() {
        let settings = StrokeToolSettings.defaultSettings

        #expect(settings.pen.color == .red)
        #expect(settings.pen.lineWidth == 13)
        #expect(settings.highlighter.color == .yellow)
        #expect(settings.highlighter.lineWidth == 36)
    }

    @Test func editorSettingsStorePersistsStrokeToolSettings() throws {
        let suiteName = "ScreenshotMaxxingTests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        var settings = StrokeToolSettings.defaultSettings
        settings.update(AnnotationStrokeStyle(color: .black, lineWidth: 7), for: .pen)
        settings.update(AnnotationStrokeStyle(color: .green, lineWidth: 40), for: .highlighter)

        let store = EditorSettingsStore(userDefaults: userDefaults)
        try store.saveStrokeToolSettings(settings)

        let reloadedStore = EditorSettingsStore(userDefaults: userDefaults)

        #expect(reloadedStore.strokeToolSettings() == settings)
    }

    @Test func hotKeyManagerRoutesRegisteredHotKeyIDs() {
        var actions: [HotKeyAction] = []
        let manager = HotKeyManager { action in
            actions.append(action)
        }

        manager.handleHotKeyPressed(id: HotKeyManager.areaCaptureHotKeyID)
        manager.handleHotKeyPressed(id: HotKeyManager.captureOptionsHotKeyID)
        manager.handleHotKeyPressed(id: 999)

        #expect(actions == [.captureArea, .showCaptureOptions])
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
            launchAtLoginEnabled: true,
            baseDirectory: baseDirectory,
            fileManager: fileManager
        )

        #expect(preferences.areaCaptureShortcut.displayString == "Control-Shift-4")
        #expect(preferences.captureOptionsShortcut.displayString == "Control-Shift-5")
        #expect(preferences.launchAtLoginEnabled)
        #expect(URL(fileURLWithPath: preferences.originalsFolderPath).lastPathComponent == "originals")
        #expect(URL(fileURLWithPath: preferences.originalsFolderPath).deletingLastPathComponent().lastPathComponent == "Captures")
        #expect(URL(fileURLWithPath: preferences.editedFolderPath).lastPathComponent == "edited")
        #expect(URL(fileURLWithPath: preferences.editedFolderPath).deletingLastPathComponent().lastPathComponent == "Captures")
        #expect(fileManager.fileExists(atPath: preferences.originalsFolderPath))
        #expect(fileManager.fileExists(atPath: preferences.editedFolderPath))
    }

    @MainActor
    @Test func preferencesDataUpdatesCaptureShortcuts() throws {
        let preferences = PreferencesData(
            areaCaptureShortcut: .defaultAreaCapture,
            captureOptionsShortcut: .defaultCaptureOptions,
            launchAtLoginEnabled: false,
            originalsFolderPath: "/tmp/originals",
            editedFolderPath: "/tmp/edited"
        )
        let areaCaptureShortcut = GlobalKeyboardShortcut(
            keyCode: UInt32(kVK_ANSI_A),
            carbonModifiers: UInt32(cmdKey | optionKey)
        )
        let captureOptionsShortcut = GlobalKeyboardShortcut(
            keyCode: UInt32(kVK_ANSI_B),
            carbonModifiers: UInt32(controlKey | optionKey)
        )

        let updatedAreaCapture = preferences.updatingAreaCaptureShortcut(areaCaptureShortcut)
        let updatedCaptureOptions = updatedAreaCapture.updatingCaptureOptionsShortcut(captureOptionsShortcut)

        #expect(updatedAreaCapture.areaCaptureShortcut == areaCaptureShortcut)
        #expect(updatedAreaCapture.captureOptionsShortcut == .defaultCaptureOptions)
        #expect(updatedCaptureOptions.areaCaptureShortcut == areaCaptureShortcut)
        #expect(updatedCaptureOptions.captureOptionsShortcut == captureOptionsShortcut)
    }

    @MainActor
    @Test func preferencesDataUpdatesLaunchAtLoginSetting() throws {
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

        let launchAtLoginEnabled = preferences.updatingLaunchAtLoginEnabled(true)

        #expect(!preferences.launchAtLoginEnabled)
        #expect(launchAtLoginEnabled.launchAtLoginEnabled)
    }

    @Test func captureOptionsOnlyIncludeStillImageCaptureModes() {
        #expect(CaptureOptionsView.availableModes == [.area, .window, .fullscreen])
    }

    @Test func screenCapturePermissionPreflightsGrantedAccess() {
        var preflightCount = 0
        var requestCount = 0
        let controller = ScreenCapturePermissionController(preflightAccess: {
            preflightCount += 1
            return true
        }, requestAccess: {
            requestCount += 1
            return false
        })

        let granted = controller.hasAccess()

        #expect(granted)
        #expect(preflightCount == 1)
        #expect(requestCount == 0)
    }

    @Test func screenCapturePermissionRequestsAccessWhenMissing() {
        var preflightCount = 0
        var requestCount = 0
        let controller = ScreenCapturePermissionController(preflightAccess: {
            preflightCount += 1
            return false
        }, requestAccess: {
            requestCount += 1
            return true
        })

        let granted = controller.requestAccessIfNeeded()

        #expect(granted)
        #expect(preflightCount == 1)
        #expect(requestCount == 1)
    }

    @Test func directScreenAccessStoresSuccessfulApproval() async {
        var approvalCompleted = false
        var requestCount = 0
        let controller = DirectScreenAccessController {
            approvalCompleted
        } requestApproval: {
            requestCount += 1
            return true
        } markApprovalCompleted: {
            approvalCompleted = true
        }

        let granted = await controller.requestAccessIfNeeded()

        #expect(granted)
        #expect(approvalCompleted)
        #expect(requestCount == 1)
        #expect(controller.hasAccess())
    }

    @Test func appPermissionControllerReportsRequiredPermissionStates() {
        let controller = AppPermissionController(
            screenCapturePermissionController: ScreenCapturePermissionController(preflightAccess: {
                true
            }),
            directScreenAccessController: DirectScreenAccessController {
                false
            } requestApproval: {
                true
            }
        )

        #expect(controller.permissionStates() == [
            AppPermissionState(permission: .screenCapture, isGranted: true, isSetupEnabled: true),
            AppPermissionState(permission: .directScreenAccess, isGranted: false, isSetupEnabled: true)
        ])
        #expect(!controller.hasAllRequiredPermissions())
    }

    @Test func appPermissionControllerRequestsSelectedPermissionOnly() async {
        var screenCaptureRequestCount = 0
        var directScreenAccessRequestCount = 0
        let controller = AppPermissionController(
            screenCapturePermissionController: ScreenCapturePermissionController(preflightAccess: {
                false
            }, requestAccess: {
                screenCaptureRequestCount += 1
                return true
            }),
            directScreenAccessController: DirectScreenAccessController {
                false
            } requestApproval: {
                directScreenAccessRequestCount += 1
                return true
            }
        )

        let granted = await controller.requestAccessIfNeeded(for: .screenCapture)

        #expect(granted)
        #expect(screenCaptureRequestCount == 1)
        #expect(directScreenAccessRequestCount == 0)
    }

    @Test func appPermissionControllerClearsDirectApprovalWhenScreenCaptureIsMissing() {
        var clearApprovalCount = 0
        let controller = AppPermissionController(
            screenCapturePermissionController: ScreenCapturePermissionController(preflightAccess: {
                false
            }),
            directScreenAccessController: DirectScreenAccessController {
                true
            } requestApproval: {
                true
            } clearStoredApproval: {
                clearApprovalCount += 1
            }
        )

        #expect(controller.permissionStates() == [
            AppPermissionState(permission: .screenCapture, isGranted: false, isSetupEnabled: true),
            AppPermissionState(permission: .directScreenAccess, isGranted: false, isSetupEnabled: false)
        ])
        #expect(clearApprovalCount == 1)
    }

    @MainActor
    @Test func permissionOnboardingModelOpensSettingsAndOffersRelaunchWhenPermissionRemainsMissing() async {
        var requestCount = 0
        var openedURLs: [URL] = []
        var relaunchCount = 0
        let controller = AppPermissionController(
            screenCapturePermissionController: ScreenCapturePermissionController(preflightAccess: {
                false
            }, requestAccess: {
                requestCount += 1
                return false
            }),
            directScreenAccessController: DirectScreenAccessController {
                false
            } requestApproval: {
                true
            }
        )
        let model = PermissionOnboardingModel(permissionController: controller) { url in
            openedURLs.append(url)
        } relaunchApp: {
            relaunchCount += 1
        }

        await model.requestAccess(for: .screenCapture)

        #expect(requestCount == 1)
        #expect(openedURLs.isEmpty)
        #expect(model.needsRelaunch)
        #expect(model.actionTitle(for: .screenCapture) == "Open Settings")
        #expect(model.primaryActionTitle == "Relaunch")

        await model.requestAccess(for: .screenCapture)

        #expect(requestCount == 1)
        #expect(openedURLs.count == 1)
        #expect(openedURLs.first == AppPermission.screenCapture.settingsURL)
        model.primaryAction()

        #expect(model.needsRelaunch)
        #expect(relaunchCount == 1)
        #expect(model.states == [
            AppPermissionState(permission: .screenCapture, isGranted: false, isSetupEnabled: true),
            AppPermissionState(permission: .directScreenAccess, isGranted: false, isSetupEnabled: false)
        ])
    }

    @MainActor
    @Test func permissionOnboardingModelRequestsDirectScreenAccessDuringSetup() async {
        var approvalCompleted = false
        var requestCount = 0
        let controller = AppPermissionController(
            screenCapturePermissionController: ScreenCapturePermissionController(preflightAccess: {
                true
            }),
            directScreenAccessController: DirectScreenAccessController {
                approvalCompleted
            } requestApproval: {
                requestCount += 1
                return true
            } markApprovalCompleted: {
                approvalCompleted = true
            }
        )
        let model = PermissionOnboardingModel(permissionController: controller)

        await model.requestAccess(for: .directScreenAccess)

        #expect(requestCount == 1)
        #expect(model.allGranted)
        #expect(model.states == [
            AppPermissionState(permission: .screenCapture, isGranted: true, isSetupEnabled: true),
            AppPermissionState(permission: .directScreenAccess, isGranted: true, isSetupEnabled: true)
        ])
    }

    @MainActor
    @Test func permissionOnboardingModelCompletesWhenPermissionAlreadyGranted() {
        var completionCount = 0
        let controller = AppPermissionController(
            screenCapturePermissionController: ScreenCapturePermissionController(preflightAccess: {
                true
            }),
            directScreenAccessController: DirectScreenAccessController {
                true
            } requestApproval: {
                false
            }
        )
        let model = PermissionOnboardingModel(permissionController: controller)
        model.onComplete = {
            completionCount += 1
        }

        model.primaryAction()

        #expect(model.allGranted)
        #expect(!model.needsRelaunch)
        #expect(model.primaryActionTitle == "Done")
        #expect(completionCount == 1)
    }

    @Test func shortcutSettingsStorePersistsCaptureShortcuts() throws {
        let suiteName = "ScreenshotMaxxingTests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        let areaCaptureShortcut = GlobalKeyboardShortcut(
            keyCode: UInt32(kVK_ANSI_A),
            carbonModifiers: UInt32(cmdKey | optionKey)
        )
        let captureOptionsShortcut = GlobalKeyboardShortcut(
            keyCode: UInt32(kVK_ANSI_B),
            carbonModifiers: UInt32(controlKey | optionKey)
        )

        let store = ShortcutSettingsStore(userDefaults: userDefaults)
        try store.saveAreaCaptureShortcut(areaCaptureShortcut)
        try store.saveCaptureOptionsShortcut(captureOptionsShortcut)

        let reloadedStore = ShortcutSettingsStore(userDefaults: userDefaults)

        #expect(reloadedStore.areaCaptureShortcut() == areaCaptureShortcut)
        #expect(reloadedStore.areaCaptureShortcut().displayString == "Option-Command-A")
        #expect(reloadedStore.captureOptionsShortcut() == captureOptionsShortcut)
        #expect(reloadedStore.captureOptionsShortcut().displayString == "Control-Option-B")
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

    @MainActor
    @Test func captureMetadataStoreDeletesCaptureHistoryAndLocalFiles() throws {
        let fileManager = FileManager.default
        let baseDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("ScreenshotMaxxingTests-\(UUID().uuidString)", isDirectory: true)
        let originalURL = baseDirectory.appendingPathComponent("original.png")
        let editedURL = baseDirectory.appendingPathComponent("edited.png")
        defer {
            try? fileManager.removeItem(at: baseDirectory)
        }

        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        try makePNGData(width: 2, height: 2).write(to: originalURL)
        try makePNGData(width: 2, height: 2).write(to: editedURL)

        let modelContainer = try PersistenceController.makeModelContainer(inMemory: true)
        let capture = Capture(
            fileName: originalURL.lastPathComponent,
            captureMode: "area",
            width: 2,
            height: 2,
            originalFilePath: originalURL.fileSystemPath,
            editedFilePath: editedURL.fileSystemPath
        )
        modelContainer.mainContext.insert(capture)
        try modelContainer.mainContext.save()

        let store = CaptureMetadataStore(modelContainer: modelContainer)
        try store.deleteCaptureFromHistoryAndDisk(capture, fileManager: fileManager)
        let captures = try modelContainer.mainContext.fetch(FetchDescriptor<Capture>())

        #expect(captures.isEmpty)
        #expect(!fileManager.fileExists(atPath: originalURL.fileSystemPath))
        #expect(!fileManager.fileExists(atPath: editedURL.fileSystemPath))
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
        #expect(state.selectedAnnotationID == annotationID)
        #expect(annotation == Annotation(id: annotationID, type: .blur, rect: CGRect(x: 20, y: 30, width: 40, height: 50)))
        #expect(state.annotations == [annotation])
    }

    @MainActor
    @Test func editorStateStoresPenStrokeAnnotationsWithStyle() throws {
        let imageURL = URL(fileURLWithPath: "/tmp/capture.png")
        let annotationID = UUID(uuidString: "00000000-0000-0000-0000-000000000018")!
        let points = [CGPoint(x: 10, y: 20), CGPoint(x: 50, y: 20)]
        var state = ScreenshotEditorState(originalImageURL: imageURL)

        let addedAnnotation = state.addStroke(
            kind: .pen,
            points: points,
            color: .blue,
            lineWidth: 10,
            id: annotationID
        )
        let annotation = try #require(addedAnnotation)
        let stroke = AnnotationStroke(kind: .pen, points: points, color: .blue, lineWidth: 10)

        #expect(state.selectedAnnotationID == annotationID)
        #expect(state.selectedStrokeColor == .blue)
        #expect(state.selectedStrokeLineWidth == 10)
        #expect(state.strokeStyle(for: .pen) == AnnotationStrokeStyle(color: .blue, lineWidth: 10))
        #expect(annotation == Annotation(id: annotationID, type: .stroke(stroke), rect: CGRect(x: 5, y: 15, width: 50, height: 10)))
    }

    @MainActor
    @Test func editorStateUpdatesCurrentStrokeToolSettingsSeparately() {
        let imageURL = URL(fileURLWithPath: "/tmp/capture.png")
        var state = ScreenshotEditorState(originalImageURL: imageURL, selectedTool: .highlighter)

        state.updateSelectedStrokeColor(.green)
        state.updateSelectedStrokeLineWidth(24)

        #expect(state.strokeStyle(for: .highlighter) == AnnotationStrokeStyle(color: .green, lineWidth: 24))
        #expect(state.strokeStyle(for: .pen) == .defaultPen)
        #expect(state.selectedStrokeColor == .green)
        #expect(state.selectedStrokeLineWidth == 24)
    }

    @MainActor
    @Test func editorStateSelectsTopmostStrokeAtImagePointAndAppliesItsStyle() throws {
        let imageURL = URL(fileURLWithPath: "/tmp/capture.png")
        let firstAnnotationID = UUID(uuidString: "00000000-0000-0000-0000-000000000019")!
        let secondAnnotationID = UUID(uuidString: "00000000-0000-0000-0000-000000000020")!
        var state = ScreenshotEditorState(originalImageURL: imageURL)

        state.addStroke(
            kind: .pen,
            points: [CGPoint(x: 0, y: 10), CGPoint(x: 100, y: 10)],
            color: .red,
            lineWidth: 4,
            id: firstAnnotationID
        )
        state.addStroke(
            kind: .highlighter,
            points: [CGPoint(x: 0, y: 12), CGPoint(x: 100, y: 12)],
            color: .yellow,
            lineWidth: 12,
            id: secondAnnotationID
        )

        #expect(state.selectAnnotation(containing: CGPoint(x: 50, y: 12)) == secondAnnotationID)
        #expect(state.selectedAnnotationID == secondAnnotationID)
        #expect(state.selectedStrokeColor == .yellow)
        #expect(state.selectedStrokeLineWidth == 12)
        #expect(state.selectedAnnotationUsesStrokeStyle)

        #expect(state.selectAnnotation(containing: CGPoint(x: 50, y: 40)) == nil)
        #expect(state.selectedAnnotationID == nil)
        #expect(!state.selectedAnnotationUsesStrokeStyle)
    }

    @MainActor
    @Test func editorStateUpdatesSelectedStrokeStyleAndBounds() throws {
        let imageURL = URL(fileURLWithPath: "/tmp/capture.png")
        let annotationID = UUID(uuidString: "00000000-0000-0000-0000-000000000021")!
        var state = ScreenshotEditorState(originalImageURL: imageURL)

        state.addStroke(
            kind: .highlighter,
            points: [CGPoint(x: 10, y: 10), CGPoint(x: 20, y: 10)],
            color: .red,
            lineWidth: 4,
            id: annotationID
        )
        state.updateSelectedStrokeColor(.green)
        state.updateSelectedStrokeLineWidth(14)

        let annotation = try #require(state.annotation(id: annotationID))
        guard case .stroke(let stroke) = annotation.type else {
            Issue.record("Expected a stroke annotation")
            return
        }

        #expect(stroke.kind == .highlighter)
        #expect(stroke.opacity == 0.35)
        #expect(stroke.color == .green)
        #expect(stroke.lineWidth == 14)
        #expect(state.strokeStyle(for: .highlighter) == AnnotationStrokeStyle(color: .green, lineWidth: 14))
        #expect(annotation.rect == CGRect(x: 3, y: 3, width: 24, height: 14))
    }

    @MainActor
    @Test func editorStateSelectsTopmostBlurAnnotationAtImagePoint() throws {
        let imageURL = URL(fileURLWithPath: "/tmp/capture.png")
        let firstAnnotationID = UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
        let secondAnnotationID = UUID(uuidString: "00000000-0000-0000-0000-000000000012")!
        var state = ScreenshotEditorState(originalImageURL: imageURL)

        state.addBlurRect(CGRect(x: 0, y: 0, width: 20, height: 20), id: firstAnnotationID)
        state.addBlurRect(CGRect(x: 10, y: 10, width: 20, height: 20), id: secondAnnotationID)

        #expect(state.selectAnnotation(containing: CGPoint(x: 15, y: 15)) == secondAnnotationID)
        #expect(state.selectedAnnotationID == secondAnnotationID)

        #expect(state.selectAnnotation(containing: CGPoint(x: 40, y: 40)) == nil)
        #expect(state.selectedAnnotationID == nil)
    }

    @MainActor
    @Test func editorStateRemovesSelectedAnnotation() throws {
        let imageURL = URL(fileURLWithPath: "/tmp/capture.png")
        let firstAnnotationID = UUID(uuidString: "00000000-0000-0000-0000-000000000013")!
        let secondAnnotationID = UUID(uuidString: "00000000-0000-0000-0000-000000000014")!
        var state = ScreenshotEditorState(originalImageURL: imageURL)

        state.addBlurRect(CGRect(x: 0, y: 0, width: 20, height: 20), id: firstAnnotationID)
        state.addBlurRect(CGRect(x: 20, y: 20, width: 20, height: 20), id: secondAnnotationID)
        state.selectAnnotation(id: firstAnnotationID)
        state.removeSelectedAnnotation()

        #expect(state.annotations.map(\.id) == [secondAnnotationID])
        #expect(state.selectedAnnotationID == nil)
    }

    @MainActor
    @Test func editorStateMovesAnnotationAndKeepsItInsideImageBounds() throws {
        let imageURL = URL(fileURLWithPath: "/tmp/capture.png")
        let annotationID = UUID(uuidString: "00000000-0000-0000-0000-000000000015")!
        var state = ScreenshotEditorState(originalImageURL: imageURL)
        let originalRect = CGRect(x: 20, y: 30, width: 40, height: 50)

        state.addBlurRect(originalRect, id: annotationID)
        state.moveAnnotation(
            id: annotationID,
            from: originalRect,
            by: CGSize(width: 130, height: 90),
            within: CGSize(width: 160, height: 120)
        )

        let movedAnnotation = try #require(state.annotation(id: annotationID))

        #expect(movedAnnotation.rect == CGRect(x: 120, y: 70, width: 40, height: 50))
        #expect(state.selectedAnnotationID == annotationID)
    }

    @MainActor
    @Test func editorStateMovesStrokeAnnotationAndKeepsPointsInsideBounds() throws {
        let imageURL = URL(fileURLWithPath: "/tmp/capture.png")
        let annotationID = UUID(uuidString: "00000000-0000-0000-0000-000000000022")!
        var state = ScreenshotEditorState(originalImageURL: imageURL)
        let addedStrokeAnnotation = state.addStroke(
            kind: .pen,
            points: [CGPoint(x: 20, y: 30), CGPoint(x: 60, y: 30)],
            color: .black,
            lineWidth: 8,
            id: annotationID
        )
        let addedAnnotation = try #require(addedStrokeAnnotation)

        state.moveAnnotation(
            id: annotationID,
            from: addedAnnotation,
            by: CGSize(width: 120, height: 80),
            within: CGSize(width: 160, height: 120)
        )

        let movedAnnotation = try #require(state.annotation(id: annotationID))
        guard case .stroke(let stroke) = movedAnnotation.type else {
            Issue.record("Expected a stroke annotation")
            return
        }

        #expect(stroke.points == [CGPoint(x: 116, y: 110), CGPoint(x: 156, y: 110)])
        #expect(movedAnnotation.rect == CGRect(x: 112, y: 106, width: 48, height: 8))
        #expect(state.selectedAnnotationID == annotationID)
    }

    @MainActor
    @Test func editorStateMovesStrokeFromOriginalDragSnapshotWithoutAccumulating() throws {
        let imageURL = URL(fileURLWithPath: "/tmp/capture.png")
        let annotationID = UUID(uuidString: "00000000-0000-0000-0000-000000000023")!
        var state = ScreenshotEditorState(originalImageURL: imageURL)
        let addedStrokeAnnotation = state.addStroke(
            kind: .pen,
            points: [CGPoint(x: 20, y: 30), CGPoint(x: 60, y: 30)],
            color: .black,
            lineWidth: 8,
            id: annotationID
        )
        let originalAnnotation = try #require(addedStrokeAnnotation)

        state.moveAnnotation(
            id: annotationID,
            from: originalAnnotation,
            by: CGSize(width: 10, height: 0),
            within: CGSize(width: 200, height: 120)
        )
        state.moveAnnotation(
            id: annotationID,
            from: originalAnnotation,
            by: CGSize(width: 20, height: 0),
            within: CGSize(width: 200, height: 120)
        )

        let movedAnnotation = try #require(state.annotation(id: annotationID))
        guard case .stroke(let stroke) = movedAnnotation.type else {
            Issue.record("Expected a stroke annotation")
            return
        }

        #expect(stroke.points == [CGPoint(x: 40, y: 30), CGPoint(x: 80, y: 30)])
        #expect(movedAnnotation.rect == CGRect(x: 36, y: 26, width: 48, height: 8))
    }

    @MainActor
    @Test func editorStateResizesAnnotationFromCornerHandle() throws {
        let imageURL = URL(fileURLWithPath: "/tmp/capture.png")
        let annotationID = UUID(uuidString: "00000000-0000-0000-0000-000000000016")!
        let originalRect = CGRect(x: 20, y: 30, width: 40, height: 50)
        var state = ScreenshotEditorState(originalImageURL: imageURL)

        state.addBlurRect(originalRect, id: annotationID)
        state.resizeAnnotation(
            id: annotationID,
            from: originalRect,
            handle: .topLeft,
            by: CGSize(width: 10, height: -20),
            within: CGSize(width: 120, height: 120)
        )

        let resizedAnnotation = try #require(state.annotation(id: annotationID))

        #expect(resizedAnnotation.rect == CGRect(x: 30, y: 10, width: 30, height: 70))
        #expect(state.selectedAnnotationID == annotationID)
    }

    @MainActor
    @Test func editorStateResizesAnnotationWithMinimumSizeAndImageBounds() throws {
        let imageURL = URL(fileURLWithPath: "/tmp/capture.png")
        let annotationID = UUID(uuidString: "00000000-0000-0000-0000-000000000017")!
        let originalRect = CGRect(x: 20, y: 30, width: 40, height: 50)
        var state = ScreenshotEditorState(originalImageURL: imageURL)

        state.addBlurRect(originalRect, id: annotationID)
        state.resizeAnnotation(
            id: annotationID,
            from: originalRect,
            handle: .bottomRight,
            by: CGSize(width: 200, height: -200),
            within: CGSize(width: 100, height: 100)
        )

        let resizedAnnotation = try #require(state.annotation(id: annotationID))

        #expect(resizedAnnotation.rect == CGRect(
            x: 20,
            y: 30,
            width: 80,
            height: ScreenshotEditorState.minimumAnnotationSideLength
        ))
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

    @Test func imageCanvasConvertsDragToImageTranslation() {
        let geometry = ImageCanvasGeometry(
            imageSize: CGSize(width: 200, height: 100),
            containerSize: CGSize(width: 100, height: 100)
        )

        let translation = geometry.imageTranslation(
            fromViewStart: CGPoint(x: 25, y: 25),
            toViewEnd: CGPoint(x: 75, y: 50)
        )

        #expect(translation == CGSize(width: 100, height: 50))
    }

    @Test func imageCanvasScalesImageDistanceIntoViewDistance() {
        let geometry = ImageCanvasGeometry(
            imageSize: CGSize(width: 200, height: 100),
            containerSize: CGSize(width: 100, height: 100)
        )

        #expect(geometry.viewDistance(forImageDistance: ImageRenderer.defaultBlurRadius) == 6)
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
    @Test func imageRendererBakesEdgeBlurAnnotationsIntoPNG() throws {
        let fileManager = FileManager.default
        let baseDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("ScreenshotMaxxingTests-\(UUID().uuidString)", isDirectory: true)
        let imageURL = baseDirectory.appendingPathComponent("split.png")
        defer {
            try? fileManager.removeItem(at: baseDirectory)
        }

        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        try makeVerticalSplitPNGData(width: 12, height: 8).write(to: imageURL)

        let renderer = ImageRenderer()
        let uneditedPNGData = try renderer.renderPNG(imageURL: imageURL, annotations: [])
        let renderedPNGData = try renderer.renderPNG(
            imageURL: imageURL,
            annotations: [
                Annotation(type: .blur, rect: CGRect(x: 0, y: 0, width: 8, height: 8))
            ]
        )
        let originalRed = try redChannel(in: uneditedPNGData, x: 5, y: 4)
        let renderedRed = try redChannel(in: renderedPNGData, x: 5, y: 4)
        let outsideOriginalRed = try redChannel(in: uneditedPNGData, x: 10, y: 4)
        let outsideRenderedRed = try redChannel(in: renderedPNGData, x: 10, y: 4)

        #expect(abs(renderedRed - originalRed) > 0.01)
        #expect(abs(outsideRenderedRed - outsideOriginalRed) < 0.01)
    }

    @MainActor
    @Test func imageRendererBakesPenStrokeAnnotationsIntoPNG() throws {
        let fileManager = FileManager.default
        let baseDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("ScreenshotMaxxingTests-\(UUID().uuidString)", isDirectory: true)
        let imageURL = baseDirectory.appendingPathComponent("split.png")
        defer {
            try? fileManager.removeItem(at: baseDirectory)
        }

        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        try makeVerticalSplitPNGData(width: 12, height: 8).write(to: imageURL)

        let renderer = ImageRenderer()
        let stroke = AnnotationStroke(
            kind: .pen,
            points: [CGPoint(x: 1, y: 4), CGPoint(x: 10, y: 4)],
            color: .blue,
            lineWidth: 4
        )
        let renderedPNGData = try renderer.renderPNG(
            imageURL: imageURL,
            annotations: [Annotation(type: .stroke(stroke), rect: stroke.visibleBounds)]
        )
        let renderedColor = try color(in: renderedPNGData, x: 6, y: 4)

        #expect(renderedColor.blueComponent > 0.5)
        #expect(renderedColor.redComponent < 0.4)
    }

    @MainActor
    @Test func imageRendererBakesHighlighterStrokeWithOpacityIntoPNG() throws {
        let fileManager = FileManager.default
        let baseDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("ScreenshotMaxxingTests-\(UUID().uuidString)", isDirectory: true)
        let imageURL = baseDirectory.appendingPathComponent("split.png")
        defer {
            try? fileManager.removeItem(at: baseDirectory)
        }

        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        try makeVerticalSplitPNGData(width: 12, height: 8).write(to: imageURL)

        let renderer = ImageRenderer()
        let stroke = AnnotationStroke(
            kind: .highlighter,
            points: [CGPoint(x: 1, y: 4), CGPoint(x: 5, y: 4)],
            color: .yellow,
            lineWidth: 6
        )
        let renderedPNGData = try renderer.renderPNG(
            imageURL: imageURL,
            annotations: [Annotation(type: .stroke(stroke), rect: stroke.visibleBounds)]
        )
        let renderedColor = try color(in: renderedPNGData, x: 2, y: 4)

        #expect(renderedColor.redComponent > 0.15)
        #expect(renderedColor.redComponent < 0.8)
        #expect(renderedColor.greenComponent > 0.10)
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
    @Test func editorClipboardWritesStringToPasteboard() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("ScreenshotMaxxingTests-\(UUID().uuidString)"))
        defer {
            pasteboard.releaseGlobally()
        }
        let filePath = "/tmp/ScreenshotMaxxing Tests/edited.png"

        let copied = EditorClipboard.copyString(filePath, to: pasteboard)

        #expect(copied)
        #expect(pasteboard.string(forType: .string) == filePath)
    }

    @MainActor
    @Test func editorFileSaverWritesEditedImageAndCreatesNewHistoryCapture() throws {
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
        let pngData = try makeVerticalSplitPNGData(width: 2, height: 2)
        let editedFileURL = try saver.saveEditedPNG(
            pngData,
            originalFileName: capture.fileName,
            capture: capture,
            baseDirectory: baseDirectory
        )
        let captures = try modelContainer.mainContext.fetch(FetchDescriptor<Capture>())
        let editedCapture = try #require(captures.first { $0.originalFilePath == editedFileURL.fileSystemPath })

        #expect(fileManager.fileExists(atPath: editedFileURL.fileSystemPath))
        #expect(editedFileURL.deletingLastPathComponent().lastPathComponent == "edited")
        #expect(captures.count == 2)
        #expect(capture.editedFilePath == nil)
        #expect(editedCapture.fileName == editedFileURL.lastPathComponent)
        #expect(editedCapture.captureMode == capture.captureMode)
        #expect(editedCapture.width == 2)
        #expect(editedCapture.height == 2)
        #expect(editedCapture.editedFilePath == nil)
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

    @MainActor
    @Test func captureHistorySearchMatchesDatesAndMetadata() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var mayComponents = DateComponents()
        mayComponents.calendar = calendar
        mayComponents.timeZone = calendar.timeZone
        mayComponents.year = 2026
        mayComponents.month = 5
        mayComponents.day = 26
        mayComponents.hour = 10
        mayComponents.minute = 15
        var juneComponents = mayComponents
        juneComponents.month = 6
        juneComponents.day = 1
        juneComponents.hour = 11
        let mayCapture = Capture(
            createdAt: try #require(calendar.date(from: mayComponents)),
            fileName: "may.png",
            captureMode: "area",
            width: 20,
            height: 10,
            originalFilePath: "/tmp/may.png"
        )
        let juneCapture = Capture(
            createdAt: try #require(calendar.date(from: juneComponents)),
            fileName: "june.png",
            captureMode: "fullscreen",
            width: 40,
            height: 30,
            originalFilePath: "/tmp/june.png"
        )
        let captures = [mayCapture, juneCapture]

        #expect(CaptureHistoryData.filteredCaptures(captures, searchText: "2026-05-26", calendar: calendar).map(\.fileName) == ["may.png"])
        #expect(CaptureHistoryData.filteredCaptures(captures, searchText: "May 26", calendar: calendar).map(\.fileName) == ["may.png"])
        #expect(CaptureHistoryData.filteredCaptures(captures, searchText: "05/26/26", calendar: calendar).map(\.fileName) == ["may.png"])
        #expect(CaptureHistoryData.filteredCaptures(captures, searchText: "10:15", calendar: calendar).map(\.fileName) == ["may.png"])
        #expect(CaptureHistoryData.filteredCaptures(captures, searchText: "fullscreen", calendar: calendar).map(\.fileName) == ["june.png"])
        #expect(CaptureHistoryData.filteredCaptures(captures, searchText: "missing", calendar: calendar).isEmpty)
    }

    @MainActor
    @Test func captureHistoryDeletionRemovesSelectedCaptureAndEditedVersionsFromDiskAndStore() throws {
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
        let originalURL = directories.originals.appendingPathComponent("area-20260526-101500-aaaaaaaa.png")
        let editedURL = directories.edited.appendingPathComponent("area-20260526-101500-aaaaaaaa-edited-bbbbbbbb.png")
        let diskOnlyEditedURL = directories.edited.appendingPathComponent("area-20260526-101500-aaaaaaaa-edited-cccccccc.png")
        let unrelatedURL = directories.edited.appendingPathComponent("window-20260526-101500-dddddddd-edited-eeeeeeee.png")

        try [originalURL, editedURL, diskOnlyEditedURL, unrelatedURL].forEach { fileURL in
            try Data("png".utf8).write(to: fileURL)
        }

        let modelContainer = try PersistenceController.makeModelContainer(inMemory: true)
        let originalCapture = Capture(
            fileName: originalURL.lastPathComponent,
            captureMode: "area",
            width: 20,
            height: 10,
            originalFilePath: originalURL.fileSystemPath
        )
        let editedCapture = Capture(
            fileName: editedURL.lastPathComponent,
            captureMode: "area",
            width: 20,
            height: 10,
            originalFilePath: editedURL.fileSystemPath
        )
        let unrelatedCapture = Capture(
            fileName: unrelatedURL.lastPathComponent,
            captureMode: "window",
            width: 40,
            height: 30,
            originalFilePath: unrelatedURL.fileSystemPath
        )

        modelContainer.mainContext.insert(originalCapture)
        modelContainer.mainContext.insert(editedCapture)
        modelContainer.mainContext.insert(unrelatedCapture)
        try modelContainer.mainContext.save()

        let allCaptures = try modelContainer.mainContext.fetch(FetchDescriptor<Capture>())
        let capturesToDelete = CaptureHistoryData.capturesToDelete(
            from: allCaptures,
            selectedIDs: [originalCapture.id]
        )
        let filePathsToDelete = try Set(CaptureHistoryData.fileURLsToDelete(
            for: capturesToDelete,
            allCaptures: allCaptures,
            fileManager: fileManager
        ).map(\.fileSystemPath))

        #expect(Set(capturesToDelete.map(\.fileName)) == [originalURL.lastPathComponent, editedURL.lastPathComponent])
        #expect(filePathsToDelete.contains(originalURL.fileSystemPath))
        #expect(filePathsToDelete.contains(editedURL.fileSystemPath))
        #expect(filePathsToDelete.contains(diskOnlyEditedURL.fileSystemPath))
        #expect(!filePathsToDelete.contains(unrelatedURL.fileSystemPath))

        try CaptureHistoryData.deleteCaptures(
            capturesToDelete,
            from: modelContainer.mainContext,
            allCaptures: allCaptures,
            fileManager: fileManager
        )
        let remainingCaptures = try modelContainer.mainContext.fetch(FetchDescriptor<Capture>())

        #expect(remainingCaptures.map(\.fileName) == [unrelatedURL.lastPathComponent])
        #expect(!fileManager.fileExists(atPath: originalURL.fileSystemPath))
        #expect(!fileManager.fileExists(atPath: editedURL.fileSystemPath))
        #expect(!fileManager.fileExists(atPath: diskOnlyEditedURL.fileSystemPath))
        #expect(fileManager.fileExists(atPath: unrelatedURL.fileSystemPath))
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
        try color(in: pngData, x: x, y: y).redComponent
    }

    private func color(in pngData: Data, x: Int, y: Int) throws -> NSColor {
        guard let imageRep = NSBitmapImageRep(data: pngData),
              let color = imageRep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
            throw ImageRendererError.renderFailed
        }

        return color
    }

}
