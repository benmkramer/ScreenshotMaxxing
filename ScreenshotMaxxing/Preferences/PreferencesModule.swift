//
//  PreferencesModule.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/26/26.
//

import Foundation

struct PreferencesData: Equatable {
    let areaCaptureShortcut: GlobalKeyboardShortcut
    let captureOptionsShortcut: GlobalKeyboardShortcut
    let openHistoryShortcut: GlobalKeyboardShortcut
    let launchAtLoginEnabled: Bool
    let originalsFolderPath: String
    let editedFolderPath: String
    let monoAudioExportEnabled: Bool

    init(
        areaCaptureShortcut: GlobalKeyboardShortcut,
        captureOptionsShortcut: GlobalKeyboardShortcut,
        openHistoryShortcut: GlobalKeyboardShortcut,
        launchAtLoginEnabled: Bool,
        originalsFolderPath: String,
        editedFolderPath: String,
        monoAudioExportEnabled: Bool = false
    ) {
        self.areaCaptureShortcut = areaCaptureShortcut
        self.captureOptionsShortcut = captureOptionsShortcut
        self.openHistoryShortcut = openHistoryShortcut
        self.launchAtLoginEnabled = launchAtLoginEnabled
        self.originalsFolderPath = originalsFolderPath
        self.editedFolderPath = editedFolderPath
        self.monoAudioExportEnabled = monoAudioExportEnabled
    }

    static func current(
        areaCaptureShortcut: GlobalKeyboardShortcut,
        captureOptionsShortcut: GlobalKeyboardShortcut = .defaultCaptureOptions,
        openHistoryShortcut: GlobalKeyboardShortcut = .defaultOpenHistory,
        launchAtLoginEnabled: Bool = false,
        monoAudioExportEnabled: Bool = false,
        baseDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> PreferencesData {
        let directories = try FileLocations.ensureCaptureDirectories(
            baseDirectory: baseDirectory,
            fileManager: fileManager
        )

        return PreferencesData(
            areaCaptureShortcut: areaCaptureShortcut,
            captureOptionsShortcut: captureOptionsShortcut,
            openHistoryShortcut: openHistoryShortcut,
            launchAtLoginEnabled: launchAtLoginEnabled,
            originalsFolderPath: directories.originals.fileSystemPath,
            editedFolderPath: directories.edited.fileSystemPath,
            monoAudioExportEnabled: monoAudioExportEnabled
        )
    }

    func updatingAreaCaptureShortcut(_ shortcut: GlobalKeyboardShortcut) -> PreferencesData {
        PreferencesData(
            areaCaptureShortcut: shortcut,
            captureOptionsShortcut: captureOptionsShortcut,
            openHistoryShortcut: openHistoryShortcut,
            launchAtLoginEnabled: launchAtLoginEnabled,
            originalsFolderPath: originalsFolderPath,
            editedFolderPath: editedFolderPath,
            monoAudioExportEnabled: monoAudioExportEnabled
        )
    }

    func resettingAreaCaptureShortcut() -> PreferencesData {
        updatingAreaCaptureShortcut(.defaultAreaCapture)
    }

    func updatingCaptureOptionsShortcut(_ shortcut: GlobalKeyboardShortcut) -> PreferencesData {
        PreferencesData(
            areaCaptureShortcut: areaCaptureShortcut,
            captureOptionsShortcut: shortcut,
            openHistoryShortcut: openHistoryShortcut,
            launchAtLoginEnabled: launchAtLoginEnabled,
            originalsFolderPath: originalsFolderPath,
            editedFolderPath: editedFolderPath,
            monoAudioExportEnabled: monoAudioExportEnabled
        )
    }

    func resettingCaptureOptionsShortcut() -> PreferencesData {
        updatingCaptureOptionsShortcut(.defaultCaptureOptions)
    }

    func updatingOpenHistoryShortcut(_ shortcut: GlobalKeyboardShortcut) -> PreferencesData {
        PreferencesData(
            areaCaptureShortcut: areaCaptureShortcut,
            captureOptionsShortcut: captureOptionsShortcut,
            openHistoryShortcut: shortcut,
            launchAtLoginEnabled: launchAtLoginEnabled,
            originalsFolderPath: originalsFolderPath,
            editedFolderPath: editedFolderPath,
            monoAudioExportEnabled: monoAudioExportEnabled
        )
    }

    func resettingOpenHistoryShortcut() -> PreferencesData {
        updatingOpenHistoryShortcut(.defaultOpenHistory)
    }

    func updatingLaunchAtLoginEnabled(_ isEnabled: Bool) -> PreferencesData {
        PreferencesData(
            areaCaptureShortcut: areaCaptureShortcut,
            captureOptionsShortcut: captureOptionsShortcut,
            openHistoryShortcut: openHistoryShortcut,
            launchAtLoginEnabled: isEnabled,
            originalsFolderPath: originalsFolderPath,
            editedFolderPath: editedFolderPath,
            monoAudioExportEnabled: monoAudioExportEnabled
        )
    }

    func updatingMonoAudioExportEnabled(_ isEnabled: Bool) -> PreferencesData {
        PreferencesData(
            areaCaptureShortcut: areaCaptureShortcut,
            captureOptionsShortcut: captureOptionsShortcut,
            openHistoryShortcut: openHistoryShortcut,
            launchAtLoginEnabled: launchAtLoginEnabled,
            originalsFolderPath: originalsFolderPath,
            editedFolderPath: editedFolderPath,
            monoAudioExportEnabled: isEnabled
        )
    }
}
