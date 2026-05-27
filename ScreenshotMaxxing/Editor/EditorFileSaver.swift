//
//  EditorFileSaver.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/26/26.
//

import Foundation

@MainActor
struct EditorFileSaver {
    private let fileManager: FileManager
    private let metadataStore: CaptureMetadataStore?

    init() {
        self.fileManager = .default
        self.metadataStore = CaptureMetadataStore()
    }

    init(fileManager: FileManager, metadataStore: CaptureMetadataStore?) {
        self.fileManager = fileManager
        self.metadataStore = metadataStore
    }

    func saveEditedPNG(
        _ pngData: Data,
        originalFileName: String,
        capture: Capture?,
        baseDirectory: URL? = nil
    ) throws -> URL {
        let directories = try FileLocations.ensureCaptureDirectories(
            baseDirectory: baseDirectory,
            fileManager: fileManager
        )
        let editedFileURL = FileLocations.uniqueEditedFileURL(
            originalFileName: originalFileName,
            directories: directories
        )

        try pngData.write(to: editedFileURL, options: .atomic)

        if let capture {
            try metadataStore?.updateEditedFilePath(for: capture, editedFileURL: editedFileURL)
        }

        return editedFileURL
    }
}
