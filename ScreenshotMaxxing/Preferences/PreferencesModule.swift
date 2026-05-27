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
    let originalsFolderPath: String
    let editedFolderPath: String

    static func current(
        areaCaptureShortcut: GlobalKeyboardShortcut,
        captureOptionsShortcut: GlobalKeyboardShortcut = .defaultCaptureOptions,
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
            originalsFolderPath: directories.originals.fileSystemPath,
            editedFolderPath: directories.edited.fileSystemPath
        )
    }

    func updatingAreaCaptureShortcut(_ shortcut: GlobalKeyboardShortcut) -> PreferencesData {
        PreferencesData(
            areaCaptureShortcut: shortcut,
            captureOptionsShortcut: captureOptionsShortcut,
            originalsFolderPath: originalsFolderPath,
            editedFolderPath: editedFolderPath
        )
    }
}
