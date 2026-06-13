//
//  AppOrchestration.swift
//  ScreenshotMaxxing
//
//  Created by Codex on 6/12/26.
//

import AppKit
import Foundation

@MainActor
final class AppCaptureOrchestrator {
    typealias PermissionCheck = @MainActor () -> Bool
    typealias CaptureRunner = @MainActor (CaptureMode) async throws -> CaptureResult
    typealias RecordingRunner = @MainActor (RecordingOptions) async throws -> RecordingResult
    typealias CaptureSaver = @MainActor (CaptureResult) throws -> Capture
    typealias RecordingSaver = @MainActor (RecordingResult) throws -> Capture
    typealias PermissionOnboardingOpener = @MainActor () -> Void
    typealias EditorOpener = @MainActor (URL, Capture?) -> Void
    typealias VideoEditorOpener = @MainActor (URL, Capture?) -> Void
    typealias RecordingLifecycleAction = @MainActor () -> Void
    typealias ErrorPresenter = @MainActor (Error, String) -> Void

    private let hasRequiredPermissions: PermissionCheck
    private let capture: CaptureRunner
    private let record: RecordingRunner
    private let saveCapture: CaptureSaver
    private let saveRecording: RecordingSaver
    private let openPermissionOnboarding: PermissionOnboardingOpener
    private let openEditor: EditorOpener
    private let openVideoEditor: VideoEditorOpener
    private let prepareForRecording: RecordingLifecycleAction
    private let restoreAfterRecordingStops: RecordingLifecycleAction
    private let presentError: ErrorPresenter

    init(
        hasRequiredPermissions: @escaping PermissionCheck,
        capture: @escaping CaptureRunner,
        record: @escaping RecordingRunner,
        saveCapture: @escaping CaptureSaver,
        saveRecording: @escaping RecordingSaver,
        openPermissionOnboarding: @escaping PermissionOnboardingOpener,
        openEditor: @escaping EditorOpener,
        openVideoEditor: @escaping VideoEditorOpener,
        prepareForRecording: @escaping RecordingLifecycleAction,
        restoreAfterRecordingStops: @escaping RecordingLifecycleAction,
        presentError: @escaping ErrorPresenter
    ) {
        self.hasRequiredPermissions = hasRequiredPermissions
        self.capture = capture
        self.record = record
        self.saveCapture = saveCapture
        self.saveRecording = saveRecording
        self.openPermissionOnboarding = openPermissionOnboarding
        self.openEditor = openEditor
        self.openVideoEditor = openVideoEditor
        self.prepareForRecording = prepareForRecording
        self.restoreAfterRecordingStops = restoreAfterRecordingStops
        self.presentError = presentError
    }

    @discardableResult
    func startCapture(_ mode: CaptureMode) -> Task<Void, Never>? {
        guard hasRequiredPermissions() else {
            openPermissionOnboarding()
            return nil
        }

        return Task { @MainActor in
            do {
                let result = try await capture(mode)
                let capture = try saveCapture(result)
                openEditor(result.fileURL, capture)
            } catch CaptureError.cancelled {
                return
            } catch RecordingSelectionError.cancelled {
                return
            } catch {
                presentError(error, "Capture Failed")
            }
        }
    }

    @discardableResult
    func startRecording(_ options: RecordingOptions) -> Task<Void, Never>? {
        guard hasRequiredPermissions() else {
            openPermissionOnboarding()
            return nil
        }

        prepareForRecording()

        return Task { @MainActor in
            do {
                let result = try await record(options)
                let capture = try saveRecording(result)
                openVideoEditor(result.fileURL, capture)
            } catch RecordingSelectionError.cancelled {
                restoreAfterRecordingStops()
                return
            } catch {
                restoreAfterRecordingStops()
                presentError(error, "Recording Failed")
            }
        }
    }
}

@MainActor
final class AppWindowControllerStore<Controller: AnyObject> {
    private(set) var controllers: [Controller] = []

    func open(
        matching matches: (Controller) -> Bool,
        makeController: () -> Controller,
        installCloseHandler: (Controller, @escaping (Controller) -> Void) -> Void,
        showExisting: (Controller) -> Void,
        showNew: (Controller) -> Void
    ) {
        if let controller = controllers.first(where: matches) {
            showExisting(controller)
            return
        }

        let controller = makeController()
        installCloseHandler(controller) { [weak self] closedController in
            self?.remove(closedController)
        }
        controllers.append(controller)
        showNew(controller)
    }

    private func remove(_ controller: Controller) {
        controllers.removeAll { $0 === controller }
    }
}

@MainActor
enum AppWindowPresenter {
    static func activateAndOrderFront(_ window: NSWindow) {
        activateAndOrderFront(
            setRegularActivationPolicy: {
                NSApp.setActivationPolicy(.regular)
            },
            activateIgnoringOtherApps: {
                NSApp.activate(ignoringOtherApps: true)
            },
            makeKeyAndOrderFront: {
                window.makeKeyAndOrderFront(nil)
            }
        )
    }

    static func activateAndOrderFront(
        setRegularActivationPolicy: () -> Bool,
        activateIgnoringOtherApps: () -> Void,
        makeKeyAndOrderFront: () -> Void
    ) {
        _ = setRegularActivationPolicy()
        activateIgnoringOtherApps()
        makeKeyAndOrderFront()
    }
}
