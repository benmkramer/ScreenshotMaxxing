//
//  PreferencesModule.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/26/26.
//

import Foundation

struct PreferencesData: Equatable {
    let areaCaptureShortcut: GlobalKeyboardShortcut
    let originalsFolderPath: String
    let editedFolderPath: String

    static func current(
        areaCaptureShortcut: GlobalKeyboardShortcut,
        baseDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> PreferencesData {
        let directories = try FileLocations.ensureCaptureDirectories(
            baseDirectory: baseDirectory,
            fileManager: fileManager
        )

        return PreferencesData(
            areaCaptureShortcut: areaCaptureShortcut,
            originalsFolderPath: directories.originals.path(),
            editedFolderPath: directories.edited.path()
        )
    }

    func updatingAreaCaptureShortcut(_ shortcut: GlobalKeyboardShortcut) -> PreferencesData {
        PreferencesData(
            areaCaptureShortcut: shortcut,
            originalsFolderPath: originalsFolderPath,
            editedFolderPath: editedFolderPath
        )
    }
}
