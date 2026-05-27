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
        let timestamp = utcTimestamp(from: date)

        return "\(safePrefix)-\(timestamp)-\(uuid.uuidString.prefix(8)).png"
    }

    private static func utcTimestamp(from date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)

        return String(
            format: "%04d%02d%02d-%02d%02d%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0,
            components.second ?? 0
        )
    }
}
