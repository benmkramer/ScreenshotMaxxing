//
//  RecordingController.swift
//  ScreenshotMaxxing
//
//  Created by Codex on 5/29/26.
//

import AppKit
import AVFoundation
import ScreenCaptureKit

@MainActor
final class RecordingController {
    private let fileManager: FileManager
    private var activeSession: ActiveRecordingSession?
    private var continuation: CheckedContinuation<RecordingResult, Error>?

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func record(options: RecordingOptions, baseDirectory: URL? = nil) async throws -> RecordingResult {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                Task { @MainActor in
                    do {
                        self.continuation = continuation
                        try await self.beginRecording(options: options, baseDirectory: baseDirectory)
                    } catch {
                        self.continuation = nil
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            Task { @MainActor in
                await self.cancelActiveRecording()
            }
        }
    }

    func stopActiveRecording() async {
        guard let activeSession, !activeSession.didRequestStop else {
            return
        }

        activeSession.didRequestStop = true
        activeSession.toolbar.close()

        do {
            try await stopCapture(activeSession.stream)
        } catch {
            if await recoverCompletedRecordingIfPossible() {
                return
            }

            completeWithError(error)
        }
    }

    private func beginRecording(options: RecordingOptions, baseDirectory: URL?) async throws {
        guard activeSession == nil else {
            throw RecordingError.alreadyRecording
        }

        if options.microphoneEnabled {
            try await requestMicrophoneAccessIfNeeded()
        }

        let directories = try FileLocations.ensureCaptureDirectories(
            baseDirectory: baseDirectory,
            fileManager: fileManager
        )
        let outputURL = FileLocations.uniqueOriginalFileURL(
            captureMode: options.mode.fileNamePrefix,
            directories: directories,
            fileExtension: "mp4"
        )
        let shareableContent = try await SCShareableContent.current
        let target = try await recordingTarget(for: options.mode, in: shareableContent)
        let streamConfiguration = makeStreamConfiguration(target: target, microphoneEnabled: options.microphoneEnabled)
        let recordingConfiguration = try makeRecordingConfiguration(outputURL: outputURL)
        let delegate = RecordingOutputDelegate(
            didFail: { [weak self] error in
                self?.handleRecordingOutputFailure(error)
            },
            didFinish: { [weak self] in
                self?.completeRecording()
            }
        )
        let stream = SCStream(filter: target.filter, configuration: streamConfiguration, delegate: nil)
        let recordingOutput = SCRecordingOutput(configuration: recordingConfiguration, delegate: delegate)

        try stream.addRecordingOutput(recordingOutput)
        try await startCapture(stream)

        let toolbar = RecordingToolbarWindowController { [weak self] in
            Task { @MainActor in
                await self?.stopActiveRecording()
            }
        }
        activeSession = ActiveRecordingSession(
            stream: stream,
            recordingOutput: recordingOutput,
            recordingDelegate: delegate,
            toolbar: toolbar,
            outputURL: outputURL,
            mode: options.mode,
            dimensions: target.dimensions,
            thumbnailBaseDirectory: baseDirectory
        )
        toolbar.show(on: target.screen)
    }

    private func completeRecording() {
        guard let activeSession else {
            return
        }

        do {
            let result = try makeRecordingResult(for: activeSession)
            completeWithResult(result)
        } catch {
            completeWithError(error)
        }
    }

    private func handleRecordingOutputFailure(_ error: Error) {
        guard let activeSession else {
            return
        }

        guard activeSession.didRequestStop else {
            completeWithError(error)
            return
        }

        Task { @MainActor in
            if await recoverCompletedRecordingIfPossible() {
                return
            }

            completeWithError(error)
        }
    }

    private func recoverCompletedRecordingIfPossible() async -> Bool {
        for _ in 0..<6 {
            guard let activeSession else {
                return true
            }

            let fileExists = fileManager.fileExists(atPath: activeSession.outputURL.fileSystemPath)
            if fileExists, let result = try? makeRecordingResult(for: activeSession) {
                completeWithResult(result)
                return true
            }

            try? await Task.sleep(nanoseconds: 150_000_000)
        }

        return false
    }

    private func makeRecordingResult(for activeSession: ActiveRecordingSession) throws -> RecordingResult {
        let metadata = try VideoMetadataReader.metadata(for: activeSession.outputURL)
        let thumbnailURL = try VideoThumbnailGenerator(fileManager: fileManager).writeThumbnail(
            for: activeSession.outputURL,
            originalFileName: activeSession.outputURL.lastPathComponent,
            baseDirectory: activeSession.thumbnailBaseDirectory
        )
        let dimensions = metadata.dimensions.width > 0 && metadata.dimensions.height > 0
            ? metadata.dimensions
            : activeSession.dimensions

        return RecordingResult(
            mode: activeSession.mode,
            fileURL: activeSession.outputURL,
            durationSeconds: metadata.durationSeconds,
            width: Int(dimensions.width.rounded()),
            height: Int(dimensions.height.rounded()),
            thumbnailURL: thumbnailURL
        )
    }

    private func cancelActiveRecording() async {
        guard let activeSession else {
            completeWithError(RecordingSelectionError.cancelled)
            return
        }

        activeSession.toolbar.close()
        try? await stopCapture(activeSession.stream)
        try? fileManager.removeItem(at: activeSession.outputURL)
        completeWithError(RecordingSelectionError.cancelled)
    }

    private func completeWithResult(_ result: RecordingResult) {
        let continuation = continuation
        activeSession?.toolbar.close()
        activeSession = nil
        self.continuation = nil
        continuation?.resume(returning: result)
    }

    private func completeWithError(_ error: Error) {
        let continuation = continuation
        activeSession?.toolbar.close()
        activeSession = nil
        self.continuation = nil
        continuation?.resume(throwing: error)
    }

    private func recordingTarget(for mode: RecordingMode, in content: SCShareableContent) async throws -> RecordingTarget {
        let screen = currentScreen()
        let currentDisplay = try display(for: screen, in: content)

        switch mode {
        case .fullscreen:
            let filter = displayFilter(display: currentDisplay, content: content)
            let dimensions = dimensions(for: screen.frame.size, on: screen)
            return RecordingTarget(
                filter: filter,
                sourceRect: nil,
                dimensions: dimensions,
                screen: screen
            )
        case .area:
            let selector = RecordingAreaSelectionWindowController(screen: screen)
            let selection = try await selector.select()
            let selectedDisplay = try self.display(for: selection.screen, in: content)
            let filter = displayFilter(display: selectedDisplay, content: content)
            return RecordingTarget(
                filter: filter,
                sourceRect: sourceRect(for: selection.rect, on: selection.screen),
                dimensions: dimensions(for: selection.rect.size, on: selection.screen),
                screen: selection.screen
            )
        case .window:
            let windows = selectableWindows(in: content)
            guard !windows.isEmpty else {
                throw RecordingError.noRecordableWindows
            }

            let selector = RecordingWindowSelectionWindowController(screen: screen, windows: windows)
            let selectedWindow = try await selector.select()
            let filter = SCContentFilter(desktopIndependentWindow: selectedWindow)
            return RecordingTarget(
                filter: filter,
                sourceRect: nil,
                dimensions: dimensions(for: selectedWindow.frame.size, on: screen),
                screen: screen
            )
        }
    }

    private func makeStreamConfiguration(target: RecordingTarget, microphoneEnabled: Bool) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = max(Int(target.dimensions.width.rounded()), 64)
        configuration.height = max(Int(target.dimensions.height.rounded()), 64)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.queueDepth = 8
        configuration.showsCursor = true
        configuration.showMouseClicks = true
        configuration.capturesAudio = false
        configuration.excludesCurrentProcessAudio = true
        configuration.captureMicrophone = microphoneEnabled

        if let sourceRect = target.sourceRect {
            configuration.sourceRect = sourceRect
        }

        return configuration
    }

