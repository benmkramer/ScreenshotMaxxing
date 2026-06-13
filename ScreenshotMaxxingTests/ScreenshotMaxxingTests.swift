//
//  ScreenshotMaxxingTests.swift
//  ScreenshotMaxxingTests
//
//  Created by Ben Kramer on 5/26/26.
//

import Testing
import AppKit
@preconcurrency import AVFoundation
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
    @Test func menuBarHistoryItemAdvertisesGlobalHistoryShortcut() throws {
        let menu = MenuBarController.makeMenu(target: nil)
        let historyItem = try #require(menu.items.first {
            $0.title == "Open History (Control-Option-Command-H)"
        })

        #expect(historyItem.keyEquivalent == "h")
        #expect(historyItem.keyEquivalentModifierMask == [.control, .option, .command])
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
        #expect(fileManager.fileExists(atPath: directories.thumbnails.fileSystemPath))
        #expect(originalURL.deletingLastPathComponent() == directories.originals)
        #expect(originalURL.lastPathComponent == "capture-area-19700101-000000-00000000.png")

        try Data("png".utf8).write(to: originalURL)
        #expect(fileManager.fileExists(atPath: originalURL.fileSystemPath))
    }

    @MainActor
    @Test func fileLocationsCreateMp4OriginalsAndVideoThumbnails() throws {
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
            captureMode: "recording area",
            directories: directories,
            date: Date(timeIntervalSince1970: 0),
            uuid: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            fileExtension: "mp4"
        )
        let thumbnailURL = FileLocations.uniqueThumbnailFileURL(
            originalFileName: originalURL.lastPathComponent,
            directories: directories,
            uuid: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        )

        #expect(originalURL.deletingLastPathComponent() == directories.originals)
        #expect(originalURL.lastPathComponent == "recording-area-19700101-000000-00000000.mp4")
        #expect(thumbnailURL.deletingLastPathComponent() == directories.thumbnails)
        #expect(thumbnailURL.lastPathComponent == "recording-area-19700101-000000-00000000-thumbnail-00000000.png")
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

    @Test func recordingAreaFocusOverlayConvertsScreenRectToLocalCoordinates() {
        let screenFrame = CGRect(x: -1440, y: 0, width: 1440, height: 900)
        let recordingRect = CGRect(x: -1200, y: 120, width: 400, height: 300)

        let localRect = RecordingAreaFocusOverlayGeometry.localClearRect(
            for: recordingRect,
            in: screenFrame
        )

        #expect(localRect == CGRect(x: 240, y: 120, width: 400, height: 300))
    }

    @Test func recordingWindowSelectionConvertsCGWindowBoundsToAppKitCoordinates() {
        let display = RecordingDisplayCoordinateSpace(
            displayID: 1,
            cgFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            appKitFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)
        )

        let rect = RecordingWindowSelectionResolver.appKitRect(
            forCGWindowBounds: CGRect(x: 100, y: 40, width: 400, height: 300),
            displays: [display]
        )

        #expect(rect == CGRect(x: 100, y: 560, width: 400, height: 300))
    }

    @Test func recordingWindowSelectionUsesFrontmostWindowAtSelectedPoint() {
        let display = RecordingDisplayCoordinateSpace(
            displayID: 1,
            cgFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            appKitFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)
        )
        let backWindow = RecordingWindowCandidate(
            windowID: 101,
            processID: 10,
            layer: 0,
            bounds: CGRect(x: 100, y: 100, width: 300, height: 300)
        )
        let frontWindow = RecordingWindowCandidate(
            windowID: 202,
            processID: 20,
            layer: 0,
            bounds: CGRect(x: 150, y: 150, width: 300, height: 300)
        )

        let windowID = RecordingWindowSelectionResolver.selectedWindowID(
            at: CGPoint(x: 200, y: 550),
            candidates: [frontWindow, backWindow],
            displays: [display]
        )

        #expect(windowID == 202)
    }

    @Test func recordingWindowSelectionIgnoresOwnProcessAndUnselectableWindows() {
        let display = RecordingDisplayCoordinateSpace(
            displayID: 1,
            cgFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            appKitFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)
        )
        let ownWindow = RecordingWindowCandidate(
            windowID: 101,
            processID: 10,
            layer: 0,
            bounds: CGRect(x: 100, y: 100, width: 300, height: 300)
        )
        let menuWindow = RecordingWindowCandidate(
            windowID: 202,
            processID: 20,
            layer: 1,
            bounds: CGRect(x: 100, y: 100, width: 300, height: 300)
        )
        let tinyWindow = RecordingWindowCandidate(
            windowID: 303,
            processID: 30,
            layer: 0,
            bounds: CGRect(x: 100, y: 100, width: 30, height: 30)
        )
        let selectableWindow = RecordingWindowCandidate(
            windowID: 404,
            processID: 40,
            layer: 0,
            bounds: CGRect(x: 100, y: 100, width: 300, height: 300)
        )

        let windowID = RecordingWindowSelectionResolver.selectedWindowID(
            at: CGPoint(x: 200, y: 550),
            candidates: [ownWindow, menuWindow, tinyWindow, selectableWindow],
            displays: [display],
            excludingProcessID: 10
        )

        #expect(windowID == 404)
    }

    @Test func defaultAreaCaptureShortcutUsesControlShiftFour() {
        let shortcut = GlobalKeyboardShortcut.defaultAreaCapture

        #expect(shortcut.displayString == "Control-Shift-4")
    }

    @Test func defaultCaptureOptionsShortcutUsesControlShiftFive() {
        let shortcut = GlobalKeyboardShortcut.defaultCaptureOptions

        #expect(shortcut.displayString == "Control-Shift-5")
    }

    @Test func defaultOpenHistoryShortcutUsesUniqueGlobalChord() {
        let shortcut = GlobalKeyboardShortcut.defaultOpenHistory

        #expect(shortcut.displayString == "Control-Option-Command-H")
        #expect(!shortcut.isReservedSystemScreenshotShortcut)
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
        #expect(visibleTitles[4] == "Open History (Control-Option-Command-H)")
    }

    @Test func editorToolbarShowsImplementedAnnotationTools() {
        #expect(EditorTool.implementedTools == [.select, .blur, .pen, .highlighter, .rectangle, .arrow, .text])
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
        manager.handleHotKeyPressed(id: HotKeyManager.openHistoryHotKeyID)
        manager.handleHotKeyPressed(id: 999)

        #expect(actions == [.captureArea, .showCaptureOptions, .openHistory])
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
        #expect(preferences.openHistoryShortcut.displayString == "Control-Option-Command-H")
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
            openHistoryShortcut: .defaultOpenHistory,
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
        let openHistoryShortcut = GlobalKeyboardShortcut(
            keyCode: UInt32(kVK_ANSI_C),
            carbonModifiers: UInt32(controlKey | cmdKey)
        )

        let updatedAreaCapture = preferences.updatingAreaCaptureShortcut(areaCaptureShortcut)
        let updatedCaptureOptions = updatedAreaCapture.updatingCaptureOptionsShortcut(captureOptionsShortcut)
        let updatedOpenHistory = updatedCaptureOptions.updatingOpenHistoryShortcut(openHistoryShortcut)

        #expect(updatedAreaCapture.areaCaptureShortcut == areaCaptureShortcut)
        #expect(updatedAreaCapture.captureOptionsShortcut == .defaultCaptureOptions)
        #expect(updatedAreaCapture.openHistoryShortcut == .defaultOpenHistory)
        #expect(updatedCaptureOptions.areaCaptureShortcut == areaCaptureShortcut)
        #expect(updatedCaptureOptions.captureOptionsShortcut == captureOptionsShortcut)
        #expect(updatedCaptureOptions.openHistoryShortcut == .defaultOpenHistory)
        #expect(updatedOpenHistory.areaCaptureShortcut == areaCaptureShortcut)
        #expect(updatedOpenHistory.captureOptionsShortcut == captureOptionsShortcut)
        #expect(updatedOpenHistory.openHistoryShortcut == openHistoryShortcut)
        #expect(updatedOpenHistory.resettingAreaCaptureShortcut().areaCaptureShortcut == .defaultAreaCapture)
        #expect(updatedOpenHistory.resettingCaptureOptionsShortcut().captureOptionsShortcut == .defaultCaptureOptions)
        #expect(updatedOpenHistory.resettingOpenHistoryShortcut().openHistoryShortcut == .defaultOpenHistory)
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
        #expect(CaptureOptionsView.availableRecordingModes == [.area, .window, .fullscreen])
    }

    @Test func recordingOptionsKeepMp4ContainerWithoutMicrophone() {
        #expect(RecordingOptions(mode: .area, microphoneEnabled: false, systemAudioEnabled: false).outputContainer == .mp4)
        #expect(RecordingOptions(mode: .area, microphoneEnabled: false, systemAudioEnabled: true).outputContainer == .mp4)
        #expect(RecordingOptions(mode: .area, microphoneEnabled: false, systemAudioEnabled: true).outputContainer.fileExtension == "mp4")
    }

    @Test func recordingOptionsUseMovContainerWithMicrophone() {
        #expect(RecordingOptions(mode: .window, microphoneEnabled: true, systemAudioEnabled: false).outputContainer == .mov)
        #expect(RecordingOptions(mode: .window, microphoneEnabled: true, systemAudioEnabled: true).outputContainer == .mov)
        #expect(RecordingOptions(mode: .window, microphoneEnabled: true, systemAudioEnabled: true).outputContainer.fileExtension == "mov")
    }

    @MainActor
    @Test func recordingControllerStopRecoversCompletedFileAndReturnsResult() async throws {
        let fileManager = FileManager.default
        let baseDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("ScreenshotMaxxingTests-\(UUID().uuidString)", isDirectory: true)
        let outputURL = baseDirectory.appendingPathComponent("recording.mp4")
        let options = RecordingOptions(mode: .area, microphoneEnabled: false, systemAudioEnabled: true)
        let session = SpyRecordingSession(
            options: options,
            outputURL: outputURL,
            dimensions: CGSize(width: 96, height: 64),
            thumbnailBaseDirectory: baseDirectory
        )
        defer {
            try? fileManager.removeItem(at: baseDirectory)
        }

        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        let controller = RecordingController(
            fileManager: fileManager,
            sessionFactory: { requestedOptions, requestedBaseDirectory in
                #expect(requestedOptions == options)
                #expect(requestedBaseDirectory == baseDirectory)
                return session
            },
            recoveryRetryCount: 1,
            recoveryRetryDelayNanoseconds: 0,
            completionFallbackDelayNanoseconds: 0,
            sleep: { _ in }
        )

        let recordTask = Task {
            try await controller.record(options: options, baseDirectory: baseDirectory)
        }
        try await waitForCondition(session.showCount == 1)
        try await makeTestVideo(at: outputURL, durationSeconds: 2.5, size: CGSize(width: 96, height: 64))

        await controller.stopActiveRecording()
        let result = try await recordTask.value

        #expect(session.didRequestStop)
        #expect(session.stopCount == 1)
        #expect(session.closeCount >= 1)
        #expect(result.mode == .area)
        #expect(result.fileURL == outputURL)
        #expect(isApproximately(result.durationSeconds, 2.5, accuracy: 0.08))
        #expect(result.width == 96)
        #expect(result.height == 64)
        #expect(result.microphoneEnabled == false)
        #expect(result.systemAudioEnabled == true)
        #expect(result.thumbnailURL.deletingLastPathComponent().lastPathComponent == "thumbnails")
        #expect(fileManager.fileExists(atPath: result.thumbnailURL.fileSystemPath))
    }

    @MainActor
    @Test func recordingControllerRestartReplacesSessionAndCancellationCleansUpFiles() async throws {
        let fileManager = FileManager.default
        let baseDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("ScreenshotMaxxingTests-\(UUID().uuidString)", isDirectory: true)
        let firstOutputURL = baseDirectory.appendingPathComponent("first-recording.mp4")
        let restartedOutputURL = baseDirectory.appendingPathComponent("restarted-recording.mp4")
        let options = RecordingOptions(mode: .fullscreen, microphoneEnabled: false)
        let firstSession = SpyRecordingSession(options: options, outputURL: firstOutputURL)
        let restartedSession = SpyRecordingSession(options: options, outputURL: restartedOutputURL)
        defer {
            try? fileManager.removeItem(at: baseDirectory)
        }

        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        try Data("first".utf8).write(to: firstOutputURL)
        try Data("restarted".utf8).write(to: restartedOutputURL)

        let controller = RecordingController(
            fileManager: fileManager,
            sessionFactory: { _, _ in
                firstSession
            },
            restartSessionFactory: { activeSession in
                #expect(activeSession === firstSession)
                return restartedSession
            },
            sleep: { _ in }
        )
        let recordTask = Task {
            try await controller.record(options: options, baseDirectory: baseDirectory)
        }
        try await waitForCondition(firstSession.showCount == 1)

        await controller.restartActiveRecording()
        try await waitForCondition(restartedSession.showCount == 1)

        #expect(firstSession.didRequestRestart)
        #expect(firstSession.stopCount == 1)
        #expect(firstSession.closeCount >= 1)
        #expect(!fileManager.fileExists(atPath: firstOutputURL.fileSystemPath))

        recordTask.cancel()

        do {
            _ = try await recordTask.value
            Issue.record("Expected canceled recording task to throw")
        } catch RecordingSelectionError.cancelled {
        } catch is CancellationError {
        }

        #expect(restartedSession.stopCount == 1)
        #expect(restartedSession.closeCount >= 1)
        #expect(!fileManager.fileExists(atPath: restartedOutputURL.fileSystemPath))
    }

    @MainActor
    private final class SpyRecordingSession: RecordingSessionControlling {
        let options: RecordingOptions
        let outputURL: URL
        let mode: RecordingMode
        let dimensions: CGSize
        let thumbnailBaseDirectory: URL?
        var didRequestStop = false
        var didRequestRestart = false
        var completionFallbackTask: Task<Void, Never>?
        var showCount = 0
        var closeCount = 0
        var stopCount = 0
        var stopError: Error?

        init(
            options: RecordingOptions,
            outputURL: URL,
            dimensions: CGSize = CGSize(width: 640, height: 360),
            thumbnailBaseDirectory: URL? = nil
        ) {
            self.options = options
            self.outputURL = outputURL
            self.mode = options.mode
            self.dimensions = dimensions
            self.thumbnailBaseDirectory = thumbnailBaseDirectory
        }

        func showChrome() {
            showCount += 1
        }

        func closeChrome() {
            closeCount += 1
        }

        func stopCapture() async throws {
            stopCount += 1

            if let stopError {
                throw stopError
            }
        }
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

    @Test func screenCapturePermissionTargetsScreenRecordingSettings() {
        let expectedURL = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture")

        #expect(AppPermission.screenCapture.settingsURL == expectedURL)
        #expect(AppPermission.screenCapture.settingsURL?.absoluteString.contains("Privacy_Accessibility") == false)
        #expect(AppPermission.directScreenAccess.settingsURL == nil)
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
    @Test func permissionOnboardingModelShowsCheckingStateDuringDirectScreenAccessRequest() async {
        var approvalCompleted = false
        var approvalContinuation: CheckedContinuation<Bool, Never>?
        let controller = AppPermissionController(
            screenCapturePermissionController: ScreenCapturePermissionController(preflightAccess: {
                true
            }),
            directScreenAccessController: DirectScreenAccessController {
                approvalCompleted
            } requestApproval: {
                await withCheckedContinuation { continuation in
                    approvalContinuation = continuation
                }
            } markApprovalCompleted: {
                approvalCompleted = true
            }
        )
        let model = PermissionOnboardingModel(permissionController: controller)

        let requestTask = Task {
            await model.requestAccess(for: .directScreenAccess)
        }

        while approvalContinuation == nil {
            await Task.yield()
        }

        #expect(model.isCheckingAccess(for: .directScreenAccess))
        #expect(model.actionTitle(for: .directScreenAccess) == "Try Again")

        approvalContinuation?.resume(returning: true)
        await requestTask.value

        #expect(!model.isCheckingAccess(for: .directScreenAccess))
        #expect(model.allGranted)
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
        let openHistoryShortcut = GlobalKeyboardShortcut(
            keyCode: UInt32(kVK_ANSI_C),
            carbonModifiers: UInt32(controlKey | cmdKey)
        )

        let store = ShortcutSettingsStore(userDefaults: userDefaults)
        try store.saveAreaCaptureShortcut(areaCaptureShortcut)
        try store.saveCaptureOptionsShortcut(captureOptionsShortcut)
        try store.saveOpenHistoryShortcut(openHistoryShortcut)

        let reloadedStore = ShortcutSettingsStore(userDefaults: userDefaults)

        #expect(reloadedStore.areaCaptureShortcut() == areaCaptureShortcut)
        #expect(reloadedStore.areaCaptureShortcut().displayString == "Option-Command-A")
        #expect(reloadedStore.captureOptionsShortcut() == captureOptionsShortcut)
        #expect(reloadedStore.captureOptionsShortcut().displayString == "Control-Option-B")
        #expect(reloadedStore.openHistoryShortcut() == openHistoryShortcut)
        #expect(reloadedStore.openHistoryShortcut().displayString == "Control-Command-C")

        reloadedStore.resetAreaCaptureShortcut()
        reloadedStore.resetCaptureOptionsShortcut()
        reloadedStore.resetOpenHistoryShortcut()

        #expect(reloadedStore.areaCaptureShortcut() == .defaultAreaCapture)
        #expect(reloadedStore.captureOptionsShortcut() == .defaultCaptureOptions)
        #expect(reloadedStore.openHistoryShortcut() == .defaultOpenHistory)
    }

    @Test func recordingSettingsStorePersistsAudioDefaults() throws {
        let suiteName = "ScreenshotMaxxingTests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let store = RecordingSettingsStore(userDefaults: userDefaults)
        try store.saveMicrophoneEnabled(true)
        try store.saveSystemAudioEnabled(true)
        let reloadedStore = RecordingSettingsStore(userDefaults: userDefaults)

        #expect(reloadedStore.microphoneEnabled())
        #expect(reloadedStore.systemAudioEnabled())
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
        #expect(capture.mediaType == CaptureMediaType.image.rawValue)
        #expect(capture.width == 2)
        #expect(capture.height == 3)
        #expect(capture.durationSeconds == nil)
        #expect(!capture.microphoneEnabled)
        #expect(!capture.systemAudioEnabled)
        #expect(capture.thumbnailFilePath == nil)
        #expect(capture.originalFilePath == imageURL.fileSystemPath)
        #expect(captures.count == 1)
    }

    @MainActor
    @Test func captureMetadataStoreDeletesCaptureHistoryAndTrashesLocalFiles() throws {
        let fileManager = FileManager.default
        let fileTrash = SpyFileTrash()
        let baseDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("ScreenshotMaxxingTests-\(UUID().uuidString)", isDirectory: true)
        let originalURL = baseDirectory.appendingPathComponent("original.png")
        let editedURL = baseDirectory.appendingPathComponent("edited.png")
        let thumbnailURL = baseDirectory.appendingPathComponent("thumbnail.png")
        defer {
            try? fileManager.removeItem(at: baseDirectory)
        }

        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        try makePNGData(width: 2, height: 2).write(to: originalURL)
        try makePNGData(width: 2, height: 2).write(to: editedURL)
        try makePNGData(width: 2, height: 2).write(to: thumbnailURL)

        let modelContainer = try PersistenceController.makeModelContainer(inMemory: true)
        let capture = Capture(
            fileName: originalURL.lastPathComponent,
            captureMode: "area",
            width: 2,
            height: 2,
            thumbnailFilePath: thumbnailURL.fileSystemPath,
            originalFilePath: originalURL.fileSystemPath,
            editedFilePath: editedURL.fileSystemPath
        )
        modelContainer.mainContext.insert(capture)
        try modelContainer.mainContext.save()

        let store = CaptureMetadataStore(modelContainer: modelContainer)
        try store.deleteCaptureFromHistoryAndDisk(capture, fileManager: fileManager, fileTrash: fileTrash)
        let captures = try modelContainer.mainContext.fetch(FetchDescriptor<Capture>())

        #expect(captures.isEmpty)
        #expect(Set(fileTrash.trashedFileURLs.map(\.fileSystemPath)) == [
            originalURL.fileSystemPath,
            editedURL.fileSystemPath,
            thumbnailURL.fileSystemPath
        ])
        #expect(fileManager.fileExists(atPath: originalURL.fileSystemPath))
        #expect(fileManager.fileExists(atPath: editedURL.fileSystemPath))
        #expect(fileManager.fileExists(atPath: thumbnailURL.fileSystemPath))
    }

    @Test func captureDefaultsKeepExistingCapturesAsImages() {
        let capture = Capture(
            fileName: "area.png",
            captureMode: "area",
            width: 2,
            height: 3,
            originalFilePath: "/tmp/area.png"
        )

        #expect(capture.mediaType == CaptureMediaType.image.rawValue)
        #expect(capture.durationSeconds == nil)
        #expect(!capture.microphoneEnabled)
        #expect(!capture.systemAudioEnabled)
        #expect(capture.thumbnailFilePath == nil)
    }

    @MainActor
    @Test func captureMetadataStorePersistsVideoDetails() throws {
        let modelContainer = try PersistenceController.makeModelContainer(inMemory: true)
        let store = CaptureMetadataStore(modelContainer: modelContainer)
        let videoURL = URL(fileURLWithPath: "/tmp/recording-area.mp4")
        let thumbnailURL = URL(fileURLWithPath: "/tmp/recording-area-thumbnail.png")

        let capture = try store.saveCapture(result: RecordingResult(
            mode: .area,
            fileURL: videoURL,
            durationSeconds: 12.5,
            width: 1920,
            height: 1080,
            thumbnailURL: thumbnailURL,
            microphoneEnabled: true,
            systemAudioEnabled: true
        ))
        let captures = try modelContainer.mainContext.fetch(FetchDescriptor<Capture>())

        #expect(capture.fileName == "recording-area.mp4")
        #expect(capture.captureMode == "area")
        #expect(capture.mediaType == CaptureMediaType.video.rawValue)
        #expect(capture.durationSeconds == 12.5)
        #expect(capture.microphoneEnabled)
        #expect(capture.systemAudioEnabled)
        #expect(capture.thumbnailFilePath == thumbnailURL.fileSystemPath)
        #expect(capture.originalFilePath == videoURL.fileSystemPath)
        #expect(captures.count == 1)
    }

    @MainActor
    @Test func captureMetadataStoreCarriesAudioFlagsToEditedVideoCaptures() throws {
        let modelContainer = try PersistenceController.makeModelContainer(inMemory: true)
        let store = CaptureMetadataStore(modelContainer: modelContainer)
        let sourceCapture = Capture(
            fileName: "recording-area.mov",
            captureMode: "area",
            mediaType: CaptureMediaType.video.rawValue,
            width: 1920,
            height: 1080,
            durationSeconds: 12.5,
            microphoneEnabled: true,
            systemAudioEnabled: false,
            thumbnailFilePath: "/tmp/recording-area-thumbnail.png",
            originalFilePath: "/tmp/recording-area.mov"
        )

        let editedCapture = try store.saveEditedVideoCapture(
            editedFileURL: URL(fileURLWithPath: "/tmp/recording-area-edited.mp4"),
            thumbnailURL: URL(fileURLWithPath: "/tmp/recording-area-edited-thumbnail.png"),
            sourceCapture: sourceCapture,
            durationSeconds: 10,
            dimensions: CGSize(width: 1920, height: 1080)
        )

        #expect(editedCapture.microphoneEnabled)
        #expect(!editedCapture.systemAudioEnabled)
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

    @MainActor
    @Test func screenshotEditorWindowMatchesCanonicalImageURL() {
        let imageURL = URL(fileURLWithPath: "/tmp/ScreenshotMaxxingTests/current/../example-capture.png")
        let controller = ScreenshotEditorWindowController(imageURL: imageURL)
        defer {
            controller.window?.close()
        }

        #expect(controller.isEditingImage(at: URL(fileURLWithPath: "/tmp/ScreenshotMaxxingTests/example-capture.png")))
        #expect(!controller.isEditingImage(at: URL(fileURLWithPath: "/tmp/ScreenshotMaxxingTests/other-capture.png")))
    }

    @MainActor
    @Test func videoEditorWindowCreatesAndLaysOutRecordedVideo() {
        let videoURL = URL(fileURLWithPath: "/tmp/example-recording.mp4")
        let controller = VideoEditorWindowController(videoURL: videoURL)
        defer {
            controller.window?.close()
        }

        controller.window?.contentView?.layoutSubtreeIfNeeded()

        #expect(controller.window?.title == "example-recording.mp4 - ScreenshotMaxxing")
    }

    @MainActor
    @Test func videoEditorWindowMatchesCanonicalVideoURL() {
        let videoURL = URL(fileURLWithPath: "/tmp/ScreenshotMaxxingTests/current/../example-recording.mp4")
        let controller = VideoEditorWindowController(videoURL: videoURL)
        defer {
            controller.window?.close()
        }

        #expect(controller.isEditingVideo(at: URL(fileURLWithPath: "/tmp/ScreenshotMaxxingTests/example-recording.mp4")))
        #expect(!controller.isEditingVideo(at: URL(fileURLWithPath: "/tmp/ScreenshotMaxxingTests/other-recording.mp4")))
    }

    @Test func imageCanvasFitsImageWithoutDistortion() {
        let geometry = ImageCanvasGeometry(
            imageSize: CGSize(width: 200, height: 100),
            containerSize: CGSize(width: 100, height: 100)
        )

        #expect(geometry.imageRect == CGRect(x: 0, y: 25, width: 100, height: 50))
    }

    @Test func imageCanvasDoesNotUpscaleSmallImageOnNonRetinaDisplay() {
        let geometry = ImageCanvasGeometry(
            imageSize: CGSize(width: 200, height: 100),
            containerSize: CGSize(width: 400, height: 300),
            displayScale: 1
        )

        #expect(geometry.imageRect == CGRect(x: 100, y: 100, width: 200, height: 100))
    }

    @Test func imageCanvasLimitsPreviewToNativePixelsOnRetinaDisplay() {
        let geometry = ImageCanvasGeometry(
            imageSize: CGSize(width: 200, height: 100),
            containerSize: CGSize(width: 400, height: 300),
            displayScale: 2
        )

        #expect(geometry.imageRect == CGRect(x: 150, y: 125, width: 100, height: 50))
    }

    @Test func imageCanvasZoomsPreviewPastNativePixelSize() {
        let geometry = ImageCanvasGeometry(
            imageSize: CGSize(width: 200, height: 100),
            containerSize: CGSize(width: 400, height: 300),
            displayScale: 2,
            zoomScale: 4
        )

        #expect(geometry.imageRect == CGRect(x: 0, y: 50, width: 400, height: 200))
        #expect(geometry.contentSize == CGSize(width: 400, height: 300))
    }

    @Test func imageCanvasZoomCreatesScrollableContentWhenLargerThanViewport() {
        let geometry = ImageCanvasGeometry(
            imageSize: CGSize(width: 200, height: 100),
            containerSize: CGSize(width: 300, height: 200),
            displayScale: 1,
            zoomScale: 3
        )

        #expect(geometry.imageRect == CGRect(x: 0, y: 0, width: 600, height: 300))
        #expect(geometry.contentSize == CGSize(width: 600, height: 300))
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

    @Test func imageCanvasConvertsZoomedViewRectToImageCoordinates() throws {
        let geometry = ImageCanvasGeometry(
            imageSize: CGSize(width: 200, height: 100),
            containerSize: CGSize(width: 300, height: 200),
            displayScale: 1,
            zoomScale: 3
        )

        let imageRect = try #require(geometry.imageRect(forViewRect: CGRect(x: 150, y: 75, width: 300, height: 150)))

        #expect(imageRect == CGRect(x: 50, y: 25, width: 100, height: 50))
        #expect(geometry.viewRect(forImageRect: imageRect) == CGRect(x: 150, y: 75, width: 300, height: 150))
    }

    @Test func imageCanvasScalesDistanceByZoom() {
        let unzoomedGeometry = ImageCanvasGeometry(
            imageSize: CGSize(width: 200, height: 100),
            containerSize: CGSize(width: 100, height: 100)
        )
        let zoomedGeometry = ImageCanvasGeometry(
            imageSize: CGSize(width: 200, height: 100),
            containerSize: CGSize(width: 100, height: 100),
            zoomScale: 4
        )

        #expect(unzoomedGeometry.viewDistance(forImageDistance: ImageRenderer.defaultBlurRadius) == 6)
        #expect(zoomedGeometry.viewDistance(forImageDistance: ImageRenderer.defaultBlurRadius) == 24)
    }


    @MainActor
    @Test func editorStateStoresBlurRectAnnotationsInImageCoordinates() throws {
        let imageURL = URL(fileURLWithPath: "/tmp/capture.png")
        let annotationID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
        var state = ScreenshotEditorState(originalImageURL: imageURL)

        let addedAnnotation = state.addBlurRect(CGRect(x: 20, y: 30, width: 40, height: 50), id: annotationID)
        let annotation = try #require(addedAnnotation)

        #expect(state.originalImageURL == imageURL)
        #expect(state.selectedTool == .select)
        #expect(state.selectedAnnotationID == annotationID)
        #expect(annotation == Annotation(
            id: annotationID,
            type: .blur(AnnotationBlur()),
            rect: CGRect(x: 20, y: 30, width: 40, height: 50)
        ))
        #expect(state.annotations == [annotation])
    }

    @MainActor
    @Test func editorStateStoresCustomBlurStrengthOnBlurAnnotations() throws {
        let imageURL = URL(fileURLWithPath: "/tmp/capture.png")
        let annotationID = UUID(uuidString: "00000000-0000-0000-0000-000000000028")!
        var state = ScreenshotEditorState(originalImageURL: imageURL)

        state.updateSelectedBlurRadius(36)
        let addedAnnotation = state.addBlurRect(CGRect(x: 20, y: 30, width: 40, height: 50), id: annotationID)
        let annotation = try #require(addedAnnotation)

        #expect(annotation == Annotation(
            id: annotationID,
            type: .blur(AnnotationBlur(radius: 36)),
            rect: CGRect(x: 20, y: 30, width: 40, height: 50)
        ))
        #expect(state.selectedBlurRadius == 36)
    }

    @MainActor
    @Test func editorStateUpdatesSelectedBlurStrength() throws {
        let imageURL = URL(fileURLWithPath: "/tmp/capture.png")
        let annotationID = UUID(uuidString: "00000000-0000-0000-0000-000000000029")!
        var state = ScreenshotEditorState(originalImageURL: imageURL)
        state.addBlurRect(CGRect(x: 20, y: 30, width: 40, height: 50), id: annotationID)

        state.updateSelectedBlurRadius(48)
        let annotation = try #require(state.annotation(id: annotationID))

        #expect(annotation.type == .blur(AnnotationBlur(radius: 48)))
        #expect(state.selectedBlurRadius == 48)
        #expect(state.selectedAnnotationUsesBlurStyle)
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
    @Test func editorStateStoresArrowAnnotationsWithPenStyle() throws {
        let imageURL = URL(fileURLWithPath: "/tmp/capture.png")
        let annotationID = UUID(uuidString: "00000000-0000-0000-0000-000000000024")!
        var state = ScreenshotEditorState(originalImageURL: imageURL)

        let addedAnnotation = state.addArrow(
            from: CGPoint(x: 10, y: 20),
            to: CGPoint(x: 50, y: 20),
            color: .blue,
            lineWidth: 10,
            id: annotationID
        )
        let annotation = try #require(addedAnnotation)
        let arrow = AnnotationArrow(
            startPoint: CGPoint(x: 10, y: 20),
            endPoint: CGPoint(x: 50, y: 20),
            color: .blue,
            lineWidth: 10
        )

        #expect(state.selectedAnnotationID == annotationID)
        #expect(state.selectedStrokeColor == .blue)
        #expect(state.selectedStrokeLineWidth == 10)
        #expect(state.strokeStyle(for: .pen) == AnnotationStrokeStyle(color: .blue, lineWidth: 10))
        #expect(annotation == Annotation(id: annotationID, type: .arrow(arrow), rect: arrow.visibleBounds))
    }

    @MainActor
    @Test func editorStateSelectsTopmostArrowAtImagePointAndAppliesItsStyle() throws {
        let imageURL = URL(fileURLWithPath: "/tmp/capture.png")
        let firstAnnotationID = UUID(uuidString: "00000000-0000-0000-0000-000000000025")!
        let secondAnnotationID = UUID(uuidString: "00000000-0000-0000-0000-000000000026")!
        var state = ScreenshotEditorState(originalImageURL: imageURL)

        state.addArrow(
            from: CGPoint(x: 0, y: 10),
            to: CGPoint(x: 100, y: 10),
            color: .red,
            lineWidth: 4,
            id: firstAnnotationID
        )
        state.addArrow(
            from: CGPoint(x: 0, y: 12),
            to: CGPoint(x: 100, y: 12),
            color: .green,
            lineWidth: 12,
            id: secondAnnotationID
        )

        #expect(state.selectAnnotation(containing: CGPoint(x: 50, y: 12)) == secondAnnotationID)
        #expect(state.selectedAnnotationID == secondAnnotationID)
        #expect(state.selectedStrokeColor == .green)
        #expect(state.selectedStrokeLineWidth == 12)
        #expect(state.selectedAnnotationUsesStrokeStyle)

        #expect(state.selectAnnotation(containing: CGPoint(x: 50, y: 40)) == nil)
        #expect(state.selectedAnnotationID == nil)
    }

    @MainActor
    @Test func editorStateUpdatesSelectedArrowStyleAndBounds() throws {
        let imageURL = URL(fileURLWithPath: "/tmp/capture.png")
        let annotationID = UUID(uuidString: "00000000-0000-0000-0000-000000000027")!
        var state = ScreenshotEditorState(originalImageURL: imageURL)

        state.addArrow(
            from: CGPoint(x: 10, y: 10),
            to: CGPoint(x: 20, y: 10),
            color: .red,
            lineWidth: 4,
            id: annotationID
        )
        state.updateSelectedStrokeColor(.black)
        state.updateSelectedStrokeLineWidth(14)

        let annotation = try #require(state.annotation(id: annotationID))
        guard case .arrow(let arrow) = annotation.type else {
            Issue.record("Expected an arrow annotation")
            return
        }

        #expect(arrow.color == .black)
        #expect(arrow.lineWidth == 14)
        #expect(state.strokeStyle(for: .pen) == AnnotationStrokeStyle(color: .black, lineWidth: 14))
        #expect(annotation.rect == arrow.visibleBounds)
    }

    @MainActor
    @Test func editorStateStoresRectangleAnnotations() throws {
        let imageURL = URL(fileURLWithPath: "/tmp/capture.png")
        let annotationID = UUID(uuidString: "00000000-0000-0000-0000-000000000030")!
        var state = ScreenshotEditorState(originalImageURL: imageURL, selectedTool: .rectangle)

        let addedAnnotation = state.addRectangle(CGRect(x: 20, y: 30, width: 40, height: 50), id: annotationID)
        let annotation = try #require(addedAnnotation)

        #expect(state.selectedAnnotationID == annotationID)
        #expect(annotation == Annotation(
            id: annotationID,
            type: .rectangle(AnnotationRectangle()),
            rect: CGRect(x: 20, y: 30, width: 40, height: 50)
        ))
        #expect(state.selectAnnotation(containing: CGPoint(x: 30, y: 40)) == annotationID)
    }

    @MainActor
    @Test func editorStateUpdatesSelectedRectangleStyle() throws {
        let imageURL = URL(fileURLWithPath: "/tmp/capture.png")
        let annotationID = UUID(uuidString: "00000000-0000-0000-0000-000000000032")!
        var state = ScreenshotEditorState(originalImageURL: imageURL, selectedTool: .rectangle)

        state.addRectangle(CGRect(x: 20, y: 30, width: 40, height: 50), id: annotationID)
        state.updateSelectedRectangleColor(.blue)
        state.updateSelectedRectangleLineWidth(9)

        let annotation = try #require(state.annotation(id: annotationID))
        guard case .rectangle(let rectangle) = annotation.type else {
            Issue.record("Expected a rectangle annotation")
            return
        }

        #expect(rectangle.color == .blue)
        #expect(rectangle.lineWidth == 9)
        #expect(state.selectedRectangleColor == .blue)
        #expect(state.selectedRectangleLineWidth == 9)
        #expect(state.rectangleToolSettings == AnnotationRectangle(color: .blue, lineWidth: 9))
    }

    @MainActor
    @Test func editorStateStoresAndUpdatesTextAnnotations() throws {
        let imageURL = URL(fileURLWithPath: "/tmp/capture.png")
        let annotationID = UUID(uuidString: "00000000-0000-0000-0000-000000000031")!
        var state = ScreenshotEditorState(originalImageURL: imageURL, selectedTool: .text)

        let addedAnnotation = state.addText("  Ship it  ", rect: CGRect(x: 20, y: 30, width: 80, height: 40), id: annotationID)
        let annotation = try #require(addedAnnotation)

        #expect(state.selectedAnnotationID == annotationID)
        #expect(state.selectedAnnotationUsesTextContent)
        #expect(annotation == Annotation(
            id: annotationID,
            type: .text(AnnotationText(content: "Ship it")),
            rect: CGRect(x: 20, y: 30, width: 80, height: 40)
        ))

        state.updateSelectedText("Done now ")

        #expect(state.annotation(id: annotationID)?.type == .text(AnnotationText(content: "Done now ")))
        #expect(state.textContent(id: annotationID) == "Done now ")
        state.updateText(id: annotationID, "Edited inline")
        #expect(state.annotation(id: annotationID)?.type == .text(AnnotationText(content: "Edited inline")))
        state.updateText(id: annotationID, "")
        #expect(state.annotation(id: annotationID)?.type == .text(AnnotationText(content: "")))
        #expect(state.selectAnnotation(containing: CGPoint(x: 30, y: 40)) == annotationID)
    }

    @MainActor
    @Test func editorStateUpdatesSelectedTextStyle() throws {
        let imageURL = URL(fileURLWithPath: "/tmp/capture.png")
        let annotationID = UUID(uuidString: "00000000-0000-0000-0000-000000000033")!
        var state = ScreenshotEditorState(originalImageURL: imageURL, selectedTool: .text)

        state.addText("Label", rect: CGRect(x: 20, y: 30, width: 80, height: 40), id: annotationID)
        state.updateSelectedTextColor(.green)
        state.updateSelectedTextFontSize(36)

        let annotation = try #require(state.annotation(id: annotationID))
        guard case .text(let text) = annotation.type else {
            Issue.record("Expected a text annotation")
            return
        }

        #expect(text.content == "Label")
        #expect(text.color == .green)
        #expect(text.fontSize == 36)
        #expect(state.selectedTextColor == .green)
        #expect(state.selectedTextFontSize == 36)
        #expect(state.textToolSettings.color == .green)
        #expect(state.textToolSettings.fontSize == 36)
    }

    @MainActor
    @Test func editorStateCreatesDefaultTextRectInsideImageBounds() {
        let rect = ScreenshotEditorState.textRect(
            startingAt: CGPoint(x: 190, y: 90),
            within: CGSize(width: 200, height: 100)
        )

        #expect(rect == CGRect(
            x: 40,
            y: 52,
            width: AnnotationText.defaultSize.width,
            height: AnnotationText.defaultSize.height
        ))
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
    @Test func editorStateUndoesLastAnnotation() throws {
        let imageURL = URL(fileURLWithPath: "/tmp/capture.png")
        let firstAnnotationID = UUID(uuidString: "00000000-0000-0000-0000-000000000022")!
        let secondAnnotationID = UUID(uuidString: "00000000-0000-0000-0000-000000000023")!
        var state = ScreenshotEditorState(originalImageURL: imageURL)

        state.addBlurRect(CGRect(x: 0, y: 0, width: 20, height: 20), id: firstAnnotationID)
        state.addBlurRect(CGRect(x: 20, y: 20, width: 20, height: 20), id: secondAnnotationID)
        state.undoLastAnnotation()

        #expect(state.annotations.map(\.id) == [firstAnnotationID])
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
    @Test func editorStateMovesArrowAnnotationAndKeepsEndpointsInsideBounds() throws {
        let imageURL = URL(fileURLWithPath: "/tmp/capture.png")
        let annotationID = UUID(uuidString: "00000000-0000-0000-0000-000000000028")!
        var state = ScreenshotEditorState(originalImageURL: imageURL)
        let addedArrowAnnotation = state.addArrow(
            from: CGPoint(x: 30, y: 30),
            to: CGPoint(x: 70, y: 30),
            color: .black,
            lineWidth: 8,
            id: annotationID
        )
        let addedAnnotation = try #require(addedArrowAnnotation)

        state.moveAnnotation(
            id: annotationID,
            from: addedAnnotation,
            by: CGSize(width: 60, height: 40),
            within: CGSize(width: 160, height: 120)
        )

        let movedAnnotation = try #require(state.annotation(id: annotationID))
        guard case .arrow(let arrow) = movedAnnotation.type else {
            Issue.record("Expected an arrow annotation")
            return
        }

        #expect(arrow.startPoint == CGPoint(x: 90, y: 70))
        #expect(arrow.endPoint == CGPoint(x: 130, y: 70))
        #expect(movedAnnotation.rect == arrow.visibleBounds)
        #expect(state.selectedAnnotationID == annotationID)
    }

    @MainActor
    @Test func editorStateResizesArrowAnnotationFromCornerHandle() throws {
        let imageURL = URL(fileURLWithPath: "/tmp/capture.png")
        let annotationID = UUID(uuidString: "00000000-0000-0000-0000-000000000029")!
        var state = ScreenshotEditorState(originalImageURL: imageURL)
        let addedArrowAnnotation = state.addArrow(
            from: CGPoint(x: 30, y: 40),
            to: CGPoint(x: 70, y: 40),
            color: .black,
            lineWidth: 8,
            id: annotationID
        )
        let originalAnnotation = try #require(addedArrowAnnotation)

        state.resizeAnnotation(
            id: annotationID,
            from: originalAnnotation,
            handle: .bottomRight,
            by: CGSize(width: 40, height: 20),
            within: CGSize(width: 160, height: 120)
        )

        let resizedAnnotation = try #require(state.annotation(id: annotationID))
        guard case .arrow(let arrow) = resizedAnnotation.type else {
            Issue.record("Expected an arrow annotation")
            return
        }

        #expect(abs(arrow.startPoint.x - 41.6666666667) < 0.001)
        #expect(abs(arrow.endPoint.x - 98.3333333333) < 0.001)
        #expect(abs(arrow.startPoint.y - 50) < 0.001)
        #expect(abs(arrow.endPoint.y - 50) < 0.001)
        #expect(resizedAnnotation.rect == arrow.visibleBounds)
        #expect(state.selectedAnnotationID == annotationID)
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
                Annotation(type: .blur(AnnotationBlur()), rect: CGRect(x: 4, y: 0, width: 4, height: 8))
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
                Annotation(type: .blur(AnnotationBlur()), rect: CGRect(x: 0, y: 0, width: 8, height: 8))
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
    @Test func imageRendererAppliesPixelatedBlurToSelectedVerticalRegionOnly() throws {
        let fileManager = FileManager.default
        let baseDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("ScreenshotMaxxingTests-\(UUID().uuidString)", isDirectory: true)
        let imageURL = baseDirectory.appendingPathComponent("vertical-gradient.png")
        defer {
            try? fileManager.removeItem(at: baseDirectory)
        }

        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        try makeVerticalGradientPNGData(width: 16, height: 16).write(to: imageURL)

        let renderer = ImageRenderer()
        let uneditedPNGData = try renderer.renderPNG(imageURL: imageURL, annotations: [])
        let renderedPNGData = try renderer.renderPNG(
            imageURL: imageURL,
            annotations: [
                Annotation(type: .blur(AnnotationBlur(radius: 8)), rect: CGRect(x: 0, y: 0, width: 16, height: 8))
            ]
        )
        let originalInsideRed = try redChannel(in: uneditedPNGData, x: 8, y: 2)
        let renderedInsideRed = try redChannel(in: renderedPNGData, x: 8, y: 2)
        let originalOutsideRed = try redChannel(in: uneditedPNGData, x: 8, y: 12)
        let renderedOutsideRed = try redChannel(in: renderedPNGData, x: 8, y: 12)

        #expect(abs(renderedInsideRed - originalInsideRed) > 0.01)
        #expect(abs(renderedOutsideRed - originalOutsideRed) < 0.01)
    }

    @MainActor
    @Test func imageRendererUsesCustomBlurStrengthForExportedPixels() throws {
        let fileManager = FileManager.default
        let baseDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("ScreenshotMaxxingTests-\(UUID().uuidString)", isDirectory: true)
        let imageURL = baseDirectory.appendingPathComponent("gradient.png")
        defer {
            try? fileManager.removeItem(at: baseDirectory)
        }

        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        try makeHorizontalGradientPNGData(width: 48, height: 16).write(to: imageURL)

        let renderer = ImageRenderer()
        let blurRect = CGRect(x: 0, y: 0, width: 48, height: 16)
        let defaultBlurPNGData = try renderer.renderPNG(
            imageURL: imageURL,
            annotations: [Annotation(type: .blur(AnnotationBlur()), rect: blurRect)]
        )
        let strongerBlurPNGData = try renderer.renderPNG(
            imageURL: imageURL,
            annotations: [Annotation(type: .blur(AnnotationBlur(radius: 48)), rect: blurRect)]
        )
        let defaultRed = try redChannel(in: defaultBlurPNGData, x: 4, y: 8)
        let strongerRed = try redChannel(in: strongerBlurPNGData, x: 4, y: 8)

        #expect(strongerBlurPNGData != defaultBlurPNGData)
        #expect(abs(strongerRed - defaultRed) > 0.01)
    }

    @MainActor
    @Test func imageRendererRendersBlurAsPixelatedColorBlocks() throws {
        let fileManager = FileManager.default
        let baseDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("ScreenshotMaxxingTests-\(UUID().uuidString)", isDirectory: true)
        let imageURL = baseDirectory.appendingPathComponent("gradient.png")
        defer {
            try? fileManager.removeItem(at: baseDirectory)
        }

        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        let originalPNGData = try makeHorizontalGradientPNGData(width: 16, height: 8)
        try originalPNGData.write(to: imageURL)

        let renderer = ImageRenderer()
        let renderedPNGData = try renderer.renderPNG(
            imageURL: imageURL,
            annotations: [
                Annotation(
                    type: .blur(AnnotationBlur(radius: 4)),
                    rect: CGRect(x: 0, y: 0, width: 16, height: 8)
                )
            ]
        )
        let originalFirstRed = try redChannel(in: originalPNGData, x: 0, y: 4)
        let originalSameBlockRed = try redChannel(in: originalPNGData, x: 3, y: 4)
        let renderedFirstRed = try redChannel(in: renderedPNGData, x: 0, y: 4)
        let renderedSameBlockRed = try redChannel(in: renderedPNGData, x: 3, y: 4)
        let renderedNextBlockRed = try redChannel(in: renderedPNGData, x: 6, y: 4)

        #expect(abs(originalSameBlockRed - originalFirstRed) > 0.05)
        #expect(abs(renderedSameBlockRed - renderedFirstRed) < 0.01)
        #expect(abs(renderedNextBlockRed - renderedFirstRed) > 0.05)
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
    @Test func imageRendererBakesArrowAnnotationsIntoPNG() throws {
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
        let arrow = AnnotationArrow(
            startPoint: CGPoint(x: 1, y: 4),
            endPoint: CGPoint(x: 10, y: 4),
            color: .blue,
            lineWidth: 4
        )
        let renderedPNGData = try renderer.renderPNG(
            imageURL: imageURL,
            annotations: [Annotation(type: .arrow(arrow), rect: arrow.visibleBounds)]
        )
        let renderedColor = try color(in: renderedPNGData, x: 6, y: 4)

        #expect(renderedColor.blueComponent > 0.5)
        #expect(renderedColor.redComponent < 0.4)
    }

    @MainActor
    @Test func imageRendererBakesRectangleAnnotationsIntoPNG() throws {
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
        let renderedPNGData = try renderer.renderPNG(
            imageURL: imageURL,
            annotations: [Annotation(type: .rectangle(AnnotationRectangle()), rect: CGRect(x: 1, y: 1, width: 10, height: 6))]
        )
        let renderedColor = try color(in: renderedPNGData, x: 1, y: 1)

        #expect(renderedColor.redComponent > 0.5)
        #expect(renderedColor.greenComponent < 0.4)
    }

    @MainActor
    @Test func imageRendererUsesRectangleStyleForExportedPixels() throws {
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
        let renderedPNGData = try renderer.renderPNG(
            imageURL: imageURL,
            annotations: [
                Annotation(
                    type: .rectangle(AnnotationRectangle(color: .blue, lineWidth: 6)),
                    rect: CGRect(x: 1, y: 1, width: 10, height: 6)
                )
            ]
        )
        let hasBluePixel = try (1..<11).contains { x in
            try (1..<7).contains { y in
                let renderedColor = try color(in: renderedPNGData, x: x, y: y)
                return renderedColor.blueComponent > 0.5 && renderedColor.redComponent < 0.4
            }
        }

        #expect(hasBluePixel)
    }

    @MainActor
    @Test func imageRendererBakesTextAnnotationsIntoPNG() throws {
        let fileManager = FileManager.default
        let baseDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("ScreenshotMaxxingTests-\(UUID().uuidString)", isDirectory: true)
        let imageURL = baseDirectory.appendingPathComponent("split.png")
        defer {
            try? fileManager.removeItem(at: baseDirectory)
        }

        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        try makeVerticalSplitPNGData(width: 80, height: 40).write(to: imageURL)

        let renderer = ImageRenderer()
        let uneditedPNGData = try renderer.renderPNG(imageURL: imageURL, annotations: [])
        let renderedPNGData = try renderer.renderPNG(
            imageURL: imageURL,
            annotations: [Annotation(type: .text(AnnotationText(content: "Text")), rect: CGRect(x: 2, y: 2, width: 76, height: 36))]
        )

        #expect(renderedPNGData != uneditedPNGData)
    }

    @MainActor
    @Test func imageRendererUsesTextStyleForExportedPixels() throws {
        let fileManager = FileManager.default
        let baseDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("ScreenshotMaxxingTests-\(UUID().uuidString)", isDirectory: true)
        let imageURL = baseDirectory.appendingPathComponent("split.png")
        defer {
            try? fileManager.removeItem(at: baseDirectory)
        }

        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        try makeVerticalSplitPNGData(width: 80, height: 40).write(to: imageURL)

        let renderer = ImageRenderer()
        let renderedPNGData = try renderer.renderPNG(
            imageURL: imageURL,
            annotations: [
                Annotation(
                    type: .text(AnnotationText(content: "Text", color: .blue, fontSize: 32)),
                    rect: CGRect(x: 2, y: 2, width: 76, height: 36)
                )
            ]
        )
        let hasBluePixel = try (2..<78).contains { x in
            try (2..<38).contains { y in
                let renderedColor = try color(in: renderedPNGData, x: x, y: y)
                return renderedColor.blueComponent > 0.5 && renderedColor.redComponent < 0.4
            }
        }

        #expect(hasBluePixel)
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
    @Test func editorClipboardWritesMP4DataToPasteboard() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("ScreenshotMaxxingTests-\(UUID().uuidString)"))
        defer {
            pasteboard.releaseGlobally()
        }
        let mp4Data = Data("mp4".utf8)

        let copied = EditorClipboard.copyMP4Data(mp4Data, to: pasteboard)

        #expect(copied)
        #expect(pasteboard.data(forType: NSPasteboard.PasteboardType("public.mpeg-4")) == mp4Data)
        #expect(pasteboard.data(forType: NSPasteboard.PasteboardType("public.movie")) == mp4Data)
    }

    @MainActor
    @Test func savedFilePresenterRevealsSavedFileInFinder() {
        let fileURL = URL(fileURLWithPath: "/tmp/example-edited.png")
        var revealedFileURL: URL?
        let presenter = SavedFilePresenter { revealedFileURL = $0 }

        presenter.revealInFinder(fileURL)

        #expect(revealedFileURL == fileURL)
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
        #expect(CaptureHistoryData.contentFileURL(for: newerCapture) == URL(fileURLWithPath: "/tmp/newer-edited.png"))
        #expect(CaptureHistoryData.detailText(for: newerCapture) == "Fullscreen - 40x30")
    }

    @Test func captureHistoryDetectsMissingContentAndFindsExistingStorageFolder() throws {
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
        let originalURL = directories.originals.appendingPathComponent("area.png")
        let editedURL = directories.edited.appendingPathComponent("area-edited.png")
        let capture = Capture(
            fileName: originalURL.lastPathComponent,
            captureMode: "area",
            width: 20,
            height: 10,
            originalFilePath: originalURL.fileSystemPath,
            editedFilePath: editedURL.fileSystemPath
        )

        try Data("png".utf8).write(to: originalURL)

        #expect(!CaptureHistoryData.fileExists(for: capture, fileManager: fileManager))
        #expect(CaptureHistoryData.lastKnownPath(for: capture) == editedURL.fileSystemPath)
        #expect(CaptureHistoryData.storageFolderURL(for: capture, fileManager: fileManager) == directories.edited)

        try Data("png".utf8).write(to: editedURL)

        #expect(CaptureHistoryData.fileExists(for: capture, fileManager: fileManager))
        #expect(CaptureHistoryData.storageFolderURL(for: capture, fileManager: fileManager) == directories.edited)
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

    @Test func captureHistoryDeleteConfirmationMentionsTrash() {
        #expect(CaptureHistoryData.deleteConfirmationMessage.contains("Local files that still exist are moved to the Trash"))
        #expect(!CaptureHistoryData.deleteConfirmationMessage.contains("cannot be undone"))
        #expect(CaptureHistoryData.removeMissingConfirmationMessage.contains("only deletes its History metadata"))
        #expect(CaptureHistoryData.removeMissingConfirmationMessage.contains("will not move any files to the Trash"))
    }

    @MainActor
    @Test func captureHistoryDeletionTrashesSelectedCaptureAndEditedVersions() throws {
        let fileManager = FileManager.default
        let fileTrash = SpyFileTrash()
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
        let thumbnailURL = directories.thumbnails.appendingPathComponent("area-20260526-101500-aaaaaaaa-thumbnail.png")
        let unrelatedURL = directories.edited.appendingPathComponent("window-20260526-101500-dddddddd-edited-eeeeeeee.png")

        try [originalURL, editedURL, diskOnlyEditedURL, thumbnailURL, unrelatedURL].forEach { fileURL in
            try Data("png".utf8).write(to: fileURL)
        }

        let modelContainer = try PersistenceController.makeModelContainer(inMemory: true)
        let originalCapture = Capture(
            fileName: originalURL.lastPathComponent,
            captureMode: "area",
            width: 20,
            height: 10,
            thumbnailFilePath: thumbnailURL.fileSystemPath,
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
        ).map { canonicalFileSystemPath(for: $0) })

        #expect(Set(capturesToDelete.map(\.fileName)) == [originalURL.lastPathComponent, editedURL.lastPathComponent])
        #expect(filePathsToDelete.contains(canonicalFileSystemPath(for: originalURL)))
        #expect(filePathsToDelete.contains(canonicalFileSystemPath(for: editedURL)))
        #expect(filePathsToDelete.contains(canonicalFileSystemPath(for: diskOnlyEditedURL)))
        #expect(filePathsToDelete.contains(canonicalFileSystemPath(for: thumbnailURL)))
        #expect(!filePathsToDelete.contains(canonicalFileSystemPath(for: unrelatedURL)))

        try CaptureHistoryData.deleteCaptures(
            capturesToDelete,
            from: modelContainer.mainContext,
            allCaptures: allCaptures,
            fileManager: fileManager,
            fileTrash: fileTrash
        )
        let remainingCaptures = try modelContainer.mainContext.fetch(FetchDescriptor<Capture>())

        #expect(remainingCaptures.map(\.fileName) == [unrelatedURL.lastPathComponent])
        #expect(Set(fileTrash.trashedFileURLs.map(\.fileSystemPath)) == [
            originalURL.fileSystemPath,
            editedURL.fileSystemPath,
            diskOnlyEditedURL.fileSystemPath,
            thumbnailURL.fileSystemPath
        ])
        #expect(fileManager.fileExists(atPath: originalURL.fileSystemPath))
        #expect(fileManager.fileExists(atPath: editedURL.fileSystemPath))
        #expect(fileManager.fileExists(atPath: diskOnlyEditedURL.fileSystemPath))
        #expect(fileManager.fileExists(atPath: thumbnailURL.fileSystemPath))
        #expect(fileManager.fileExists(atPath: unrelatedURL.fileSystemPath))
    }

    @MainActor
    @Test func captureHistoryRemovesMissingCaptureMetadataWithoutTrashingFiles() throws {
        let fileTrash = SpyFileTrash()
        let modelContainer = try PersistenceController.makeModelContainer(inMemory: true)
        let missingCapture = Capture(
            fileName: "missing.png",
            captureMode: "area",
            width: 20,
            height: 10,
            originalFilePath: "/tmp/ScreenshotMaxxingTests-missing-\(UUID().uuidString).png"
        )
        let unrelatedCapture = Capture(
            fileName: "unrelated.png",
            captureMode: "window",
            width: 40,
            height: 30,
            originalFilePath: "/tmp/ScreenshotMaxxingTests-unrelated-\(UUID().uuidString).png"
        )

        modelContainer.mainContext.insert(missingCapture)
        modelContainer.mainContext.insert(unrelatedCapture)
        try modelContainer.mainContext.save()

        try CaptureHistoryData.removeCapturesFromHistoryOnly(
            [missingCapture],
            from: modelContainer.mainContext
        )
        let remainingCaptures = try modelContainer.mainContext.fetch(FetchDescriptor<Capture>())

        #expect(remainingCaptures.map(\.fileName) == ["unrelated.png"])
        #expect(fileTrash.trashedFileURLs.isEmpty)
    }

    @MainActor
    @Test func captureHistoryDeletionOfMissingCaptureKeepsLinkedExistingEditedCapture() throws {
        let fileManager = FileManager.default
        let fileTrash = SpyFileTrash()
        let baseDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("ScreenshotMaxxingTests-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? fileManager.removeItem(at: baseDirectory)
        }

        let directories = try FileLocations.ensureCaptureDirectories(
            baseDirectory: baseDirectory,
            fileManager: fileManager
        )
        let missingOriginalURL = directories.originals.appendingPathComponent("area-20260526-101500-aaaaaaaa.png")
        let editedURL = directories.edited.appendingPathComponent("area-20260526-101500-aaaaaaaa-edited-bbbbbbbb.png")
        try Data("png".utf8).write(to: editedURL)

        let modelContainer = try PersistenceController.makeModelContainer(inMemory: true)
        let missingOriginalCapture = Capture(
            fileName: missingOriginalURL.lastPathComponent,
            captureMode: "area",
            width: 20,
            height: 10,
            originalFilePath: missingOriginalURL.fileSystemPath
        )
        let editedCapture = Capture(
            fileName: editedURL.lastPathComponent,
            captureMode: "area",
            width: 20,
            height: 10,
            originalFilePath: editedURL.fileSystemPath
        )

        modelContainer.mainContext.insert(missingOriginalCapture)
        modelContainer.mainContext.insert(editedCapture)
        try modelContainer.mainContext.save()

        let allCaptures = try modelContainer.mainContext.fetch(FetchDescriptor<Capture>())
        try CaptureHistoryData.deleteCaptures(
            [missingOriginalCapture],
            from: modelContainer.mainContext,
            allCaptures: allCaptures,
            fileManager: fileManager,
            fileTrash: fileTrash
        )
        let remainingCaptures = try modelContainer.mainContext.fetch(FetchDescriptor<Capture>())

        #expect(remainingCaptures.map(\.fileName) == [editedURL.lastPathComponent])
        #expect(fileTrash.trashedFileURLs.isEmpty)
        #expect(fileManager.fileExists(atPath: editedURL.fileSystemPath))
    }

    @MainActor
    @Test func captureHistoryMetadataOnlyRemovalRefusesAvailableFiles() throws {
        let fileManager = FileManager.default
        let baseDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("ScreenshotMaxxingTests-\(UUID().uuidString)", isDirectory: true)
        let existingURL = baseDirectory.appendingPathComponent("available.png")
        defer {
            try? fileManager.removeItem(at: baseDirectory)
        }

        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        try Data("png".utf8).write(to: existingURL)

        let modelContainer = try PersistenceController.makeModelContainer(inMemory: true)
        let availableCapture = Capture(
            fileName: existingURL.lastPathComponent,
            captureMode: "area",
            width: 20,
            height: 10,
            originalFilePath: existingURL.fileSystemPath
        )

        modelContainer.mainContext.insert(availableCapture)
        try modelContainer.mainContext.save()

        do {
            try CaptureHistoryData.removeCapturesFromHistoryOnly(
                [availableCapture],
                from: modelContainer.mainContext
            )
            Issue.record("Expected metadata-only removal to reject captures whose files are available")
        } catch {
            #expect(error.localizedDescription.contains("available again"))
        }

        let remainingCaptures = try modelContainer.mainContext.fetch(FetchDescriptor<Capture>())

        #expect(remainingCaptures.map(\.fileName) == [existingURL.lastPathComponent])
        #expect(fileManager.fileExists(atPath: existingURL.fileSystemPath))
    }

    @MainActor
    @Test func captureHistoryDeletionSkipsTrashForNonexistentFiles() throws {
        let fileManager = FileManager.default
        let fileTrash = SpyFileTrash()
        let modelContainer = try PersistenceController.makeModelContainer(inMemory: true)
        let missingCapture = Capture(
            fileName: "missing.png",
            captureMode: "area",
            width: 20,
            height: 10,
            originalFilePath: "/tmp/ScreenshotMaxxingTests-missing-\(UUID().uuidString).png"
        )

        modelContainer.mainContext.insert(missingCapture)
        try modelContainer.mainContext.save()

        try CaptureHistoryData.deleteCaptures(
            [missingCapture],
            from: modelContainer.mainContext,
            allCaptures: [missingCapture],
            fileManager: fileManager,
            fileTrash: fileTrash
        )
        let remainingCaptures = try modelContainer.mainContext.fetch(FetchDescriptor<Capture>())

        #expect(remainingCaptures.isEmpty)
        #expect(fileTrash.trashedFileURLs.isEmpty)
    }

    private func canonicalFileSystemPath(for fileURL: URL) -> String {
        fileURL.resolvingSymlinksInPath().fileSystemPath
    }

    @Test func captureHistoryRoutesVideosToContentAndThumbnailPaths() {
        let videoCapture = Capture(
            fileName: "recording-window.mp4",
            captureMode: "window",
            mediaType: CaptureMediaType.video.rawValue,
            width: 1920,
            height: 1080,
            durationSeconds: 75,
            thumbnailFilePath: "/tmp/recording-window-thumb.png",
            originalFilePath: "/tmp/recording-window.mp4",
            editedFilePath: "/tmp/recording-window-edited.mp4"
        )

        #expect(CaptureHistoryData.mediaType(for: videoCapture) == .video)
        #expect(CaptureHistoryData.previewFilePath(for: videoCapture) == "/tmp/recording-window-thumb.png")
        #expect(CaptureHistoryData.contentFilePath(for: videoCapture) == "/tmp/recording-window-edited.mp4")
        #expect(CaptureHistoryData.detailText(for: videoCapture) == "Window - 1920x1080 - 1:15")
    }

    @Test func videoSilenceDetectorIgnoresSubsecondSilenceAndFindsLongBlocks() {
        let ranges = VideoSilenceDetector.silentRanges(
            from: [
                VideoSilenceDetector.AudioLevelWindow(start: 0, end: 0.4, rmsAmplitude: 0.02),
                VideoSilenceDetector.AudioLevelWindow(start: 0.4, end: 0.9, rmsAmplitude: 0.001),
                VideoSilenceDetector.AudioLevelWindow(start: 0.9, end: 1, rmsAmplitude: 0.02),
                VideoSilenceDetector.AudioLevelWindow(start: 1, end: 1.6, rmsAmplitude: 0.001),
                VideoSilenceDetector.AudioLevelWindow(start: 1.6, end: 2.2, rmsAmplitude: 0.001)
            ],
            configuration: VideoSilenceDetectionConfiguration(
                minimumSilenceDuration: 1,
                silenceThresholdDecibels: -45,
                maximumNoiseGapDuration: 0,
                edgePaddingDuration: 0
            )
        )

        #expect(rangePairs(ranges) == [[1, 2.2]])
        #expect(ranges.allSatisfy { $0.source == .detectedSilence })
    }

    @Test func videoSilenceDetectorMergesBriefNoiseAndPadsCutEdges() {
        let ranges = VideoSilenceDetector.silentRanges(
            from: [
                VideoSilenceDetector.AudioLevelWindow(start: 0, end: 0.55, rmsAmplitude: 0.001),
                VideoSilenceDetector.AudioLevelWindow(start: 0.55, end: 0.62, rmsAmplitude: 0.02),
                VideoSilenceDetector.AudioLevelWindow(start: 0.62, end: 1.3, rmsAmplitude: 0.001)
            ],
            configuration: VideoSilenceDetectionConfiguration(
                minimumSilenceDuration: 1,
                silenceThresholdDecibels: -45,
                maximumNoiseGapDuration: 0.12,
                edgePaddingDuration: 0.1
            )
        )

        #expect(rangePairs(ranges) == [[0.1, 1.2]])
        #expect(ranges.allSatisfy { $0.source == .detectedSilence })
    }

    @Test func videoEditStateKeepsTrimOnlyRange() {
        let state = VideoEditState(durationSeconds: 10, trimStart: 2, trimEnd: 8)

        #expect(rangePairs(state.keptRanges) == [[2, 8]])
    }

    @Test func videoEditStateRemovesMiddleCut() {
        let state = VideoEditState(
            durationSeconds: 10,
            removedRanges: [VideoTimeRange(start: 4, end: 5)]
        )

        #expect(rangePairs(state.keptRanges) == [[0, 4], [5, 10]])
    }

    @Test func videoEditStateSortsMultipleCuts() {
        let state = VideoEditState(
            durationSeconds: 10,
            removedRanges: [
                VideoTimeRange(start: 6, end: 7),
                VideoTimeRange(start: 2, end: 3)
            ]
        )

        #expect(rangePairs(state.keptRanges) == [[0, 2], [3, 6], [7, 10]])
    }

    @Test func videoEditStateMergesOverlappingCuts() {
        let state = VideoEditState(
            durationSeconds: 10,
            removedRanges: [
                VideoTimeRange(start: 2, end: 5),
                VideoTimeRange(start: 4, end: 8)
            ]
        )

        #expect(rangePairs(state.keptRanges) == [[0, 2], [8, 10]])
    }

    @Test func videoEditStatePreservesSilenceCutSource() throws {
        var state = VideoEditState(durationSeconds: 10)

        state.addRemovedRange(VideoTimeRange(start: 4, end: 5, source: .detectedSilence))

        let range = try #require(state.removedRanges.first)
        #expect(range.source == .detectedSilence)
    }

    @Test func videoEditStateMarksMergedCutAsSilenceWhenDetectedRangeOverlapsManualCut() throws {
        let state = VideoEditState(
            durationSeconds: 10,
            removedRanges: [
                VideoTimeRange(start: 2, end: 5),
                VideoTimeRange(start: 4, end: 8, source: .detectedSilence)
            ]
        )

        let range = try #require(state.removedRanges.first)
        #expect(rangePairs(state.removedRanges) == [[2, 8]])
        #expect(range.source == .detectedSilence)
    }

    @Test func videoEditStateIgnoresZeroLengthCuts() {
        let state = VideoEditState(
            durationSeconds: 10,
            removedRanges: [
                VideoTimeRange(start: 3, end: 3),
                VideoTimeRange(start: 8, end: 7)
            ]
        )

        #expect(rangePairs(state.keptRanges) == [[0, 7], [8, 10]])
    }

    @Test func videoEditStateClampsCutsTouchingTrimBoundaries() {
        let state = VideoEditState(
            durationSeconds: 10,
            trimStart: 2,
            trimEnd: 8,
            removedRanges: [
                VideoTimeRange(start: 0, end: 3),
                VideoTimeRange(start: 7, end: 10)
            ]
        )

        #expect(rangePairs(state.keptRanges) == [[3, 7]])
    }

    @Test func videoEditStateSelectsAddedCut() {
        var state = VideoEditState(durationSeconds: 10)

        let selectedID = state.addRemovedRange(VideoTimeRange(start: 4, end: 5))
        let selectedRange = state.selectedRemovedRange.map { [$0] } ?? []

        #expect(state.selectedRemovedRangeID == selectedID)
        #expect(rangePairs(selectedRange) == [[4, 5]])
    }

    @Test func videoEditStateDeletesSelectedCut() {
        var state = VideoEditState(
            durationSeconds: 10,
            removedRanges: [
                VideoTimeRange(start: 2, end: 3),
                VideoTimeRange(start: 6, end: 7)
            ]
        )
        state.selectRemovedRange(id: state.removedRanges[0].id)

        state.removeSelectedRange()

        #expect(rangePairs(state.removedRanges) == [[6, 7]])
        #expect(state.selectedRemovedRangeID == nil)
    }

    @Test func videoEditUndoHistoryRestoresPreviousEditState() throws {
        var history = VideoEditUndoHistory()
        var state = VideoEditState(durationSeconds: 10)

        history.record(state)
        state.addRemovedRange(VideoTimeRange(start: 4, end: 5))

        let undoState = history.undo()
        let restoredState = try #require(undoState)
        #expect(restoredState == VideoEditState(durationSeconds: 10))
        #expect(!history.canUndo)
    }

    @Test func videoEditUndoHistoryIgnoresDuplicateSnapshots() {
        var history = VideoEditUndoHistory()
        let state = VideoEditState(durationSeconds: 10)

        history.record(state)
        history.record(state)

        #expect(history.snapshots.count == 1)
    }

    @Test func videoEditStateResizesSelectedCutEdges() {
        var state = VideoEditState(
            durationSeconds: 10,
            removedRanges: [VideoTimeRange(start: 4, end: 5)]
        )
        let cutID = state.removedRanges[0].id

        state.setRemovedRangeStart(id: cutID, 3)
        state.setRemovedRangeEnd(id: cutID, 6)

        #expect(rangePairs(state.removedRanges) == [[3, 6]])
        #expect(state.selectedRemovedRangeID == cutID)
        #expect(rangePairs(state.keptRanges) == [[0, 3], [6, 10]])
    }

    @Test func videoEditStateMovesSelectedCutWithoutChangingDuration() {
        var state = VideoEditState(
            durationSeconds: 10,
            removedRanges: [VideoTimeRange(start: 4, end: 5)]
        )
        let cutID = state.removedRanges[0].id

        state.moveRemovedRange(id: cutID, start: 6)

        #expect(rangePairs(state.removedRanges) == [[6, 7]])
        #expect(state.selectedRemovedRangeID == cutID)
        #expect(rangePairs(state.keptRanges) == [[0, 6], [7, 10]])
    }

    @Test func videoEditStateClampsMovedCutToTrimBounds() {
        var state = VideoEditState(
            durationSeconds: 10,
            trimStart: 2,
            trimEnd: 8,
            removedRanges: [VideoTimeRange(start: 4, end: 5)]
        )
        let cutID = state.removedRanges[0].id

        state.moveRemovedRange(id: cutID, start: 9)
        #expect(rangePairs(state.removedRanges) == [[7, 8]])

        state.moveRemovedRange(id: cutID, start: 0)
        #expect(rangePairs(state.removedRanges) == [[2, 3]])
    }

    @Test func videoEditStateKeepsMinimumDurationWhenResizingCut() {
        var state = VideoEditState(
            durationSeconds: 10,
            removedRanges: [VideoTimeRange(start: 4, end: 5)]
        )
        let cutID = state.removedRanges[0].id

        state.setRemovedRangeStart(id: cutID, 4.9, minimumDuration: 0.5)
        state.setRemovedRangeEnd(id: cutID, 4.75, minimumDuration: 0.5)

        #expect(rangePairs(state.removedRanges) == [[4.5, 5]])
    }

    @Test func videoEditStatePlaybackSkipTargetAdvancesPastCut() throws {
        let state = VideoEditState(
            durationSeconds: 10,
            removedRanges: [VideoTimeRange(start: 4, end: 5)]
        )

        #expect(state.playbackSkipTarget(for: 3.9, offset: 0.04) == nil)
        #expect(try isApproximately(#require(state.playbackSkipTarget(for: 4.1, offset: 0.04)), 5.04))
        #expect(state.playbackSkipTarget(for: 5, offset: 0.04) == nil)
    }

    @Test func videoEditStatePlaybackSkipTargetAdvancesThroughNextCutIfOffsetLandsInsideIt() throws {
        let state = VideoEditState(
            durationSeconds: 10,
            removedRanges: [
                VideoTimeRange(start: 4, end: 5),
                VideoTimeRange(start: 5.02, end: 6)
            ]
        )

        #expect(try isApproximately(#require(state.playbackSkipTarget(for: 4.5, offset: 0.04)), 6.04))
    }

    @Test func videoEditStatePlaybackSkipTargetClampsToTrimEnd() throws {
        let state = VideoEditState(
            durationSeconds: 10,
            trimStart: 2,
            trimEnd: 8,
            removedRanges: [VideoTimeRange(start: 7, end: 8)]
        )

        #expect(try isApproximately(#require(state.playbackSkipTarget(for: 7.5, offset: 0.04)), 8))
    }

    @Test func videoExportPlannerComputesOutputDurationFromKeptRanges() {
        let state = VideoEditState(
            durationSeconds: 10,
            removedRanges: [
                VideoTimeRange(start: 2, end: 3),
                VideoTimeRange(start: 6, end: 8)
            ]
        )
        let plan = VideoExportPlanner.plan(for: state)

        #expect(rangePairs(plan.keptRanges) == [[0, 2], [3, 6], [8, 10]])
        #expect(plan.outputDurationSeconds == 7)
    }

    @MainActor
    @Test func videoExporterWritesTrimmedCutFixtureAndOverwritesOutput() async throws {
        let fileManager = FileManager.default
        let baseDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("ScreenshotMaxxingTests-\(UUID().uuidString)", isDirectory: true)
        let inputURL = baseDirectory.appendingPathComponent("source.mp4")
        let outputURL = baseDirectory.appendingPathComponent("edited.mp4")
        defer {
            try? fileManager.removeItem(at: baseDirectory)
        }

        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        try await makeTestVideo(at: inputURL, durationSeconds: 3, size: CGSize(width: 96, height: 64))
        try Data("old output".utf8).write(to: outputURL)

        let result = try await VideoExporter(fileManager: fileManager).export(
            videoURL: inputURL,
            editState: VideoEditState(
                durationSeconds: 3,
                trimStart: 0.5,
                trimEnd: 2.5,
                removedRanges: [VideoTimeRange(start: 1, end: 1.5)]
            ),
            outputURL: outputURL
        )
        let exportedVideoTracks = try await AVURLAsset(url: outputURL).loadTracks(withMediaType: .video)

        #expect(result.fileURL == outputURL)
        #expect(isApproximately(result.durationSeconds, 1.5, accuracy: 0.08))
        #expect(result.dimensions == CGSize(width: 96, height: 64))
        #expect(try Data(contentsOf: outputURL) != Data("old output".utf8))
        #expect(!exportedVideoTracks.isEmpty)
    }

    private func rangePairs(_ ranges: [VideoTimeRange]) -> [[Double]] {
        ranges.map { [$0.start, $0.end] }
    }

    @MainActor
    private func waitForCondition(
        _ condition: @autoclosure () -> Bool,
        timeout: Duration = .seconds(1)
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while clock.now < deadline {
            if condition() {
                return
            }

            try await Task.sleep(nanoseconds: 1_000_000)
        }

        throw TestFixtureError.conditionTimedOut
    }

    private func makeTestVideo(at outputURL: URL, durationSeconds: Double, size: CGSize) async throws {
        let width = Int(size.width)
        let height = Int(size.height)
        let frameRate: Int32 = 30
        let frameCount = max(Int(durationSeconds * Double(frameRate)), 1)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height
            ]
        )
        videoInput.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )

        guard writer.canAdd(videoInput) else {
            throw TestFixtureError.videoWriterFailed("Could not add video input")
        }

        writer.add(videoInput)

        guard writer.startWriting() else {
            throw writer.error ?? TestFixtureError.videoWriterFailed("Could not start writing")
        }

        writer.startSession(atSourceTime: .zero)

        for frameIndex in 0..<frameCount {
            while !videoInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 1_000_000)
            }

            let pixelBuffer = try makePixelBuffer(
                width: width,
                height: height,
                red: UInt8((frameIndex * 5) % 255),
                green: 64,
                blue: UInt8(255 - ((frameIndex * 3) % 255))
            )
            let presentationTime = CMTime(value: CMTimeValue(frameIndex), timescale: frameRate)

            guard adaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
                throw writer.error ?? TestFixtureError.videoWriterFailed("Could not append frame")
            }
        }

        videoInput.markAsFinished()
        try finishWriting(writer)
    }

    private func makePixelBuffer(width: Int, height: Int, red: UInt8, green: UInt8, blue: UInt8) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            [
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
            ] as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw TestFixtureError.pixelBufferCreationFailed(status)
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw TestFixtureError.pixelBufferCreationFailed(kCVReturnInvalidPixelBufferAttributes)
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)

        for y in 0..<height {
            let row = bytes.advanced(by: y * bytesPerRow)

            for x in 0..<width {
                let pixel = row.advanced(by: x * 4)
                pixel[0] = blue
                pixel[1] = green
                pixel[2] = red
                pixel[3] = 255
            }
        }

        return pixelBuffer
    }

    private func finishWriting(_ writer: AVAssetWriter) throws {
        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting {
            semaphore.signal()
        }
        semaphore.wait()

        if let error = writer.error {
            throw error
        }

        guard writer.status == .completed else {
            throw TestFixtureError.videoWriterFailed("Writer ended with status \(writer.status.rawValue)")
        }
    }

    private enum TestFixtureError: Error {
        case videoWriterFailed(String)
        case pixelBufferCreationFailed(CVReturn)
        case conditionTimedOut
    }

    private func isApproximately(_ first: Double, _ second: Double, accuracy: Double = 0.000001) -> Bool {
        abs(first - second) <= accuracy
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

    private func makeHorizontalGradientPNGData(width: Int, height: Int) throws -> Data {
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

        let denominator = CGFloat(max(width - 1, 1))

        for y in 0..<height {
            for x in 0..<width {
                let red = CGFloat(x) / denominator
                imageRep.setColor(NSColor(deviceRed: red, green: 0, blue: 0, alpha: 1), atX: x, y: y)
            }
        }

        guard let pngData = imageRep.representation(using: .png, properties: [:]) else {
            throw ImageRendererError.renderFailed
        }

        return pngData
    }

    private func makeVerticalGradientPNGData(width: Int, height: Int) throws -> Data {
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

        let denominator = CGFloat(max(height - 1, 1))

        for y in 0..<height {
            for x in 0..<width {
                let red = CGFloat(y) / denominator
                imageRep.setColor(NSColor(deviceRed: red, green: 0, blue: 0, alpha: 1), atX: x, y: y)
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

private final class SpyFileTrash: CaptureFileTrashing {
    private(set) var trashedFileURLs = [URL]()

    func moveItemToTrash(at fileURL: URL) throws {
        trashedFileURLs.append(fileURL)
    }
}
