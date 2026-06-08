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
protocol RecordingSessionControlling: AnyObject {
    var options: RecordingOptions { get }
    var outputURL: URL { get }
    var mode: RecordingMode { get }
    var dimensions: CGSize { get }
    var thumbnailBaseDirectory: URL? { get }
    var didRequestStop: Bool { get set }
    var didRequestRestart: Bool { get set }
    var completionFallbackTask: Task<Void, Never>? { get set }

    func showChrome()
    func closeChrome()
    func stopCapture() async throws
}

@MainActor
final class RecordingController {
    private let fileManager: FileManager
    private let sessionFactory: (@MainActor (RecordingOptions, URL?) async throws -> any RecordingSessionControlling)?
    private let restartSessionFactory: (@MainActor (any RecordingSessionControlling) async throws -> any RecordingSessionControlling)?
    private let recordingResultFactory: (@MainActor (any RecordingSessionControlling) throws -> RecordingResult)?
    private let recoveryRetryCount: Int
    private let recoveryRetryDelayNanoseconds: UInt64
    private let completionFallbackDelayNanoseconds: UInt64
    private let sleep: (UInt64) async -> Void
    private var activeSession: (any RecordingSessionControlling)?
    private var continuation: CheckedContinuation<RecordingResult, Error>?

    init(
        fileManager: FileManager = .default,
        sessionFactory: (@MainActor (RecordingOptions, URL?) async throws -> any RecordingSessionControlling)? = nil,
        restartSessionFactory: (@MainActor (any RecordingSessionControlling) async throws -> any RecordingSessionControlling)? = nil,
        recordingResultFactory: (@MainActor (any RecordingSessionControlling) throws -> RecordingResult)? = nil,
        recoveryRetryCount: Int = 20,
        recoveryRetryDelayNanoseconds: UInt64 = 250_000_000,
        completionFallbackDelayNanoseconds: UInt64 = 8_000_000_000,
        sleep: @escaping (UInt64) async -> Void = { nanoseconds in
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.fileManager = fileManager
        self.sessionFactory = sessionFactory
        self.restartSessionFactory = restartSessionFactory
        self.recordingResultFactory = recordingResultFactory
        self.recoveryRetryCount = recoveryRetryCount
        self.recoveryRetryDelayNanoseconds = recoveryRetryDelayNanoseconds
        self.completionFallbackDelayNanoseconds = completionFallbackDelayNanoseconds
        self.sleep = sleep
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
        activeSession.closeChrome()

        do {
            try await activeSession.stopCapture()
            scheduleRecordingCompletionFallback(for: activeSession)
        } catch {
            if await recoverCompletedRecordingIfPossible() {
                return
            }

            completeWithError(recordingFailureError(error, options: activeSession.options))
        }
    }

    func restartActiveRecording() async {
        guard let activeSession,
              !activeSession.didRequestStop,
              !activeSession.didRequestRestart else {
            return
        }

        activeSession.didRequestRestart = true
        activeSession.closeChrome()

        do {
            try await activeSession.stopCapture()
            try? fileManager.removeItem(at: activeSession.outputURL)

            let restartedSession = try await makeRestartedSession(from: activeSession)

            guard self.activeSession === activeSession else {
                restartedSession.closeChrome()
                try? await restartedSession.stopCapture()
                try? fileManager.removeItem(at: restartedSession.outputURL)
                return
            }

            self.activeSession = restartedSession
            restartedSession.showChrome()
        } catch {
            try? fileManager.removeItem(at: activeSession.outputURL)
            if self.activeSession === activeSession {
                completeWithError(error)
            }
        }
    }

    private func beginRecording(options: RecordingOptions, baseDirectory: URL?) async throws {
        guard activeSession == nil else {
            throw RecordingError.alreadyRecording
        }

        if let sessionFactory {
            let activeSession = try await sessionFactory(options, baseDirectory)
            self.activeSession = activeSession
            activeSession.showChrome()
            return
        }

        if options.microphoneEnabled {
            try await requestMicrophoneAccessIfNeeded()
        }

        let shareableContent = try await SCShareableContent.current
        let target = try await recordingTarget(for: options.mode, in: shareableContent)
        let activeSession = try await makeActiveSession(
            options: options,
            target: target,
            baseDirectory: baseDirectory
        )

        self.activeSession = activeSession
        activeSession.showChrome()
    }

    private func makeRestartedSession(
        from activeSession: any RecordingSessionControlling
    ) async throws -> any RecordingSessionControlling {
        if let restartSessionFactory {
            return try await restartSessionFactory(activeSession)
        }

        guard let activeSession = activeSession as? ActiveRecordingSession else {
            throw RecordingError.recordingDidNotFinish
        }

        return try await makeActiveSession(
            options: activeSession.options,
            target: activeSession.target,
            baseDirectory: activeSession.thumbnailBaseDirectory
        )
    }

    private func makeActiveSession(
        options: RecordingOptions,
        target: RecordingTarget,
        baseDirectory: URL?
    ) async throws -> ActiveRecordingSession {
        let directories = try FileLocations.ensureCaptureDirectories(
            baseDirectory: baseDirectory,
            fileManager: fileManager
        )
        let outputContainer = options.outputContainer
        let outputURL = FileLocations.uniqueOriginalFileURL(
            captureMode: options.mode.fileNamePrefix,
            directories: directories,
            fileExtension: outputContainer.fileExtension
        )
        let streamConfiguration = makeStreamConfiguration(target: target, options: options)
        let recordingConfiguration = try makeRecordingConfiguration(outputURL: outputURL, container: outputContainer)
        let delegate = RecordingOutputDelegate(
            didFail: { [weak self] recordingOutput, error in
                self?.handleRecordingOutputFailure(error, from: recordingOutput)
            },
            didFinish: { [weak self] recordingOutput in
                self?.completeRecording(from: recordingOutput)
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
        } restartAction: { [weak self] in
            Task { @MainActor in
                await self?.restartActiveRecording()
            }
        }
        let focusOverlay = target.recordingRect.map {
            RecordingAreaFocusWindowController(screen: target.screen, recordingRect: $0)
        }

        return ActiveRecordingSession(
            options: options,
            target: target,
            stream: stream,
            recordingOutput: recordingOutput,
            recordingDelegate: delegate,
            toolbar: toolbar,
            focusOverlay: focusOverlay,
            outputURL: outputURL,
            mode: options.mode,
            dimensions: target.dimensions,
            thumbnailBaseDirectory: baseDirectory
        )
    }

    private func completeRecording(from recordingOutput: SCRecordingOutput? = nil) {
        guard let activeSession,
              !activeSession.didRequestRestart else {
            return
        }

        if let recordingOutput {
            guard let activeSession = activeSession as? ActiveRecordingSession,
                  activeSession.recordingOutput === recordingOutput else {
                return
            }
        }

        Task { @MainActor in
            if await recoverCompletedRecordingIfPossible() {
                return
            }

            completeWithError(RecordingError.recordingDidNotFinish)
        }
    }

    private func handleRecordingOutputFailure(_ error: Error, from recordingOutput: SCRecordingOutput) {
        guard let activeSession = activeSession as? ActiveRecordingSession,
              activeSession.recordingOutput === recordingOutput else {
            return
        }

        guard !activeSession.didRequestRestart else {
            return
        }

        guard activeSession.didRequestStop else {
            completeWithError(recordingFailureError(error, options: activeSession.options))
            return
        }

        Task { @MainActor in
            if await recoverCompletedRecordingIfPossible() {
                return
            }

            completeWithError(recordingFailureError(error, options: activeSession.options))
        }
    }

    private func scheduleRecordingCompletionFallback(for activeSession: any RecordingSessionControlling) {
        activeSession.completionFallbackTask?.cancel()
        activeSession.completionFallbackTask = Task { @MainActor [weak self, weak activeSession] in
            guard let self else {
                return
            }

            await sleep(completionFallbackDelayNanoseconds)

            guard let activeSession,
                  self.activeSession === activeSession,
                  activeSession.didRequestStop else {
                return
            }

            if await self.recoverCompletedRecordingIfPossible() {
                return
            }

            self.completeWithError(RecordingError.recordingDidNotFinish)
        }
    }

    private func recoverCompletedRecordingIfPossible() async -> Bool {
        for _ in 0..<recoveryRetryCount {
            guard let activeSession, !activeSession.didRequestRestart else {
                return true
            }

            let fileExists = fileManager.fileExists(atPath: activeSession.outputURL.fileSystemPath)
            if fileExists, let result = try? makeRecordingResult(for: activeSession) {
                completeWithResult(result)
                return true
            }

            await sleep(recoveryRetryDelayNanoseconds)
        }

        return false
    }

    private func makeRecordingResult(for activeSession: any RecordingSessionControlling) throws -> RecordingResult {
        if let recordingResultFactory {
            return try recordingResultFactory(activeSession)
        }

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
            thumbnailURL: thumbnailURL,
            microphoneEnabled: activeSession.options.microphoneEnabled,
            systemAudioEnabled: activeSession.options.systemAudioEnabled
        )
    }

    private func cancelActiveRecording() async {
        guard let activeSession else {
            completeWithError(RecordingSelectionError.cancelled)
            return
        }

        activeSession.closeChrome()
        try? await activeSession.stopCapture()
        try? fileManager.removeItem(at: activeSession.outputURL)
        completeWithError(RecordingSelectionError.cancelled)
    }

    private func completeWithResult(_ result: RecordingResult) {
        let continuation = continuation
        activeSession?.completionFallbackTask?.cancel()
        activeSession?.closeChrome()
        activeSession = nil
        self.continuation = nil
        continuation?.resume(returning: result)
    }

    private func completeWithError(_ error: Error) {
        let continuation = continuation
        activeSession?.completionFallbackTask?.cancel()
        activeSession?.closeChrome()
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
                recordingRect: nil,
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
                recordingRect: selection.rect,
                dimensions: dimensions(for: selection.rect.size, on: selection.screen),
                screen: selection.screen
            )
        case .window:
            guard !selectableWindows(in: content).isEmpty else {
                throw RecordingError.noRecordableWindows
            }

            let selectedWindowID = try await RecordingWindowSelectionController(fileManager: fileManager)
                .selectWindowID(excludingProcessID: ProcessInfo.processInfo.processIdentifier)
            let latestContent = try await SCShareableContent.current
            let windows = selectableWindows(in: latestContent)
            guard let selectedWindow = windows.first(where: { $0.windowID == selectedWindowID }) else {
                throw RecordingError.selectedWindowUnavailable
            }

            let filter = SCContentFilter(desktopIndependentWindow: selectedWindow)
            let selectedScreen = screenContaining(window: selectedWindow) ?? screen
            return RecordingTarget(
                filter: filter,
                sourceRect: nil,
                recordingRect: nil,
                dimensions: dimensions(for: selectedWindow.frame.size, on: selectedScreen),
                screen: selectedScreen
            )
        }
    }

    private func makeStreamConfiguration(target: RecordingTarget, options: RecordingOptions) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = max(Int(target.dimensions.width.rounded()), 64)
        configuration.height = max(Int(target.dimensions.height.rounded()), 64)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.queueDepth = 8
        configuration.showsCursor = true
        configuration.showMouseClicks = true
        configuration.capturesAudio = options.systemAudioEnabled
        configuration.excludesCurrentProcessAudio = true
        configuration.captureMicrophone = options.microphoneEnabled

        if let sourceRect = target.sourceRect {
            configuration.sourceRect = sourceRect
        }

        return configuration
    }

    private func makeRecordingConfiguration(
        outputURL: URL,
        container: RecordingOutputContainer
    ) throws -> SCRecordingOutputConfiguration {
        let configuration = SCRecordingOutputConfiguration()

        guard configuration.availableOutputFileTypes.contains(container.avFileType) else {
            throw RecordingError.outputFileTypeUnavailable(container.displayName)
        }

        guard configuration.availableVideoCodecTypes.contains(.h264) else {
            throw RecordingError.h264RecordingUnavailable
        }

        configuration.outputURL = outputURL
        configuration.outputFileType = container.avFileType
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

    private func recordingFailureError(_ error: Error, options: RecordingOptions) -> RecordingError {
        let nsError = error as NSError
        if nsError.domain == SCStreamErrorDomain {
            switch SCStreamError.Code(rawValue: nsError.code) {
            case .failedToStartAudioCapture, .failedToStopAudioCapture:
                return .systemAudioCaptureFailed(errorDetails(from: nsError))
            case .failedToStartMicrophoneCapture:
                return .microphoneCaptureFailed(errorDetails(from: nsError))
            default:
                break
            }
        }

        if options.microphoneEnabled && options.systemAudioEnabled {
            return .audioCaptureFailed(errorDetails(from: nsError))
        }

        if options.microphoneEnabled {
            return .microphoneCaptureFailed(errorDetails(from: nsError))
        }

        if options.systemAudioEnabled {
            return .systemAudioCaptureFailed(errorDetails(from: nsError))
        }

        return .recordingOutputFailed(errorDetails(from: nsError))
    }

    private func errorDetails(from error: NSError) -> String {
        let description = error.localizedDescription
        return "\(description) (\(error.domain) \(error.code))"
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

    private func screenContaining(window: SCWindow) -> NSScreen? {
        let displaySpaces = RecordingWindowSelectionResolver.currentDisplayCoordinateSpaces()
        let windowRect = RecordingWindowSelectionResolver.appKitRect(
            forCGWindowBounds: window.frame,
            displays: displaySpaces
        )

        return NSScreen.screens.first { $0.frame.intersects(windowRect) }
    }
}

private final class ActiveRecordingSession: RecordingSessionControlling {
    let options: RecordingOptions
    let target: RecordingTarget
    let stream: SCStream
    let recordingOutput: SCRecordingOutput
    let recordingDelegate: RecordingOutputDelegate
    let toolbar: RecordingToolbarWindowController
    let focusOverlay: RecordingAreaFocusWindowController?
    let outputURL: URL
    let mode: RecordingMode
    let dimensions: CGSize
    let thumbnailBaseDirectory: URL?
    var didRequestStop = false
    var didRequestRestart = false
    var completionFallbackTask: Task<Void, Never>?

    init(
        options: RecordingOptions,
        target: RecordingTarget,
        stream: SCStream,
        recordingOutput: SCRecordingOutput,
        recordingDelegate: RecordingOutputDelegate,
        toolbar: RecordingToolbarWindowController,
        focusOverlay: RecordingAreaFocusWindowController?,
        outputURL: URL,
        mode: RecordingMode,
        dimensions: CGSize,
        thumbnailBaseDirectory: URL?
    ) {
        self.options = options
        self.target = target
        self.stream = stream
        self.recordingOutput = recordingOutput
        self.recordingDelegate = recordingDelegate
        self.toolbar = toolbar
        self.focusOverlay = focusOverlay
        self.outputURL = outputURL
        self.mode = mode
        self.dimensions = dimensions
        self.thumbnailBaseDirectory = thumbnailBaseDirectory
    }

    func showChrome() {
        focusOverlay?.show()
        toolbar.show(on: target.screen)
    }

    func closeChrome() {
        toolbar.close()
        focusOverlay?.close()
    }

    func stopCapture() async throws {
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
}

private struct RecordingTarget {
    let filter: SCContentFilter
    let sourceRect: CGRect?
    let recordingRect: CGRect?
    let dimensions: CGSize
    let screen: NSScreen
}

private final class RecordingOutputDelegate: NSObject, SCRecordingOutputDelegate {
    private let didFail: @MainActor (SCRecordingOutput, Error) -> Void
    private let didFinish: @MainActor (SCRecordingOutput) -> Void

    init(
        didFail: @escaping @MainActor (SCRecordingOutput, Error) -> Void,
        didFinish: @escaping @MainActor (SCRecordingOutput) -> Void
    ) {
        self.didFail = didFail
        self.didFinish = didFinish
    }

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        Task { @MainActor in
            didFail(recordingOutput, error)
        }
    }

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in
            didFinish(recordingOutput)
        }
    }
}