    private func makeRecordingConfiguration(outputURL: URL) throws -> SCRecordingOutputConfiguration {
        let configuration = SCRecordingOutputConfiguration()

        guard configuration.availableOutputFileTypes.contains(.mp4) else {
            throw RecordingError.mp4RecordingUnavailable
        }

        guard configuration.availableVideoCodecTypes.contains(.h264) else {
            throw RecordingError.h264RecordingUnavailable
        }

        configuration.outputURL = outputURL
        configuration.outputFileType = .mp4
        configuration.videoCodecType = .h264

        return configuration
    }

    private func requestMicrophoneAccessIfNeeded() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if !granted {
                throw RecordingError.microphonePermissionDenied
            }
        case .denied, .restricted:
            throw RecordingError.microphonePermissionDenied
        @unknown default:
            throw RecordingError.microphonePermissionDenied
        }
    }

    private func startCapture(_ stream: SCStream) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            stream.startCapture { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func stopCapture(_ stream: SCStream) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            stream.stopCapture { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func displayFilter(display: SCDisplay, content: SCShareableContent) -> SCContentFilter {
        if let currentApp = currentApplication(in: content) {
            return SCContentFilter(display: display, excludingApplications: [currentApp], exceptingWindows: [])
        }

        return SCContentFilter(display: display, excludingWindows: [])
    }

    private func currentApplication(in content: SCShareableContent) -> SCRunningApplication? {
        let processID = ProcessInfo.processInfo.processIdentifier
        return content.applications.first { $0.processID == processID }
    }

    private func selectableWindows(in content: SCShareableContent) -> [SCWindow] {
        let processID = ProcessInfo.processInfo.processIdentifier
        return content.windows.filter { window in
            window.isOnScreen &&
                window.windowLayer == 0 &&
                window.frame.width >= 48 &&
                window.frame.height >= 48 &&
                window.owningApplication?.processID != processID
        }
    }

    private func currentScreen() -> NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func display(for screen: NSScreen, in content: SCShareableContent) throws -> SCDisplay {
        guard let screenDisplayID = screen.displayID,
              let display = content.displays.first(where: { $0.displayID == screenDisplayID }) else {
            throw RecordingError.displayUnavailable
        }

        return display
    }

    private func dimensions(for size: CGSize, on screen: NSScreen) -> CGSize {
        CGSize(
            width: max(size.width * screen.backingScaleFactor, 64),
            height: max(size.height * screen.backingScaleFactor, 64)
        )
    }

    private func sourceRect(for rect: CGRect, on screen: NSScreen) -> CGRect {
        CGRect(
            x: rect.minX - screen.frame.minX,
            y: screen.frame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}

private final class ActiveRecordingSession {
    let stream: SCStream
    let recordingOutput: SCRecordingOutput
    let recordingDelegate: RecordingOutputDelegate
    let toolbar: RecordingToolbarWindowController
    let outputURL: URL
    let mode: RecordingMode
    let dimensions: CGSize
    let thumbnailBaseDirectory: URL?
    var didRequestStop = false

    init(
        stream: SCStream,
        recordingOutput: SCRecordingOutput,
        recordingDelegate: RecordingOutputDelegate,
        toolbar: RecordingToolbarWindowController,
        outputURL: URL,
        mode: RecordingMode,
        dimensions: CGSize,
        thumbnailBaseDirectory: URL?
    ) {
        self.stream = stream
        self.recordingOutput = recordingOutput
        self.recordingDelegate = recordingDelegate
        self.toolbar = toolbar
        self.outputURL = outputURL
        self.mode = mode
        self.dimensions = dimensions
        self.thumbnailBaseDirectory = thumbnailBaseDirectory
    }
}

private struct RecordingTarget {
    let filter: SCContentFilter
    let sourceRect: CGRect?
    let dimensions: CGSize
    let screen: NSScreen
}

private final class RecordingOutputDelegate: NSObject, SCRecordingOutputDelegate {
    private let didFail: @MainActor (Error) -> Void
    private let didFinish: @MainActor () -> Void

    init(didFail: @escaping @MainActor (Error) -> Void, didFinish: @escaping @MainActor () -> Void) {
        self.didFail = didFail
        self.didFinish = didFinish
    }

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        Task { @MainActor in
            didFail(error)
        }
    }

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in
            didFinish()
        }
    }
}

enum RecordingError: LocalizedError, Equatable {
    case alreadyRecording
    case displayUnavailable
    case noRecordableWindows
    case microphonePermissionDenied
    case mp4RecordingUnavailable
    case h264RecordingUnavailable

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            "A recording is already in progress."
        case .displayUnavailable:
            "Could not find the display to record."
        case .noRecordableWindows:
            "No recordable windows are available."
        case .microphonePermissionDenied:
            "Microphone access is required to record microphone audio."
        case .mp4RecordingUnavailable:
            "ScreenCaptureKit cannot record MP4 files on this Mac."
        case .h264RecordingUnavailable:
            "ScreenCaptureKit cannot record H.264 video on this Mac."
        }
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
            .map { CGDirectDisplayID($0.uint32Value) }
    }
}
