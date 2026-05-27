//
//  FileLocations.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/26/26.
//

import Foundation

struct CaptureDirectories: Equatable {
    let root: URL
    let originals: URL
    let edited: URL
}

enum FileLocations {
    static let applicationSupportFolderName = "ScreenshotMaxxing"

    static func applicationSupportDirectory(fileManager: FileManager = .default) throws -> URL {
        try fileManager
            .url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            .appendingPathComponent(applicationSupportFolderName, isDirectory: true)
    }

    static func captureDirectories(baseDirectory: URL? = nil, fileManager: FileManager = .default) throws -> CaptureDirectories {
        let appSupport = try baseDirectory ?? applicationSupportDirectory(fileManager: fileManager)
        let root = appSupport.appendingPathComponent("Captures", isDirectory: true)

        return CaptureDirectories(
            root: root,
            originals: root.appendingPathComponent("originals", isDirectory: true),
            edited: root.appendingPathComponent("edited", isDirectory: true)
        )
    }

    @discardableResult
    static func ensureCaptureDirectories(
        baseDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> CaptureDirectories {
        let directories = try captureDirectories(baseDirectory: baseDirectory, fileManager: fileManager)

        try [directories.root, directories.originals, directories.edited].forEach { directory in
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        return directories
    }

    static func uniqueOriginalFileURL(
        captureMode: String,
        directories: CaptureDirectories,
        date: Date = Date(),
        uuid: UUID = UUID()
    ) -> URL {
        let fileName = uniqueFileName(prefix: captureMode, date: date, uuid: uuid)
        return directories.originals.appendingPathComponent(fileName, isDirectory: false)
    }

    static func uniqueEditedFileURL(
        originalFileName: String,
        directories: CaptureDirectories,
        uuid: UUID = UUID()
    ) -> URL {
        let baseName = URL(fileURLWithPath: originalFileName).deletingPathExtension().lastPathComponent
        return directories.edited.appendingPathComponent("\(baseName)-edited-\(uuid.uuidString.prefix(8)).png")
    }

    private static func uniqueFileName(prefix: String, date: Date, uuid: UUID) -> String {
        let safePrefix = prefix
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        let timestamp = fileNameDateFormatter.string(from: date)

        return "\(safePrefix)-\(timestamp)-\(uuid.uuidString.prefix(8)).png"
    }

    private static let fileNameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}