enum RecordingError: LocalizedError, Equatable {
    case alreadyRecording
    case displayUnavailable
    case noRecordableWindows
    case selectedWindowUnavailable
    case windowSelectionFailed(status: Int32)
    case microphonePermissionDenied
    case audioCaptureFailed(String)
    case microphoneCaptureFailed(String)
    case systemAudioCaptureFailed(String)
    case outputFileTypeUnavailable(String)
    case h264RecordingUnavailable
    case recordingOutputFailed(String)
    case recordingDidNotFinish

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            "A recording is already in progress."
        case .displayUnavailable:
            "Could not find the display to record."
        case .noRecordableWindows:
            "No recordable windows are available."
        case .selectedWindowUnavailable:
            "The selected window is no longer available for recording."
        case .windowSelectionFailed(let status):
            "Window selection failed with status \(status)."
        case .microphonePermissionDenied:
            "Microphone access is required to record microphone audio."
        case .audioCaptureFailed(let details):
            "Audio recording failed. Turn off Microphone or System Audio, or check audio recording permissions in System Settings. \(details)"
        case .microphoneCaptureFailed(let details):
            "Microphone recording failed. Turn off Microphone or check Microphone permission in System Settings. \(details)"
        case .systemAudioCaptureFailed(let details):
            "System audio recording failed. Turn off System Audio or check Screen & System Audio Recording permission in System Settings. \(details)"
        case .outputFileTypeUnavailable(let fileType):
            "ScreenCaptureKit cannot record \(fileType) files on this Mac."
        case .h264RecordingUnavailable:
            "ScreenCaptureKit cannot record H.264 video on this Mac."
        case .recordingOutputFailed(let details):
            "ScreenCaptureKit failed to finish the recording. \(details)"
        case .recordingDidNotFinish:
            "ScreenCaptureKit did not finish writing the recording file."
        }
    }
}

private extension RecordingOutputContainer {
    var avFileType: AVFileType {
        switch self {
        case .mp4:
            .mp4
        case .mov:
            .mov
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
            .map { CGDirectDisplayID($0.uint32Value) }
    }
}
